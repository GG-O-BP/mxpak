// 워크스페이스 관리 — 초기화, 설정, 기본 경로
// ~/mendix-workspaces/ 하위 프로젝트의 공통 파일을 CAS + 하드 링크로 중복제거

import gleam/result
import gleam/string
import simplifile

/// 워크스페이스 설정
pub type WorkspaceConfig {
  WorkspaceConfig(
    root: String,
    include: List(String),
    include_dirs: List(String),
    exclude_dirs: List(String),
  )
}

/// 워크스페이스 초기화 — 디렉토리 + 설정 파일 생성
pub fn init(root: String) -> Result(Nil, String) {
  use _ <- result.try(
    simplifile.create_directory_all(root)
    |> result.map_error(fn(_) { "워크스페이스 디렉토리 생성 실패: " <> root }),
  )
  let config_path = root <> "/.mxpak-workspace.toml"
  case simplifile.is_file(config_path) {
    Ok(True) -> Ok(Nil)
    _ ->
      simplifile.write(config_path, default_config_toml())
      |> result.map_error(fn(_) { "설정 파일 생성 실패" })
  }
}

/// 워크스페이스 설정 읽기
pub fn read_config(root: String) -> Result(WorkspaceConfig, String) {
  let config_path = root <> "/.mxpak-workspace.toml"
  case simplifile.is_file(config_path) {
    Ok(True) -> parse_config(root, config_path)
    _ -> Ok(default_config(root))
  }
}

/// 프로젝트 디렉토리 목록 수집 (워크스페이스 하위 1단계)
pub fn list_projects(root: String) -> Result(List(String), String) {
  use entries <- result.try(
    simplifile.read_directory(root)
    |> result.map_error(fn(_) { "워크스페이스 디렉토리 읽기 실패: " <> root }),
  )
  Ok(
    list_filter_map(entries, fn(name) {
      let path = root <> "/" <> name
      // 숨김 디렉토리(. 접두사) 제외
      case string.starts_with(name, ".") {
        True -> Error(Nil)
        False ->
          case simplifile.is_directory(path) {
            Ok(True) -> Ok(path)
            _ -> Error(Nil)
          }
      }
    }),
  )
}

// ── 내부 ──

import gleam/list

fn list_filter_map(
  items: List(a),
  f: fn(a) -> Result(b, Nil),
) -> List(b) {
  list.filter_map(items, f)
}

fn default_config(root: String) -> WorkspaceConfig {
  WorkspaceConfig(
    root: root,
    // 확장자 기반 — install이 손대지 않는 라이브러리
    include: ["*.jar"],
    // 디렉토리 기반 — Mendix 표준 테마 자산 (확장자 무관 전체 스캔)
    include_dirs: ["themesource"],
    exclude_dirs: [
      ".git", ".svn",
      ".mendix-cache", "theme-cache",
      "deployment", "mprcontents",
      "releases", "resources",
      "javascriptsource", "javasource", "mlsource", "modules",
      "theme",
      // widgets는 mxp install이 CAS+하드링크로 일원 관리
      "widgets",
      "node_modules",
    ],
  )
}

fn default_config_toml() -> String {
  "# mxpak 워크스페이스 설정 — 자동 생성
# widgets/*.mpk 는 mxp install 이 CAS+하드링크로 관리 — scan 대상 아님
[workspace]
version = \"0.1.0\"

[scan]
# 확장자 기반 — install 이 손대지 않는 라이브러리
include = [\"*.jar\"]

# 디렉토리 기반 — Mendix 표준 테마 자산 (확장자 무관, 하위 전체 스캔)
include_dirs = [\"themesource\"]

# 제외 디렉토리 — 빌드 아티팩트 / 프로젝트 고유 코드 / install 관리 영역
exclude_dirs = [
  \".git\", \".svn\",
  \".mendix-cache\", \"theme-cache\",
  \"deployment\", \"mprcontents\",
  \"releases\", \"resources\",
  \"javascriptsource\", \"javasource\", \"mlsource\", \"modules\",
  \"theme\",
  \"widgets\",
  \"node_modules\",
]
"
}

fn parse_config(
  root: String,
  config_path: String,
) -> Result(WorkspaceConfig, String) {
  use content <- result.try(
    simplifile.read(config_path)
    |> result.map_error(fn(_) { "설정 파일 읽기 실패: " <> config_path }),
  )
  use parsed <- result.try(
    tom.parse(content)
    |> result.map_error(fn(_) { "설정 파일 파싱 실패" }),
  )

  let include = case tom.get_array(parsed, ["scan", "include"]) {
    Ok(arr) -> list.filter_map(arr, fn(v) {
      case v {
        tom.String(s) -> Ok(s)
        _ -> Error(Nil)
      }
    })
    Error(_) -> default_config(root).include
  }

  let include_dirs = case tom.get_array(parsed, ["scan", "include_dirs"]) {
    Ok(arr) -> list.filter_map(arr, fn(v) {
      case v {
        tom.String(s) -> Ok(s)
        _ -> Error(Nil)
      }
    })
    Error(_) -> default_config(root).include_dirs
  }

  let exclude_dirs = case tom.get_array(parsed, ["scan", "exclude_dirs"]) {
    Ok(arr) -> list.filter_map(arr, fn(v) {
      case v {
        tom.String(s) -> Ok(s)
        _ -> Error(Nil)
      }
    })
    Error(_) -> default_config(root).exclude_dirs
  }

  Ok(WorkspaceConfig(
    root: root,
    include: include,
    include_dirs: include_dirs,
    exclude_dirs: exclude_dirs,
  ))
}

import tom
