// Marketplace 로더 프로세스 관리 — 시작/중지/릴레이

import gleam/erlang/process.{type Subject}
import gleam/option.{None, Some}
import mxpak/marketplace/loader.{type LoaderMsg}
import mxpak/marketplace/state.{type Model, type Msg, LoaderUpdated, Model}

pub fn start_loader(model: Model) -> Model {
  case model.all_loaded {
    True -> model
    False -> {
      case model.shore_subject {
        Some(shore_subject) -> {
          let handle_ready = process.new_subject()
          let pat = model.pat
          let offset = model.offset
          let widgets = model.all_widgets
          let _ =
            process.spawn(fn() {
              let loader_subject = process.new_subject()
              let loader_handle_ready = process.new_subject()
              loader.start(
                pat,
                offset,
                widgets,
                loader_subject,
                loader_handle_ready,
              )
              case process.receive(loader_handle_ready, 10_000) {
                Ok(handle) -> {
                  process.send(handle_ready, handle)
                  relay_loop(loader_subject, shore_subject)
                }
                Error(_) -> Nil
              }
            })
          case process.receive(handle_ready, 15_000) {
            Ok(handle) -> Model(..model, loader: Some(handle))
            Error(_) -> model
          }
        }
        None -> model
      }
    }
  }
}

pub fn stop_loader(model: Model) -> Model {
  case model.loader {
    Some(handle) -> {
      loader.stop(handle)
      Model(..model, loader: None)
    }
    None -> model
  }
}

pub fn cleanup(model: Model) -> Nil {
  let _ = stop_loader(model)
  Nil
}

fn relay_loop(from: Subject(LoaderMsg), to: Subject(Msg)) -> Nil {
  case process.receive(from, 60_000) {
    Ok(msg) -> {
      process.send(to, LoaderUpdated(msg))
      case msg {
        loader.LoaderUpdate(_, _, True) -> Nil
        _ -> relay_loop(from, to)
      }
    }
    Error(_) -> Nil
  }
}
