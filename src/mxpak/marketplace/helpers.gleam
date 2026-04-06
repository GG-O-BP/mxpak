// Marketplace TUI 순수 헬퍼 — 페이지네이션, 필터링

import gleam/int
import gleam/list
import gleam/option
import gleam/string
import mxpak/marketplace/state.{type Model, display_size}
import mxpak/registry/content_api.{type Widget}

pub fn get_source(model: Model) -> List(Widget) {
  case model.filtered {
    option.Some(f) -> f
    option.None -> model.all_widgets
  }
}

pub fn current_page_items(model: Model) -> List(Widget) {
  get_source(model)
  |> list.drop(model.page_index * display_size)
  |> list.take(display_size)
}

pub fn total_pages_str(model: Model) -> String {
  let len = list.length(get_source(model))
  let total = case len {
    0 -> 1
    _ -> { len + display_size - 1 } / display_size
  }
  let suffix = case model.all_loaded || option.is_some(model.filtered) {
    True -> ""
    False -> "+"
  }
  int.to_string(total) <> suffix
}

pub fn filter_widgets(widgets: List(Widget), query: String) -> List(Widget) {
  let q = string.lowercase(query)
  list.filter(widgets, fn(w) {
    let name = string.lowercase(option.unwrap(w.name, ""))
    let publisher = string.lowercase(option.unwrap(w.publisher, ""))
    string.contains(name, q) || string.contains(publisher, q)
  })
}
