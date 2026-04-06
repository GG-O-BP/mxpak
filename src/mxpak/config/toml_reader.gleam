// gleam.toml [tools.mendraw.widgets.*] 파싱 — tom 라이브러리 사용

import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/result
import simplifile
import tom.{type Toml}

/// 위젯 설정 정보
pub type WidgetConfig {
  WidgetConfig(
    version: String,
    id: Option(Int),
    s3_id: Option(String),
    classic: Option(Bool),
  )
}

/// [tools.mendraw] 전체 설정
pub type MendrawConfig {
  MendrawConfig(
    mendix_version: Option(String),
    mode: String,
    widgets_dir: String,
    widgets: Dict(String, WidgetConfig),
  )
}

/// gleam.toml을 파싱하여 mendraw 위젯 설정을 추출
pub fn read_config(project_root: String) -> Result(MendrawConfig, String) {
  let toml_path = project_root <> "/gleam.toml"
  use content <- result.try(
    simplifile.read(toml_path)
    |> result.map_error(fn(_) { "gleam.toml 읽기 실패: " <> toml_path }),
  )
  use parsed <- result.try(
    tom.parse(content)
    |> result.map_error(fn(_) { "gleam.toml 파싱 실패" }),
  )
  Ok(extract_mendraw_config(parsed))
}

/// 파싱된 TOML에서 mendraw 설정 추출
fn extract_mendraw_config(toml: Dict(String, Toml)) -> MendrawConfig {
  let mendix_version =
    tom.get_string(toml, ["tools", "mendraw", "mendix_version"])
    |> option.from_result

  let mode =
    tom.get_string(toml, ["tools", "mendraw", "mode"])
    |> result.unwrap("extract")

  let widgets_dir =
    tom.get_string(toml, ["tools", "mendraw", "widgets_dir"])
    |> result.unwrap("widgets")

  let widgets = case tom.get_table(toml, ["tools", "mendraw", "widgets"]) {
    Ok(widgets_table) -> parse_widgets(widgets_table)
    Error(_) -> dict.new()
  }

  MendrawConfig(
    mendix_version: mendix_version,
    mode: mode,
    widgets_dir: widgets_dir,
    widgets: widgets,
  )
}

/// widgets 테이블의 각 위젯을 WidgetConfig로 파싱
fn parse_widgets(table: Dict(String, Toml)) -> Dict(String, WidgetConfig) {
  dict.fold(table, dict.new(), fn(acc, name, value) {
    case value {
      tom.Table(widget_table) | tom.InlineTable(widget_table) ->
        dict.insert(acc, name, parse_single_widget(widget_table))
      _ -> acc
    }
  })
}

fn parse_single_widget(table: Dict(String, Toml)) -> WidgetConfig {
  let version = tom.get_string(table, ["version"]) |> result.unwrap("")
  let id = tom.get_int(table, ["id"]) |> option.from_result
  let s3_id = tom.get_string(table, ["s3_id"]) |> option.from_result
  let classic = tom.get_bool(table, ["classic"]) |> option.from_result

  WidgetConfig(version: version, id: id, s3_id: s3_id, classic: classic)
}

/// meta.toml 파싱 (build/widgets/{name}/meta.toml)
pub fn read_meta_toml(path: String) -> Result(WidgetConfig, String) {
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "meta.toml 읽기 실패: " <> path }),
  )
  use parsed <- result.try(
    tom.parse(content)
    |> result.map_error(fn(_) { "meta.toml 파싱 실패: " <> path }),
  )
  Ok(parse_single_widget(parsed))
}
