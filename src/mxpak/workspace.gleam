// 워크스페이스 관리 — 설정 읽기, 프로젝트 목록, 루트 검증
// 여러 Mendix 프로젝트의 공통 파일을 CAS + 하드 링크로 중복제거

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

/// 워크스페이스 설정 읽기 — 파일 없으면 기본값
pub fn read_config(root: String) -> Result(WorkspaceConfig, String) {
  let config_path = root <> "/.mxpak-workspace.toml"
  case simplifile.is_file(config_path) {
    Ok(True) -> parse_config(root, config_path)
    _ -> Ok(default_config(root))
  }
}

/// 단일 Mendix 프로젝트 디렉토리 여부 — *.mpr 파일 존재로 판별
pub fn is_mendix_project_dir(root: String) -> Bool {
  case simplifile.read_directory(root) {
    Ok(entries) ->
      list.any(entries, fn(name) { string.ends_with(name, ".mpr") })
    Error(_) -> False
  }
}

/// 스캔 대상 프로젝트 자동 감지
/// - root 자체가 Mendix 프로젝트(*.mpr 포함) → [root] 단독
/// - 아니면 root 하위 1단계 중 *.mpr 가진 디렉토리들
pub fn discover_projects(root: String) -> Result(List(String), String) {
  case is_mendix_project_dir(root) {
    True -> Ok([root])
    False -> {
      use entries <- result.try(
        simplifile.read_directory(root)
        |> result.map_error(fn(_) { "디렉토리 읽기 실패: " <> root }),
      )
      let projects =
        list.filter_map(entries, fn(name) {
          let path = root <> "/" <> name
          case string.starts_with(name, ".") {
            True -> Error(Nil)
            False ->
              case simplifile.is_directory(path) {
                Ok(True) ->
                  case is_mendix_project_dir(path) {
                    True -> Ok(path)
                    False -> Error(Nil)
                  }
                _ -> Error(Nil)
              }
          }
        })
      Ok(projects)
    }
  }
}


// ── 내부 ──

import gleam/list

fn default_config(root: String) -> WorkspaceConfig {
  WorkspaceConfig(
    root: root,
    // 확장자 기반: 위젯(*.mpk) + 라이브러리(*.jar)
    // install 받은 위젯은 이미 CAS+하드링크 상태라 scan은 사실상 no-op,
    // Studio Pro가 직접 배치한 위젯은 scan이 처음으로 흡수 → 절감 발생.
    include: ["*.mpk", "*.jar"],
    // 디렉토리 기반 — Mendix 표준 테마 자산 (확장자 무관 전체 스캔)
    include_dirs: ["themesource"],
    exclude_dirs: [
      ".git", ".svn",
      ".mendix-cache", "theme-cache",
      "deployment", "mprcontents",
      "releases", "resources",
      "javascriptsource", "javasource", "mlsource", "modules",
      "theme",
      "node_modules",
    ],
  )
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
