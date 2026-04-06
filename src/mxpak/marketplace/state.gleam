// Marketplace TUI 상태 타입 정의

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import mxpak/downloader
import mxpak/marketplace/loader.{type LoaderHandle}
import mxpak/registry/content_api.{type ContentApiVersion, type Widget}
import mxpak/registry/version_merger.{type MergedVersion}
import mxpak/registry/xas_parser.{type XasVersion}

pub const display_size = 10

pub type ViewMode {
  Browse
  SelectVersion(
    name: String,
    versions: List(MergedVersion),
    ver_cursor: Int,
    queue: List(#(Int, String)),
    xas_data: Dict(Int, List(XasVersion)),
    content_id: Int,
  )
  InitialLoading(label: String)
  Working(label: String)
}

pub type Model {
  Model(
    pat: String,
    project_root: String,
    all_widgets: List(Widget),
    filtered: Option(List(Widget)),
    page_index: Int,
    cursor: Int,
    selected: List(Int),
    all_loaded: Bool,
    loader: Option(LoaderHandle),
    offset: Int,
    search_query: String,
    view_mode: ViewMode,
    status_msg: Option(String),
    shore_subject: Option(Subject(Msg)),
    exit_subject: Option(Subject(Nil)),
  )
}

pub type Msg {
  MoveCursor(Int)
  ChangePage(Int)
  GoHome
  GoEnd
  ToggleSelection
  SearchChanged(String)
  StartDownload
  ConfirmVersion
  GoBack
  Quit
  LoaderUpdated(loader.LoaderMsg)
  SessionReady(Result(Nil, String))
  VersionInfoReady(
    widgets: List(#(Int, String)),
    result: Result(Dict(Int, List(XasVersion)), String),
  )
  ApiVersionsReady(
    name: String,
    content_id: Int,
    queue: List(#(Int, String)),
    xas_data: Dict(Int, List(XasVersion)),
    result: Result(List(ContentApiVersion), String),
  )
  DownloadDone(
    name: String,
    queue: List(#(Int, String)),
    xas_data: Dict(Int, List(XasVersion)),
    result: Result(downloader.DownloadResult, String),
  )
}
