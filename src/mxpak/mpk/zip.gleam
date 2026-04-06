// MPK(ZIP) 파일 처리 — OTP zip 모듈 래핑

import gleam/list
import gleam/result

/// ZIP 엔트리: 파일명 + 내용 바이너리
pub type ZipEntry {
  ZipEntry(name: String, content: BitArray)
}

/// ZIP 바이너리를 메모리에 압축 해제
pub fn extract(zip_binary: BitArray) -> Result(List(ZipEntry), String) {
  unzip_to_memory(zip_binary)
  |> result.map(fn(raw_entries) {
    list.map(raw_entries, fn(entry) {
      ZipEntry(name: entry.0, content: entry.1)
    })
  })
}

/// ZIP에서 특정 파일 하나만 추출
pub fn extract_file(
  zip_binary: BitArray,
  file_name: String,
) -> Result(BitArray, String) {
  use entries <- result.try(extract(zip_binary))
  list.find(entries, fn(e) { e.name == file_name })
  |> result.replace_error("ZIP 엔트리를 찾을 수 없습니다: " <> file_name)
  |> result.map(fn(e) { e.content })
}

/// ZIP 엔트리 목록(파일명만)
pub fn list_entries(zip_binary: BitArray) -> Result(List(String), String) {
  use entries <- result.map(extract(zip_binary))
  list.map(entries, fn(e) { e.name })
}

// ── Erlang FFI ──

@external(erlang, "mxpak_zip_ffi", "unzip_to_memory")
fn unzip_to_memory(
  zip_binary: BitArray,
) -> Result(List(#(String, BitArray)), String)
