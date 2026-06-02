<# 
.SYNOPSIS
  Build SecureClientCleanup.exe from a Windows PowerShell script by using ps2exe.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1
#>
[CmdletBinding()]
param(
  [string]$InputFile  = (Join-Path $PSScriptRoot '..\src\SecureClientCleanup.ps1'),
  [string]$OutputFile = (Join-Path $PSScriptRoot '..\dist\SecureClientCleanup.exe'),
  [string]$IconFile   = (Join-Path $PSScriptRoot '..\assets\secure-client-cleanup.ico'),
  [switch]$Console,
  [switch]$NoIcon,
  [switch]$InstallPs2Exe
)
$ErrorActionPreference = 'Stop'
function Write-Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Write-Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err($m){ Write-Host "[FAIL] $m" -ForegroundColor Red }

function Ensure-Ps2Exe([switch]$Install){
  if (-not (Get-Module -ListAvailable -Name 'ps2exe')) {
    if (-not $Install.IsPresent) {
      throw "Module 'ps2exe' was not found. Install it with: Install-Module ps2exe -Scope CurrentUser"
    }

    Write-Info "Module 'ps2exe' was not found. Installing because -InstallPs2Exe was specified..."
    try {
      Install-Module ps2exe -Scope CurrentUser -Force -ErrorAction Stop
      Write-Ok "Module 'ps2exe' installed."
    } catch {
      Write-Err "Failed to install module 'ps2exe': $($_.Exception.Message)"
      throw
    }
  } else {
    Write-Ok "Module 'ps2exe' is already installed."
  }

  Import-Module ps2exe -Force
}

function Assert-File([string]$Path,[string]$Friendly){
  if (-not (Test-Path -LiteralPath $Path)) { throw "$Friendly not found: $Path" }
}

try {
  $InputFile = [System.IO.Path]::GetFullPath($InputFile)
  $OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
  $IconFile = [System.IO.Path]::GetFullPath($IconFile)

  Write-Info "Build directory: $PSScriptRoot"
  Write-Info "Input:  $InputFile"
  Write-Info "Output: $OutputFile"
  if ($NoIcon.IsPresent) {
    Write-Info "Icon: disabled by -NoIcon"
  } else {
    Write-Info "Icon: $IconFile"
  }

  Assert-File -Path $InputFile -Friendly "Input .ps1"

  $outDir = Split-Path -LiteralPath $OutputFile -Parent
  if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    Write-Ok "Created directory: $outDir"
  }

  $useIcon = $false
  if (-not $NoIcon.IsPresent) {
    if (Test-Path -LiteralPath $IconFile) {
      $useIcon = $true
    } else {
      Write-Warn "Icon was not found, build will continue without it: $IconFile"
    }
  }

  Ensure-Ps2Exe -Install:$InstallPs2Exe.IsPresent

  Write-Info "Building exe..."
  $ps2exeArgs = @{
    inputFile = $InputFile
    outputFile = $OutputFile
  }
  if ($useIcon) { $ps2exeArgs.iconFile = $IconFile }
  if (-not $Console.IsPresent) { $ps2exeArgs.noConsole = $true }

  Invoke-ps2exe @ps2exeArgs

  if (-not (Test-Path -LiteralPath $OutputFile)) {
    throw "Invoke-ps2exe did not create output file: $OutputFile"
  }

  $fi = Get-Item -LiteralPath $OutputFile
  $hash = Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256
  Write-Ok "Done: $($fi.FullName)"
  Write-Info ("Size: {0} bytes ({1} MB)" -f $fi.Length, ([math]::Round($fi.Length/1MB,2)))
  Write-Info ("SHA256: {0}" -f $hash.Hash)
} catch {
  Write-Err "Build failed: $($_.Exception.Message)"
  exit 1
}
