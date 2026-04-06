import gleam/option.{None, Some}
import mxpak/mpk/xml
import mxpak/mpk/zip

// === ZIP 테스트 ===

/// 유효하지 않은 ZIP 바이너리 처리
pub fn zip_extract_invalid_binary_test() {
  let assert Error(_) = zip.extract(<<"not a zip":utf8>>)
}

/// 빈 ZIP에서 특정 파일 추출 실패
pub fn zip_extract_file_from_invalid_test() {
  let assert Error(_) = zip.extract_file(<<"bad":utf8>>, "foo.txt")
}

// === XML 파싱 테스트 ===

pub fn parse_widget_name_test() {
  let xml = "<widget><name>DataGrid</name></widget>"
  let assert Ok("DataGrid") = xml.parse_widget_name(xml)
}

pub fn parse_widget_name_missing_test() {
  let assert Error(Nil) = xml.parse_widget_name("<widget></widget>")
}

pub fn extract_widget_file_paths_test() {
  let package_xml =
    "<package><clientModule><widgetFile path=\"com/example/Widget.mjs\"/><widgetFile path=\"com/example/Other.mjs\"/></clientModule></package>"
  let paths = xml.extract_widget_file_paths(package_xml)
  let assert True = paths == ["com/example/Widget.mjs", "com/example/Other.mjs"]
}

pub fn extract_widget_file_paths_empty_test() {
  let assert [] = xml.extract_widget_file_paths("<package></package>")
}

pub fn parse_properties_test() {
  let widget_xml =
    "<widget><property key=\"dataSource\" required=\"true\"/><property key=\"label\" required=\"false\">desc</property></widget>"
  let props = xml.parse_properties(widget_xml)
  let assert True = {
    case props {
      [first, second] -> {
        first.key == "dataSource"
        && first.required == True
        && second.key == "label"
        && second.required == False
      }
      _ -> False
    }
  }
}

pub fn parse_properties_no_required_test() {
  let widget_xml = "<widget><property key=\"value\"/></widget>"
  let props = xml.parse_properties(widget_xml)
  let assert [prop] = props
  let assert True = prop.key == "value"
  let assert True = prop.required == False
}

// === 네이밍 유틸 테스트 ===

pub fn to_safe_identifier_test() {
  let assert True = xml.to_safe_identifier("Progress Bar") == "ProgressBar"
  let assert True = xml.to_safe_identifier("Data-Grid") == "DataGrid"
  let assert True = xml.to_safe_identifier("Normal") == "Normal"
}

pub fn to_module_file_name_test() {
  let assert True = xml.to_module_file_name("Progress Bar") == "progress_bar"
  let assert True = xml.to_module_file_name("DataGrid") == "data_grid"
}

pub fn to_snake_case_test() {
  let assert True = xml.to_snake_case("camelCase") == "camel_case"
  let assert True = xml.to_snake_case("HTTPClient") == "http_client"
  let assert True = xml.to_snake_case("simpleTest") == "simple_test"
}

pub fn to_gleam_var_test() {
  let assert True = xml.to_gleam_var("dataSource") == "data_source"
  let assert True = xml.to_gleam_var("type") == "type_"
  let assert True = xml.to_gleam_var("import") == "import_"
  let assert True = xml.to_gleam_var("normalName") == "normal_name"
}

// === metadata 테스트 ===

import mxpak/mpk/metadata
import simplifile

pub fn metadata_write_read_roundtrip_test() {
  let dir = "build/test_tmp/meta_rt"
  let _ = simplifile.create_directory_all(dir)
  let path = dir <> "/meta.toml"

  let assert Ok(_) = metadata.write(path, "2.0.0", Some(42), False)
  let assert Ok(config) = metadata.read(path)
  let assert True = config.version == "2.0.0"
  let assert Some(42) = config.id
  let assert None = config.classic

  let _ = simplifile.delete(dir)
  Nil
}

pub fn metadata_classic_roundtrip_test() {
  let dir = "build/test_tmp/meta_rt2"
  let _ = simplifile.create_directory_all(dir)
  let path = dir <> "/meta.toml"

  let assert Ok(_) = metadata.write(path, "1.0.0", None, True)
  let assert Ok(config) = metadata.read(path)
  let assert True = config.version == "1.0.0"
  let assert None = config.id
  let assert Some(True) = config.classic

  let _ = simplifile.delete(dir)
  Nil
}
