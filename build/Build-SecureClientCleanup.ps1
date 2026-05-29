<# 
.SYNOPSIS
  Build-Exe.ps1 — сборка GUI .exe из PowerShell-скрипта с помощью ps2exe.
#>
[CmdletBinding()]
param(
  [string]$InputFile  = (Join-Path $PSScriptRoot 'Cisco-Cleanup-GUI-Scan_vivid.ps1'),
  [string]$OutputFile = (Join-Path $PSScriptRoot 'Cisco-Cleanup-GUI.exe'),
  [string]$IconFile   = (Join-Path $PSScriptRoot 'cisco_cleanup.ico'),
  [switch]$Console
)
$ErrorActionPreference = 'Stop'
function Write-Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok($m){ Write-Host "[ OK ] $m" -ForegroundColor Green }
function Write-Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err($m){ Write-Host "[FAIL] $m" -ForegroundColor Red }
function Ensure-Module([string]$Name){
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    Write-Info "Модуль '$Name' не найден. Устанавливаю..."
    try {
      $policy = Get-ExecutionPolicy -Scope Process -ErrorAction SilentlyContinue
      if ($policy -eq $null -or $policy -eq 'Undefined') {
        Set-ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue | Out-Null
      }
      Install-Module $Name -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
      Write-Ok "Модуль '$Name' установлен."
    } catch {
      Write-Err "Не удалось установить модуль '$Name': $($_.Exception.Message)"
      throw
    }
  } else { Write-Ok "Модуль '$Name' уже установлен." }
  Import-Module $Name -Force
}
function Assert-File([string]$Path,[string]$Friendly){
  if (-not (Test-Path -LiteralPath $Path)) { throw "$Friendly не найден: $Path" }
}
try {
  Write-Info "Каталог сборки: $PSScriptRoot"
  Write-Info "Вход:  $InputFile"
  Write-Info "Выход: $OutputFile"
  Write-Info "Иконка: $IconFile"
  Assert-File -Path $InputFile -Friendly "Входной .ps1"
  if (-not (Test-Path -LiteralPath $IconFile)) { Write-Warn "Иконка не найдена — продолжу без неё"; $IconFile = $null }
  $outDir = Split-Path -LiteralPath $OutputFile -Parent
  if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
  Ensure-Module -Name 'ps2exe'
  Write-Info "Собираю exe..."
  if ($IconFile) { Invoke-ps2exe -InputFile $InputFile -OutputFile $OutputFile -IconFile $IconFile -NoConsole:(!$Console.IsPresent) }
  else { Invoke-ps2exe -InputFile $InputFile -OutputFile $OutputFile -NoConsole:(!$Console.IsPresent) }
  if (Test-Path -LiteralPath $OutputFile) { $fi = Get-Item -LiteralPath $OutputFile; Write-Ok "Готово: $($fi.FullName) ($([math]::Round($fi.Length/1MB,2)) MB)" }
  else { throw "Invoke-ps2exe не создал файл." }
} catch { Write-Err "Сборка не удалась: $($_.Exception.Message)"; exit 1 }
