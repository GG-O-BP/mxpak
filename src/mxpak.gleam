//// mxpak — Mendix 위젯 .mpk 패키지매니저
//// CLI: mxp install / add / marketplace / update / ...

import gleam/dict
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import mxpak/cache
import mxpak/cli
import mxpak/config
import mxpak/lockfile
import mxpak/marketplace
import mxpak/output
import mxpak/resolver

pub const version = "0.1.0"

pub fn main() {
  ensure_apps_started()
  let args = get_arguments()

  case cli.parse(args) {
    cli.Install(project_root) -> run_install(project_root)
    cli.Marketplace(project_root) -> run_marketplace(project_root)
    cli.Add(name, version_constraint) -> run_add(name, version_constraint)
    cli.Remove(name) -> run_remove(name)
    cli.Update(name) -> run_update(name)
    cli.Outdated(project_root) -> run_outdated(project_root)
    cli.List(project_root) -> run_list(project_root)
    cli.Info(name) -> run_info(name)
    cli.Audit(project_root) -> run_audit(project_root)
    cli.CacheClean -> run_cache_clean()
    cli.Version -> io.println("mxpak v" <> version)
    cli.Help -> cli.print_help()
    cli.Unknown(cmd) -> {
      io.println_error("알 수 없는 명령: " <> cmd)
      cli.print_help()
    }
  }
}

// ── install ──

fn run_install(project_root: String) -> Nil {
  output.log("mxpak v" <> version <> " — 위젯 설치")

  case resolver.resolve_all(project_root) {
    Ok(results) -> {
      // 락파일 갱신
      let entries =
        list.fold(results, dict.new(), fn(acc, r) {
          dict.insert(
            acc,
            r.name,
            lockfile.LockEntry(
              version: r.version,
              hash: r.hash,
              content_id: r.content_id,
              s3_id: r.s3_id,
              classic: r.classic,
            ),
          )
        })
      let _ = lockfile.write(project_root, entries)

      // JSON 결과 출력
      let widgets_json =
        list.map(results, fn(r) {
          json.object([
            #("name", json.string(r.name)),
            #("version", json.string(r.version)),
            #("classic", json.bool(r.classic)),
          ])
        })
        |> json.array(fn(x) { x })
      output.result_ok(widgets_json)
    }
    Error(msg) -> output.result_error(msg)
  }
}

// ── marketplace ──

fn run_marketplace(project_root: String) -> Nil {
  case config.get_pat(project_root) {
    Some(pat) -> marketplace.run(pat, project_root)
    None -> {
      io.println_error("MENDIX_PAT가 필요합니다. .env에 설정하세요.")
    }
  }
}

// ── add ──

fn run_add(name: String, version_arg: cli.VersionArg) -> Nil {
  let version = case version_arg {
    cli.VersionSpecified(v) -> v
    cli.VersionLatest -> ""
  }
  case version {
    "" -> io.println_error("버전을 지정하세요: mxp add " <> name <> " --version <v>")
    v -> {
      case config.write_widget(".", name, v, None, None) {
        Ok(_) -> {
          output.log(name <> " v" <> v <> " 추가됨")
          run_install(".")
        }
        Error(msg) -> io.println_error("추가 실패: " <> msg)
      }
    }
  }
}

// ── remove ──

fn run_remove(name: String) -> Nil {
  case config.remove_widget(".", name) {
    Ok(_) -> output.log(name <> " 제거됨")
    Error(msg) -> io.println_error("제거 실패: " <> msg)
  }
}

// ── update ──

fn run_update(name: String) -> Nil {
  case name {
    "" -> output.log("전체 업데이트: mxp install 실행")
    _ -> output.log("업데이트: " <> name <> " (락파일 삭제 후 재설치)")
  }
  let _ = lockfile.remove(".")
  run_install(".")
}

// ── outdated ──

fn run_outdated(project_root: String) -> Nil {
  case config.read(project_root) {
    Ok(cfg) -> {
      let widgets = dict.to_list(cfg.widgets)
      case widgets {
        [] -> io.println("설치된 위젯 없음")
        _ ->
          list.each(widgets, fn(pair) {
            let #(name, widget) = pair
            io.println(name <> " v" <> widget.version)
          })
      }
    }
    Error(msg) -> io.println_error(msg)
  }
}

// ── list ──

fn run_list(project_root: String) -> Nil {
  case config.read(project_root) {
    Ok(cfg) -> {
      let widgets = dict.to_list(cfg.widgets)
      case widgets {
        [] -> io.println("설치된 위젯 없음")
        _ ->
          list.each(widgets, fn(pair) {
            let #(name, widget) = pair
            let id_str = case widget.id {
              Some(id) -> " [" <> string.inspect(id) <> "]"
              None -> ""
            }
            let classic_str = case widget.classic {
              Some(True) -> " (classic)"
              _ -> ""
            }
            io.println(
              "  " <> name <> " v" <> widget.version <> id_str <> classic_str,
            )
          })
      }
    }
    Error(msg) -> io.println_error(msg)
  }
}

// ── info ──

fn run_info(name: String) -> Nil {
  io.println("위젯 정보: " <> name)
  io.println("(API 조회는 PAT가 필요합니다)")
}

// ── audit ──

fn run_audit(project_root: String) -> Nil {
  case lockfile.read(project_root) {
    Ok(lock) -> {
      let entries = dict.to_list(lock.entries)
      case entries {
        [] -> io.println("락파일에 엔트리 없음")
        _ ->
          list.each(entries, fn(pair) {
            let #(name, entry) = pair
            case entry.hash {
              "" -> io.println("  " <> name <> " — 해시 없음 (검증 불가)")
              hash ->
                case cache.has(hash) {
                  True ->
                    io.println("  " <> name <> " v" <> entry.version <> " ✓")
                  False ->
                    io.println(
                      "  " <> name <> " v" <> entry.version <> " ✗ 캐시 없음",
                    )
                }
            }
          })
      }
    }
    Error(_) -> io.println("mxpak.lock 파일이 없습니다. mxp install을 먼저 실행하세요.")
  }
}

// ── cache clean ──

fn run_cache_clean() -> Nil {
  case cache.clean() {
    Ok(_) -> output.log("캐시 삭제 완료")
    Error(msg) -> io.println_error("캐시 삭제 실패: " <> msg)
  }
}

// ── FFI ──

@external(erlang, "mxpak_ffi", "get_arguments")
fn get_arguments() -> List(String)

@external(erlang, "mxpak_ffi", "ensure_apps_started")
fn ensure_apps_started() -> Nil
