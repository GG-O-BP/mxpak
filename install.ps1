# mxpak installer for Windows (PowerShell)
# Usage: iwr -useb https://github.com/GG-O-BP/mxpak/releases/latest/download/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo        = "GG-O-BP/mxpak"
$BinName     = "mxp"
$InstallDir  = if ($env:MXPAK_HOME) { Join-Path $env:MXPAK_HOME "bin" } else { Join-Path $env:USERPROFILE ".mxpak\bin" }
$DownloadUrl = "https://github.com/$Repo/releases/latest/download/$BinName"

function Write-Info  ($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Ok    ($msg) { Write-Host $msg -ForegroundColor Green }
function Write-Err   ($msg) { Write-Host $msg -ForegroundColor Red }

# 1. Erlang detection
if (-not (Get-Command escript -ErrorAction SilentlyContinue)) {
  Write-Err "Erlang/OTP is required (escript command not found)."
  Write-Host ""
  Write-Host "Install with:"
  Write-Host "  winget install Erlang.ErlangOTP"
  Write-Host "  # or: choco install erlang"
  Write-Host ""
  Write-Host "Then open a new terminal and re-run this installer."
  exit 1
}

# 2. Install directory
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# 3. Download escript
Write-Info "Downloading mxp..."
$Target = Join-Path $InstallDir $BinName
try {
  Invoke-WebRequest -Uri $DownloadUrl -OutFile $Target -UseBasicParsing
} catch {
  Write-Err "Download failed: $_"
  exit 1
}

# 4. .cmd wrapper (so 'mxp' resolves on Windows without an extension)
$CmdWrapper = Join-Path $InstallDir "$BinName.cmd"
@"
@echo off
escript "%~dp0$BinName" %*
"@ | Set-Content -Path $CmdWrapper -Encoding ASCII

Write-Ok "Installed to: $InstallDir"

# 5. Register PATH (User scope, no admin required)
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notlike "*$InstallDir*") {
  $NewPath = if ([string]::IsNullOrEmpty($UserPath)) { $InstallDir } else { "$UserPath;$InstallDir" }
  [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
  Write-Ok "Added to user PATH."
  Write-Host ""
  Write-Info "Open a NEW terminal, then verify:"
  Write-Host "  mxp --version"
  Write-Host ""
  Write-Info "Or use it in this session right now:"
  Write-Host "  `$env:PATH = `"$InstallDir;`$env:PATH`""
  Write-Host "  mxp --version"
} else {
  Write-Ok "Already on PATH."
  Write-Host ""
  Write-Info "Verify with:"
  Write-Host "  mxp --version"
}
