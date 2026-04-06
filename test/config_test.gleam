import gleam/dict
import gleam/option.{None, Some}
import gleeunit
import mxpak/config/env_reader
import mxpak/config/toml_reader
import mxpak/config/toml_writer
import simplifile

pub fn main() -> Nil {
  gleeunit.main()
}

// === toml_reader 테스트 ===

pub fn read_config_with_widgets_test() {
  let dir = "build/test_tmp/reader1"
  let _ = simplifile.create_directory_all(dir)
  let toml =
    "name = \"test\"\nversion = \"1.0.0\"\n\n[tools.mendraw.widgets.DataGrid]\nversion = \"2.5.0\"\nid = 12345\ns3_id = \"abc/def\"\n"
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", toml)

  let assert Ok(config) = toml_reader.read_config(dir)
  let assert True = dict.size(config.widgets) == 1
  let assert Ok(widget) = dict.get(config.widgets, "DataGrid")
  let assert True = widget.version == "2.5.0"
  let assert Some(12_345) = widget.id
  let assert Some("abc/def") = widget.s3_id

  let _ = simplifile.delete(dir)
  Nil
}

pub fn read_config_empty_widgets_test() {
  let dir = "build/test_tmp/reader2"
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", "name = \"test\"\n")

  let assert Ok(config) = toml_reader.read_config(dir)
  let assert True = dict.size(config.widgets) == 0

  let _ = simplifile.delete(dir)
  Nil
}

pub fn read_config_with_mendix_version_test() {
  let dir = "build/test_tmp/reader3"
  let _ = simplifile.create_directory_all(dir)
  let toml =
    "name = \"test\"\n\n[tools.mendraw]\nmendix_version = \"10.12.0\"\n"
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", toml)

  let assert Ok(config) = toml_reader.read_config(dir)
  let assert Some("10.12.0") = config.mendix_version

  let _ = simplifile.delete(dir)
  Nil
}

pub fn read_config_multiple_widgets_test() {
  let dir = "build/test_tmp/reader4"
  let _ = simplifile.create_directory_all(dir)
  let toml =
    "name = \"test\"\n\n[tools.mendraw.widgets.A]\nversion = \"1.0.0\"\n\n[tools.mendraw.widgets.B]\nversion = \"2.0.0\"\nclassic = true\n"
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", toml)

  let assert Ok(config) = toml_reader.read_config(dir)
  let assert True = dict.size(config.widgets) == 2
  let assert Ok(b) = dict.get(config.widgets, "B")
  let assert Some(True) = b.classic

  let _ = simplifile.delete(dir)
  Nil
}

pub fn read_config_missing_file_test() {
  let assert Error(_) = toml_reader.read_config("build/test_tmp/nonexistent")
}

// === toml_reader meta.toml 테스트 ===

pub fn read_meta_toml_test() {
  let dir = "build/test_tmp/meta1"
  let _ = simplifile.create_directory_all(dir)
  let meta = "version = \"3.0.0\"\nid = 999\nclassic = true\n"
  let assert Ok(_) = simplifile.write(dir <> "/meta.toml", meta)

  let assert Ok(config) = toml_reader.read_meta_toml(dir <> "/meta.toml")
  let assert True = config.version == "3.0.0"
  let assert Some(999) = config.id
  let assert Some(True) = config.classic

  let _ = simplifile.delete(dir)
  Nil
}

// === toml_writer 테스트 ===

pub fn write_widget_new_section_test() {
  let dir = "build/test_tmp/writer1"
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", "name = \"test\"\n")

  let assert Ok(_) =
    toml_writer.write_widget(dir, "Charts", "4.0.0", Some(100), None)

  let assert Ok(content) = simplifile.read(dir <> "/gleam.toml")
  let assert True =
    content
    |> contains("[tools.mendraw.widgets.Charts]")
  let assert True = content |> contains("version = \"4.0.0\"")
  let assert True = content |> contains("id = 100")

  let _ = simplifile.delete(dir)
  Nil
}

