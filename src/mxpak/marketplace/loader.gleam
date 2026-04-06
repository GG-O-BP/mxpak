// 백그라운드 위젯 로더 — Erlang 프로세스 기반

import gleam/erlang/process.{type Subject}
import gleam/list
import mxpak/registry/content_api.{type Widget, fetch_content_page, fetch_size}

pub type LoaderMsg {
  LoaderUpdate(widgets: List(Widget), offset: Int, done: Bool)
}

pub type LoaderHandle {
  LoaderHandle(control: Subject(LoaderControl))
}

pub type LoaderControl {
  StopLoader
}

pub fn start(
  pat: String,
  initial_offset: Int,
  initial_widgets: List(Widget),
  notify: Subject(LoaderMsg),
  ready: Subject(LoaderHandle),
) -> Nil {
  let _ =
    process.spawn(fn() {
      let control = process.new_subject()
      process.send(ready, LoaderHandle(control))
      loader_loop(pat, initial_offset, initial_widgets, notify, control)
    })
  Nil
}

pub fn stop(handle: LoaderHandle) -> Nil {
  process.send(handle.control, StopLoader)
}

fn loader_loop(
  pat: String,
  offset: Int,
  widgets: List(Widget),
  notify: Subject(LoaderMsg),
  control: Subject(LoaderControl),
) -> Nil {
  case process.receive(control, 0) {
    Ok(StopLoader) -> Nil
    Error(_) -> {
      case fetch_content_page(pat, offset, fetch_size) {
        Ok(page) -> {
          let new_widgets = list.append(widgets, page.widgets)
          let new_offset = offset + fetch_size
          process.send(
            notify,
            LoaderUpdate(new_widgets, new_offset, page.all_done),
          )
          case page.all_done {
            True -> Nil
            False -> loader_loop(pat, new_offset, new_widgets, notify, control)
          }
        }
        Error(_) -> {
          process.send(notify, LoaderUpdate(widgets, offset, True))
        }
      }
    }
  }
}
