import gleam/json
import gleam/option.{None, Some}
import mxpak/registry/content_api
import mxpak/registry/version_merger
import mxpak/registry/xas_parser

// === XAS 파서 테스트 ===

pub fn parse_xas_body_valid_test() {
  let body =
    "{\"objects\":[{\"objectType\":\"AppStore.Version\",\"attributes\":{\"S3ObjectId\":{\"value\":\"widgets/abc/1.0.0/Widget.mpk\"},\"IsReactClientReady\":{\"value\":true},\"PublishDate\":{\"value\":\"2024-01-15\"},\"DisplayVersionNumber\":{\"value\":\"1.0.0\"}}}]}"
  let versions = xas_parser.parse_xas_body(body)
  let assert [v] = versions
  let assert True = v.s3_object_id == "widgets/abc/1.0.0/Widget.mpk"
  let assert True = v.react_ready == True
  let assert True = v.version_number == "1.0.0"
}

pub fn parse_xas_body_non_version_objects_test() {
  let body =
    "{\"objects\":[{\"objectType\":\"AppStore.Other\",\"attributes\":{}},{\"objectType\":\"AppStore.Version\",\"attributes\":{\"S3ObjectId\":{\"value\":\"test/path\"}}}]}"
  let versions = xas_parser.parse_xas_body(body)
  let assert [v] = versions
  let assert True = v.s3_object_id == "test/path"
}

pub fn parse_xas_body_invalid_json_test() {
  let assert [] = xas_parser.parse_xas_body("not json")
}

pub fn parse_xas_body_missing_s3_test() {
  let body =
    "{\"objects\":[{\"objectType\":\"AppStore.Version\",\"attributes\":{\"PublishDate\":{\"value\":\"2024-01-01\"}}}]}"
  let assert [] = xas_parser.parse_xas_body(body)
}

pub fn encode_version_test() {
  let v =
    xas_parser.XasVersion(
      s3_object_id: "a/b/1.0/W.mpk",
      react_ready: True,
      publish_date: "2024-03-01",
      version_number: "1.0.0",
    )
  let encoded = json.to_string(xas_parser.encode_version(v))
  let assert True = {
    encoded
    |> contains("\"s3ObjectId\":\"a/b/1.0/W.mpk\"")
  }
  let assert True = {
    encoded
    |> contains("\"reactReady\":true")
  }
}

// === version_merger 테스트 ===

pub fn merge_exact_match_test() {
  let api = [
    content_api.ContentApiVersion("1.0.0", Some("2024-01-01"), Some("10.0.0")),
  ]
  let xas = [
    xas_parser.XasVersion("w/id/1.0.0/W.mpk", True, "2024-01-01", "1.0.0"),
  ]
  let merged = version_merger.merge(api, xas)
  let assert [v] = merged
  let assert True = v.downloadable == True
  let assert Some("w/id/1.0.0/W.mpk") = v.s3_object_id
  let assert Some(True) = v.react_ready
}

pub fn merge_s3_template_fallback_test() {
  let api = [
    content_api.ContentApiVersion("2.0.0", None, None),
    content_api.ContentApiVersion("1.0.0", None, None),
  ]
  let xas = [
    xas_parser.XasVersion("prefix/id/1.0.0/Widget.mpk", False, "", "1.0.0"),
  ]
  let merged = version_merger.merge(api, xas)
  let assert [v2, _v1] = merged
  // 2.0.0은 XAS에 없지만 S3 템플릿으로 추정
  let assert True = v2.downloadable == True
  let assert Some("prefix/id/2.0.0/Widget.mpk") = v2.s3_object_id
}

pub fn merge_no_xas_data_test() {
  let api = [
    content_api.ContentApiVersion("1.0.0", None, None),
  ]
  let merged = version_merger.merge(api, [])
  let assert [v] = merged
  let assert True = v.downloadable == False
  let assert None = v.s3_object_id
}

// ── 헬퍼 ──

import gleam/string

fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
