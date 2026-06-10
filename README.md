# Secure Client Cleanup Utility

[Русский язык](README.ru.md)

Secure Client Cleanup Utility is a Windows PowerShell 5.1 WPF tool for support engineers and system administrators who need to safely prepare a Windows workstation for Cisco AnyConnect / Cisco Secure Client reinstall.

## Purpose

Use this tool when Cisco AnyConnect or Cisco Secure Client is broken, partially removed, or cannot be reinstalled cleanly.

The goal is controlled cleanup before reinstall. The utility targets known Cisco AnyConnect and Cisco Secure Client artifacts; it is not intended to broadly remove all Cisco software or data from a workstation.

## Administrator Warning

Run the utility only with administrator privileges.

Cleanup can stop services and processes, delete targeted folders, and remove targeted registry keys. Always use Scan, diagnostics, and Dry Run / WhatIf before destructive cleanup.

## Safe Workflow

1. Scan
2. Dry Run / WhatIf
3. Backup
4. Cleanup
5. Reboot
6. Reinstall Cisco Secure Client

## Features

- Scan Cisco AnyConnect and Cisco Secure Client services, processes, folders, registry keys, user AppData locations, ProgramData locations, installed programs, and protected Cisco roots.
- Smart discovery under `Program Files\Cisco` and `Program Files (x86)\Cisco`.
- Non-destructive Dry Run / WhatIf cleanup preview.
- Registry and folder backups before removal when backup is enabled.
- HTML, CSV, and JSON export.
- HTML reports with escaped content.
- VPN-related diagnostics for DNS, ping, TCP 443, proxy settings, routes, adapters, and conflicting VPN tools.
- Safety guards that block broad Cisco registry roots and broad Cisco folders from automated cleanup.
- GUI executable build with ps2exe.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Administrator rights for cleanup and full diagnostics

## Quick Start: Script

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\SecureClientCleanup.ps1
```

The bootstrap relaunches the utility elevated and in STA mode when required.

## Build EXE

Install ps2exe:

```powershell
Install-Module ps2exe -Scope CurrentUser
```

Build the executable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1
```

Default output:

```text
dist\SecureClientCleanup.exe
```

After a successful build, the build script prints the executable SHA256 hash and output information.

See the [Build Guide](docs/BUILD.md) for additional build options.

## Logs And Reports

Logs, scan exports, backups, and HTML reports are written under the cleanup output directory selected in the GUI.

These artifacts may contain local paths, hostnames, service names, adapter names, and diagnostic details. Review and sanitize them before sharing.

## Important Limitations

- Broad Cisco registry roots are not removed automatically.
- Broad Cisco program folders are blocked from automated cleanup.
- Network reset is not performed automatically.
- `Win32_Product` is not used and must not be added.
- The tool is intended for Cisco AnyConnect / Cisco Secure Client cleanup, not general Cisco software removal.
- Review Dry Run / WhatIf output before destructive cleanup.

## Documentation

- [Safety Model](docs/SAFETY.md)
- [Operating Modes](docs/OPERATING_MODES.md)
- [Build Guide](docs/BUILD.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Security Policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
