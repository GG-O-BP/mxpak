// 위젯 다운로드 + ZIP 추출 + CAS 캐시 연동

import gleam/bit_array
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import mxpak/cache
import mxpak/cache/integrity
import mxpak/config/toml_writer
import mxpak/mpk/xml
import mxpak/mpk/zip

// ── 타입 ──

pub type DownloadResult {
  DownloadResult(
    name: String,
    version: String,
    content_id: Option(Int),
    s3_id: String,
    hash: String,
    classic: Bool,
  )
}

// ── 다운로드 + 추출 ──

/// URL에서 .mpk를 다운로드하고 CAS 캐시 → 프로젝트에 추출
pub fn download_and_extract(
  url: String,
  name: String,
  version: String,
  content_id: Option(Int),
  project_root: String,
) -> Result(DownloadResult, String) {
  let cache_dir = project_root <> "/build/widgets/" <> name

  // HTTP 다운로드
  use zip_data <- result.try(download_binary(url))
  let hash = integrity.sha256(zip_data)

  // CAS 캐시 히트 체크
  case cache.has(hash) {
    True -> {
      io.println_error(name <> " v" <> version <> " — 캐시 히트")
      use _ <- result.try(cache.restore(hash, cache_dir))
      let classic = !has_mjs_in_dir(cache_dir)
      Ok(DownloadResult(name, version, content_id, url, hash, classic))
    }
    False -> {
      // ZIP 추출
      use entries <- result.try(
        zip.extract(zip_data)
        |> result.map_error(fn(e) { name <> " — 추출 실패: " <> e }),
      )

      let has_mjs =
        list.any(entries, fn(e) { string.ends_with(e.name, ".mjs") })
      let classic = !has_mjs

      // 저장할 파일 목록 구성
      let save_entries = build_save_entries(entries, classic)

      // CAS 캐시에 저장
      use _ <- result.try(cache.put(zip_data, save_entries))

      // 프로젝트 디렉토리에 파일 쓰기
      use _ <- result.try(write_to_project(save_entries, cache_dir))

      // meta.toml 기록
      use _ <- result.try(toml_writer.write_meta_toml(
        cache_dir <> "/meta.toml",
        version,
        content_id,
        classic,
      ))

      io.println_error(
        name <> " v" <> version <> " — 다운로드 완료 [" <> short_hash(hash) <> "]",
      )
      Ok(DownloadResult(name, version, content_id, url, hash, classic))
    }
  }
}

/// MPK 모드: .mpk 다운로드 → CAS 캐시 → 대상 경로에 하드 링크
pub fn download_mpk(
  url: String,
  name: String,
  version: String,
  content_id: Option(Int),
  target_path: String,
) -> Result(DownloadResult, String) {
  // HTTP 다운로드
  use zip_data <- result.try(download_binary(url))
  let hash = integrity.sha256(zip_data)

  // CAS 캐시 히트 체크
  case cache.has(hash) {
    True -> {
      io.println_error(name <> " v" <> version <> " — 캐시 히트")
      use _ <- result.try(cache.restore_mpk(hash, target_path))
      let classic = detect_classic_from_cache(hash)
      Ok(DownloadResult(name, version, content_id, url, hash, classic))
    }
    False -> {
      // ZIP 추출 (메타데이터 + 캐시용)
      use entries <- result.try(
        zip.extract(zip_data)
        |> result.map_error(fn(e) { name <> " — 추출 실패: " <> e }),
      )

      let has_mjs =
        list.any(entries, fn(e) { string.ends_with(e.name, ".mjs") })
      let classic = !has_mjs
      let save_entries = build_save_entries(entries, classic)

      // CAS 캐시에 저장 (original.mpk + 추출 파일)
      use _ <- result.try(cache.put(zip_data, save_entries))

      // 하드 링크로 프로젝트에 배치
      use _ <- result.try(cache.restore_mpk(hash, target_path))

      io.println_error(
        name <> " v" <> version <> " — 다운로드 완료 [" <> short_hash(hash) <> "]",
      )
      Ok(DownloadResult(name, version, content_id, url, hash, classic))
    }
  }
}

fn detect_classic_from_cache(hash: String) -> Bool {
  let dir = cache.path(hash)
  !has_mjs_in_dir(dir)
}

