// 위젯 해결 오케스트레이터 — TOML 읽기 → API 조회 → 버전 선택 → 다운로드

import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mxpak/cache
import mxpak/config
import mxpak/config/toml_reader.{type MendrawConfig, type WidgetConfig}
import mxpak/downloader
import mxpak/lockfile.{type Lockfile}
import mxpak/mpk/metadata
import mxpak/registry/content_api
import mxpak/session
import simplifile

/// 해결 결과 (위젯별)
pub type ResolveResult {
  ResolveResult(
    name: String,
    version: String,
    content_id: Option(Int),
    s3_id: Option(String),
    hash: String,
    classic: Bool,
  )
}

/// gleam.toml 기반 전체 위젯 해결 + 다운로드
pub fn resolve_all(project_root: String) -> Result(List(ResolveResult), String) {
  use cfg <- result.try(config.read(project_root))
  let pat = config.get_pat(project_root)

  case cfg.mode {
    "mpk" -> resolve_all_mpk(project_root, cfg, pat)
    _ -> resolve_all_extract(project_root, cfg, pat)
  }
}

// ── extract 모드 (기존 동작) ──

fn resolve_all_extract(
  project_root: String,
  cfg: MendrawConfig,
  pat: Option(String),
) -> Result(List(ResolveResult), String) {
  cleanup_stale_widgets(project_root, cfg.widgets |> dict.keys)

  let widget_list = dict.to_list(cfg.widgets)
  case widget_list {
    [] -> {
      io.println_error("설치할 위젯 없음")
      Ok([])
    }
    _ ->
      list.try_fold(widget_list, [], fn(acc, pair) {
        let #(name, widget) = pair
        case resolve_single(project_root, name, widget, pat) {
          Ok(result) -> Ok([result, ..acc])
          Error(msg) -> {
            io.println_error("경고: " <> name <> " — " <> msg)
            Ok(acc)
          }
        }
      })
  }
}

// ── mpk 모드 ──

fn resolve_all_mpk(
  project_root: String,
  cfg: MendrawConfig,
  pat: Option(String),
) -> Result(List(ResolveResult), String) {
  let widgets_dir = project_root <> "/" <> cfg.widgets_dir
  let _ = simplifile.create_directory_all(widgets_dir)

  let lock = case lockfile.read(project_root) {
    Ok(l) -> Some(l)
    Error(_) -> None
  }

  let widget_list = dict.to_list(cfg.widgets)
  case widget_list {
    [] -> {
      io.println_error("설치할 위젯 없음")
      Ok([])
    }
    _ ->
      list.try_fold(widget_list, [], fn(acc, pair) {
        let #(name, widget) = pair
        case resolve_single_mpk(widgets_dir, project_root, name, widget, pat, lock)
        {
          Ok(result) -> Ok([result, ..acc])
          Error(msg) -> {
            io.println_error("경고: " <> name <> " — " <> msg)
            Ok(acc)
          }
        }
      })
  }
}

fn resolve_single_mpk(
  widgets_dir: String,
  project_root: String,
  name: String,
  widget: WidgetConfig,
  pat: Option(String),
  lock: Option(Lockfile),
) -> Result(ResolveResult, String) {
  let target_path = widgets_dir <> "/" <> name <> ".mpk"

  case widget.version {
    "" -> Error("version이 지정되지 않았습니다")
    version -> {
      // 락파일 + 파일 존재 확인
      case check_mpk_installed(target_path, name, version, lock) {
        Ok(result) -> {
          io.println_error(name <> " v" <> version <> " — 이미 설치됨")
          Ok(result)
        }
        Error(_) ->
          case widget.s3_id {
            Some(s3_id) ->
              download_mpk_with_s3(
                target_path,
                name,
                version,
                widget.id,
                s3_id,
              )
            None ->
              resolve_mpk_via_api(
                target_path,
                project_root,
                name,
                version,
                widget.id,
                pat,
              )
          }
      }
    }
  }
}

