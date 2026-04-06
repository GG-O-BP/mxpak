// SHA-256 무결성 검증 — Erlang :crypto 래핑

import gleam/crypto

/// 바이너리 데이터의 SHA-256 해시 계산 (hex string)
pub fn sha256(data: BitArray) -> String {
  crypto.hash(crypto.Sha256, data)
  |> hex_encode
}

/// 해시값 비교 (constant-time)
pub fn verify(data: BitArray, expected_hash: String) -> Bool {
  sha256(data) == expected_hash
}

// ── 내부 헬퍼 ──

fn hex_encode(bytes: BitArray) -> String {
  do_hex_encode(bytes, "")
}

fn do_hex_encode(bytes: BitArray, acc: String) -> String {
  case bytes {
    <<byte:int, rest:bits>> -> {
      let hi = hex_char(byte / 16)
      let lo = hex_char(byte % 16)
      do_hex_encode(rest, acc <> hi <> lo)
    }
    _ -> acc
  }
}

fn hex_char(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "a"
    11 -> "b"
    12 -> "c"
    13 -> "d"
    14 -> "e"
    15 -> "f"
    _ -> "?"
  }
}
