# Troubleshooting

## Parse OK Check

Before committing script changes, run the PowerShell parser check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("src\SecureClientCleanup.ps1",[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors|Format-List *; exit 1}; "Parse OK"'
```

For the build script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("build\Build-SecureClientCleanup.ps1",[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors|Format-List *; exit 1}; "Build script Parse OK"'
```

## ExecutionPolicy Issues

Run scripts with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\SecureClientCleanup.ps1
```

This bypass applies to the launched process and does not permanently change machine policy.

## Administrator Rights

Cleanup requires elevation. If the utility cannot relaunch elevated, start Windows PowerShell as Administrator and run the script again.

## WPF / STA

WPF requires a single-threaded apartment (STA) thread. The script bootstrap relaunches `.ps1` execution with `-STA` when needed.

If the UI does not open, verify that Windows PowerShell 5.1 is used and that the script was not launched from an incompatible host.

## ps2exe Not Found

Install ps2exe manually:

```powershell
Install-Module ps2exe -Scope CurrentUser
```

Or explicitly allow the build script to install it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-SecureClientCleanup.ps1 -InstallPs2Exe
```

## reg.exe Export Did Not Create Backup

Registry backup can fail if:

- The key no longer exists.
- The path is not a supported registry provider path.
- `reg.exe` returns a non-zero exit code.
- The backup directory cannot be created.

When backup is enabled and export fails, registry removal is skipped for that key.

## Access Denied When Removing Folders

Access denied can happen when files are locked by services, processes, antivirus, endpoint management tools, or another user session.

Recommended steps:

1. Re-run as Administrator.
2. Stop related Cisco Secure Client services.
3. Run Dry Run / WhatIf again.
4. Reboot and retry cleanup if files remain locked.

## HTML Report Did Not Open

Check that the report path exists and that the selected output directory is writable. If the browser does not open automatically, open the generated `.html` file manually from the output directory shown in the GUI.
