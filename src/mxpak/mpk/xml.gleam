// 위젯 XML 파싱 — 이름/속성/경로 추출 (Erlang regexp)

import gleam/list
import gleam/option.{Some}
import gleam/regexp
import gleam/string

/// 위젯 속성 정보
pub type WidgetProperty {
  WidgetProperty(key: String, required: Bool)
}

/// XML에서 <name>...</name> 추출
pub fn parse_widget_name(xml: String) -> Result(String, Nil) {
  let assert Ok(re) = regexp.from_string("<name>([^<]+)</name>")
  case regexp.scan(re, xml) {
    [match, ..] ->
      case match.submatches {
        [Some(name), ..] -> Ok(name)
        _ -> Error(Nil)
      }
    [] -> Error(Nil)
  }
}

/// package.xml에서 모든 widgetFile path 추출
pub fn extract_widget_file_paths(package_xml: String) -> List(String) {
  let assert Ok(re) = regexp.from_string("widgetFile\\s+path=\"([^\"]+)\"")
  regexp.scan(re, package_xml)
  |> list.filter_map(fn(match) {
    case match.submatches {
      [Some(path), ..] -> Ok(path)
      _ -> Error(Nil)
    }
  })
}

/// 위젯 XML에서 속성 정보 파싱 (key, required)
pub fn parse_properties(widget_xml: String) -> List(WidgetProperty) {
  let assert Ok(re) = regexp.from_string("<property\\s+([^>]*?)\\s*(?:/>|>)")
  regexp.scan(re, widget_xml)
  |> list.filter_map(fn(match) {
    case match.submatches {
      [Some(attrs), ..] -> parse_property_attrs(attrs)
      _ -> Error(Nil)
    }
  })
}

/// 위젯 이름을 유효한 식별자로 변환 ("Progress Bar" → "ProgressBar")
pub fn to_safe_identifier(name: String) -> String {
  string.to_graphemes(name)
  |> list.filter(fn(ch) { is_alnum_or_underscore(ch) })
  |> string.concat
}

/// 위젯 이름 → 모듈 파일명 ("Progress Bar" → "progress_bar")
pub fn to_module_file_name(name: String) -> String {
  name
  |> string.replace(" ", "_")
  |> camel_to_snake
  |> string.lowercase
}

/// camelCase → snake_case
pub fn to_snake_case(str: String) -> String {
  camel_to_snake(str) |> string.lowercase
}

/// Gleam 예약어 회피
pub fn to_gleam_var(key: String) -> String {
  let snake = to_snake_case(key)
  case is_gleam_keyword(snake) {
    True -> snake <> "_"
    False -> snake
  }
}

// ── 내부 헬퍼 ──

fn parse_property_attrs(attrs: String) -> Result(WidgetProperty, Nil) {
  let assert Ok(key_re) = regexp.from_string("key=\"([^\"]+)\"")
  case regexp.scan(key_re, attrs) {
    [key_match, ..] ->
      case key_match.submatches {
        [Some(key), ..] -> {
          let assert Ok(req_re) = regexp.from_string("required=\"([^\"]+)\"")
          let required = case regexp.scan(req_re, attrs) {
            [req_match, ..] ->
              case req_match.submatches {
                [Some("true"), ..] -> True
                _ -> False
              }
            [] -> False
          }
          Ok(WidgetProperty(key: key, required: required))
        }
        _ -> Error(Nil)
      }
    [] -> Error(Nil)
  }
}

fn camel_to_snake(str: String) -> String {
  let assert Ok(re1) = regexp.from_string("([a-z0-9])([A-Z])")
  let assert Ok(re2) = regexp.from_string("([A-Z])([A-Z][a-z])")
  str
  |> regexp.replace(each: re1, with: "\\1_\\2")
  |> regexp.replace(each: re2, with: "\\1_\\2")
}

fn is_alnum_or_underscore(ch: String) -> Bool {
  case ch {
    "_" | "$" -> True
    _ -> {
      let assert Ok(re) = regexp.from_string("^[a-zA-Z0-9]$")
      regexp.check(re, ch)
    }
  }
}

const gleam_keywords = [
  "as", "assert", "auto", "case", "const", "delegate", "derive", "echo", "else",
  "fn", "if", "implement", "import", "let", "macro", "opaque", "panic", "pub",
  "return", "test", "todo", "type", "use",
]

fn is_gleam_keyword(word: String) -> Bool {
  list.contains(gleam_keywords, word)
}
