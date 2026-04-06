// Mendix 세션 관리 — 프로필 기반 Chrome 쿠키 유지
// headless로 로그인 상태 확인 → 미로그인 시 visible 브라우저로 로그인 유도

import chrobot_extra
import chrobot_extra/browser_utils
import gleam/result
import gleam/string
import simplifile

/// Mendix 세션 보장 (프로필 쿠키 기반)
pub fn ensure_session() -> Result(Nil, String) {
  cleanup_stale_lockfile()
  case validate_profile_session() {
    Ok(True) -> Ok(Nil)
    _ ->
      case interactive_login() {
        Ok(Nil) -> Ok(Nil)
        Error(msg) -> Error(msg)
      }
  }
}

/// 현재 세션이 유효한지 확인
pub fn is_valid() -> Result(Bool, String) {
  cleanup_stale_lockfile()
  validate_profile_session()
}

// ── 내부 구현 ──

fn cleanup_stale_lockfile() -> Nil {
  let lockfile = "C:/tmp/chrobot-ws-profile/lockfile"
  case simplifile.delete(lockfile) {
    Ok(_) -> Nil
    Error(_) -> {
      kill_zombie_chrome()
      let _ = simplifile.delete(lockfile)
      Nil
    }
  }
}

@external(erlang, "mxpak_ffi", "kill_zombie_chrome")
fn kill_zombie_chrome() -> Nil

fn validate_profile_session() -> Result(Bool, String) {
  use browser <- result.try(
    chrobot_extra.launch()
    |> result.map_error(fn(e) { "브라우저 시작 실패: " <> string.inspect(e) }),
  )

  let result = {
    use page <- result.try(
      chrobot_extra.open(browser, "https://home.mendix.com/", 30_000)
      |> result.map_error(fn(e) { "페이지 열기 실패: " <> string.inspect(e) }),
    )

    use _ <- result.try(
      browser_utils.wait_for_url(
        page: chrobot_extra.with_timeout(page, 30_000),
        matching: fn(url) { url != "about:blank" },
        time_out: 30_000,
      )
      |> result.map_error(fn(e) { "페이지 로드 대기 실패: " <> string.inspect(e) }),
    )

    use _ <- result.try(
      chrobot_extra.await_selector(
        on: chrobot_extra.with_timeout(page, 30_000),
        select: "body",
      )
      |> result.map_error(fn(e) { "페이지 렌더링 대기 실패: " <> string.inspect(e) }),
    )

    use url <- result.try(
      browser_utils.get_url(page)
      |> result.map_error(fn(e) { "URL 확인 실패: " <> string.inspect(e) }),
    )

    Ok(string.contains(url, "home.mendix"))
  }

  let _ = chrobot_extra.quit(browser)
  result
}

fn interactive_login() -> Result(Nil, String) {
  use browser <- result.try(
    chrobot_extra.launch_window()
    |> result.map_error(fn(e) { "visible 브라우저 시작 실패: " <> string.inspect(e) }),
  )

  let result = {
    use page <- result.try(
      chrobot_extra.open(browser, "https://login.mendix.com/", 30_000)
      |> result.map_error(fn(e) { "로그인 페이지 열기 실패: " <> string.inspect(e) }),
    )

    use _ <- result.try(
      browser_utils.wait_for_url(
        page: chrobot_extra.with_timeout(page, 300_000),
        matching: fn(url) { string.starts_with(url, "https://home.mendix.com") },
        time_out: 300_000,
      )
      |> result.map_error(fn(e) { "로그인 타임아웃 (5분): " <> string.inspect(e) }),
    )

    Ok(Nil)
  }

  let _ = chrobot_extra.quit(browser)
  result
}
