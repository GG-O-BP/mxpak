#!/usr/bin/env sh
# mxpak installer for macOS / Linux
# Usage: curl -fsSL https://github.com/GG-O-BP/mxpak/releases/latest/download/install.sh | sh

set -eu

REPO="GG-O-BP/mxpak"
BIN_NAME="mxp"
INSTALL_DIR="${MXPAK_HOME:-$HOME/.mxpak}/bin"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${BIN_NAME}"

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
cyan()  { printf '\033[36m%s\033[0m\n' "$1"; }

# 1. Erlang detection
if ! command -v escript >/dev/null 2>&1; then
  red "Erlang/OTP is required (escript command not found)."
  echo ""
  echo "Install with:"
  case "$(uname -s)" in
    Darwin) echo "  brew install erlang" ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        echo "  sudo apt-get install -y erlang"
      elif command -v dnf >/dev/null 2>&1; then
        echo "  sudo dnf install -y erlang"
      elif command -v pacman >/dev/null 2>&1; then
        echo "  sudo pacman -S erlang"
      else
        echo "  use your distro's package manager to install erlang"
      fi
      ;;
    *) echo "  https://www.erlang.org/downloads" ;;
  esac
  echo ""
  echo "Then re-run this installer."
  exit 1
fi

# 2. Download tool
if command -v curl >/dev/null 2>&1; then
  DL="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -qO"
else
  red "Either curl or wget is required."
  exit 1
fi

# 3. Download escript
cyan "Downloading mxp..."
mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/$BIN_NAME"
$DL "$TARGET" "$DOWNLOAD_URL"
chmod +x "$TARGET"

green "Installed to: $TARGET"

# 4. PATH guidance
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    green "Already on PATH."
    echo ""
    cyan "Verify with:"
    echo "  mxp --version"
    ;;
  *)
    echo ""
    cyan "Add this directory to your PATH:"
    echo ""
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
    SHELL_NAME="$(basename "${SHELL:-}")"
    case "$SHELL_NAME" in
      bash) echo "  # append to ~/.bashrc or ~/.bash_profile" ;;
      zsh)  echo "  # append to ~/.zshrc" ;;
      fish) echo "  # fish: fish_add_path $INSTALL_DIR" ;;
    esac
    echo ""
    echo "Then verify: mxp --version"
    ;;
esac
