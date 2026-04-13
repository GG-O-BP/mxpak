// CLI 인자 파싱 + 도움말

import gleam/io

/// 버전 인자: 지정 또는 미지정
pub type VersionArg {
  VersionSpecified(String)
  VersionLatest
}

/// 파싱된 CLI 명령
pub type Command {
  Install(project_root: String)
  Marketplace(project_root: String)
  Add(name: String, version: VersionArg)
  Remove(name: String)
  Update(name: String)
  Outdated(project_root: String)
  List(project_root: String)
  Info(name: String)
  Audit(project_root: String)
  CacheClean
  Init(path: String)
  Scan(path: String)
  Status(path: String)
  Version
  Help
  Unknown(cmd: String)
}

/// CLI 인자를 Command로 파싱
pub fn parse(args: List(String)) -> Command {
  case args {
    [] -> Help
    ["--version"] | ["-v"] -> Version
    ["--help"] | ["-h"] -> Help
    ["install"] -> Install(".")
    ["install", root] -> Install(root)
    ["marketplace"] -> Marketplace(".")
    ["marketplace", root] -> Marketplace(root)
    ["add", name] -> Add(name, VersionLatest)
    ["add", name, "--version", v] -> Add(name, VersionSpecified(v))
    ["remove", name] -> Remove(name)
    ["update"] -> Update("")
    ["update", name] -> Update(name)
    ["outdated"] -> Outdated(".")
    ["outdated", root] -> Outdated(root)
    ["list"] -> List(".")
    ["list", root] -> List(root)
    ["info", name] -> Info(name)
    ["audit"] -> Audit(".")
    ["audit", root] -> Audit(root)
    ["cache", "clean"] -> CacheClean
    ["init"] -> Init("")
    ["init", path] -> Init(path)
    ["scan"] -> Scan("")
    ["scan", path] -> Scan(path)
    ["status"] -> Status("")
    ["status", path] -> Status(path)
    [cmd, ..] -> Unknown(cmd)
  }
}

/// 도움말 출력
pub fn print_help() -> Nil {
  io.println(
    "mxpak — Mendix 위젯/공통파일 패키지매니저

사용법: mxp <command> [options]

명령어:
  install [project_root]           위젯 설치 (락파일 우선, 없으면 해결)
  add <name> [--version <v>]       위젯 추가
  remove <name>                    위젯 제거
  update [name]                    위젯 업데이트
  marketplace [project_root]       Marketplace TUI 브라우저
  outdated [project_root]          업데이트 가능한 위젯 목록
  list [project_root]              설치된 위젯 목록
  info <name>                      위젯 상세 정보
  audit [project_root]             무결성 검증 (SHA-256)
  cache clean                      글로벌 캐시 정리

워크스페이스:
  init [path]                      워크스페이스 초기화 (기본: 현재 디렉토리)
  scan [path]                      파일 스캔 + 중복제거 (CAS + 하드 링크)
  status [path]                    중복제거 상태 + 절감량 표시

옵션:
  --version, -v                    버전 출력
  --help, -h                       도움말",
  )
}
