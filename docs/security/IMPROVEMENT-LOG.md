# LotCaster / Care improvement log

## 2026-10-19 — offline privacy and Carrie audit

Authorized scope: 2011vge-hub/LOTCASTER_MOBILE and LOTCASTER_DESKTOP only. No lotengage-hq access, deployment, production data queries, customer messages, or history rewrite. Changes are for review, not deployed behavior.

Baseline mobile commit: 73297f12b585891923dcbdc55a87b5219ff1c71c.
Baseline desktop commit: 373fee004d981f6333926ef809d0553482872633.
Review branch: codex/privacy-carrie-audit-20261019. Its Vercel auto-deployment is disabled in branch configuration.

### Evidence and changes

- Retrieved 336 current UTF-8/text candidates across the two repository snapshots. Five image/archive assets across the two repositories were excluded from text retrieval. This is a heuristic text audit plus targeted manual classification, not a comprehensive privacy certification.
- Scanned returned file patches from 580 mobile and 2 desktop commits reachable through the main commit listing. Found one historical fixture change containing the same two non-reserved example phone values as current tests. Replaced current values with reserved fictional 555-01xx numbers. No history was rewritten.
- 40 historical file entries had no text patch (mostly archives/images, some placeholders/renames, and one large source file). All branch/tag histories, binary contents, omitted/truncated patches and commit metadata have NOT been fully audited. No claim of zero customer data or absence of a leak is supported by this work.
- Inspected contact-shaped current values: identified operational support/CRM addresses and synthetic test identities; no confirmed real customer record identified in the reviewed candidates. Existing free-text names and dialogue provenance still need owner confirmation. Replaced a real-looking inventory URL/VIN in a test with an example.test URL.
- Added a redacting privacy guard to both repos, an opt-in staged-byte pre-commit hook, and PR/workflow-dispatch checks. It flags non-reserved fixture phone numbers, non-example/test fixture email domains, known operational export filenames, private key markers, selected secret prefixes and service-role JWTs. It does NOT identify every real name/address, international phone, secret, screenshot, or copied conversation.
- New synthetic suite executes the actual shared triage and SMS autopilot policy. Initial run: 8 failures / 21 cases. After fixes: 21 / 21 pass.
- Fixed natural-language opt-out recognition; prevented cancellation/declined visits and finance questions with temporal words from becoming appointment-ready; made appointment draft wording explicitly pending team confirmation.
- Existing appointment tests now assert pending confirmation rather than prohibit it. The downstream appointment persistence/status and alert delivery code was not changed or live-tested; it needs a separate mocked integration review before launch.

### Executed verification

- `node tests/synthetic/carrie-regression.mjs`: 21 cases pass.
- `npm run check`: complete existing offline check script passes.
- `node tests/carrie-speech-replay.mjs`: passes with mocked WebSockets/backend and clock; no live call.
- `node tests/marketplace-conversation-signals.mjs`: passes; message direction/unread detection only.
- `node tests/lotrescue-import.mjs`: passes after synthetic phone replacement.
- Both repos: `python3 scripts/check_customer_data.py` and `python3 tests/privacy-guard.py` pass. Guard tests cover 9 checks, including scanning staged bytes when working-tree bytes differ and withholding matched values.

### Remaining acceptance gates

| Gate | Status / next step |
| --- | --- |
| Shared deterministic reply rules and suppression | Offline cases pass; broader language cases remain possible |
| Voice wording / generative response quality | Mocked transport replay passes; no live model quality evaluation |
| Marketplace message import and reply transport | Not exercised live; needs connected Muse/browser and synthetic authorized test thread |
| Buying-signal/appointment alerts | Delivery unverified; add mocked end-to-end event tests then a Gage-only test |
| Human takeover, duplicate delivery and sold inventory | Full cross-system pilot still unverified |
| Appointment hours, actual reservation and backend confirmation | Integration review required; reply draft no longer promises confirmation |
| Historical and binary data privacy | Incomplete; requires full-object/branch audit and human provenance review |
| Enforcement | CI/hook prepared only. Review/merge and required-check configuration needed; hooks require opt-in on each workstation |

### Reproduce / continue

Run `npm run check:privacy`, `npm run test:carrie-synthetic`, and `npm run check` from the mobile repo. On desktop run the two Python commands above. Python 3 and Node 24 were used for this audit. Speech replay needs Node 24.

To enable the optional local hook: `git config core.hooksPath .githooks` (requires `python3` on PATH). This changes local Git configuration only. Do not bypass the guard to commit customer data. A guard finding should be replaced with synthetic data or reviewed as a narrowly documented false positive.

Use fictional names, example.com/example.test email addresses, reserved fictional phone values and invented dialogue. Never paste matched customer data into this log, PRs, chat, or test failures. Keep existing operational configuration separate from customer fixtures.

A daily ChatGPT improvement task is enabled around 3 PM America/Chicago starting 2026-10-20. Future runs must check access, read this log, distinguish executed checks from blocked checks, and report new results without repeatedly modifying already-passing code. Scheduling is not proof that future execution or external tooling will succeed.

## 2026-10-21 — expanded identifier and history guard

Scope remained limited to the two LotCaster repositories. No deployment, merge, history rewrite, live data access, outbound message, or production verification occurred.

### Sanitized changes

- Expanded the redacting guard to cover source-wide emails, contextual phone values, VINs, eLeads-style customer/deal/opportunity/task/activity/owner/message identifiers, explicit customer name fields, and training/fine-tune/dataset/memory/transcript/export/capture paths.
- Added deduplicated full-history blob scanning and commit-message scanning to CI. Findings report only object/path, line, and category; matched values are withheld.
- Expanded guard regression coverage from 9 to 15 checks, including surname fields, VINs, CRM identifiers, sensitive artifact paths, staged bytes, old blobs, commit messages, and redacted output.
- Replaced current-tree real-looking identifiers, VINs, names, contact addresses, and the hardcoded CRM notification destination with synthetic or settings-based values.
- The desktop hosted owner address now comes from `LOTCASTER_OWNER_EMAIL` and setup fails closed when it is missing.
- Current-tree scans are clean: mobile 288 text files / 0 findings; desktop 60 text files / 0 findings.
- The locally reconstructed baseline history still produces redacted findings (mobile 27; desktop 8). This is expected because history was not rewritten. The local repositories contain only one reconstructed baseline commit, so these counts do not clear the authoritative remote history.

### Executed verification

- Mobile `npm run check`: passed after keeping calibrated synthetic identifiers consistent across implementation and tests.
- Mobile synthetic Carrie regression: 21 / 21 passed.
- Both privacy-guard regression suites: 15 / 15 passed.
- Both current-tree privacy scans: passed with zero findings.
- History mode executed against each local repository and correctly failed on historical baseline content while withholding values.
- `git diff --check`: passed.

### Static checks and blocked verification

- Static inspection confirms CI invokes current-tree and history scans, and the desktop owner address is no longer embedded in source.
- Desktop PowerShell pricing and reliability suites were not executed because `pwsh` is unavailable in this environment.
- Authoritative all-ref remote history, binary/image OCR, unknown surname provenance, live Marketplace transport, alert delivery, and customer messaging remain unverified. Independent scanning and human provenance review are still required.

## 2026-10-22 — changed-code delta review

Desktop main remains unchanged at `373fee004d981f6333926ef809d0553482872633`; the review branch remains one commit ahead and zero commits behind. No repetitive fixes or tests were run. The unresolved PowerShell execution and authoritative-history review gates remain unchanged.
