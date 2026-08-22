# SmartLib — Frontend (Flutter + Riverpod)

Single codebase across mobile and web. Riverpod handles state.

Scaffolded and verified against Flutter **3.47.0** / Dart **3.13.0** (stable).
Enabled platforms: **web, android, windows**. Add more with
`flutter create --platforms=ios,macos,linux .`

## Prerequisites

- Flutter SDK on your PATH — `flutter doctor` should be green for the platform
  you intend to run on
- The Node backend running (see `../backend/README.md`); the AI backend too if
  you want the second status line to read `ok`

## Setup

```bash
cd frontend
flutter pub get
```

## Run

```bash
flutter run -d chrome      # web
flutter run -d windows     # Windows desktop
flutter run                # pick from connected devices
```

Expected on screen:

```
Backend status: ok
AI backend status: ok
```

If a status shows an error instead, hit **Retry** — the button invalidates both
providers and refetches, so you don't need a hot restart while bringing the
backends up.

## Verify without a GUI

Useful in CI, or over a remote session where no browser window can open:

```bash
flutter analyze
flutter test
flutter build web
```

`flutter test` covers the health screen with the providers overridden, so it
passes without either backend running.

## Backend URL per platform

`lib/core/api_client.dart` resolves the base URL:

| Target | URL |
|---|---|
| Web / desktop | `http://localhost:3000` |
| Android emulator | `http://10.0.2.2:3000` (the emulator's alias for the host) |
| Physical device / anything else | pass it in explicitly |

```bash
flutter run --dart-define=SMARTLIB_API_BASE_URL=http://192.168.1.20:3000
```

The platform check uses `defaultTargetPlatform` from `flutter/foundation`,
**not** `dart:io`'s `Platform` — `dart:io` doesn't exist on web and importing it
breaks the web build outright.

For Flutter web, the Node backend already sends permissive CORS headers, so no
extra setup is needed.

## Layout

```
lib/
├── main.dart
├── core/
│   └── api_client.dart          # Dio provider + health providers
└── features/
    └── health/
        └── health_check_screen.dart
test/
└── widget_test.dart             # health screen, providers overridden
```

Phase 2 adds `features/auth`, `features/lending`, and `features/booking`
alongside `features/health`, and brings in `go_router` for navigation
(`flutter pub add go_router` — deliberately not added yet, since Phase 1 has a
single screen).