pub fn write_widget_update_existing_test() {
  let dir = "build/test_tmp/writer2"
  let _ = simplifile.create_directory_all(dir)
  let toml =
    "name = \"test\"\n\n[tools.mendraw.widgets.Charts]\nversion = \"3.0.0\"\n"
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", toml)

  let assert Ok(_) =
    toml_writer.write_widget(dir, "Charts", "4.0.0", None, None)

  let assert Ok(content) = simplifile.read(dir <> "/gleam.toml")
  let assert True = content |> contains("version = \"4.0.0\"")
  let assert False = content |> contains("version = \"3.0.0\"")

  let _ = simplifile.delete(dir)
  Nil
}

pub fn write_widget_quoted_name_test() {
  let dir = "build/test_tmp/writer3"
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", "name = \"test\"\n")

  let assert Ok(_) =
    toml_writer.write_widget(dir, "Data Widgets", "1.0.0", None, None)

  let assert Ok(content) = simplifile.read(dir <> "/gleam.toml")
  let assert True =
    content
    |> contains("[tools.mendraw.widgets.\"Data Widgets\"]")

  let _ = simplifile.delete(dir)
  Nil
}

pub fn remove_widget_test() {
  let dir = "build/test_tmp/writer4"
  let _ = simplifile.create_directory_all(dir)
  let toml =
    "name = \"test\"\n\n[tools.mendraw.widgets.A]\nversion = \"1.0.0\"\n\n[tools.mendraw.widgets.B]\nversion = \"2.0.0\"\n"
  let assert Ok(_) = simplifile.write(dir <> "/gleam.toml", toml)

  let assert Ok(_) = toml_writer.remove_widget(dir, "A")

  let assert Ok(content) = simplifile.read(dir <> "/gleam.toml")
  let assert False = content |> contains("[tools.mendraw.widgets.A]")
  let assert True = content |> contains("[tools.mendraw.widgets.B]")

  let _ = simplifile.delete(dir)
  Nil
}

// === meta.toml 쓰기 테스트 ===

pub fn write_meta_toml_test() {
  let dir = "build/test_tmp/meta_w1"
  let _ = simplifile.create_directory_all(dir)

  let assert Ok(_) =
    toml_writer.write_meta_toml(dir <> "/meta.toml", "5.0.0", Some(42), False)

  let assert Ok(content) = simplifile.read(dir <> "/meta.toml")
  let assert True = content |> contains("version = \"5.0.0\"")
  let assert True = content |> contains("id = 42")
  let assert False = content |> contains("classic")

  let _ = simplifile.delete(dir)
  Nil
}

pub fn write_meta_toml_classic_test() {
  let dir = "build/test_tmp/meta_w2"
  let _ = simplifile.create_directory_all(dir)

  let assert Ok(_) =
    toml_writer.write_meta_toml(dir <> "/meta.toml", "1.0.0", None, True)

  let assert Ok(content) = simplifile.read(dir <> "/meta.toml")
  let assert True = content |> contains("classic = true")
  let assert False = content |> contains("id")

  let _ = simplifile.delete(dir)
  Nil
}

// === env_reader 테스트 ===

pub fn env_reader_dotenv_test() {
  let dir = "build/test_tmp/env1"
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) =
    simplifile.write(
      dir <> "/.env",
      "# 코멘트\nMENDIX_PAT=test_token_123\nOTHER=val\n",
    )

  let assert Some("test_token_123") = env_reader.get("MENDIX_PAT", dir)
  let assert Some("val") = env_reader.get("OTHER", dir)
  let assert None = env_reader.get("MISSING", dir)

  let _ = simplifile.delete(dir)
  Nil
}

pub fn env_reader_quoted_value_test() {
  let dir = "build/test_tmp/env2"
  let _ = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.write(dir <> "/.env", "KEY=\"quoted_value\"\n")

  let assert Some("quoted_value") = env_reader.get("KEY", dir)

  let _ = simplifile.delete(dir)
  Nil
}

pub fn env_reader_missing_file_test() {
  let assert None = env_reader.get("KEY", "build/test_tmp/no_env")
}

// 헬퍼

import gleam/string

fn contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
