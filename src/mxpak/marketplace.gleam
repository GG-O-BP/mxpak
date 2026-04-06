// mxpak Marketplace TUI — Shore TEA 앱

import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import mxpak/browser
import mxpak/config
import mxpak/downloader
import mxpak/marketplace/helpers
import mxpak/marketplace/loader
import mxpak/marketplace/process_mgr
import mxpak/marketplace/state.{
  type Model, type Msg, ApiVersionsReady, Browse, ChangePage, ConfirmVersion,
  DownloadDone, GoBack, GoEnd, GoHome, InitialLoading, LoaderUpdated, Model,
  MoveCursor, Quit, SearchChanged, SelectVersion, SessionReady, StartDownload,
  ToggleSelection, VersionInfoReady, Working, display_size,
}
import mxpak/marketplace/view
import mxpak/registry/content_api.{fetch_size}
import mxpak/registry/version_merger
import mxpak/registry/xas_parser.{type XasVersion}
import mxpak/session
import shore
import shore/key
import shore/style
import shore/ui

/// Marketplace TUI 실행
pub fn run(pat: String, project_root: String) -> Nil {
  let exit = process.new_subject()

  let assert Ok(_) =
    shore.spec_with_subject(
      init: fn(subject) { init(pat, project_root, subject, exit) },
      view: view_fn,
      update: update,
      exit: exit,
      keybinds: shore.keybinds(
        exit: key.Ctrl("X"),
        submit: key.Enter,
        focus_clear: key.Esc,
        focus_next: key.Tab,
        focus_prev: key.BackTab,
      ),
      redraw: shore.on_update(),
    )
    |> shore.start

  let _ = process.receive_forever(exit)
  Nil
}

// ── TEA: init ──

fn init(
  pat: String,
  project_root: String,
  shore_subject: process.Subject(Msg),
  exit_subject: process.Subject(Nil),
) -> #(Model, List(fn() -> Msg)) {
  let model =
    Model(
      pat: pat,
      project_root: project_root,
      all_widgets: [],
      filtered: None,
      page_index: 0,
      cursor: 0,
      selected: [],
      all_loaded: False,
      loader: None,
      offset: 0,
      search_query: "",
      view_mode: InitialLoading("위젯 목록 불러오는 중..."),
      status_msg: None,
      shore_subject: Some(shore_subject),
      exit_subject: Some(exit_subject),
    )

  let load_first = fn() {
    case content_api.fetch_content_page(pat, 0, fetch_size) {
      Ok(page) ->
        LoaderUpdated(loader.LoaderUpdate(
          page.widgets,
          fetch_size,
          page.all_done,
        ))
      Error(_) -> LoaderUpdated(loader.LoaderUpdate([], 0, True))
    }
  }

  #(model, [load_first])
}

// ── TEA: view ──

fn view_fn(model: Model) -> shore.Node(Msg) {
  case model.view_mode {
    InitialLoading(label) -> view.view_loading(label)
    Working(label) -> view.view_loading(label)
    Browse ->
      ui.col([
        view.view_browse(
          helpers.current_page_items(model),
          model.cursor,
          model.selected,
          model.page_index + 1,
          helpers.total_pages_str(model),
          model.status_msg,
          model.all_loaded,
        ),
        ui.input("  검색: ", model.search_query, style.Fill, SearchChanged),
        ui.keybind(key.Up, MoveCursor(-1)),
        ui.keybind(key.Down, MoveCursor(1)),
        ui.keybind(key.Left, ChangePage(-1)),
        ui.keybind(key.Right, ChangePage(1)),
        ui.keybind(key.PageUp, ChangePage(-1)),
        ui.keybind(key.PageDown, ChangePage(1)),
        ui.keybind(key.Home, GoHome),
        ui.keybind(key.End, GoEnd),
        ui.keybind(key.Char(" "), ToggleSelection),
        ui.keybind(key.Enter, StartDownload),
      ])
    SelectVersion(name, versions, ver_cursor, _, _, _) ->
      ui.col([
        view.view_version(name, versions, ver_cursor, model.status_msg),
        ui.keybind(key.Up, MoveCursor(-1)),
        ui.keybind(key.Down, MoveCursor(1)),
        ui.keybind(key.Home, GoHome),
        ui.keybind(key.End, GoEnd),
        ui.keybind(key.Enter, ConfirmVersion),
        ui.keybind(key.Esc, GoBack),
      ])
  }
}

// ── TEA: update ──

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case model.view_mode {
    Working(_) | InitialLoading(_) ->
      case msg {
        Quit
        | SessionReady(_)
        | VersionInfoReady(..)
        | ApiVersionsReady(..)
        | DownloadDone(..)
        | LoaderUpdated(_) -> update_inner(model, msg)
        _ -> #(model, [])
      }
    _ -> update_inner(model, msg)
  }
}

