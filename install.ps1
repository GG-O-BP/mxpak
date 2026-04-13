# mxpak 설치 스크립트 — Windows (PowerShell)
# 사용법: iwr -useb https://github.com/GG-O-BP/mxpak/releases/latest/download/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo        = "GG-O-BP/mxpak"
$BinName     = "mxp"
$InstallDir  = if ($env:MXPAK_HOME) { Join-Path $env:MXPAK_HOME "bin" } else { Join-Path $env:USERPROFILE ".mxpak\bin" }
$DownloadUrl = "https://github.com/$Repo/releases/latest/download/$BinName"

function Write-Info  ($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok    ($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Err   ($msg) { Write-Host $msg -ForegroundColor Red }

# 1. Erlang 감지
if (-not (Get-Command escript -ErrorAction SilentlyContinue)) {
  Write-Err "Erlang/OTP이 필요합니다 (escript 명령을 찾을 수 없음)."
  Write-Host ""
  Write-Host "설치 방법:"
  Write-Host "  winget install Erlang.ErlangOTP"
  Write-Host "  # 또는: choco install erlang"
  Write-Host ""
  Write-Host "설치 후 새 터미널을 열고 다시 실행하세요."
  exit 1
}

# 2. 설치 디렉토리
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# 3. escript 다운로드
Write-Info "mxp 다운로드 중..."
$Target = Join-Path $InstallDir $BinName
try {
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $Target -UseBasicParsing
} catch {
  Write-Err "다운로드 실패: $_"
  exit 1
}

# 4. .cmd 래퍼 생성 (Windows에서 확장자 없이 실행하려면 필요)
$CmdWrapper = Join-Path $InstallDir "$BinName.cmd"
@"
@echo off
escript "%~dp0$BinName" %*
"@ | Set-Content -Path $CmdWrapper -Encoding ASCII

Write-Ok "설치 완료: $InstallDir"

# 5. PATH 등록 (User scope — 관리자 권한 불필요)
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$InstallDir*") {
  $NewPath = if ([string]::IsNullOrEmpty($UserPath)) { $InstallDir } else { "$UserPath;$InstallDir" }
  [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
  Write-Ok "PATH에 추가했습니다."
  Write-Host ""
  Write-Info "새 터미널을 열어 다음 명령으로 확인하세요:"
  Write-Host "  mxp --version"
} else {
  Write-Ok "PATH에 이미 등록되어 있습니다."
  Write-Host ""
  Write-Info "다음 명령으로 확인:"
  Write-Host "  mxp --version"
}
