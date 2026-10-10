# SmartLib — Frontend (Flutter + Riverpod)

The SmartLib student app: catalog search, borrowing and the waitlist, loans and
renewals, seat and room booking with check-in, reliability, and recommendations.
One codebase for **web, Android, and Windows**.

The app talks to exactly one server, the Node backend on port 3000. It has no
offline mode and no demo data of its own: without the backend running, every
screen shows its error state.

Verified against Flutter **3.47.0** / Dart **3.13.0** (stable).

## Prerequisites

- **Flutter SDK** on your PATH. `flutter doctor` should be green for your target.
- **The backend, seeded and running** (see `../backend/README.md`):
  ```bash
  cd ../backend
  npm run seed     # resets the demo data; safe to re-run
  npm run dev      # http://localhost:3000
  ```
  Demo login: `aditi.sharma@thapar.edu` / `password123`
- **Windows target only:** Visual Studio (or Build Tools) with the *Desktop
  development with C++* workload **plus the "C++ ATL" component**. The
  `flutter_secure_storage` plugin stores the session in Windows Credential
  Manager and includes `atlstr.h`; without ATL the build fails with
  `Cannot open include file: 'atlstr.h'`. To add it, open Visual Studio
  Installer → *Modify* → *Individual components* → search **ATL** → tick
  *C++ ATL for latest build tools (x86 & x64)*.
