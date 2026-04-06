// meta.toml 읽기/쓰기 — 위젯 캐시 메타데이터 관리

import gleam/option.{type Option}
import mxpak/config/toml_reader.{type WidgetConfig}
import mxpak/config/toml_writer

/// meta.toml 읽기
pub fn read(path: String) -> Result(WidgetConfig, String) {
  toml_reader.read_meta_toml(path)
}

/// meta.toml 쓰기
pub fn write(
  path: String,
  version: String,
  id: Option(Int),
  classic: Bool,
) -> Result(Nil, String) {
  toml_writer.write_meta_toml(path, version, id, classic)
}