/// 캐시에서만 복원 (재다운로드 없이)
pub fn restore_from_cache(
  hash: String,
  name: String,
  version: String,
  content_id: Option(Int),
  project_root: String,
) -> Result(DownloadResult, String) {
  let cache_dir = project_root <> "/build/widgets/" <> name
  use _ <- result.try(cache.restore(hash, cache_dir))
  let classic = !has_mjs_in_dir(cache_dir)
  Ok(DownloadResult(name, version, content_id, "", hash, classic))
}

// ── 내부 헬퍼 ──

fn download_binary(url: String) -> Result(BitArray, String) {
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { "잘못된 URL: " <> url }),
  )
  let config =
    httpc.configure()
    |> httpc.follow_redirects(True)
    |> httpc.timeout(60_000)

  let req = request.map(req, bit_array.from_string)
  httpc.dispatch_bits(config, req)
  |> result.map(fn(resp) { resp.body })
  |> result.map_error(fn(_) { "다운로드 실패" })
}

/// ZIP 엔트리에서 저장할 파일 선별
fn build_save_entries(
  entries: List(zip.ZipEntry),
  classic: Bool,
) -> List(#(String, BitArray)) {
  // package.xml에서 위젯 XML 경로 추출
  let widget_xml_paths = case
    list.find(entries, fn(e) { basename(e.name) == "package.xml" })
  {
    Ok(pkg_entry) ->
      case bit_array.to_string(pkg_entry.content) {
        Ok(xml_str) -> xml.extract_widget_file_paths(xml_str)
        Error(_) -> []
      }
    Error(_) -> []
  }

  list.filter_map(entries, fn(entry) {
    let name = entry.name
    let fname = basename(name)
    let content = entry.content

    // package.xml
    case fname == "package.xml" {
      True -> Ok(#(fname, content))
      False ->
        // 위젯 XML
        case list.contains(widget_xml_paths, name) {
          True -> Ok(#(fname, content))
          False ->
            // .mjs 파일
            case string.ends_with(name, ".mjs") {
              True -> Ok(#(fname, content))
              False ->
                // .css (editorPreview 제외)
                case
                  string.ends_with(name, ".css")
                  && !string.contains(name, "editorPreview")
                {
                  True -> Ok(#(fname, content))
                  False ->
                    // Classic 위젯: .js, .html (경로 유지)
                    case
                      classic
                      && !string.ends_with(name, "/")
                      && {
                        string.ends_with(name, ".js")
                        || string.ends_with(name, ".html")
                      }
                    {
                      True -> Ok(#(name, content))
                      False -> Error(Nil)
                    }
                }
            }
        }
    }
  })
}

fn write_to_project(
  entries: List(#(String, BitArray)),
  cache_dir: String,
) -> Result(Nil, String) {
  use _ <- result.try(create_dir(cache_dir))
  list.try_each(entries, fn(entry) {
    let #(name, content) = entry
    let out_path = cache_dir <> "/" <> name
    let dir = dirname(out_path)
    use _ <- result.try(create_dir(dir))
    write_file(out_path, content)
  })
}

fn create_dir(path: String) -> Result(Nil, String) {
  case simplifile.create_directory_all(path) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error("디렉토리 생성 실패: " <> path)
  }
}

fn write_file(path: String, content: BitArray) -> Result(Nil, String) {
  simplifile.write_bits(path, content)
  |> result.map_error(fn(_) { "파일 쓰기 실패: " <> path })
}

import simplifile

fn has_mjs_in_dir(dir: String) -> Bool {
  case simplifile.read_directory(dir) {
    Ok(files) -> list.any(files, fn(f) { string.ends_with(f, ".mjs") })
    Error(_) -> False
  }
}

fn basename(path: String) -> String {
  case string.split(path, "/") |> list.last {
    Ok(name) -> name
    Error(_) -> path
  }
}

fn dirname(path: String) -> String {
  let parts = string.split(path, "/")
  case list.length(parts) > 1 {
    True ->
      list.take(parts, list.length(parts) - 1)
      |> string.join("/")
    False -> "."
  }
}

fn short_hash(hash: String) -> String {
  string.slice(hash, 0, 8)
}
