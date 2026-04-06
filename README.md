# mxpak

Mendix widget `.mpk` package manager with global caching and hard links.

Download each widget once, cache it globally, and share it across all your projects at zero extra disc cost.

## How it works

When you run `mxp install`, mxpak downloads `.mpk` files from the Mendix Marketplace and stores them in a global cache at `~/.mxpak/store/`, organised by SHA-256 hash. Any project that needs the same widget gets a hard link to the cached file — no network request, no file copy, no additional disc usage.

If the cache and project are on different drives (where hard links don't work), mxpak falls back to a regular file copy automatically.

## Install

```sh
# Build from source (requires Gleam + Erlang/OTP)
gleam export erlang-shipment
# The built binary is at build/erlang-shipment/entrypoint.sh
```

## Usage

```
mxp <command> [options]
```

| Command | Description |
|---|---|
| `install [project_root]` | Resolve and install all widgets from config (lock file preferred) |
| `add <name> --version <v>` | Add a widget to config and install |
| `remove <name>` | Remove a widget from config |
| `update [name]` | Update widget(s) (clears lock, re-resolves) |
| `marketplace [project_root]` | Interactive TUI browser for the Mendix Marketplace |
| `outdated [project_root]` | List widgets with available updates |
| `list [project_root]` | List installed widgets |
| `info <name>` | Show widget details |
| `audit [project_root]` | Verify SHA-256 integrity of all installed `.mpk` files |
| `cache clean` | Clean the global cache |

## Configuration

Add a `[tools.mendraw]` section to your project's TOML config:

```toml
[tools.mendraw]
mode = "mpk"
widgets_dir = "widgets"

[tools.mendraw.widgets.Badge]
version = "3.2.2"
id = 50325

[tools.mendraw.widgets."com.mendix.widget.web.Datagrid"]
version = "2.22.3"
id = 116540
```

Running `mxp install` generates a lock file (`mxpak.lock`) that pins exact versions and SHA-256 hashes for reproducible builds.

## Disc savings

| | Without mxpak | With mxpak |
|---|---|---|
| 5 projects, ~55 MB widgets each | 275 MB, downloaded 5 times | 55 MB total, instant after first install |

## Licence

[MPL-2.0](LICENCE)
