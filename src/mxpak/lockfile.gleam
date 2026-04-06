// mxpak.lock — TOML 기반 락파일 읽기/쓰기
// 결정론적 설치를 위한 정확한 버전 + 해시 고정

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import tom

/// 락파일 엔트리
pub type LockEntry {
  LockEntry(
    version: String,
    hash: String,
    content_id: Option(Int),
    s3_id: Option(String),
    classic: Bool,
  )
}

/// 락파일 전체
pub type Lockfile {
  Lockfile(entries: Dict(String, LockEntry))
}

const lock_filename = "mxpak.lock"

/// 락파일 읽기
pub fn read(project_root: String) -> Result(Lockfile, String) {
  let path = project_root <> "/" <> lock_filename
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "mxpak.lock 읽기 실패" }),
  )
  use parsed <- result.try(
    tom.parse(content)
    |> result.map_error(fn(_) { "mxpak.lock 파싱 실패" }),
  )
  Ok(parse_lockfile(parsed))
}

/// 락파일 존재 여부
pub fn exists(project_root: String) -> Bool {
  case simplifile.is_file(project_root <> "/" <> lock_filename) {
    Ok(True) -> True
    _ -> False
  }
}

/// 락파일 쓰기 (결정론적 순서)
pub fn write(
  project_root: String,
  entries: Dict(String, LockEntry),
) -> Result(Nil, String) {
  let path = project_root <> "/" <> lock_filename
  let content = serialize_lockfile(entries)
  simplifile.write(path, content)
  |> result.map_error(fn(_) { "mxpak.lock 쓰기 실패" })
}

/// 특정 위젯의 락 엔트리 조회
pub fn get_entry(lockfile: Lockfile, name: String) -> Result(LockEntry, Nil) {
  dict.get(lockfile.entries, name)
}

/// 락파일 삭제
pub fn remove(project_root: String) -> Result(Nil, String) {
  let path = project_root <> "/" <> lock_filename
  case simplifile.is_file(path) {
    Ok(True) ->
      simplifile.delete(path)
      |> result.map_error(fn(_) { "mxpak.lock 삭제 실패" })
    _ -> Ok(Nil)
  }
}

// ── 파싱 ──

fn parse_lockfile(toml: Dict(String, tom.Toml)) -> Lockfile {
  let entries = case tom.get_table(toml, ["widgets"]) {
    Ok(widgets_table) ->
      dict.fold(widgets_table, dict.new(), fn(acc, name, value) {
        case value {
          tom.Table(t) | tom.InlineTable(t) ->
            dict.insert(acc, name, parse_lock_entry(t))
          _ -> acc
        }
      })
    Error(_) -> dict.new()
  }
  Lockfile(entries)
}

fn parse_lock_entry(table: Dict(String, tom.Toml)) -> LockEntry {
  let version = tom.get_string(table, ["version"]) |> result.unwrap("")
  let hash = tom.get_string(table, ["hash"]) |> result.unwrap("")
  let content_id = tom.get_int(table, ["content_id"]) |> option.from_result
  let s3_id = tom.get_string(table, ["s3_id"]) |> option.from_result
  let classic = tom.get_bool(table, ["classic"]) |> result.unwrap(False)
  LockEntry(version, hash, content_id, s3_id, classic)
}

// ── 직렬화 ──

fn serialize_lockfile(entries: Dict(String, LockEntry)) -> String {
  let header = "# mxpak.lock — 자동 생성 파일, 직접 수정하지 마세요\n\n"
  let sorted =
    dict.to_list(entries)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

  let body =
    list.map(sorted, fn(pair) {
      let #(name, entry) = pair
      serialize_entry(name, entry)
    })
    |> string.join("\n")

  header <> body
}

fn serialize_entry(name: String, entry: LockEntry) -> String {
  let header = "[widgets." <> quote_key(name) <> "]\n"
  let lines = [
    "version = \"" <> entry.version <> "\"",
    "hash = \"" <> entry.hash <> "\"",
  ]
  let lines = case entry.content_id {
    Some(id) -> list.append(lines, ["content_id = " <> int.to_string(id)])
    None -> lines
  }
  let lines = case entry.s3_id {
    Some(s3) -> list.append(lines, ["s3_id = \"" <> s3 <> "\""])
    None -> lines
  }
  let lines = case entry.classic {
    True -> list.append(lines, ["classic = true"])
    False -> lines
  }
  header <> string.join(lines, "\n") <> "\n"
}

fn quote_key(name: String) -> String {
  case
    string.contains(name, " ")
    || string.contains(name, "-")
    || string.contains(name, ".")
  {
    True -> "\"" <> name <> "\""
    False -> name
  }
}
