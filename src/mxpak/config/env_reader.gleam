// .env 파일 + 환경변수에서 설정 값 읽기
// 우선순위: 환경변수 > .env 파일

import envoy
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile

/// 환경변수 → .env 파일 순으로 값 조회
pub fn get(key: String, project_root: String) -> Option(String) {
  case envoy.get(key) {
    Ok(val) -> Some(val)
    Error(_) -> read_from_dotenv(key, project_root)
  }
}

/// .env 파일에서 key=value 형태로 값 읽기
fn read_from_dotenv(key: String, project_root: String) -> Option(String) {
  case simplifile.read(project_root <> "/.env") {
    Error(_) -> None
    Ok(content) ->
      string.split(content, "\n")
      |> list.find_map(fn(line) {
        let trimmed = string.trim(line)
        case trimmed == "" || string.starts_with(trimmed, "#") {
          True -> Error(Nil)
          False ->
            case string.split_once(trimmed, "=") {
              Ok(#(k, v)) ->
                case string.trim(k) == key {
                  True ->
                    Ok(
                      string.trim(v)
                      |> strip_quotes,
                    )
                  False -> Error(Nil)
                }
              _ -> Error(Nil)
            }
        }
      })
      |> option.from_result
  }
}

fn strip_quotes(s: String) -> String {
  s
  |> string.replace("\"", "")
  |> string.replace("'", "")
}
