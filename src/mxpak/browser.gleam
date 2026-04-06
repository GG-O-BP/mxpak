// headless 브라우저로 Marketplace Releases 탭 → XAS 응답 수집

import chrobot_extra
import chrobot_extra/chrome
import chrobot_extra/network_idle
import chrobot_extra/network_listener
import chrobot_extra/protocol/page as page_protocol
import chrobot_extra/protocol/runtime
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import mxpak/registry/xas_parser.{type XasVersion}

/// 모든 content_id에 대해 XAS 버전 정보를 브라우저로 수집
pub fn get_all_versions(
  content_ids: List(Int),
) -> Result(Dict(Int, List(XasVersion)), String) {
  use browser <- result.try(
    chrobot_extra.launch()
    |> result.map_error(fn(_) { "브라우저 시작 실패" }),
  )

  let results =
    list.fold(content_ids, dict.new(), fn(acc, content_id) {
      let versions = collect_versions_for_id(browser, content_id)
      dict.insert(acc, content_id, versions)
    })

  let _ = chrobot_extra.quit(browser)
  Ok(results)
}

/// 단일 content_id에 대한 XAS 버전 수집
pub fn get_versions_for(content_id: Int) -> Result(List(XasVersion), String) {
  use browser <- result.try(
    chrobot_extra.launch()
    |> result.map_error(fn(_) { "브라우저 시작 실패" }),
  )

  let versions = collect_versions_for_id(browser, content_id)
  let _ = chrobot_extra.quit(browser)
  Ok(versions)
}

// ── 내부 구현 ──

fn collect_versions_for_id(
  browser: process.Subject(chrome.Message),
  content_id: Int,
) -> List(XasVersion) {
  let url =
    "https://marketplace.mendix.com/link/component/"
    <> int.to_string(content_id)

  case collect_versions_impl(browser, url) {
    Ok(versions) -> versions
    Error(msg) -> {
      io.println_error(
        "  [mxpak] 오류 (id=" <> int.to_string(content_id) <> "): " <> msg,
      )
      []
    }
  }
}

fn collect_versions_impl(
  browser: process.Subject(chrome.Message),
  url: String,
) -> Result(List(XasVersion), String) {
  use page <- result.try(
    chrobot_extra.open(browser, "about:blank", 30_000)
    |> result.map_error(fn(_) { "페이지 생성 실패" }),
  )

  let result = {
    use response_listener <- result.try(
      network_listener.start(page)
      |> result.map_error(fn(_) { "network listener 시작 실패" }),
    )

    let inner_result = {
      use idle_listener <- result.try(
        network_idle.start(page)
        |> result.map_error(fn(_) { "network idle listener 시작 실패" }),
      )

      let caller = chrobot_extra.page_caller(page)
      use _ <- result.try(
        page_protocol.navigate(
          caller,
          url: url,
          referrer: option.None,
          transition_type: option.None,
          frame_id: option.None,
        )
        |> result.map_error(fn(_) { "네비게이션 실패" }),
      )

      let _ =
        network_idle.wait_for_idle(
          idle_listener,
          quiet_ms: 500,
          time_out: 30_000,
        )
      network_idle.stop(idle_listener)

      try_click_releases_tab(page)

      case network_idle.start(page) {
        Ok(idle2) -> {
          let _ =
            network_idle.wait_for_idle(idle2, quiet_ms: 500, time_out: 30_000)
          network_idle.stop(idle2)
        }
        Error(_) -> Nil
      }

      process.sleep(3000)

      let xas_responses =
        network_listener.collect_responses(response_listener, filter: fn(event) {
          string.contains(event.response.url, "/xas/")
        })
        |> result.unwrap([])

      let versions =
        list.flat_map(xas_responses, fn(resp) {
          xas_parser.parse_xas_body(resp.body)
        })

      Ok(deduplicate_versions(versions))
    }

    network_listener.stop(response_listener)
    inner_result
  }

  let _ = chrobot_extra.close(page)
  result
}

fn deduplicate_versions(versions: List(XasVersion)) -> List(XasVersion) {
  list.fold(versions, #([], dict.new()), fn(acc, v) {
    let #(result_list, seen) = acc
    case dict.has_key(seen, v.s3_object_id) {
      True -> acc
      False -> #(
        list.append(result_list, [v]),
        dict.insert(seen, v.s3_object_id, True),
      )
    }
  }).0
}

// Releases 탭 클릭 — 3개 셀렉터 순차 시도
fn try_click_releases_tab(page: chrobot_extra.Page) -> Nil {
  case chrobot_extra.click_selector(on: page, target: "a.mx-name-tabPage10") {
    Ok(_) -> Nil
    Error(_) -> {
      case try_click_tab_by_text(page) {
        Ok(_) -> Nil
        Error(_) -> {
          let _ =
            chrobot_extra.eval(
              on: page,
              js: "(() => { const tabs = document.querySelectorAll('a[role=\"tab\"]'); for (const t of tabs) { if (t.textContent.includes('Releases')) { t.click(); return true; } } return false; })()",
            )
          Nil
        }
      }
    }
  }
}

fn try_click_tab_by_text(
  page: chrobot_extra.Page,
) -> Result(Nil, chrome.RequestError) {
  use tabs <- result.try(chrobot_extra.select_all(
    on: page,
    matching: "a[role=\"tab\"]",
  ))
  find_and_click_releases(page, tabs)
}

fn find_and_click_releases(
  page: chrobot_extra.Page,
  tabs: List(runtime.RemoteObjectId),
) -> Result(Nil, chrome.RequestError) {
  case tabs {
    [] -> Error(chrome.NotFoundError)
    [tab, ..rest] -> {
      case chrobot_extra.get_text(on: page, from: tab) {
        Ok(text) -> {
          case string.contains(text, "Releases") {
            True ->
              chrobot_extra.click(on: page, target: tab)
              |> result.map(fn(_) { Nil })
            False -> find_and_click_releases(page, rest)
          }
        }
        Error(_) -> find_and_click_releases(page, rest)
      }
    }
  }
}
