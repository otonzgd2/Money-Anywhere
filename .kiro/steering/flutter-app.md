---
inclusion: fileMatch
fileMatchPattern: ["**/*.dart", "app/**", "pubspec.yaml"]
---

# Flutter app conventions

- Android first; keep code iOS-compatible but do not spend time on iOS for the Demo.
- Screens, tabs, menus and button actions come from `GET /v1/app-config`. Widgets render config; buttons reference action ids only. Do not hardcode navigation that the config defines.
- After an action succeeds, refresh every screen whose data tag is in the action's `invalidates` list.
- API base URL comes from build config (`--dart-define=API_BASE_URL=...`): emulator `http://10.0.2.2:8080`, phone on the same Wi-Fi uses the laptop IP, other networks use a tunnel (`docs/guide/run-demo-server.md`).
- Always show the data label the API returns (`dataStatus`, `amount.basis`, `aiStatus`). Mock items show "DEMO / MOCK".
- Thai UI text, large-text setting supported, main menu stays at 4 tabs.
- Follow `analysis_options.yaml` / `flutter analyze`. Keep the client generated from `contracts/openapi.yaml` (task B7) instead of hand-writing models.