fn check_mpk_installed(
  target_path: String,
  name: String,
  version: String,
  lock: Option(Lockfile),
) -> Result(ResolveResult, String) {
  case simplifile.is_file(target_path) {
    Ok(True) ->
      case lock {
        Some(lf) ->
          case lockfile.get_entry(lf, name) {
            Ok(entry) ->
              case entry.version == version {
                True ->
                  Ok(ResolveResult(
                    name: name,
                    version: version,
                    content_id: entry.content_id,
                    s3_id: entry.s3_id,
                    hash: entry.hash,
                    classic: entry.classic,
                  ))
                False -> Error("버전 불일치")
              }
            Error(_) -> Error("락파일 엔트리 없음")
          }
        None -> Error("락파일 없음")
      }
    _ -> {
      // 파일은 없지만 락파일에 해시가 있으면 캐시에서 복원 시도
      case lock {
        Some(lf) ->
          case lockfile.get_entry(lf, name) {
            Ok(entry) ->
              case entry.version == version && entry.hash != "" {
                True ->
                  case cache.restore_mpk(entry.hash, target_path) {
                    Ok(_) -> {
                      io.println_error(name <> " v" <> version <> " — 캐시에서 복원")
                      Ok(ResolveResult(
                        name: name,
                        version: version,
                        content_id: entry.content_id,
                        s3_id: entry.s3_id,
                        hash: entry.hash,
                        classic: entry.classic,
                      ))
                    }
                    Error(_) -> Error("캐시 복원 실패")
                  }
                False -> Error("버전 불일치")
              }
            Error(_) -> Error("락파일 엔트리 없음")
          }
        None -> Error("파일 없음")
      }
    }
  }
}

fn download_mpk_with_s3(
  target_path: String,
  name: String,
  version: String,
  content_id: Option(Int),
  s3_id: String,
) -> Result(ResolveResult, String) {
  let url = "https://files.appstore.mendix.com/" <> s3_id
  use dl <- result.try(downloader.download_mpk(
    url,
    name,
    version,
    content_id,
    target_path,
  ))
  Ok(ResolveResult(
    name: name,
    version: version,
    content_id: content_id,
    s3_id: Some(s3_id),
    hash: dl.hash,
    classic: dl.classic,
  ))
}

fn resolve_mpk_via_api(
  target_path: String,
  project_root: String,
  name: String,
  version: String,
  content_id: Option(Int),
  pat: Option(String),
) -> Result(ResolveResult, String) {
  use pat_val <- require_pat(pat)

  use cid <- result.try(case content_id {
    Some(id) -> Ok(id)
    None -> {
      use page <- result.try(content_api.fetch_content_page(pat_val, 0, 40))
      case list.find(page.widgets, fn(w) { w.name == Some(name) }) {
        Ok(w) -> {
          let _ =
            config.write_widget(
              project_root,
              name,
              version,
              Some(w.content_id),
              None,
            )
          Ok(w.content_id)
        }
        Error(_) -> Error("'" <> name <> "' 위젯을 찾을 수 없습니다")
      }
    }
  })

  use _ <- result.try(session.ensure_session())

  use xas_versions <- result.try(
    mxpak_browser_get_versions(cid)
    |> result.map_error(fn(_) { "XAS 버전 수집 실패" }),
  )

  case list.find(xas_versions, fn(xas) { xas.version_number == version }) {
    Ok(xas) -> {
      let _ =
        config.write_widget(
          project_root,
          name,
          version,
          Some(cid),
          Some(xas.s3_object_id),
        )
      download_mpk_with_s3(
        target_path,
        name,
        version,
        Some(cid),
        xas.s3_object_id,
      )
    }
    Error(_) ->
      Error(
        "v"
        <> version
        <> " s3_id를 찾을 수 없습니다 (id="
        <> int.to_string(cid)
        <> ")",
      )
  }
}

// ── 단일 위젯 해결 ──

fn resolve_single(
  project_root: String,
  name: String,
  widget: WidgetConfig,
  pat: Option(String),
) -> Result(ResolveResult, String) {
  case widget.version {
    "" -> Error("version이 지정되지 않았습니다")
    version -> {
      // 캐시 확인
      case check_cache(project_root, name, version) {
        Ok(result) -> {
          io.println_error(name <> " v" <> version <> " — 캐시 사용")
          Ok(result)
        }
        Error(_) ->
          // s3_id가 있으면 직접 다운로드
          case widget.s3_id {
            Some(s3_id) ->
              download_with_s3(project_root, name, version, widget.id, s3_id)
            None ->
              // content_id로 API 조회
              resolve_via_api(project_root, name, version, widget.id, pat)
          }
      }
    }
  }
}

