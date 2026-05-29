# Secure Client Cleanup Utility

Secure Client Cleanup Utility is a Windows PowerShell WPF tool for safe cleanup of Cisco AnyConnect / Cisco Secure Client before reinstall.

## Purpose

The tool helps support engineers and system administrators prepare a Windows workstation for a clean Cisco VPN reinstall.

## Features

- Scan Cisco AnyConnect / Cisco Secure Client components.
- Detect related services, processes, folders, registry keys and user AppData leftovers.
- Run diagnostics for VPN, proxy, routes and network adapters.
- Export reports for troubleshooting.
- Support safe cleanup workflow before reinstall.

## Planned safety model

1. Scan only.
2. Dry run.
3. Create backup.
4. Clean selected leftovers.
5. Reboot.
6. Reinstall Cisco Secure Client.

## Requirements

- Windows 10 / Windows 11
- Windows PowerShell 5.1
- Administrator rights

## Project status

Work in progress.
