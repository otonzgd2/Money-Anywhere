---
inclusion: fileMatch
fileMatchPattern: ["contracts/**"]
---

# API and demo server conventions

- The Flutter app depends only on `openapi.yaml` and app-config. Anything behind them (storage, AI provider, sources, notifier, gov) is an adapter in `contracts/adapters/` and must stay swappable by env or one file.
- Plural resource nouns. Task state changes go through `POST /v1/tasks/{id}/events`, not verb paths.
- Headers: `X-Device-Id` (no login), `X-Api-Key` for `/v1/integrations`, `X-Request-Id` on every response, `Idempotency-Key` for events, ETag on app-config.
- One error shape `{code, message, status, retryable, requestId}`. Lists are `{items}` with cursor paging.
- Consent purposes core / location / ai / reminders / gov. Missing consent returns 403 `CONSENT_REQUIRED`; AI without consent returns `aiStatus: skipped_no_consent`.
- AI write tools (create_task, snooze_task, complete_step, update_facts) need user confirmation; `remember` saves a visible memory item; any other tool is refused.
- Money rules are data in `fixtures/reference.json` (`moneyPrograms`), evaluated by `adapters/money.js`. Every program carries `sources` with `checkedAt`. Changing a rate or criterion: update `reference.json`, the matching `MONEY` entry in `docs/mockups/index.html`, the tests, and `open-items.md` if unsure.
- Additive changes only unless the Owner agrees to a break. Bump `package.json` and `openapi.yaml` `info.version` together and add a `CHANGELOG.md` entry.
- `test-contract.js` validates every response against the schema and fails if any operation is not called. New endpoints need a test call.
- Tests must use the memory store: never point `DATA_FILE` or `AI_LOG_FILE` at real data in tests.
