// CAS (Content-Addressable Storage) — ~/.mxpak/store/{sha256}/

import gleam/list
import gleam/result
import gleam/string
import mxpak/cache/integrity
import simplifile

/// 글로벌 캐시 루트 경로
pub fn cache_root() -> String {
  case get_home_dir() {
    Ok(home) -> home <> "/.mxpak/store"
    Error(_) -> ".mxpak/store"
  }
}

/// SHA-256 기반 캐시 경로
pub fn cache_path(hash: String) -> String {
  cache_root() <> "/" <> hash
}

/// 캐시에 해당 해시가 존재하는지 확인
pub fn has(hash: String) -> Bool {
  case simplifile.is_directory(cache_path(hash)) {
    Ok(True) -> True
    _ -> False
  }
}

/// 바이너리 데이터를 캐시에 저장 (SHA-256 해시 키)
/// 반환: 저장된 디렉토리 경로 + 해시
pub fn put(
  data: BitArray,
  entries: List(#(String, BitArray)),
) -> Result(#(String, String), String) {
  let hash = integrity.sha256(data)
  let dir = cache_path(hash)

  case has(hash) {
    True -> Ok(#(dir, hash))
    False -> {
      use _ <- result.try(
        simplifile.create_directory_all(dir)
        |> result.map_error(fn(_) { "캐시 디렉토리 생성 실패: " <> dir }),
      )
      // 원본 .mpk 저장
      use _ <- result.try(
        simplifile.write_bits(dir <> "/original.mpk", data)
        |> result.map_error(fn(_) { "원본 .mpk 캐시 저장 실패" }),
      )
      // 엔트리를 캐시에 저장
      use _ <- result.try(
        list.try_each(entries, fn(entry) {
          let #(name, content) = entry
          let out_path = dir <> "/" <> name
          let out_dir = dirname(out_path)
          use _ <- result.try(
            simplifile.create_directory_all(out_dir)
            |> result.map_error(fn(_) { "디렉토리 생성 실패: " <> out_dir }),
          )
          simplifile.write_bits(out_path, content)
          |> result.map_error(fn(_) { "캐시 파일 쓰기 실패: " <> out_path })
        }),
      )
      Ok(#(dir, hash))
    }
  }
}

/// 캐시에서 프로젝트 build/widgets/{name}/ 으로 복사
pub fn link_to_project(hash: String, target_dir: String) -> Result(Nil, String) {
  let src = cache_path(hash)
  case has(hash) {
    False -> Error("캐시에 해당 해시가 없습니다: " <> hash)
    True -> {
      use _ <- result.try(
        simplifile.create_directory_all(target_dir)
        |> result.map_error(fn(_) { "대상 디렉토리 생성 실패" }),
      )
      copy_dir(src, target_dir)
    }
  }
}

/// 전체 캐시 삭제
pub fn clean() -> Result(Nil, String) {
  let root = cache_root()
  case simplifile.is_directory(root) {
    Ok(True) ->
      simplifile.delete(root)
      |> result.map_error(fn(_) { "캐시 삭제 실패" })
    _ -> Ok(Nil)
  }
}

/// 캐시의 original.mpk를 대상 경로에 하드 링크 (실패 시 복사 폴백)
pub fn restore_mpk(hash: String, target_path: String) -> Result(Nil, String) {
  let src = cache_path(hash) <> "/original.mpk"
  case simplifile.is_file(src) {
    Ok(True) -> {
      // 대상 파일이 이미 존재하면 삭제 (하드 링크는 기존 파일 위에 생성 불가)
      let _ = simplifile.delete(target_path)
      case make_hard_link(src, target_path) {
        Ok(_) -> Ok(Nil)
        Error(_) ->
          // 볼륨이 다르면 하드 링크 불가 → 복사 폴백
          simplifile.copy_file(src, target_path)
          |> result.map_error(fn(_) { "mpk 복사 실패: " <> target_path })
          |> result.map(fn(_) { Nil })
      }
    }
    _ -> Error("캐시에 original.mpk가 없습니다: " <> hash)
  }
}

@external(erlang, "mxpak_ffi", "make_hard_link")
fn make_hard_link(existing: String, new: String) -> Result(Nil, String)

// ── 내부 헬퍼 ──

@external(erlang, "mxpak_ffi", "get_home_dir")
fn get_home_dir() -> Result(String, Nil)

fn dirname(path: String) -> String {
  let parts = string.split(path, "/")
  case list.length(parts) > 1 {
    True ->
      list.take(parts, list.length(parts) - 1)
      |> string.join("/")
    False -> "."
  }
}

fn copy_dir(src: String, dest: String) -> Result(Nil, String) {
  use files <- result.try(
    simplifile.read_directory(src)
    |> result.map_error(fn(_) { "디렉토리 읽기 실패: " <> src }),
  )
  list.try_each(files, fn(file) {
    // 원본 .mpk는 프로젝트에 복사하지 않음
    case file == "original.mpk" {
      True -> Ok(Nil)
      False -> copy_entry(src <> "/" <> file, dest <> "/" <> file)
    }
  })
}

fn copy_entry(src_path: String, dest_path: String) -> Result(Nil, String) {
  case simplifile.is_directory(src_path) {
    Ok(True) -> {
      use _ <- result.try(
        simplifile.create_directory_all(dest_path)
        |> result.map_error(fn(_) { "디렉토리 생성 실패" }),
      )
      copy_dir(src_path, dest_path)
    }
    _ ->
      simplifile.copy_file(src_path, dest_path)
      |> result.map_error(fn(_) { "파일 복사 실패: " <> src_path })
      |> result.map(fn(_) { Nil })
  }
}
