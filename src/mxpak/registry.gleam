// 레지스트리 통합 인터페이스 — Content API + XAS + 병합

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import mxpak/browser
import mxpak/registry/content_api.{type ContentApiVersion, type ContentPage}
import mxpak/registry/version_merger.{type MergedVersion}
import mxpak/registry/xas_parser.{type XasVersion}

/// 위젯 페이지 조회
pub fn fetch_widgets(
  pat: String,
  offset: Int,
  limit: Int,
) -> Result(ContentPage, String) {
  content_api.fetch_content_page(pat, offset, limit)
}

/// 위젯 버전 목록 조회 (Content API)
pub fn fetch_versions(
  pat: String,
  content_id: Int,
) -> Result(List(ContentApiVersion), String) {
  content_api.fetch_versions(pat, content_id)
}

/// XAS 버전 수집 (브라우저)
pub fn collect_xas_versions(
  content_ids: List(Int),
) -> Result(Dict(Int, List(XasVersion)), String) {
  browser.get_all_versions(content_ids)
}

/// Content API + XAS 병합된 버전 목록 조회
pub fn fetch_merged_versions(
  pat: String,
  content_id: Int,
  xas_versions: List(XasVersion),
) -> Result(List(MergedVersion), String) {
  use api_versions <- result.try(content_api.fetch_versions(pat, content_id))
  Ok(version_merger.merge(api_versions, xas_versions))
}

/// 여러 위젯의 병합 버전을 한번에 조회
pub fn fetch_all_merged_versions(
  pat: String,
  content_ids: List(Int),
) -> Result(Dict(Int, List(MergedVersion)), String) {
  use xas_map <- result.try(browser.get_all_versions(content_ids))

  list.try_fold(content_ids, dict.new(), fn(acc, cid) {
    let xas = case dict.get(xas_map, cid) {
      Ok(v) -> v
      Error(_) -> []
    }
    use merged <- result.try(fetch_merged_versions(pat, cid, xas))
    Ok(dict.insert(acc, cid, merged))
  })
}
