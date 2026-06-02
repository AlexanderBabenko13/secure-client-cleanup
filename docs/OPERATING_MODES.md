# Operating Modes

This document describes the intended operating modes for Secure Client Cleanup Utility.

## Scan Only

Scan only collects information about known Cisco AnyConnect / Cisco Secure Client targets.

Reads:
- Service status.
- Process list.
- Known program folder paths.
- User AppData paths.
- Targeted registry keys.

Changes:
- No destructive changes.
- Updates the UI scan table.

Admin required:
- Recommended. Some locations may not be fully visible without elevation.

Risks:
- Low. This mode is read-oriented.

## Dry Run / WhatIf

Dry Run / WhatIf previews cleanup actions.

Reads:
- Current scan targets.
- Services, processes, folders, and registry keys selected for cleanup.

Changes:
- No files are deleted.
- No registry keys are removed.
- No restore point is created during dry-run analysis.

Admin required:
- Recommended for realistic results.

Risks:
- Low. Review the output before running real cleanup.

## Full Cleanup

Full cleanup runs selected destructive cleanup actions.

Reads:
- Services and processes.
- Targeted folders.
- Targeted registry keys.

Changes:
- Can stop Cisco VPN processes and services.
- Can disable and delete targeted services.
- Can remove targeted folders.
- Can remove targeted registry keys.
- Can create backups when backup is enabled.

Admin required:
- Yes.

Risks:
- Medium to high. Use only after Scan, Dry Run / WhatIf, and Backup review.

## Diagnostics Only

Diagnostics only helps support engineers inspect common VPN blockers.

Reads:
- DNS and connectivity checks.
- WinINET and WinHTTP proxy settings.
- Network interfaces and default routes.
- Running processes.
- Scheduled tasks, services, and driver files for common conflicting tools.

Changes:
- Diagnostics read information and log findings.
- Separate action buttons may stop or disable selected conflicting items only when explicitly used.

Admin required:
- Recommended. Some diagnostics may be incomplete without elevation.

Risks:
- Low for diagnostics. Higher only when explicit action buttons are used.

## Support Bundle

Status:
- Planned / future mode.

Expected reads:
- Logs.
- Scan exports.
- HTML report.
- Diagnostic output.

Expected changes:
- Package local support artifacts into a bundle.

Admin required:
- To be determined.

Risks:
- Privacy risk. Bundles may include hostnames, paths, service names, adapter names, and diagnostic details.
