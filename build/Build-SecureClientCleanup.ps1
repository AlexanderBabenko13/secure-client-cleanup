<# 
.SYNOPSIS
  Build SecureClientCleanup.exe from a Windows PowerShell script by using ps2exe.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1
#>
[CmdletBinding()]
param(
  [string]$InputFile,
  [string]$OutputFile,
  [string]$IconFile,
  [switch]$Console,
  [switch]$NoIcon,
  [switch]$InstallPs2Exe
)
$ErrorActionPreference = 'Stop'
$ScriptRoot = if ($PSScriptRoot) {
  $PSScriptRoot
} elseif ($PSCommandPath) {
  Split-Path -Parent $PSCommandPath
} elseif ($MyInvocation.MyCommand.Path) {
  Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
  Get-Location
}

if ([string]::IsNullOrWhiteSpace($InputFile)) {
  $InputFile = Join-Path $ScriptRoot '..\src\SecureClientCleanup.ps1'
}
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
  $OutputFile = Join-Path $ScriptRoot '..\dist\SecureClientCleanup.exe'
}
if ([string]::IsNullOrWhiteSpace($IconFile)) {
  $IconFile = Join-Path $ScriptRoot '..\assets\secure-client-cleanup.ico'
}

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

function Wait-FileReadable([string]$Path,[int]$TimeoutSeconds = 10){
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    try {
      $stream = [System.IO.File]::Open($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
      $stream.Close()
      return
    } catch {
      Start-Sleep -Milliseconds 250
    }
  } while ([DateTime]::UtcNow -lt $deadline)

  throw "Output file exists but is not readable: $Path"
}

try {
  $InputFile = [System.IO.Path]::GetFullPath($InputFile)
  $OutputFile = [System.IO.Path]::GetFullPath($OutputFile)
  $IconFile = [System.IO.Path]::GetFullPath($IconFile)

  Write-Info "Build directory: $ScriptRoot"
  Write-Info "Input:  $InputFile"
  Write-Info "Output: $OutputFile"
  if ($NoIcon.IsPresent) {
    Write-Info "Icon: disabled by -NoIcon"
  } else {
    Write-Info "Icon: $IconFile"
  }

  Assert-File -Path $InputFile -Friendly "Input .ps1"

  $outDir = [System.IO.Path]::GetDirectoryName($OutputFile)
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
  if (Test-Path -LiteralPath $OutputFile) {
    Remove-Item -LiteralPath $OutputFile -Force -ErrorAction Stop
  }

  $ps2exeArgs = @($InputFile, $OutputFile)
  if ($useIcon) {
    $ps2exeArgs += '-iconFile'
    $ps2exeArgs += $IconFile
  }
  if (-not $Console.IsPresent) { $ps2exeArgs += '-noConsole' }
  $ps2exeArgs += '-STA'
  $ps2exeArgs += '-requireAdmin'

  $displayArgs = $ps2exeArgs | ForEach-Object {
    $arg = [string]$_
    if ($arg -match '[\s"]') { '"' + ($arg -replace '"','\"') + '"' } else { $arg }
  }
  Write-Info ("Invoke-ps2exe {0}" -f ($displayArgs -join ' '))

  $buildJob = Start-Job -ScriptBlock {
    param(
      [string]$JobInputFile,
      [string]$JobOutputFile,
      [string]$JobIconFile,
      [bool]$JobUseIcon,
      [bool]$JobNoConsole
    )

    $ErrorActionPreference = 'Stop'
    Import-Module ps2exe -Force
    if ($JobUseIcon -and $JobNoConsole) {
      Invoke-ps2exe $JobInputFile $JobOutputFile -iconFile $JobIconFile -noConsole -STA -requireAdmin
    } elseif ($JobUseIcon) {
      Invoke-ps2exe $JobInputFile $JobOutputFile -iconFile $JobIconFile -STA -requireAdmin
    } elseif ($JobNoConsole) {
      Invoke-ps2exe $JobInputFile $JobOutputFile -noConsole -STA -requireAdmin
    } else {
      Invoke-ps2exe $JobInputFile $JobOutputFile -STA -requireAdmin
    }
  } -ArgumentList $InputFile,$OutputFile,$IconFile,$useIcon,(-not $Console.IsPresent)

  try {
    Wait-Job -Job $buildJob | Out-Null
    $buildOutput = Receive-Job -Job $buildJob -Keep 2>&1
    $buildOutput | ForEach-Object { Write-Host $_ }
    if ($buildJob.State -ne 'Completed') {
      $reason = $buildJob.ChildJobs[0].JobStateInfo.Reason
      if ($reason) { throw "Invoke-ps2exe failed: $($reason.Message)" }
      throw "Invoke-ps2exe failed: job state is $($buildJob.State)"
    }
  } finally {
    Remove-Job -Job $buildJob -Force -ErrorAction SilentlyContinue
  }
  [System.GC]::Collect()
  [System.GC]::WaitForPendingFinalizers()

  if (-not (Test-Path -LiteralPath $OutputFile)) {
    throw "Invoke-ps2exe did not create output file: $OutputFile"
  }

  Wait-FileReadable -Path $OutputFile
  $fi = Get-Item -LiteralPath $OutputFile
  $hash = Get-FileHash -LiteralPath $OutputFile -Algorithm SHA256
  Write-Ok "Done: $($fi.FullName)"
  Write-Info ("Size: {0} bytes ({1} MB)" -f $fi.Length, ([math]::Round($fi.Length/1MB,2)))
  Write-Info ("SHA256: {0}" -f $hash.Hash)
} catch {
  Write-Err "Build failed: $($_.Exception.Message)"
  exit 1
}
