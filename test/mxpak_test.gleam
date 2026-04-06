import gleeunit
import mxpak/cli

pub fn main() -> Nil {
  gleeunit.main()
}

// === CLI 인자 파싱 테스트 ===

pub fn parse_empty_test() {
  let assert cli.Help = cli.parse([])
}

pub fn parse_version_test() {
  let assert cli.Version = cli.parse(["--version"])
}

pub fn parse_version_short_test() {
  let assert cli.Version = cli.parse(["-v"])
}

pub fn parse_help_test() {
  let assert cli.Help = cli.parse(["--help"])
}

pub fn parse_install_default_test() {
  let assert cli.Install(".") = cli.parse(["install"])
}

pub fn parse_install_with_root_test() {
  let assert cli.Install("/some/path") = cli.parse(["install", "/some/path"])
}

pub fn parse_marketplace_default_test() {
  let assert cli.Marketplace(".") = cli.parse(["marketplace"])
}

pub fn parse_add_name_only_test() {
  let assert cli.Add("DataGrid", cli.VersionLatest) =
    cli.parse(["add", "DataGrid"])
}

pub fn parse_add_with_version_test() {
  let assert cli.Add("DataGrid", cli.VersionSpecified("2.0.0")) =
    cli.parse(["add", "DataGrid", "--version", "2.0.0"])
}

pub fn parse_remove_test() {
  let assert cli.Remove("DataGrid") = cli.parse(["remove", "DataGrid"])
}

pub fn parse_update_all_test() {
  let assert cli.Update("") = cli.parse(["update"])
}

pub fn parse_update_specific_test() {
  let assert cli.Update("DataGrid") = cli.parse(["update", "DataGrid"])
}

pub fn parse_cache_clean_test() {
  let assert cli.CacheClean = cli.parse(["cache", "clean"])
}

pub fn parse_unknown_test() {
  let assert cli.Unknown("foo") = cli.parse(["foo"])
}

pub fn parse_audit_default_test() {
  let assert cli.Audit(".") = cli.parse(["audit"])
}

pub fn parse_list_default_test() {
  let assert cli.List(".") = cli.parse(["list"])
}

pub fn parse_info_test() {
  let assert cli.Info("Charts") = cli.parse(["info", "Charts"])
}
