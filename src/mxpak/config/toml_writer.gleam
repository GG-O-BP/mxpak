// gleam.toml 위젯 섹션 쓰기 — 기존 파일 내용을 보존하며 섹션/키 업데이트

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// gleam.toml에 위젯 정보 기록 (기존 내용 보존)
pub fn write_widget(
  project_root: String,
  name: String,
  version: String,
  content_id: Option(Int),
  s3_id: Option(String),
) -> Result(Nil, String) {
  let toml_path = project_root <> "/gleam.toml"
  use content <- result.try(
    simplifile.read(toml_path)
    |> result.map_error(fn(_) { "gleam.toml 읽기 실패" }),
  )

  let section_header = "[tools.mendraw.widgets." <> quote_key(name) <> "]"
  let entries =
    [#("version", quote_string(version))]
    |> append_opt(content_id, fn(id) { #("id", int.to_string(id)) })
    |> append_opt(s3_id, fn(s) { #("s3_id", quote_string(s)) })

  let new_content = case string.contains(content, section_header) {
    True ->
      list.fold(entries, content, fn(acc, entry) {
        update_key_in_section(acc, section_header, entry.0, entry.1)
      })
    False -> {
      let section_lines =
        list.map(entries, fn(e) { e.0 <> " = " <> e.1 })
        |> string.join("\n")
      let insertion = "\n\n" <> section_header <> "\n" <> section_lines <> "\n"
      // 기존 [tools.mendraw.widgets.*] 섹션 뒤에 삽입
      insert_after_mendraw_section(content, insertion)
    }
  }

  simplifile.write(toml_path, new_content)
  |> result.map_error(fn(_) { "gleam.toml 쓰기 실패" })
}

/// 위젯 섹션 제거
pub fn remove_widget(project_root: String, name: String) -> Result(Nil, String) {
  let toml_path = project_root <> "/gleam.toml"
  use content <- result.try(
    simplifile.read(toml_path)
    |> result.map_error(fn(_) { "gleam.toml 읽기 실패" }),
  )

  let section_header = "[tools.mendraw.widgets." <> quote_key(name) <> "]"
  let new_content = remove_section(content, section_header)

  simplifile.write(toml_path, new_content)
  |> result.map_error(fn(_) { "gleam.toml 쓰기 실패" })
}

/// meta.toml 쓰기 (build/widgets/{name}/meta.toml)
pub fn write_meta_toml(
  path: String,
  version: String,
  id: Option(Int),
  classic: Bool,
) -> Result(Nil, String) {
  let lines = ["version = " <> quote_string(version)]
  let lines = case id {
    Some(i) -> list.append(lines, ["id = " <> int.to_string(i)])
    None -> lines
  }
  let lines = case classic {
    True -> list.append(lines, ["classic = true"])
    False -> lines
  }

  simplifile.write(path, string.join(lines, "\n") <> "\n")
  |> result.map_error(fn(_) { "meta.toml 쓰기 실패: " <> path })
}

// ── 내부 헬퍼 ──

/// TOML 키에 특수문자가 있으면 따옴표로 감쌈
pub fn quote_key(name: String) -> String {
  case
    string.contains(name, " ")
    || string.contains(name, "-")
    || string.contains(name, ".")
  {
    True -> "\"" <> name <> "\""
    False -> name
  }
}

fn quote_string(value: String) -> String {
  "\"" <> value <> "\""
}

/// 섹션 내 특정 키의 값을 업데이트 (없으면 섹션 끝에 추가)
fn update_key_in_section(
  content: String,
  section_header: String,
  key: String,
  value: String,
) -> String {
  let lines = string.split(content, "\n")
  let new_line = key <> " = " <> value

  let #(result_lines, _, found_key) =
    list.fold(lines, #([], False, False), fn(state, line) {
      let #(acc, in_section, key_found) = state
      let trimmed = string.trim(line)
      case in_section {
        False ->
          case trimmed == section_header {
            True -> #([line, ..acc], True, key_found)
            False -> #([line, ..acc], False, key_found)
          }
        True ->
          case string.starts_with(trimmed, "[") {
            True -> {
              // 섹션 끝 도달. 키를 못 찾았으면 여기에 삽입
              case key_found {
                True -> #([line, ..acc], False, key_found)
                False -> #([line, new_line, ..acc], False, True)
              }
            }
            False ->
              case
                string.starts_with(trimmed, key <> " ")
                || string.starts_with(trimmed, key <> "=")
              {
                True -> #([new_line, ..acc], True, True)
                False -> #([line, ..acc], True, key_found)
              }
          }
      }
    })

  // 파일 끝에 도달했지만 키를 못 찾은 경우
  let final_lines = case found_key {
    True -> result_lines
    False -> [new_line, ..result_lines]
  }

  list.reverse(final_lines) |> string.join("\n")
}

/// [tools.mendraw.*] 섹션 뒤에 새 블록을 삽입
fn insert_after_mendraw_section(content: String, block: String) -> String {
  let lines = string.split(content, "\n")
  let last_mendraw_idx = find_last_mendraw_line(lines, 0, -1, False)

  case last_mendraw_idx >= 0 {
    True -> {
      let #(before, after) = list_split_at(lines, last_mendraw_idx + 1)
      string.join(before, "\n") <> block <> string.join(after, "\n")
    }
    False -> content <> block
  }
}

fn find_last_mendraw_line(
  lines: List(String),
  idx: Int,
  last: Int,
  in_mendraw: Bool,
) -> Int {
  case lines {
    [] -> last
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case string.starts_with(trimmed, "[tools.mendraw") {
        True -> find_last_mendraw_line(rest, idx + 1, idx, True)
        False ->
          case in_mendraw && !string.starts_with(trimmed, "[") {
            True -> find_last_mendraw_line(rest, idx + 1, idx, True)
            False ->
              case in_mendraw {
                True -> find_last_mendraw_line(rest, idx + 1, last, False)
                False -> find_last_mendraw_line(rest, idx + 1, last, False)
              }
          }
      }
    }
  }
}

/// 섹션 전체 제거 (헤더 + 그 아래 키들)
fn remove_section(content: String, section_header: String) -> String {
  let lines = string.split(content, "\n")
  let #(result_lines, _) =
    list.fold(lines, #([], False), fn(state, line) {
      let #(acc, skipping) = state
      let trimmed = string.trim(line)
      case skipping {
        True ->
          case string.starts_with(trimmed, "[") {
            True -> #([line, ..acc], False)
            False -> #(acc, True)
          }
        False ->
          case trimmed == section_header {
            True -> #(acc, True)
            False -> #([line, ..acc], False)
          }
      }
    })
  list.reverse(result_lines) |> string.join("\n")
}

fn append_opt(
  entries: List(#(String, String)),
  opt: Option(a),
  to_entry: fn(a) -> #(String, String),
) -> List(#(String, String)) {
  case opt {
    Some(v) -> list.append(entries, [to_entry(v)])
    None -> entries
  }
}

fn list_split_at(items: List(a), at: Int) -> #(List(a), List(a)) {
  list_split_at_acc(items, at, [])
}

fn list_split_at_acc(
  items: List(a),
  at: Int,
  acc: List(a),
) -> #(List(a), List(a)) {
  case at <= 0 || items == [] {
    True -> #(list.reverse(acc), items)
    False ->
      case items {
        [] -> #(list.reverse(acc), [])
        [x, ..rest] -> list_split_at_acc(rest, at - 1, [x, ..acc])
      }
  }
}
