# Security Policy

## Supported Versions

Security fixes are applied to the current repository state. No separate supported release matrix is maintained.

## Reporting a Security Issue

Report suspected vulnerabilities privately to the repository maintainer. Do not include credentials, tokens, certificates, private keys, or unrelated personal data.

Include the affected commit or revision, the exact operating mode, whether Dry Run / WhatIf was reviewed, expected behavior, actual behavior, and sanitized log excerpts when useful.

Do not publish a security issue before the maintainer has had a reasonable opportunity to investigate it.

## Safety Model

- The tool is intended to remove only targeted Cisco AnyConnect / Cisco Secure Client artifacts.
- Broad Cisco roots are blocked from automated cleanup.
- Registry and folder backup safety must not be bypassed.
- Dry Run / WhatIf must remain non-destructive.
- Requests to add broad delete targets should be rejected.

## Sensitive Data

Reports and logs may contain hostnames, local paths, service names, adapter names, registry paths, proxy and route information, and diagnostic details.

Do not publish logs, reports, or support bundles publicly without reviewing and sanitizing them.

The utility must not collect credentials, tokens, VPN secrets, certificates, or private keys.

## Out of Scope

- General Cisco software removal unrelated to Cisco AnyConnect / Cisco Secure Client.
- Requests to remove all Cisco registry or filesystem data.
- Support for bypassing backup checks or protected-root safeguards.
- Issues caused by locally modified builds that disable safety controls.

---

# Политика безопасности

## Поддерживаемые версии

Исправления безопасности применяются к текущему состоянию репозитория. Отдельная матрица поддерживаемых выпусков не ведётся.

## Сообщение о проблеме безопасности

Сообщайте о предполагаемых уязвимостях сопровождающему проекта по закрытому каналу. Не прикладывайте учётные данные, токены, сертификаты, закрытые ключи или несвязанные персональные данные.

Укажите затронутый commit или ревизию, точный режим работы, был ли проверен пробный запуск / WhatIf, ожидаемое и фактическое поведение, а также очищенные фрагменты журнала при необходимости.

Не публикуйте информацию об уязвимости до того, как сопровождающий получит разумное время на её проверку.

## Модель безопасности

- Утилита предназначена для удаления только целевых компонентов Cisco AnyConnect / Cisco Secure Client.
- Широкие корневые пути Cisco заблокированы для автоматической очистки.
- Нельзя обходить защиту резервного копирования реестра и папок.
- Пробный запуск / WhatIf должен оставаться неразрушающим.
- Запросы на добавление широких целей удаления должны отклоняться.

## Чувствительные данные

Отчёты и журналы могут содержать имена компьютеров, локальные пути, названия служб и адаптеров, пути реестра, сведения о прокси и маршрутах, а также диагностические данные.

Не публикуйте журналы, отчёты и пакеты поддержки без предварительной проверки и очистки.

Утилита не должна собирать учётные данные, токены, VPN-секреты, сертификаты или закрытые ключи.

## Вне области безопасности

- Общее удаление программного обеспечения Cisco, не связанного с Cisco AnyConnect / Cisco Secure Client.
- Запросы на удаление всех данных Cisco из реестра или файловой системы.
- Помощь в обходе проверок резервного копирования или защиты корневых путей.
- Проблемы в локально изменённых сборках с отключёнными механизмами безопасности.
