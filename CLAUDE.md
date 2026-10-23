# SmartLib — Frontend (Flutter + Riverpod)

The SmartLib student app for **Web, Android, and Windows Desktop**: catalog and
borrowing, waitlist, loans, seat/room booking with check-in, reliability, and
recommendations. It talks only to the Node backend (`../backend`, port 3000).
Librarian/admin tools are a separate planned web console, not part of this app.

## Tech Stack
- **Framework**: Flutter (Dart) — verified on Flutter 3.47 / Dart 3.13
- **State**: Riverpod 3 (`flutter_riverpod: ^3.3.1`)
- **Networking**: Dio (`dio: ^5.0.0`)
- **Routing**: GoRouter (`go_router: ^17.5.0`)
- **Serialization**: `json_serializable` + `build_runner` (generated `*.g.dart` committed)
- **Session storage**: `flutter_secure_storage`

---

## Commands

Always run from `frontend/`:

```bash
flutter pub get
flutter analyze
flutter test                      # never needs a backend
flutter build web                 # web compile check
dart run build_runner build       # after changing any model in lib/models/
flutter run -d chrome --web-port 8080 | -d windows | -d <android-device>
```

`build_runner` 2.16+ ignores `--delete-conflicting-outputs`; use the plain command.

---

## Critical Platform Rules

1. **Never import `dart:io` / use `Platform`.** It breaks the web build. Use
   `kIsWeb` and `defaultTargetPlatform` from `package:flutter/foundation.dart`.
2. **Base URL** (`resolveBaseUrl()` in `lib/core/api_client.dart`): web/Windows
   → `http://localhost:3000`; Android → `http://10.0.2.2:3000`; override with
   `--dart-define=SMARTLIB_API_BASE_URL=...`.
3. **Android cleartext is debug-only** (`android/app/src/debug/AndroidManifest.xml`).
   Don't move it to the main manifest; release builds need an HTTPS backend.
4. **Windows builds need the Visual Studio "C++ ATL" component.**
   `flutter_secure_storage_windows` includes `atlstr.h`.
5. **Web secure storage works only on HTTPS or localhost.** `TokenStore` degrades
   to "session not remembered" and must never throw on a storage failure.

---

## Data Layer Conventions

- **Repositories** are `Provider<SomeRepository>` (an interface). Production
  defaults are the `Http*` implementations; the `Mock*` implementations remain
  as **test doubles only**. Don't route production code back to mocks.
- **Every HTTP call goes through `guardApi()`**, which maps `DioException` to
  `ApiException(statusCode, message, details)`, `UnauthorizedException` (401),
  or `ConflictException` (409). Status code `0` means network failure. Show
  the backend's `message` verbatim; its copy is written for users.
- **401 handling is centralized.** `AuthInterceptor` clears the token, and
  `AuthController` listens to `TokenStore` and flips to unauthenticated with
  the session-expired message. Screens never handle 401 themselves.
- **User-initiated writes go through `UiController.attempt()`.** It toasts
  success only after the server agrees and toasts the server's reason on
  refusal. It returns the error so the caller can react (for example, not
  flipping a button). Controllers rethrow after `_refetchIfStale(e)`, which
  reloads the list on `meansStaleState` (409/404) but keeps it on network
  errors. Guard against double taps for non-idempotent actions (see
  `LoansController._renewing`, `BookingFlowController._confirming`).
- **Availability: use `Book.freeCopies`, not `availableCopies`.** A copy held
  for a waitlisted student's claim (`heldCopies`) is on the shelf but refused
  to everyone else. The one exception is the claimant: when the student's own
  `Reservation` is `held`, offer Request to borrow.
- **Per-user state is keyed on the user.** Controllers holding a user's data
  `watch` `authControllerProvider.select((s) => s.user?.id)`, so logging in as
  someone else refetches instead of showing the previous user's data.
- **Screens showing a pending request wrap their body in `PendingRefresh`**
  (`lib/widgets/pending_refresh.dart`). It re-checks on open and every 30 s
  through the controllers' `refreshQuietly()`, which keeps the current list
  when the network fails.
- **Toasts are mounted at the app root** (`MaterialApp.router(builder: withToasts)`)
  so pushed routes such as book detail and the booking flow can show them.
  `ConfirmDialogHost` lives in the tab shell.

## Models & Time

