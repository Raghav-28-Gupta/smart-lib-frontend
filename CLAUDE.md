# SmartLib — Frontend (Flutter + Riverpod)

The SmartLib frontend is a single multi-platform codebase supporting **Web, Android, and Windows Desktop**. It provides the student and administrator user interfaces for book discovery, lending workflows, waitlist claiming, interactive study seat/room booking, fine monitoring, and personalized AI recommendations.

## Tech Stack
- **Framework**: Flutter (Dart)
- **State Management**: Flutter Riverpod (`flutter_riverpod: ^3.3.1`)
- **Networking**: Dio (`dio: ^5.0.0`)
- **Routing**: GoRouter (`go_router: ^17.5.0`)
- **Typography & Icons**: Google Fonts, Cupertino Icons

---

## Development & Verification Commands

Always run these commands from the `frontend/` directory:

```bash
# Fetch package dependencies
flutter pub get

# Run on specific platforms
flutter run -d chrome      # Web (Chrome)
flutter run -d windows     # Windows desktop
flutter run -d <device_id> # Connected Android emulator / physical device

# Headless verification (CI / terminal checks)
flutter analyze            # Static analysis & linting
flutter test               # Unit and widget tests
flutter build web          # Production web build validation
```

---

## Critical Platform Architecture Rules

### 1. Web-Safe Platform Checks
**Never import `dart:io` or use `Platform` directly.** `dart:io` does not exist in browser runtimes and will break web compilation.
Always import `defaultTargetPlatform` and `kIsWeb` from `package:flutter/foundation.dart`:

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
```

### 2. Backend URL Resolution (`lib/core/api_client.dart`)
The client connects exclusively to the Node.js Core Backend on port 3000:
- **Web & Windows Desktop**: `http://localhost:3000`
- **Android Emulator**: `http://10.0.2.2:3000` (emulator host routing alias)
- **Custom / Physical Device**: Pass via `--dart-define`:
  ```bash
  flutter run --dart-define=SMARTLIB_API_BASE_URL=http://192.168.1.50:3000
  ```

---

## Code Organization

```
frontend/
├── lib/
│   ├── main.dart             # App initialization & ProviderScope entrypoint
│   ├── core/
│   │   ├── api_client.dart   # Dio provider, base URL resolution, global interceptors
│   │   ├── router.dart       # GoRouter configuration & route definitions
│   │   └── theme.dart        # Global theme and styling
│   ├── models/               # Immutable Dart data models (Book, Booking, User, Loan)
│   ├── widgets/              # Reusable UI widgets (cards, dialogs, buttons)
│   └── features/             # Feature-first modules
│       ├── auth/             # Login, register, auth token state
│       ├── catalog/          # Book search, filter, detail, waitlist join
│       ├── loans/            # Active loans, renewals, return workflows
│       ├── bookings/         # Resource booking, seat grid, grace-period timer
│       ├── recommendations/  # AI-driven personalized book recommendation feed
│       ├── profile/          # User reliability score, attendance history, fines
│       ├── health/           # Backend connectivity status screen
│       └── home/             # Main navigation shell and dashboard
└── test/
    ├── widget_test.dart      # Widget tests with ProviderScope overrides
    └── features/             # Feature-specific unit and widget tests
```

---

## State Management Conventions (Riverpod)
- Use `AsyncNotifier` or `FutureProvider` for asynchronous remote data calls.
- Wrap UI screens in `ConsumerWidget` or `ConsumerStatefulWidget`.
- Handle all three states gracefully: `AsyncData`, `AsyncLoading`, and `AsyncError`.
- For widget tests, always supply provider overrides within `ProviderScope(overrides: [...])` to decouple UI tests from active network backends.

---

## Sibling Access
When started from `frontend/`, Claude has access to `../backend` to inspect API routes, request parameters, and response schemas.
