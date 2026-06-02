# Secure Client Cleanup Utility

Secure Client Cleanup Utility is a Windows PowerShell 5.1 WPF tool for support engineers and system administrators who need to safely prepare a Windows workstation for Cisco AnyConnect / Cisco Secure Client reinstall.

The utility helps find and remove targeted Cisco VPN leftovers such as service keys, known product folders, and user AppData traces. It also provides diagnostics and exportable reports for troubleshooting.

## Purpose

Use this tool when Cisco AnyConnect / Cisco Secure Client is broken, partially removed, or cannot be reinstalled cleanly. The goal is a controlled cleanup workflow before reinstalling Cisco Secure Client, not broad removal of all Cisco software data from the machine.

## Administrator Warning

Run the utility only from an elevated Windows PowerShell session or as an elevated executable.

Cleanup actions can stop services, delete targeted folders, and remove targeted registry keys. Scan, diagnostics, and dry-run workflows are intended to help review the impact before making changes.

## Safe Workflow

1. Scan
2. Dry Run / WhatIf
3. Backup
4. Cleanup
5. Reboot
6. Reinstall Cisco Secure Client

## Features

- Scan Cisco AnyConnect / Cisco Secure Client services, processes, folders, registry keys, and user AppData locations.
- Run a non-destructive Dry Run / WhatIf cleanup preview.
- Back up registry keys before removal when backup is enabled.
- Export scan results to HTML, CSV, and JSON.
- Generate an HTML report with escaped content.
- Run VPN-related diagnostics for DNS, ping, TCP 443, proxy settings, routes, adapters, and common conflicting VPN tools.
- Use safety guards that block broad Cisco registry roots and broad Cisco folders from automated cleanup.
- Build a GUI executable with ps2exe.

## Requirements

- Windows 10 or Windows 11
- Windows PowerShell 5.1
- Administrator rights for cleanup and full diagnostics

## Quick Start: Script

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\SecureClientCleanup.ps1
```

If the script is not elevated or not running in STA mode, the bootstrap logic relaunches it with the required settings.

## Build EXE

Install ps2exe when needed:

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

The build script prints the executable path, file size, and SHA256 hash after a successful build.

See [docs/BUILD.md](docs/BUILD.md) for build options such as `-NoIcon`, `-Console`, and `-InstallPs2Exe`.

## Logs And Reports

The application writes logs, scan exports, registry backups, folder backups, and HTML reports under the cleanup output directory selected in the GUI. The default paths are shown in the GUI before running actions.

Reports and bundles can include local paths, hostnames, service names, adapter names, and diagnostic details. Treat them as support artifacts, not public files.

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
- [Security](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
