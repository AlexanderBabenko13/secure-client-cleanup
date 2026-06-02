# Security

## Sensitive Data In Reports

Reports, logs, diagnostics, and future support bundles may contain:

- Local file paths.
- Service names and process names.
- Network adapter names.
- Proxy and route details.
- Hostname.
- Registry key names.

Treat these artifacts as internal support data.

## Do Not Publish Support Bundles Publicly

Do not upload support bundles, logs, or generated reports to public issue trackers, public chats, or public storage unless they have been reviewed and scrubbed.

## Reporting Dangerous Scenarios

Report dangerous cleanup scenarios by opening an internal issue or contacting the project maintainer. Include:

- Tool version or commit.
- Exact mode used.
- Whether Dry Run / WhatIf was reviewed.
- Relevant log excerpts.
- Expected vs actual behavior.

Avoid including secrets, tokens, or unrelated personal data.

## Sensitive Data Policy

- Do not add collection of credentials, tokens, VPN secrets, certificates, or private keys.
- Do not include broad environment dumps in reports.
- Keep diagnostics focused on support-relevant network and Cisco Secure Client cleanup data.
- Prefer explicit user/admin action before collecting or packaging support artifacts.
