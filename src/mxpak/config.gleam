// 프로젝트 설정 통합 인터페이스
// gleam.toml 읽기/쓰기, .env, meta.toml

import gleam/option.{type Option}
import mxpak/config/env_reader
import mxpak/config/toml_reader.{type MendrawConfig, type WidgetConfig}
import mxpak/config/toml_writer

/// 프로젝트 설정 읽기 (gleam.toml)
pub fn read(project_root: String) -> Result(MendrawConfig, String) {
  toml_reader.read_config(project_root)
}

/// MENDIX_PAT 조회 (환경변수 → .env)
pub fn get_pat(project_root: String) -> Option(String) {
  env_reader.get("MENDIX_PAT", project_root)
}

/// gleam.toml에 위젯 기록
pub fn write_widget(
  project_root: String,
  name: String,
  version: String,
  content_id: Option(Int),
  s3_id: Option(String),
) -> Result(Nil, String) {
  toml_writer.write_widget(project_root, name, version, content_id, s3_id)
}

/// gleam.toml에서 위젯 제거
pub fn remove_widget(project_root: String, name: String) -> Result(Nil, String) {
  toml_writer.remove_widget(project_root, name)
}

/// meta.toml 읽기
pub fn read_meta(path: String) -> Result(WidgetConfig, String) {
  toml_reader.read_meta_toml(path)
}

/// meta.toml 쓰기
pub fn write_meta(
  path: String,
  version: String,
  id: Option(Int),
  classic: Bool,
) -> Result(Nil, String) {
  toml_writer.write_meta_toml(path, version, id, classic)
}
