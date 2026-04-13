# mxpak

Mendix package manager and workspace deduplicator with global caching and hard links.

Download each widget once, cache it globally, and share it across all your projects at zero extra disc cost. Then deduplicate the rest of the shared assets (libraries, theme resources) in one pass.

## How it works

mxpak has two complementary mechanisms, both backed by the same content-addressable store at `~/.mxpak/store/{sha256}/`:

1. **`mxp install` — widget dependency manager.** Downloads `.mpk` files from the Mendix Marketplace, stores them in the CAS by SHA-256 hash, and hard-links them into `<project>/widgets/`. Locked via `mxpak.lock` for reproducibility.
2. **`mxp scan` — workspace deduplicator.** Scans every project under a workspace, hashes shared files that `install` doesn't manage (Java libraries in `userlib/`/`vendorlib/`, Mendix standard theme assets in `themesource/`), and replaces duplicates with hard links to a single CAS-stored copy.

If the cache and project are on different drives (where hard links don't work), mxpak falls back to a regular file copy automatically.

## Install

**Prerequisite** — Erlang/OTP 26+ must be on `PATH` (`escript` command available).

- macOS: `brew install erlang`
- Windows: `winget install Erlang.ErlangOTP`
- Linux: `sudo apt-get install erlang` (or your distro's equivalent)

### One-liner

**macOS / Linux**

```sh
curl -fsSL https://github.com/GG-O-BP/mxpak/releases/latest/download/install.sh | sh
```

**Windows (PowerShell)**

```powershell
iwr -useb https://github.com/GG-O-BP/mxpak/releases/latest/download/install.ps1 | iex
```

Both scripts place the `mxp` escript at `~/.mxpak/bin/` (macOS/Linux) or `%USERPROFILE%\.mxpak\bin\` (Windows). On Windows the installer adds this directory to your user `PATH` automatically. On macOS/Linux, add it yourself:

```sh
export PATH="$HOME/.mxpak/bin:$PATH"
```

Verify:

```sh
mxp --version
```

### From source

```sh
git clone https://github.com/GG-O-BP/mxpak.git
cd mxpak
gleam run -m gleescript    # produces ./mxpak — rename to mxp and place on PATH
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
| `init [path]` | Initialise a workspace — generate `.mxpak-workspace.toml` with default scan rules |
| `scan [path]` | Deduplicate `*.jar` and `themesource/**` across all projects under the workspace |
| `status [path]` | Show per-project deduplication stats and disc savings |

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

## Workspace deduplication

`mxp scan` targets shared assets that `install` doesn't manage. Default scan rules in `.mxpak-workspace.toml`:

```toml
[scan]
include      = ["*.jar"]            # libraries in userlib/ and vendorlib/
include_dirs = ["themesource"]      # Mendix standard theme modules (atlas_core, datawidgets, etc.)
exclude_dirs = ["widgets", "deployment", "javascriptsource", ...]
```

`widgets/` is excluded because `mxp install` already deduplicates it via the CAS — running `scan` over already-linked files would be a no-op.

### Measured savings (16 real Mendix projects, ~23 GB total)

| Target | Total | After dedup | Saved | Ratio |
|---|---|---|---|---|
| `widgets/*.mpk` (via `install`) | 804 MB | 533 MB | **270 MB** | 33.6% |
| `*.jar` in userlib/vendorlib (via `scan`) | 534 MB | 222 MB | **311 MB** | 58.3% |
| `themesource/**` (via `scan`) | 57 MB | 15 MB | **42 MB** | 74.0% |
| **Combined** | **1,395 MB** | **770 MB** | **623 MB** | **44.7%** |

## Licence

[MPL-2.0](LICENCE)
