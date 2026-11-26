---
inclusion: always
---

# Money Anywhere: how to work in this project

Competition Demo. Android app (Flutter) that tells a person where their money is and guides them end to end to claim it.
Owner speaks Thai: reply in Thai. Code, identifiers, commit messages and API field names stay English.

## Rules that never bend

- Never present mock or unverified data as verified. Every number shown to a user comes from a published rate, the user's own input, or a government adapter (`dataStatus` / `basis` say which).
- Never promise money. Results are "likely / check / need / unlikely"; only the government adapter may return "verified".
- AI never produces money amounts. Amounts in AI text that are not in tool output are stripped (`stripMoney`, `guardMoney`).
- Synthetic personas only. No real personal data, no real secrets in the repo (it is public on GitHub). Keys go in `.env`.
- Demo rules: no login, encryption, rate limiting or other production security work. Prefer simple code that works.

## When something is not certain

- Unverified facts (rates, deadlines, phone numbers, URLs) still go in, but add a row to `docs/plan/open-items.md` with what is unsure, where to check, and which file/key to fix.
- Anything still mocked goes in section 2 of that file. Anything that can be connected for free should be connected instead of mocked.
- When reporting to the Owner, say what was verified (test run, fetched page) and what was not.

## Where things are

| What | Path |
|---|---|
| Requirements | `docs/product/requirements.md` |
| Plan and task IDs (T0, TM, TB, TF) | `docs/plan/work-breakdown.md`, `docs/plan/delivery-plan.md` |
| Unsure / mocked items | `docs/plan/open-items.md` |
| Stack decision | `docs/design/adr-001-stack.md` |
| Backend status | `docs/design/backend-gaps.md` |
| API contract | `contracts/openapi.yaml` (+ `contracts/CHANGELOG.md`) |
| Screens, menus, actions (backend-driven UI) | `contracts/app-config.sample.json`, `contracts/app-config.schema.json` |
| Money rules, facts, sources | `contracts/fixtures/reference.json` → `moneyPrograms`, `facts` |
| Demo server | `contracts/mock-server.js`, adapters in `contracts/adapters/` |
| Gov money services, apps to connect, map data (update its change log on every edit) | `docs/design/gov-services-inventory.md`, mockup `docs/mockups/gov-services.html` (test: `node docs/mockups/gov-services-smoke.js`) |
| Clickable mock | `docs/mockups/index.html` (+ `smoke-test.js`) |
| Generated API docs (do not edit) | `docs/backend/index.html` |
| Locked decisions | `aidlc/spaces/default/memory/project.md` (Tech Stack, Decided) |
| Rebuild the app on Demo day (steps, prompts, known pitfalls) | `docs/guide/rebuild-playbook.md` |
| Tool versions for the team, env vars, phone setup | `docs/guide/dev-setup.md`, check with `tools/check-dev-env.ps1` |
| Build + install on the USB phone / flow test on the PC | `tools/build-and-install.ps1`, `node tools/e2e-flows.js` |

Decided, do not re-ask: Flutter; one app with ThaID mode hidden behind `govConnected`; 4 tabs (หน้าแรก, โอกาส, แผนของฉัน, ฉัน); menus and actions come from the backend config; ADR-001 stack.

## Commands (Windows PowerShell on this machine)

- Use `npm.cmd`, not `npm` (PowerShell blocks `npm.ps1`). Run inside `contracts/`.
- `npm.cmd run check` = all tests + rebuild API docs. `npm.cmd test` = tests only. `npm.cmd run mock` = demo server on :8080.
- Mock UI smoke test: `$env:JSDOM_PATH="$env:TEMP\jsd"; node ..\docs\mockups\smoke-test.js` (jsdom is installed in `%TEMP%\jsd`).
- Terminal output often does not come back to the agent. Redirect to a file under `contracts/.data/` (git-ignored), for example `cmd /c "npm.cmd test > contracts\.data\t.txt 2>&1"`, then read the file.
- Files just written to `%TEMP%` may not be visible to the next command; prefer `contracts/.data/` for scratch files.
- The agent cannot commit or push here. Give the Owner the git commands and tell them to check `git status -sb`.

## Definition of done for a change

1. Contract changes: update `openapi.yaml`, the server, `test-contract.js`, and `CHANGELOG.md`; `npm.cmd run check` passes and every operation is exercised.
2. Mock UI changes: smoke test passes.
3. Status files updated: `work-breakdown.md` row, `backend-gaps.md` or `open-items.md` when relevant.
