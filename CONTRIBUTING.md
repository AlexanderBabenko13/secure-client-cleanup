# Contributing

Contributions should keep the utility safe, targeted, and compatible with Windows PowerShell 5.1.

## Compatibility

- Support Windows PowerShell 5.1.
- Avoid syntax that requires PowerShell 7+.
- Run parser checks before opening a pull request.

## Safety Rules

- Do not use `Win32_Product`.
- Do not delete broad Cisco registry roots.
- Do not delete broad Cisco folder roots.
- Do not add automatic network reset.
- Keep destructive actions behind explicit confirmation.
- Prefer Dry Run / WhatIf support for cleanup actions.

## Cleanup Target Rules

Cleanup targets must remain specific to Cisco AnyConnect / Cisco Secure Client. Broad Cisco roots can contain unrelated products and must stay blocked from automated deletion.

## Before A Pull Request

Run the parser check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("src\SecureClientCleanup.ps1",[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors|Format-List *; exit 1}; "Parse OK"'
```

For build script changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("build\Build-SecureClientCleanup.ps1",[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors|Format-List *; exit 1}; "Build script Parse OK"'
```

Run Git whitespace checks:

```powershell
git diff --check
```

Review the diff carefully and confirm that unrelated GUI, cleanup, bootstrap, or build behavior was not changed.