fn check_cache(
  project_root: String,
  name: String,
  version: String,
) -> Result(ResolveResult, String) {
  let cache_dir = project_root <> "/build/widgets/" <> name
  let meta_path = cache_dir <> "/meta.toml"
  use meta <- result.try(metadata.read(meta_path))
  case meta.version == version {
    True -> {
      // 위젯 XML 또는 classic 파일이 존재하는지 확인
      case has_widget_files(cache_dir, meta.classic) {
        True ->
          Ok(ResolveResult(
            name: name,
            version: version,
            content_id: meta.id,
            s3_id: meta.s3_id,
            hash: "",
            classic: meta.classic == Some(True),
          ))
        False -> Error("캐시 파일 불완전")
      }
    }
    False -> Error("버전 불일치")
  }
}

fn has_widget_files(cache_dir: String, classic: Option(Bool)) -> Bool {
  case simplifile.read_directory(cache_dir) {
    Ok(files) ->
      case classic {
        Some(True) -> True
        _ ->
          list.any(files, fn(f) {
            string.ends_with(f, ".xml") && f != "package.xml"
          })
      }
    Error(_) -> False
  }
}

fn download_with_s3(
  project_root: String,
  name: String,
  version: String,
  content_id: Option(Int),
  s3_id: String,
) -> Result(ResolveResult, String) {
  let url = "https://files.appstore.mendix.com/" <> s3_id
  use dl <- result.try(downloader.download_and_extract(
    url,
    name,
    version,
    content_id,
    project_root,
  ))
  Ok(ResolveResult(
    name: name,
    version: version,
    content_id: content_id,
    s3_id: Some(s3_id),
    hash: dl.hash,
    classic: dl.classic,
  ))
}

fn resolve_via_api(
  project_root: String,
  name: String,
  version: String,
  content_id: Option(Int),
  pat: Option(String),
) -> Result(ResolveResult, String) {
  use pat_val <- require_pat(pat)

  // content_id 확보
  use cid <- result.try(case content_id {
    Some(id) -> Ok(id)
    None -> {
      use page <- result.try(content_api.fetch_content_page(pat_val, 0, 40))
      case list.find(page.widgets, fn(w) { w.name == Some(name) }) {
        Ok(w) -> {
          // gleam.toml에 id 기록
          let _ =
            config.write_widget(
              project_root,
              name,
              version,
              Some(w.content_id),
              None,
            )
          Ok(w.content_id)
        }
        Error(_) -> Error("'" <> name <> "' 위젯을 찾을 수 없습니다")
      }
    }
  })

  // 세션 확인 → XAS 버전 수집 → 다운로드
  use _ <- result.try(session.ensure_session())

  use xas_versions <- result.try(
    mxpak_browser_get_versions(cid)
    |> result.map_error(fn(_) { "XAS 버전 수집 실패" }),
  )

  // 대상 버전의 s3_id 찾기
  case list.find(xas_versions, fn(xas) { xas.version_number == version }) {
    Ok(xas) -> {
      let _ =
        config.write_widget(
          project_root,
          name,
          version,
          Some(cid),
          Some(xas.s3_object_id),
        )
      download_with_s3(project_root, name, version, Some(cid), xas.s3_object_id)
    }
    Error(_) ->
      Error(
        "v" <> version <> " s3_id를 찾을 수 없습니다 (id=" <> int.to_string(cid) <> ")",
      )
  }
}

fn require_pat(
  pat: Option(String),
  cont: fn(String) -> Result(ResolveResult, String),
) -> Result(ResolveResult, String) {
  case pat {
    Some(val) -> cont(val)
    None -> Error("PAT 필요: .env에 MENDIX_PAT를 설정하세요")
  }
}

fn cleanup_stale_widgets(
  project_root: String,
  current_names: List(String),
) -> Nil {
  let widgets_dir = project_root <> "/build/widgets"
  case simplifile.read_directory(widgets_dir) {
    Ok(dirs) ->
      list.each(dirs, fn(dir) {
        case list.contains(current_names, dir) {
          True -> Nil
          False -> {
            let _ = simplifile.delete(widgets_dir <> "/" <> dir)
            Nil
          }
        }
      })
    Error(_) -> Nil
  }
}

// browser 모듈 의존 (import cycle 방지를 위해 간접 호출)
import mxpak/browser
import mxpak/registry/xas_parser.{type XasVersion}

fn mxpak_browser_get_versions(
  content_id: Int,
) -> Result(List(XasVersion), String) {
  browser.get_versions_for(content_id)
}
