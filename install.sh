#!/usr/bin/env sh
# mxpak 설치 스크립트 — macOS / Linux
# 사용법: curl -fsSL https://github.com/GG-O-BP/mxpak/releases/latest/download/install.sh | sh

set -eu

REPO="GG-O-BP/mxpak"
BIN_NAME="mxp"
INSTALL_DIR="${MXPAK_HOME:-$HOME/.mxpak}/bin"
DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/${BIN_NAME}"

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
cyan()  { printf '\033[36m%s\033[0m\n' "$1"; }

# 1. Erlang 감지
if ! command -v escript >/dev/null 2>&1; then
  red "Erlang/OTP이 필요합니다 (escript 명령을 찾을 수 없음)."
  echo ""
  echo "설치 방법:"
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
        echo "  배포판 패키지 관리자로 erlang 을 설치하세요."
      fi
      ;;
    *) echo "  https://www.erlang.org/downloads" ;;
  esac
  echo ""
  echo "설치 후 다시 실행하세요."
  exit 1
fi

# 2. 다운로드 도구 선택
if command -v curl >/dev/null 2>&1; then
  DL="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
  DL="wget -qO"
else
  red "curl 또는 wget 이 필요합니다."
  exit 1
fi

# 3. escript 다운로드
cyan "mxp 다운로드 중..."
mkdir -p "$INSTALL_DIR"
TARGET="$INSTALL_DIR/$BIN_NAME"
$DL "$TARGET" "$DOWNLOAD_URL"
chmod +x "$TARGET"

green "설치 완료: $TARGET"

# 4. PATH 안내
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    green "PATH 에 이미 등록되어 있습니다."
    echo ""
    cyan "다음 명령으로 확인:"
    echo "  mxp --version"
    ;;
  *)
    echo ""
    cyan "PATH 에 다음을 추가하세요:"
    echo ""
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
    SHELL_NAME="$(basename "${SHELL:-}")"
    case "$SHELL_NAME" in
      bash) echo "  # ~/.bashrc 또는 ~/.bash_profile 에 추가" ;;
      zsh)  echo "  # ~/.zshrc 에 추가" ;;
      fish) echo "  # fish_add_path $INSTALL_DIR  (fish 전용)" ;;
    esac
    echo ""
    echo "적용 후: mxp --version"
    ;;
esac