fn update_inner(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
    Quit -> {
      process_mgr.cleanup(model)
      case model.exit_subject {
        Some(exit) -> process.send(exit, Nil)
        None -> Nil
      }
      #(model, [])
    }

    LoaderUpdated(loader.LoaderUpdate(widgets, offset, done)) -> {
      let was_initial_loading = case model.view_mode {
        InitialLoading(_) -> True
        _ -> False
      }
      let new_model =
        Model(
          ..model,
          all_widgets: widgets,
          offset: offset,
          all_loaded: done,
          view_mode: case was_initial_loading {
            True -> Browse
            False -> model.view_mode
          },
        )
      let new_model = case done, new_model.loader {
        False, None -> process_mgr.start_loader(new_model)
        _, _ -> new_model
      }
      let new_model = case new_model.search_query {
        "" -> new_model
        q ->
          Model(
            ..new_model,
            filtered: Some(helpers.filter_widgets(new_model.all_widgets, q)),
          )
      }
      #(new_model, [])
    }

    MoveCursor(delta) -> {
      case model.view_mode {
        Browse -> {
          let page_len = list.length(helpers.current_page_items(model))
          case page_len {
            0 -> #(model, [])
            _ -> {
              let new_cursor = int.clamp(model.cursor + delta, 0, page_len - 1)
              #(Model(..model, cursor: new_cursor), [])
            }
          }
        }
        SelectVersion(n, vs, vc, q, x, cid) -> {
          let max = int.max(0, list.length(vs) - 1)
          let new_vc = int.clamp(vc + delta, 0, max)
          #(
            Model(
              ..model,
              view_mode: SelectVersion(n, vs, new_vc, q, x, cid),
              status_msg: None,
            ),
            [],
          )
        }
        _ -> #(model, [])
      }
    }

    ChangePage(delta) -> {
      let source_len = list.length(helpers.get_source(model))
      let max_page = case source_len {
        0 -> 0
        _ -> { source_len - 1 } / display_size
      }
      let new_page = model.page_index + delta
      case new_page < 0 || new_page > max_page {
        True -> #(model, [])
        False -> #(
          Model(
            ..model,
            page_index: new_page,
            cursor: 0,
            selected: [],
            status_msg: None,
          ),
          [],
        )
      }
    }

    GoHome -> {
      case model.view_mode {
        Browse -> #(Model(..model, cursor: 0), [])
        SelectVersion(n, vs, _, q, x, cid) -> #(
          Model(..model, view_mode: SelectVersion(n, vs, 0, q, x, cid)),
          [],
        )
        _ -> #(model, [])
      }
    }

    GoEnd -> {
      case model.view_mode {
        Browse -> {
          let page_len = list.length(helpers.current_page_items(model))
          #(Model(..model, cursor: int.max(0, page_len - 1)), [])
        }
        SelectVersion(n, vs, _, q, x, cid) -> {
          let max = int.max(0, list.length(vs) - 1)
          #(Model(..model, view_mode: SelectVersion(n, vs, max, q, x, cid)), [])
        }
        _ -> #(model, [])
      }
    }

    ToggleSelection -> {
      let page_len = list.length(helpers.current_page_items(model))
      case model.cursor < page_len {
        False -> #(model, [])
        True -> {
          let new_selected = case list.contains(model.selected, model.cursor) {
            True -> list.filter(model.selected, fn(i) { i != model.cursor })
            False -> [model.cursor, ..model.selected]
          }
          #(Model(..model, selected: new_selected), [])
        }
      }
    }

    SearchChanged(query) -> {
      let filtered = case query {
        "" -> None
        _ -> Some(helpers.filter_widgets(model.all_widgets, query))
      }
      #(
        Model(
          ..model,
          search_query: query,
          filtered: filtered,
          page_index: 0,
          cursor: 0,
          selected: [],
        ),
        [],
      )
    }

    StartDownload -> {
      let page = helpers.current_page_items(model)
      let page_len = list.length(page)
      case page_len {
        0 -> #(model, [])
        _ -> {
          let indices = case model.selected {
            [] -> [model.cursor]
            sel -> list.sort(sel, int.compare)
          }
          let selected_widgets =
            list.filter_map(indices, fn(idx) {
              case idx >= 0 && idx < page_len {
                False -> Error(Nil)
                True ->
                  case list.drop(page, idx) |> list.first {
                    Ok(w) -> Ok(#(w.content_id, option.unwrap(w.name, "?")))
                    Error(_) -> Error(Nil)
                  }
              }
            })

          let model = process_mgr.stop_loader(model)
          let model =
            Model(..model, view_mode: Working("세션 확인 중..."), status_msg: None)

          let widgets = selected_widgets
          let cmd = fn() {
            case session.ensure_session() {
              Ok(_) -> {
                let content_ids = list.map(widgets, fn(s) { s.0 })
                let result = browser.get_all_versions(content_ids)
                VersionInfoReady(widgets, result)
              }
              Error(msg) -> SessionReady(Error(msg))
            }
          }

          #(model, [cmd])
        }
      }
    }

    SessionReady(result) -> {
      case result {
        Ok(_) -> #(model, [])
        Error(msg) -> {
          let model = process_mgr.start_loader(model)
          #(
            Model(
              ..model,
              view_mode: Browse,
              status_msg: Some("  세션 확인 실패: " <> msg),
            ),
            [],
          )
        }
      }
    }

    VersionInfoReady(widgets, result) -> {
      case result {
        Ok(xas_data) -> enter_version_mode(model, widgets, xas_data)
        Error(msg) -> {
          let model = process_mgr.start_loader(model)
          #(
            Model(
              ..model,
              view_mode: Browse,
              status_msg: Some("  버전 정보 조회 실패: " <> msg),
            ),
            [],
          )
        }
      }
    }

    ApiVersionsReady(name, content_id, queue, xas_data, result) -> {
      case result {
        Ok(api_versions) -> {
          case api_versions {
            [] ->
              enter_version_mode(
                Model(
                  ..model,
                  status_msg: Some("  " <> name <> " — 버전 정보를 가져올 수 없습니다"),
                ),
                queue,
                xas_data,
              )
            _ -> {
              let xas_versions = case dict.get(xas_data, content_id) {
                Ok(v) -> v
                Error(_) -> []
              }
              let merged = version_merger.merge(api_versions, xas_versions)
              #(
                Model(
                  ..model,
                  view_mode: SelectVersion(
                    name,
                    merged,
                    0,
                    queue,
                    xas_data,
                    content_id,
                  ),
                  status_msg: None,
                ),
                [],
              )
            }
          }
        }
        Error(_) ->
          enter_version_mode(
            Model(
              ..model,
              status_msg: Some("  " <> name <> " — 버전 정보를 가져올 수 없습니다"),
            ),
            queue,
            xas_data,
          )
      }
    }

    ConfirmVersion -> {
      case model.view_mode {
        SelectVersion(name, versions, ver_cursor, queue, xas_data, content_id) -> {
          case list.drop(versions, ver_cursor) |> list.first {
            Error(_) -> #(model, [])
            Ok(selected) ->
              case selected.downloadable, selected.s3_object_id {
                True, Some(s3_id) -> {
                  let url = "https://files.appstore.mendix.com/" <> s3_id
                  let model =
                    Model(..model, view_mode: Working(name <> " 다운로드 중..."))
                  let root = model.project_root
                  let version = selected.version_number
                  let react = selected.react_ready

                  let cmd = fn() {
                    let result =
                      downloader.download_and_extract(
                        url,
                        name,
                        version,
                        Some(content_id),
                        root,
                      )
                    case result {
                      Ok(dl) -> {
                        let _ =
                          config.write_widget(
                            root,
                            name,
                            version,
                            Some(content_id),
                            Some(s3_id),
                          )
                        let type_label = case react {
                          Some(True) -> " (Pluggable)"
                          Some(False) -> " (Classic)"
                          None -> ""
                        }
                        DownloadDone(
                          name,
                          queue,
                          xas_data,
                          Ok(
                            downloader.DownloadResult(
                              ..dl,
                              s3_id: "✓ " <> name <> " 다운로드 완료" <> type_label,
                            ),
                          ),
                        )
                      }
                      Error(msg) ->
                        DownloadDone(name, queue, xas_data, Error(msg))
                    }
                  }

                  #(model, [cmd])
                }
                _, _ -> #(
                  Model(
                    ..model,
                    status_msg: Some(
                      "  v" <> selected.version_number <> "은 다운로드할 수 없습니다",
                    ),
                  ),
                  [],
                )
              }
          }
        }
        _ -> #(model, [])
      }
    }

    DownloadDone(_name, queue, xas_data, result) -> {
      case result {
        Ok(dl) -> {
          let model = Model(..model, status_msg: Some("  " <> dl.s3_id))
          enter_version_mode(model, queue, xas_data)
        }
        Error(msg) -> {
          let model = Model(..model, status_msg: Some("  ✗ 다운로드 실패: " <> msg))
          enter_version_mode(model, queue, xas_data)
        }
      }
    }

    GoBack -> {
      case model.view_mode {
        SelectVersion(..) -> {
          let model =
            process_mgr.start_loader(
              Model(..model, view_mode: Browse, status_msg: None),
            )
          #(model, [])
        }
        _ -> #(model, [])
      }
    }
  }
}

fn enter_version_mode(
  model: Model,
  widgets: List(#(Int, String)),
  xas_data: Dict(Int, List(XasVersion)),
) -> #(Model, List(fn() -> Msg)) {
  case widgets {
    [] -> {
      let model =
        process_mgr.start_loader(
          Model(..model, view_mode: Browse, selected: []),
        )
      #(model, [])
    }
    [#(cid, name), ..rest] -> {
      let model_pat = model.pat
      let model = Model(..model, view_mode: Working(name <> " 버전 조회 중..."))
      let cmd = fn() {
        ApiVersionsReady(
          name,
          cid,
          rest,
          xas_data,
          content_api.fetch_versions(model_pat, cid),
        )
      }
      #(model, [cmd])
    }
  }
}
