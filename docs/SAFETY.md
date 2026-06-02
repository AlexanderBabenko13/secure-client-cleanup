# Safety Model

Secure Client Cleanup Utility is designed for controlled cleanup of Cisco AnyConnect / Cisco Secure Client leftovers before reinstall. It favors review, dry-run output, and targeted cleanup over broad deletion.

## What The Utility Does

- Scans for known Cisco VPN services, processes, folders, registry keys, and user AppData locations.
- Runs diagnostics for common VPN connectivity blockers.
- Exports scan results and HTML reports.
- Can stop targeted Cisco VPN services and processes.
- Can remove targeted Cisco Secure Client / AnyConnect folders and targeted service registry keys.
- Can create registry backups before registry cleanup.

## What The Utility Does Not Do

- It does not remove every Cisco-related registry key.
- It does not delete broad Cisco program or data folders automatically.
- It does not perform automatic network reset.
- It does not use `Win32_Product`.
- It does not replace a normal Cisco Secure Client reinstall workflow.

## Broad Cisco Registry Roots

Broad registry roots such as `HKLM:\SOFTWARE\Cisco`, `HKLM:\SOFTWARE\WOW6432Node\Cisco`, and `HKCU:\Software\Cisco` can contain data for unrelated Cisco products, licensing, management tools, and user settings.

For that reason, automated cleanup is limited to targeted service keys. Broad Cisco registry roots are blocked from automated export and removal even if they accidentally appear in a cleanup list.

## Broad Cisco Folders

Broad folders such as `C:\Program Files\Cisco`, `C:\Program Files\Cisco Systems`, `C:\ProgramData\Cisco`, and their 32-bit equivalents can contain unrelated Cisco product data.

The utility blocks these broad roots from automated deletion. Cleanup targets are limited to known Cisco AnyConnect / Cisco Secure Client folder names and subfolders.

## Network Reset

Network reset can affect adapters, routes, DNS settings, proxy behavior, VPN clients, and other endpoint management tools. It is intentionally not performed automatically.

Diagnostics may show network-related findings, but any network reset must remain a separate, explicit administrator decision.

## Win32_Product

`Win32_Product` is forbidden because querying it can trigger MSI consistency checks and repair actions across installed products. That behavior is too risky for a support cleanup utility.

## WhatIf / Dry Run

WhatIf / Dry Run is the safe preview mode. It logs what cleanup would attempt without deleting files, removing registry keys, or creating restore points.

Use Dry Run before any real cleanup to confirm that the target list is expected.

## Before Real Cleanup

1. Run Scan.
2. Review all found items.
3. Run Dry Run / WhatIf.
4. Enable Backup for real cleanup.
5. Confirm selected actions and scope.
6. Run cleanup as administrator.
7. Reboot.
8. Reinstall Cisco Secure Client.
