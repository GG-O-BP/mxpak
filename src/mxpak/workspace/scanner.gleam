// 워크스페이스 파일 스캔 + CAS 중복제거 엔진
// 해시별 파일 그룹 → 2개 이상이면 CAS 저장 → 하드 링크 교체

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import mxpak/cache/integrity
import mxpak/cache/store
import mxpak/workspace.{type WorkspaceConfig}
import simplifile

/// 스캔 + 중복제거 결과
pub type ScanResult {
  ScanResult(
    total_files: Int,
    unique_hashes: Int,
    duplicate_groups: Int,
    linked_files: Int,
    saved_bytes: Int,
  )
}

/// 워크스페이스 스캔 + 중복제거 실행
pub fn scan_and_dedup(config: WorkspaceConfig) -> Result(ScanResult, String) {
  // 1. 프로젝트 목록 수집
  use projects <- result.try(workspace.discover_projects(config.root))
  case projects {
    [] -> Ok(ScanResult(0, 0, 0, 0, 0))
    _ -> {
      // 2. 모든 프로젝트에서 파일 수집
      use all_files <- result.try(collect_files(projects, config))

      // 3. 파일별 해시 계산 → 해시별 그룹화
      use hash_groups <- result.try(group_by_hash(all_files))

      // 4. 중복 그룹만 추출 (2개 이상 파일이 같은 해시)
      let dup_groups =
        dict.filter(hash_groups, fn(_hash, files) { list.length(files) > 1 })

      // 5. CAS 저장 + 하드 링크 교체
      use dedup_result <- result.try(dedup_groups(dup_groups))

      let total = list.length(all_files)
      let unique = dict.size(hash_groups)
      let groups = dict.size(dup_groups)

      Ok(ScanResult(
        total_files: total,
        unique_hashes: unique,
        duplicate_groups: groups,
        linked_files: dedup_result.linked,
        saved_bytes: dedup_result.saved,
      ))
    }
  }
}

// ── 파일 수집 ──

/// 파일 경로 + 크기 페어
type FileEntry {
  FileEntry(path: String, size: Int)
}

fn collect_files(
  projects: List(String),
  config: WorkspaceConfig,
) -> Result(List(FileEntry), String) {
  use nested <- result.try(
    list.try_map(projects, fn(project) {
      collect_project_files(project, config)
    }),
  )
  Ok(list.flatten(nested))
}

fn collect_project_files(
  project_root: String,
  config: WorkspaceConfig,
) -> Result(List(FileEntry), String) {
  use file_paths <- result.try(
    list_dir_recursive(project_root, config.exclude_dirs)
    |> result.map_error(fn(_) { "디렉토리 스캔 실패: " <> project_root }),
  )
  Ok(
    list.filter_map(file_paths, fn(path) {
      case matches_scan(path, config) {
        False -> Error(Nil)
        True ->
          case file_info(path) {
            Ok(#(size, _inode)) -> Ok(FileEntry(path, size))
            Error(_) -> Error(Nil)
          }
      }
    }),
  )
}

/// 확장자 OR 디렉토리 어느 한쪽이라도 매칭되면 스캔 대상
fn matches_scan(path: String, config: WorkspaceConfig) -> Bool {
  matches_include(path, config.include)
  || matches_include_dir(path, config.include_dirs)
}

fn matches_include(path: String, patterns: List(String)) -> Bool {
  list.any(patterns, fn(pattern) {
    // "*.ext" 패턴 → 확장자 매칭
    case string.starts_with(pattern, "*.") {
      True -> {
        let ext = string.drop_start(pattern, 1)
        string.ends_with(path, ext)
      }
      False -> string.ends_with(path, pattern)
    }
  })
}

fn matches_include_dir(path: String, dirs: List(String)) -> Bool {
  let normalized = string.replace(path, "\\", "/")
  list.any(dirs, fn(dir) {
    string.contains(normalized, "/" <> dir <> "/")
  })
}

// ── 해시 그룹화 ──

fn group_by_hash(
  files: List(FileEntry),
) -> Result(Dict(String, List(FileEntry)), String) {
  list.try_fold(files, dict.new(), fn(acc, entry) {
    use data <- result.try(
      simplifile.read_bits(entry.path)
      |> result.map_error(fn(_) { "파일 읽기 실패: " <> entry.path }),
    )
    let hash = integrity.sha256(data)
    let current = case dict.get(acc, hash) {
      Ok(existing) -> [entry, ..existing]
      Error(_) -> [entry]
    }
    Ok(dict.insert(acc, hash, current))
  })
}

// ── 중복제거 실행 ──

type DedupStats {
  DedupStats(linked: Int, saved: Int)
}

fn dedup_groups(
  groups: Dict(String, List(FileEntry)),
) -> Result(DedupStats, String) {
  dict.fold(groups, Ok(DedupStats(0, 0)), fn(acc_result, hash, files) {
    use acc <- result.try(acc_result)
    use stats <- result.try(dedup_single_group(hash, files))
    Ok(DedupStats(
      linked: acc.linked + stats.linked,
      saved: acc.saved + stats.saved,
    ))
  })
}

fn dedup_single_group(
  hash: String,
  files: List(FileEntry),
) -> Result(DedupStats, String) {
  case files {
    [] | [_] -> Ok(DedupStats(0, 0))
    [first, ..rest] -> {
      // CAS에 없으면 첫 번째 파일로 저장
      let _ = case store.has(hash) {
        False -> {
          case simplifile.read_bits(first.path) {
            Ok(data) -> {
              let filename = basename(first.path)
              let _ = store.put_file(data, filename)
              Ok(Nil)
            }
            Error(_) -> Error("파일 읽기 실패: " <> first.path)
          }
        }
        True -> Ok(Nil)
      }

      // 모든 파일(첫 번째 포함)을 CAS에서 하드 링크로 교체
      let all_files = [first, ..rest]
      use linked_count <- result.try(
        list.try_fold(all_files, 0, fn(count, entry) {
          let filename = basename(entry.path)
          case store.restore_file(hash, filename, entry.path) {
            Ok(_) -> Ok(count + 1)
            Error(_) -> Ok(count)
          }
        }),
      )
      // 절감량 = (전체 - 1) × 파일 크기 (CAS 1개 + 하드링크 N개)
      let saved = { list.length(all_files) - 1 } * first.size
      Ok(DedupStats(linked: linked_count, saved: saved))
    }
  }
}

fn basename(path: String) -> String {
  // 윈도우와 유닉스 경로 구분자 모두 처리
  let normalized = string.replace(path, "\\", "/")
  case string.split(normalized, "/") |> list.last {
    Ok(name) -> name
    Error(_) -> path
  }
}

// ── FFI ──

@external(erlang, "mxpak_ffi", "file_info")
fn file_info(path: String) -> Result(#(Int, Int), String)

@external(erlang, "mxpak_ffi", "list_dir_recursive")
fn list_dir_recursive(
  dir: String,
  exclude_dirs: List(String),
) -> Result(List(String), String)
