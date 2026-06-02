# Build Guide

Secure Client Cleanup Utility can be built into a Windows GUI executable with ps2exe.

## Requirements

- Windows PowerShell 5.1
- ps2exe PowerShell module

## Install ps2exe

Install ps2exe manually:

```powershell
Install-Module ps2exe -Scope CurrentUser
```

The build script does not install ps2exe automatically unless `-InstallPs2Exe` is explicitly provided.

## Build

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1
```

## Build And Install ps2exe

Use this only when you intentionally want the build script to install ps2exe:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1 -InstallPs2Exe
```

## Build Without Icon

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1 -NoIcon
```

## Console Build

For troubleshooting build output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1 -Console
```

## Defaults

Input script:

```text
src\SecureClientCleanup.ps1
```

Icon:

```text
assets\secure-client-cleanup.ico
```

Output:

```text
dist\SecureClientCleanup.exe
```

## SHA256 Hash

After a successful build, the build script prints:

- Full path to the executable.
- File size.
- SHA256 hash.

Use the SHA256 hash to verify that the executable distributed to support engineers matches the build output.
