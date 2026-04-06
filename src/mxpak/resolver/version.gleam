// Semantic Versioning 파싱 + 비교

import gleam/int
import gleam/list
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type Version {
  Version(major: Int, minor: Int, patch: Int)
}

/// 문자열 → Version 파싱
pub fn parse(str: String) -> Result(Version, Nil) {
  let clean = string.trim(str)
  let parts = string.split(clean, ".")
  case parts {
    [maj, min, pat] -> {
      use major <- result.try(int.parse(maj))
      use minor <- result.try(int.parse(min))
      // patch에 pre-release 접미사가 있을 수 있음 (예: "1-beta")
      let pat_str = case string.split_once(pat, "-") {
        Ok(#(p, _)) -> p
        Error(_) -> pat
      }
      use patch <- result.try(int.parse(pat_str))
      Ok(Version(major, minor, patch))
    }
    [maj, min] -> {
      use major <- result.try(int.parse(maj))
      use minor <- result.try(int.parse(min))
      Ok(Version(major, minor, 0))
    }
    [maj] -> {
      use major <- result.try(int.parse(maj))
      Ok(Version(major, 0, 0))
    }
    _ -> Error(Nil)
  }
}

/// Version → 문자열
pub fn to_string(v: Version) -> String {
  int.to_string(v.major)
  <> "."
  <> int.to_string(v.minor)
  <> "."
  <> int.to_string(v.patch)
}

/// 두 버전 비교
pub fn compare(a: Version, b: Version) -> Order {
  case int.compare(a.major, b.major) {
    Eq ->
      case int.compare(a.minor, b.minor) {
        Eq -> int.compare(a.patch, b.patch)
        other -> other
      }
    other -> other
  }
}

/// a >= b
pub fn gte(a: Version, b: Version) -> Bool {
  case compare(a, b) {
    Gt | Eq -> True
    Lt -> False
  }
}

/// a > b
pub fn gt(a: Version, b: Version) -> Bool {
  compare(a, b) == Gt
}

/// a <= b
pub fn lte(a: Version, b: Version) -> Bool {
  case compare(a, b) {
    Lt | Eq -> True
    Gt -> False
  }
}

/// a < b
pub fn lt(a: Version, b: Version) -> Bool {
  compare(a, b) == Lt
}

/// a == b
pub fn eq(a: Version, b: Version) -> Bool {
  compare(a, b) == Eq
}

/// 버전 목록에서 최신 버전 선택
pub fn latest(versions: List(Version)) -> Result(Version, Nil) {
  case versions {
    [] -> Error(Nil)
    [first, ..rest] ->
      Ok(
        list.fold(rest, first, fn(best, v) {
          case compare(v, best) {
            Gt -> v
            _ -> best
          }
        }),
      )
  }
}
