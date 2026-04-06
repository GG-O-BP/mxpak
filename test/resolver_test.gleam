import gleam/order
import mxpak/resolver/constraint
import mxpak/resolver/version.{Version}

// === version 테스트 ===

pub fn parse_full_test() {
  let assert Ok(v) = version.parse("1.2.3")
  let assert True = v == Version(1, 2, 3)
}

pub fn parse_two_part_test() {
  let assert Ok(v) = version.parse("2.5")
  let assert True = v == Version(2, 5, 0)
}

pub fn parse_one_part_test() {
  let assert Ok(v) = version.parse("3")
  let assert True = v == Version(3, 0, 0)
}

pub fn parse_with_prerelease_test() {
  let assert Ok(v) = version.parse("1.0.0-beta")
  let assert True = v == Version(1, 0, 0)
}

pub fn parse_invalid_test() {
  let assert Error(Nil) = version.parse("abc")
}

pub fn compare_equal_test() {
  let assert Ok(a) = version.parse("1.2.3")
  let assert Ok(b) = version.parse("1.2.3")
  let assert True = version.compare(a, b) == order.Eq
}

pub fn compare_major_test() {
  let assert Ok(a) = version.parse("2.0.0")
  let assert Ok(b) = version.parse("1.9.9")
  let assert True = version.compare(a, b) == order.Gt
}

pub fn compare_minor_test() {
  let assert Ok(a) = version.parse("1.3.0")
  let assert Ok(b) = version.parse("1.2.9")
  let assert True = version.compare(a, b) == order.Gt
}

pub fn compare_patch_test() {
  let assert Ok(a) = version.parse("1.2.4")
  let assert Ok(b) = version.parse("1.2.3")
  let assert True = version.gt(a, b)
}

pub fn to_string_test() {
  let assert True = version.to_string(Version(1, 2, 3)) == "1.2.3"
}

pub fn latest_test() {
  let versions = [Version(1, 0, 0), Version(3, 1, 0), Version(2, 5, 0)]
  let assert Ok(best) = version.latest(versions)
  let assert True = best == Version(3, 1, 0)
}

pub fn latest_empty_test() {
  let assert Error(Nil) = version.latest([])
}

// === constraint 테스트 ===

pub fn parse_gte_test() {
  let assert Ok(c) = constraint.parse(">= 2.0.0")
  let assert Ok(v) = version.parse("2.5.0")
  let assert True = constraint.satisfies(c, v)
}

pub fn parse_lt_test() {
  let assert Ok(c) = constraint.parse("< 3.0.0")
  let assert Ok(v) = version.parse("2.9.9")
  let assert True = constraint.satisfies(c, v)
  let assert Ok(v3) = version.parse("3.0.0")
  let assert True = constraint.satisfies(c, v3) == False
}

pub fn parse_range_test() {
  let assert Ok(c) = constraint.parse(">= 2.0.0 and < 3.0.0")
  let assert Ok(v1) = version.parse("2.5.0")
  let assert Ok(v2) = version.parse("3.0.0")
  let assert Ok(v3) = version.parse("1.9.0")
  let assert True = constraint.satisfies(c, v1)
  let assert True = constraint.satisfies(c, v2) == False
  let assert True = constraint.satisfies(c, v3) == False
}

pub fn parse_exact_test() {
  let assert Ok(c) = constraint.parse("== 1.5.0")
  let assert Ok(v1) = version.parse("1.5.0")
  let assert Ok(v2) = version.parse("1.5.1")
  let assert True = constraint.satisfies(c, v1)
  let assert True = constraint.satisfies(c, v2) == False
}

pub fn parse_compatible_major_test() {
  // ~> 2.5 → >= 2.5.0 and < 3.0.0
  let assert Ok(c) = constraint.parse("~> 2.5")
  let assert Ok(v1) = version.parse("2.5.0")
  let assert Ok(v2) = version.parse("2.9.9")
  let assert Ok(v3) = version.parse("3.0.0")
  let assert True = constraint.satisfies(c, v1)
  let assert True = constraint.satisfies(c, v2)
  let assert True = constraint.satisfies(c, v3) == False
}

pub fn parse_compatible_minor_test() {
  // ~> 2.5.1 → >= 2.5.1 and < 2.6.0
  let assert Ok(c) = constraint.parse("~> 2.5.1")
  let assert Ok(v1) = version.parse("2.5.1")
  let assert Ok(v2) = version.parse("2.5.9")
  let assert Ok(v3) = version.parse("2.6.0")
  let assert True = constraint.satisfies(c, v1)
  let assert True = constraint.satisfies(c, v2)
  let assert True = constraint.satisfies(c, v3) == False
}

pub fn resolve_latest_test() {
  let assert Ok(c) = constraint.parse(">= 2.0.0 and < 3.0.0")
  let versions = [
    Version(1, 9, 0),
    Version(2, 1, 0),
    Version(2, 5, 0),
    Version(3, 0, 0),
  ]
  let assert Ok(best) = constraint.resolve_latest(c, versions)
  let assert True = best == Version(2, 5, 0)
}

pub fn any_constraint_test() {
  let c = constraint.any()
  let assert Ok(v) = version.parse("99.99.99")
  let assert True = constraint.satisfies(c, v)
}
