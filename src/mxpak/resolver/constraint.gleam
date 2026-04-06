// 버전 제약 조건 파서 — ">= 2.0 and < 3.0", "~> 2.28", "== 1.0.0"

import gleam/list
import gleam/result
import gleam/string
import mxpak/resolver/version.{type Version}

/// 단일 제약 조건
pub type Bound {
  Gte(Version)
  Gt(Version)
  Lte(Version)
  Lt(Version)
  Exact(Version)
  /// ~> 2.5 → >= 2.5.0 and < 3.0.0
  /// ~> 2.5.1 → >= 2.5.1 and < 2.6.0
  Compatible(Version)
}

/// 복합 제약 (AND로 결합)
pub type Constraint {
  Constraint(bounds: List(Bound))
}

/// 제약 조건 문자열 파싱
pub fn parse(str: String) -> Result(Constraint, Nil) {
  let parts =
    string.split(str, " and ")
    |> list.map(string.trim)
    |> list.filter(fn(s) { s != "" })

  use bounds <- result.try(try_map(parts, parse_single_bound))
  Ok(Constraint(bounds))
}

/// 버전이 제약 조건을 만족하는지 확인
pub fn satisfies(constraint: Constraint, v: Version) -> Bool {
  list.all(constraint.bounds, fn(bound) { check_bound(bound, v) })
}

/// 버전 목록에서 제약 조건을 만족하는 것만 필터
pub fn filter(constraint: Constraint, versions: List(Version)) -> List(Version) {
  list.filter(versions, fn(v) { satisfies(constraint, v) })
}

/// 제약 조건을 만족하는 최신 버전 선택
pub fn resolve_latest(
  constraint: Constraint,
  versions: List(Version),
) -> Result(Version, Nil) {
  filter(constraint, versions) |> version.latest
}

/// 와일드카드 제약 (모든 버전 허용)
pub fn any() -> Constraint {
  Constraint(bounds: [])
}

// ── 내부 구현 ──

fn parse_single_bound(str: String) -> Result(Bound, Nil) {
  let s = string.trim(str)
  case s {
    ">= " <> rest -> {
      use v <- try_parse_version(rest)
      Ok(Gte(v))
    }
    ">" <> rest -> {
      use v <- try_parse_version(string.trim(rest))
      Ok(Gt(v))
    }
    "<= " <> rest -> {
      use v <- try_parse_version(rest)
      Ok(Lte(v))
    }
    "< " <> rest -> {
      use v <- try_parse_version(rest)
      Ok(Lt(v))
    }
    "== " <> rest -> {
      use v <- try_parse_version(rest)
      Ok(Exact(v))
    }
    "~> " <> rest -> {
      use v <- try_parse_version(rest)
      Ok(Compatible(v))
    }
    _ -> {
      // 버전 번호만 있으면 정확 매치로 처리
      case version.parse(s) {
        Ok(v) -> Ok(Exact(v))
        Error(_) -> Error(Nil)
      }
    }
  }
}

fn try_parse_version(
  str: String,
  cont: fn(Version) -> Result(Bound, Nil),
) -> Result(Bound, Nil) {
  case version.parse(string.trim(str)) {
    Ok(v) -> cont(v)
    Error(_) -> Error(Nil)
  }
}

fn check_bound(bound: Bound, v: Version) -> Bool {
  case bound {
    Gte(min) -> version.gte(v, min)
    Gt(min) -> version.gt(v, min)
    Lte(max) -> version.lte(v, max)
    Lt(max) -> version.lt(v, max)
    Exact(target) -> version.eq(v, target)
    Compatible(base) -> check_compatible(base, v)
  }
}

/// ~> 호환 범위 계산
fn check_compatible(base: Version, v: Version) -> Bool {
  case base.patch {
    0 ->
      // ~> 2.5 → >= 2.5.0 and < 3.0.0
      version.gte(v, base) && v.major == base.major
    _ ->
      // ~> 2.5.1 → >= 2.5.1 and < 2.6.0
      version.gte(v, base) && v.major == base.major && v.minor == base.minor
  }
}

fn try_map(items: List(a), f: fn(a) -> Result(b, Nil)) -> Result(List(b), Nil) {
  list.try_map(items, f)
}