- **Android target only:** the Android SDK and an emulator (or a device; see
  [Physical devices](#physical-devices)).

## Run

```bash
cd frontend
flutter pub get

flutter run -d chrome --web-port 8080   # web
flutter run -d windows                  # Windows desktop
flutter run -d emulator-5554            # Android emulator (id from `flutter devices`)
```

The app opens on a brief splash screen while it checks for a saved session,
then lands on **Home** (signed in) or **Log in**.

To start an emulator, use `flutter emulators --launch <id>`. If that lists
nothing even though you have emulators in Android Studio, start one directly:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd <name>
```

## Backend URL per platform

`resolveBaseUrl()` in `lib/core/api_client.dart` picks:

| Target | URL |
|---|---|
| Web / Windows | `http://localhost:3000` |
| Android emulator | `http://10.0.2.2:3000` (the emulator's alias for the host machine) |
| Anything else | whatever you pass in, below |

### Physical devices

A phone can't reach your PC's `localhost`. Pass the PC's LAN address:

```bash
flutter run --dart-define=SMARTLIB_API_BASE_URL=http://192.168.1.20:3000
```

The phone and PC must be on the same network, and Windows Firewall must allow
inbound connections to port 3000.

## Platform notes

These are the things that differ by platform and will bite if you don't know them.

**Android allows plain HTTP in debug builds only.** Android 9+ blocks
cleartext traffic, and the dev backend is `http://`. The exception lives in
`android/app/src/debug/AndroidManifest.xml`, so it applies to debug builds and
nothing else. A **release or profile APK will fail every request** until the
backend is served over HTTPS. That's deliberate.

**Where the session is stored.** The login token is kept by
`flutter_secure_storage`:

| Platform | Storage |
|---|---|
| Android | Android Keystore–backed encrypted storage |
| Windows | Windows Credential Manager (needs the ATL component above) |
| Web | Encrypted with WebCrypto into `localStorage`, *per origin* |

On web, secure storage only works on **HTTPS or `localhost`**. Anywhere else
the app still works, but the session isn't remembered across reloads.
`TokenStore` treats a storage failure as "not remembered", never as a crash.
Because storage is per origin, `--web-port 8080` matters: without it
`flutter run` picks a new port each time and every run starts signed out.
`flutter run -d chrome` also uses a throwaway Chrome profile, so a fresh
`flutter run` always starts signed out. Reloading the page in the same window
keeps you signed in.

**Time zones: client and server must agree.** Booking slots ("3:00 PM") are
turned into timestamps in the *client's* local time, and the server checks
them against its own slot table in *its* local time. These line up only when
both are in the same time zone. That holds for a campus deployment (IST) but
would break with, for example, a server in UTC. Timestamps on the wire are always
UTC (`…Z`) and are shown in local time.

**Web builds must never import `dart:io`.** It doesn't exist in browsers, and
importing it breaks the web build. Use `kIsWeb` / `defaultTargetPlatform` from
`package:flutter/foundation.dart`.

The backend sends permissive CORS headers, so web needs no proxy.

## Tests

```bash
flutter analyze
flutter test           # no backend needed
```

The test suite never touches the network or a real keystore. The app's
repositories talk HTTP, and every test swaps them for in-memory mocks with
`mockRepositoryOverrides()` (`test/support/mock_overrides.dart`). **Any test
that builds a `ProviderScope` or `ProviderContainer` must use it.** Without
it, the test makes real HTTP calls.

**Fixtures.** The JSON-parsing tests read real backend responses saved in
`test/fixtures/`. When a backend response shape changes, re-capture them. The
script **writes to the dev database**, so seed before and after:

```bash
cd ../backend && npm run seed && npm run dev    # separate terminal
dart run tool/capture_fixtures.dart             # from frontend/
cd ../backend && npm run seed                   # restore the demo data
```

**Code generation.** Models use `json_serializable`. After changing a model,
regenerate and commit the `*.g.dart` output:

```bash
dart run build_runner build
```

## Manual acceptance checklist

Run this on each platform. Start from a freshly seeded backend, and re-seed
when you're done, because the steps change the demo data.

| # | Do | Expect | Chrome | Windows | Android |
|---|---|---|---|---|---|
| 1 | Launch for the first time | Splash, then **Log in** | ☐ | ☐ | ☐ |
| 2 | *Create account* with a new email and an 8+ character password | Lands on Home | ☐ | ☐ | ☐ |
| 3 | Profile → **Log out** | Back on Log in | ☐ | ☐ | ☐ |
| 4 | Log in as the demo user | Home: *Welcome back, Aditi* | ☐ | ☐ | ☐ |
| 5 | My Loans | 4 loans; one overdue showing *Fine: ₹30.0 and counting*; one showing *Renewal unavailable — 1 student is waiting for this title.* | ☐ | ☐ | ☐ |
| 6 | Search for a title, open a book with copies available, **Borrow this copy** | Button becomes *Borrowed — see My Loans…*; available count drops; the loan appears in My Loans | ☐ | ☐ | ☐ |
| 7 | **Renew** a renewable loan | *Renewed — now due …* | ☐ | ☐ | ☐ |
| 8 | **Return** a loan → confirm | Toast *Returned.*; the loan leaves the list | ☐ | ☐ | ☐ |
| 9 | Bookings → New → Seats → Tomorrow → pick a slot → Continue → **Confirm booking** | *Booked*; it appears under Bookings with *check-in opens at the start time* | ☐ | ☐ | ☐ |
| 10 | **Conflict**: on this platform, get to the confirm screen for a seat and slot. On another platform or browser tab, book that same seat and slot first. Then tap Confirm here | *That slot was just taken* with alternatives; tapping one books it | ☐ | ☐ | ☐ |
| 11 | **Check in**: between :00 and :15 past the hour (9 AM–7 PM), book today's current slot, open Bookings, tap **Check In** | *Enjoy your session.* | ☐ | ☐ | ☐ |
| 12 | **Cancel** a booking → confirm | Toast *Booking canceled.*; it leaves the list | ☐ | ☐ | ☐ |
| 13 | Profile | Reliability ring at 50, *Building back up*; **How reliability works** opens a dialog | ☐ | ☐ | ☐ |
| 14 | Home → Recommended for You → See all | A list of books | ☐ | ☐ | ☐ |
| 15 | **Relaunch** (web: reload the page; Windows: close the window and run again; Android: swipe it away from Recents and reopen) | Splash, then Home, **without logging in** | ☐ | ☐ | ☐ |
| 16 | **Expired session**: restart the backend with a throwaway secret (below), then type in Search | Back on Log in with *Your session has expired. Please log in again.* | ☐ | ☐ | ☐ |
| 17 | Restart the backend normally and log in again | Home | ☐ | ☐ | ☐ |

**Step 10 needs two clients.** The picker greys out slots that are already
taken, so a conflict only happens when someone else books the slot while
you're on the confirm screen. A second browser tab works for this.

**Step 16** invalidates every issued token without touching any file. The
backend loads `.env` with `dotenv`, which never overrides a variable that's
already set:

```powershell
# in backend/, after stopping the running server
$env:JWT_SECRET = 'acceptance-throwaway'; npm run dev
# step 17: stop it, then
Remove-Item Env:JWT_SECRET; npm run dev
```

**Leftover data.** Accounts created in step 2 persist in the dev database:
`npm run seed` only resets the demo rows it owns. Use an obviously-test email.

## Layout

```
lib/
├── main.dart                  # ProviderScope + MaterialApp.router; toasts mounted above every route
├── core/
│   ├── api_client.dart        # Dio, base URL, auth interceptor, guardApi()
│   ├── api_exception.dart     # ApiException / UnauthorizedException / ConflictException
│   ├── auth/token_store.dart  # in-memory token + secure-storage persistence
│   ├── clock.dart             # injectable "now" for tests
│   ├── time_format.dart
│   ├── router/app_router.dart # splash → login/home redirects, tab shell
│   ├── theme/                 # tokens + ThemeData
│   └── ui/                    # confirm dialogs, toasts, UiController.attempt()
├── models/                    # json_serializable models (+ committed *.g.dart)
├── widgets/                   # shared widgets (covers, skeletons, empty/error states)
└── features/
    ├── auth/                  # login/register, session restore, splash
    ├── catalog/               # search, book detail, borrow, waitlist
    ├── loans/                 # active loans, renew, return
    ├── bookings/              # booking flow, conflicts, check-in, time slots
    ├── profile/               # reliability
    ├── recommendations/
    ├── home/
    └── health/                # Phase 1 connectivity screen; no longer routed
test/
├── support/                   # mockRepositoryOverrides, fixtures loader, HTTP stub
├── fixtures/                  # captured real backend responses
├── models/                    # JSON parsing against the fixtures
├── core/ · features/          # unit + widget tests, mirroring lib/
└── e2e_smoke_test.dart        # login → borrow → booking conflict, on mocks
tool/capture_fixtures.dart     # refreshes test/fixtures from a live backend
```

## Known limitations

- **Waitlist status isn't remembered.** After joining, the book screen says so,
  but leaving and reopening it offers *Join Waitlist* again. The app doesn't yet
  fetch the student's reservations. Joining twice is refused by the server, with
  its reason shown.
- **Search sends a request on every keystroke**, with no debounce.
- **The app is student-only.** It receives the user's `role`, but librarian
  tools are planned as a separate web console.