- Models use `@JsonSerializable(createToJson: false)`. Edit the model, then run
  `build_runner`; never hand-edit `*.g.dart`.
- **Values computed from server data are getters, not fields**
  (`Book.coverPalette`, `ResourceBooking.timeSlot`). Client-only UI state is a
  field excluded from JSON (`Loan.justRenewed`).
- **Incoming timestamps are UTC.** Convert at the parse boundary with the
  `localDateTime` converter (`models/json_converters.dart`). **Outgoing**
  timestamps must be `.toUtc().toIso8601String()`, because the backend requires
  an offset.
- Nullable backend strings that are non-null in Dart get `@JsonKey(defaultValue: '')`.
  Never write `as double` for JSON numbers; integers arrive as `int`.
- `kTimeSlots`/`kSlotHours` (`features/bookings/time_slots.dart`) mirror the backend's
  `TIME_SLOTS`, and `kCheckInGracePeriod` mirrors `GRACE_PERIOD_MINUTES`. Change
  both sides together. Slot windows are built in client local time and the
  server uses its own local time, so they must share a time zone.
- Read "now" through `clockProvider` in anything a test needs to pin.

---

## Testing Conventions

- **Every `ProviderScope`/`ProviderContainer` in a test must use
  `mockRepositoryOverrides()`** (`test/support/mock_overrides.dart`). Otherwise
  it hits the real network and keystore. Substitute a specific double through its
  named parameter (`mockRepositoryOverrides(loans: _MyRepo())`) rather than
  appending a second override for the same provider.
- Riverpod 3 doesn't export the `Override` type, so don't annotate override-list
  return types.
- **JSON tests parse real captured payloads** from `test/fixtures/`
  (`fixture('name')`). Refresh with `dart run tool/capture_fixtures.dart`
  against a freshly seeded backend, which writes to the DB; re-seed afterwards.
- HTTP repository tests use `StubHttpAdapter` (`test/support/stub_http_adapter.dart`).
  Don't add `http_mock_adapter`.
- **The splash screen must stay static.** No spinner or repeating animation:
  `pumpAndSettle()` would never settle and router tests would hang.
- Follow TDD: write a failing test, implement, run the full suite, then
  `flutter analyze`.
- **Live checks** against the real backend go in a temporary
  `test/zz_live_*_test.dart`, which is deleted afterwards. `flutter test`
  reports Android as the platform, so override `baseUrl` to
  `http://localhost:3000`. Seed before and after.

---

## Code Organization

```
lib/
├── main.dart                  # ProviderScope, MaterialApp.router, withToasts
├── core/
│   ├── api_client.dart        # Dio, resolveBaseUrl, AuthInterceptor, guardApi
│   ├── api_exception.dart
│   ├── auth/token_store.dart  # leaf ChangeNotifier holding the token
│   ├── clock.dart · time_format.dart
│   ├── router/app_router.dart # /splash → /login | /home; tab shell
│   ├── theme/                 # SmartLibTokens + ThemeData
│   └── ui/                    # UiController, confirm dialogs, toasts
├── models/                    # json_serializable models + *.g.dart
├── widgets/                   # shared widgets
└── features/                  # auth, catalog, loans, bookings, waitlist, profile,
                               # recommendations, home, health (unrouted, Phase 1)
test/
├── support/                   # mock_overrides, fixtures, stub_http_adapter, fake_token_store
├── fixtures/                  # captured backend responses
└── models/ · core/ · features/ · e2e_smoke_test.dart
tool/capture_fixtures.dart
```

## Release & Deploy

- Android app ID `io.github.raghav28gupta.smartlib`. It's permanent once
  published, so don't change it.
- Release signing reads `android/key.properties`, which is never committed.
  Without it, release builds silently use the debug key, and the release
  workflow refuses those.
- Deployed builds always pass `--dart-define=SMARTLIB_API_BASE_URL=...`
  (`web.yml`, `release.yml`).
- `test/platform/release_config_test.dart` guards the platform files release
  depends on: `INTERNET` in the main manifest, cleartext debug-only, and app
  names.

## Generated & Protected Files

Never hand-edit: `lib/**/*.g.dart` (regenerate), `build/**`, `.dart_tool/**`.

## Sibling Access

When started from `frontend/`, read `../backend` for routes, Zod schemas
(`src/schemas/`), DTOs, and constants (`src/config/constants.ts`) before
changing a model or repository.
