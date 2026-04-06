// 구조화 출력 — subprocess 통신 + 사람 읽기용 진행 메시지

import gleam/io
import gleam/json

const result_marker = "---MXP_RESULT---"

/// stderr에 진행 메시지 출력 (사람 읽기용)
pub fn log(message: String) -> Nil {
  io.println_error(message)
}

/// stdout에 JSON 결과 출력 (subprocess 통신용)
pub fn result_ok(widgets: json.Json) -> Nil {
  let payload = json.object([#("ok", json.bool(True)), #("widgets", widgets)])
  io.println(result_marker)
  io.println(json.to_string(payload))
}

/// stdout에 에러 결과 출력
pub fn result_error(message: String) -> Nil {
  let payload =
    json.object([
      #("ok", json.bool(False)),
      #("error", json.string(message)),
    ])
  io.println(result_marker)
  io.println(json.to_string(payload))
}
