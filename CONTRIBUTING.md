# Contributing

Contributions should keep the utility targeted, reviewable, and safe for administrator use.

## Development Rules

- Maintain Windows PowerShell 5.1 compatibility.
- Keep changes focused and avoid unrelated refactoring.
- Do not use `Win32_Product`.
- Preserve existing public control names and documented workflows when changing the GUI.
- Test the GUI scan manually after UI changes.

## Safety Rules

- Do not add broad Cisco registry roots to automatic cleanup.
- Do not add broad Cisco folders to automatic cleanup.
- Keep Dry Run / WhatIf safe and non-destructive.
- Keep registry and folder backup checks before destructive removal.
- Do not bypass protected-root or targeted-removal safeguards.

## Pull Request Checklist

- The change has a clear and limited purpose.
- Safety-sensitive behavior is explained in the pull request.
- Documentation is updated when behavior changes.
- The parser check passes.
- `git diff --check` passes.
- The final diff contains no unrelated files.

## Testing Checklist

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("src\SecureClientCleanup.ps1",[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors|Format-List *; exit 1}; "Parse OK"'
```

```powershell
git diff --check
```

For GUI changes, manually verify startup, scan, table population, scrolling, Dry Run / WhatIf, and return from busy state.

---

# Участие в разработке

Изменения должны сохранять целевой характер утилиты, удобство проверки и безопасность для администратора.

## Правила разработки

- Сохраняйте совместимость с Windows PowerShell 5.1.
- Делайте изменения локальными и не добавляйте несвязанные рефакторинги.
- Не используйте `Win32_Product`.
- При изменении GUI сохраняйте существующие публичные имена контролов и документированные сценарии.
- После изменений интерфейса вручную проверяйте сканирование в GUI.

## Правила безопасности

- Не добавляйте широкие корневые ключи Cisco в автоматическую очистку.
- Не добавляйте широкие корневые папки Cisco в автоматическую очистку.
- Пробный запуск / WhatIf должен оставаться безопасным и неразрушающим.
- Сохраняйте проверки резервных копий реестра и папок перед разрушительным удалением.
- Не обходите защиту корневых путей и ограничения целевого удаления.

## Чек-лист Pull Request

- Изменение имеет ясную и ограниченную цель.
- В Pull Request описано влияние на безопасность.
- Документация обновлена при изменении поведения.
- Проверка парсером проходит успешно.
- `git diff --check` проходит успешно.
- В итоговом diff нет несвязанных файлов.

## Чек-лист тестирования

Выполните:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command '$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile("src\SecureClientCleanup.ps1",[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors|Format-List *; exit 1}; "Parse OK"'
```

```powershell
git diff --check
```

После изменений GUI вручную проверьте запуск, сканирование, заполнение таблицы, прокрутку, пробный запуск / WhatIf и выход интерфейса из busy-состояния.
