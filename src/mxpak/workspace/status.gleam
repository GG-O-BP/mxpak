// 워크스페이스 중복제거 상태 조회

import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import mxpak/cache/integrity
import mxpak/workspace.{type WorkspaceConfig}
import simplifile

/// 프로젝트별 파일 통계
pub type ProjectStats {
  ProjectStats(name: String, total_files: Int, total_bytes: Int)
}

/// 워크스페이스 전체 상태
pub type WorkspaceStatus {
  WorkspaceStatus(
    projects: List(ProjectStats),
    total_files: Int,
    unique_hashes: Int,
    potential_savings: Int,
  )
}

/// 워크스페이스 상태 조회 (읽기 전용, 변경 없음)
pub fn check(config: WorkspaceConfig) -> Result(WorkspaceStatus, String) {
  use projects <- result.try(workspace.discover_projects(config.root))

  // 프로젝트별 통계 수집
  use project_stats <- result.try(
    list.try_map(projects, fn(project) {
      count_project(project, config)
    }),
  )

  // 전체 파일 해시 → 그룹화하여 중복 파악
  use hash_counts <- result.try(count_hashes(projects, config))

  let total = list.fold(project_stats, 0, fn(acc, ps) { acc + ps.total_files })
  let unique = dict.size(hash_counts)

  // 잠재 절감량 = 중복 파일 크기 합
  let potential =
    dict.fold(hash_counts, 0, fn(acc, _hash, info) {
      let #(count, size) = info
      case count > 1 {
        True -> acc + { { count - 1 } * size }
        False -> acc
      }
    })

  Ok(WorkspaceStatus(
    projects: project_stats,
    total_files: total,
    unique_hashes: unique,
    potential_savings: potential,
  ))
}

/// 상태를 사람이 읽을 수 있는 문자열로 포맷
pub fn format(status: WorkspaceStatus) -> String {
  let header = "워크스페이스 상태\n"
  let divider = string.repeat("─", 40) <> "\n"

  let project_lines =
    list.map(status.projects, fn(ps) {
      "  "
      <> ps.name
      <> ": "
      <> int.to_string(ps.total_files)
      <> "개 파일, "
      <> format_bytes(ps.total_bytes)
    })
    |> string.join("\n")

  let summary =
    "\n"
    <> divider
    <> "전체 파일: "
    <> int.to_string(status.total_files)
    <> "\n고유 해시: "
    <> int.to_string(status.unique_hashes)
    <> "\n중복 파일: "
    <> int.to_string(status.total_files - status.unique_hashes)
    <> "\n절감 가능: "
    <> format_bytes(status.potential_savings)

  header <> divider <> project_lines <> summary
}

// ── 내부 ──

fn count_project(
  project_root: String,
  config: WorkspaceConfig,
) -> Result(ProjectStats, String) {
  use files <- result.try(
    list_dir_recursive(project_root, config.exclude_dirs)
    |> result.map_error(fn(_) { "디렉토리 읽기 실패" }),
  )
  let matching =
    list.filter(files, fn(path) { matches_include(path, config.include) })
  let total_bytes =
    list.fold(matching, 0, fn(acc, path) {
      case file_info(path) {
        Ok(#(size, _)) -> acc + size
        Error(_) -> acc
      }
    })
  let name = basename(project_root)
  Ok(ProjectStats(name: name, total_files: list.length(matching), total_bytes: total_bytes))
}

fn count_hashes(
  projects: List(String),
  config: WorkspaceConfig,
) -> Result(dict.Dict(String, #(Int, Int)), String) {
  list.try_fold(projects, dict.new(), fn(acc, project) {
    use files <- result.try(
      list_dir_recursive(project, config.exclude_dirs)
      |> result.map_error(fn(_) { "디렉토리 읽기 실패" }),
    )
    let matching =
      list.filter(files, fn(path) { matches_scan(path, config) })
    list.try_fold(matching, acc, fn(hash_map, path) {
      case file_info(path) {
        Ok(#(size, _)) -> {
          use data <- result.try(
            simplifile.read_bits(path)
            |> result.map_error(fn(_) { "파일 읽기 실패" }),
          )
          let hash = integrity.sha256(data)
          let current = case dict.get(hash_map, hash) {
            Ok(#(count, s)) -> #(count + 1, s)
            Error(_) -> #(1, size)
          }
          Ok(dict.insert(hash_map, hash, current))
        }
        Error(_) -> Ok(hash_map)
      }
    })
  })
}

fn matches_scan(path: String, config: WorkspaceConfig) -> Bool {
  matches_include(path, config.include)
  || matches_include_dir(path, config.include_dirs)
}

fn matches_include(path: String, patterns: List(String)) -> Bool {
  list.any(patterns, fn(pattern) {
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

fn format_bytes(bytes: Int) -> String {
  case bytes {
    b if b >= 1_048_576 -> {
      let mb = b / 1_048_576
      let remainder = { b % 1_048_576 } * 10 / 1_048_576
      int.to_string(mb) <> "." <> int.to_string(remainder) <> " MB"
    }
    b if b >= 1024 -> {
      let kb = b / 1024
      int.to_string(kb) <> " KB"
    }
    b -> int.to_string(b) <> " B"
  }
}

fn basename(path: String) -> String {
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
