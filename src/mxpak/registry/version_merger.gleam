// Content API 버전 + XAS 버전 데이터 병합

import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import mxpak/registry/content_api.{type ContentApiVersion}
import mxpak/registry/xas_parser.{type XasVersion}

pub type MergedVersion {
  MergedVersion(
    version_number: String,
    publication_date: Option(String),
    min_mendix_version: Option(String),
    s3_object_id: Option(String),
    react_ready: Option(Bool),
    downloadable: Bool,
  )
}

/// Content API + XAS 병합
pub fn merge(
  api_versions: List(ContentApiVersion),
  xas_versions: List(XasVersion),
) -> List(MergedVersion) {
  let xas_index = build_xas_index(xas_versions)
  let s3_template = extract_s3_template(xas_versions)

  list.map(api_versions, fn(api) {
    case dict.get(xas_index, api.version_number) {
      Ok(xas) ->
        MergedVersion(
          version_number: api.version_number,
          publication_date: api.publication_date,
          min_mendix_version: api.min_supported_mendix_version,
          s3_object_id: Some(xas.s3_object_id),
          react_ready: Some(xas.react_ready),
          downloadable: True,
        )
      Error(_) ->
        case s3_template {
          Some(#(prefix, file_name)) ->
            MergedVersion(
              version_number: api.version_number,
              publication_date: api.publication_date,
              min_mendix_version: api.min_supported_mendix_version,
              s3_object_id: Some(
                prefix <> "/" <> api.version_number <> "/" <> file_name,
              ),
              react_ready: None,
              downloadable: True,
            )
          None ->
            MergedVersion(
              version_number: api.version_number,
              publication_date: api.publication_date,
              min_mendix_version: api.min_supported_mendix_version,
              s3_object_id: None,
              react_ready: None,
              downloadable: False,
            )
        }
    }
  })
}

// ── 내부 함수 ──

fn build_xas_index(
  xas_versions: List(XasVersion),
) -> dict.Dict(String, XasVersion) {
  list.fold(xas_versions, dict.new(), fn(acc, xas) {
    let acc = case xas.version_number {
      "" -> acc
      vn -> dict.insert(acc, vn, xas)
    }
    let parts = string.split(xas.s3_object_id, "/")
    case list.length(parts) >= 4 {
      True ->
        case list.drop(parts, 2) |> list.first {
          Ok(ver) -> dict.insert(acc, ver, xas)
          Error(_) -> acc
        }
      False -> acc
    }
  })
}

fn extract_s3_template(
  xas_versions: List(XasVersion),
) -> Option(#(String, String)) {
  list.find_map(xas_versions, fn(xas) {
    let parts = string.split(xas.s3_object_id, "/")
    case list.length(parts) >= 4 {
      True -> {
        let prefix =
          list.take(parts, 2)
          |> string.join("/")
        let file_name =
          list.drop(parts, 3)
          |> string.join("/")
        Ok(#(prefix, file_name))
      }
      False -> Error(Nil)
    }
  })
  |> option.from_result
}
