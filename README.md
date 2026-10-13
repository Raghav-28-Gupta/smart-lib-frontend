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
| Anything else, and every deployed build | whatever you pass in, below |

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

## Deploy

| What | How | Where |
|---|---|---|
| Web | `.github/workflows/web.yml`: every push and PR runs analyze and the tests; a push to `main` then builds and publishes | https://raghav-28-gupta.github.io/smart-lib-frontend/ |
| Android | `.github/workflows/release.yml`: push a tag like `v1.0.0` | A GitHub Release with the signed APK (Windows isn't released; build it locally) |

Every deployed build has the production backend URL compiled in
(`--dart-define`). A release build made **without** it points at `localhost`
and can't reach anything.

### One-time setup (repository Settings)

1. **Pages** → Build and deployment → Source: **GitHub Actions**.
2. **Variable** `SMARTLIB_API_BASE_URL` (Settings → Secrets and variables →
   Actions → Variables): the backend's URL, currently
   `https://smart-lib-backend.onrender.com` (no trailing slash). Set.
3. **Android signing key.** Create it once and keep it forever: an installed
   app only accepts updates signed with the same key. Run these in a normal
   PowerShell window; `keytool` asks you to choose a password and fill in some
   name fields (anything is fine):
   ```powershell
   & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v `
     -keystore "$HOME\smartlib-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Then store it as four repository **Secrets**. `gh secret set` asks for each
   password in your terminal, so the values never appear in a file or chat:
   ```powershell
   $repo = 'Raghav-28-Gupta/smart-lib-frontend'
   gh secret set ANDROID_KEYSTORE_BASE64 -R $repo --body ([Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\smartlib-upload.jks")))
   gh secret set ANDROID_KEYSTORE_PASSWORD -R $repo   # type the keystore password
   gh secret set ANDROID_KEY_ALIAS -R $repo --body upload
   gh secret set ANDROID_KEY_PASSWORD -R $repo        # the same password again
   ```
   (keytool uses one password for both the keystore and the key.) You can also
   add them by hand under Settings → Secrets and variables → Actions → Secrets.

   Back up `smartlib-upload.jks` and its password outside the repository. If
   either is lost, installed apps can no longer be updated. Never commit them;
   `android/.gitignore` already excludes both.

### Releasing

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow runs the tests, builds the APK, refuses one signed with the
debug key, and publishes it on the repository's Releases page. To install,
open the APK on the phone and allow "install unknown apps" for the browser or
file manager you used.

The Android app ID is `io.github.raghav28gupta.smartlib`. Don't change it
after the first release.

### Building a release locally

```bash
flutter build apk --release --dart-define=SMARTLIB_API_BASE_URL=https://smartlib-backend.onrender.com
```

Without `android/key.properties`, this is signed with the debug key. That's
fine for trying the build, but don't hand it out.

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
| 9 | Open *Operating System Concepts* (no copies free) → **Join Waitlist**; go back, then open it again | *You're #3 in line.* is still there; My Loans lists it under **Waitlist** | ☐ | ☐ | ☐ |
| 10 | On that book, **Leave waitlist** | Toast *You've left the waitlist.*; *Join Waitlist* is back | ☐ | ☐ | ☐ |
| 11 | **Held copy**: on another client, log in as `seed.student1@thapar.edu` (same password) and borrow *The Midnight Library*. As Aditi, join its waitlist. Then return it as the other student | Aditi's My Loans shows *Held for you until …* and the book offers **Borrow this copy**; the other student sees *Every copy on the shelf is held for a student on the waitlist.* | ☐ | ☐ | ☐ |
| 12 | Bookings → New → Seats → Tomorrow → pick a slot → Continue → **Confirm booking** | *Booked*; it appears under Bookings with *check-in opens at the start time* | ☐ | ☐ | ☐ |
| 13 | **Conflict**: on this platform, get to the confirm screen for a seat and slot. On another platform or browser tab, book that same seat and slot first. Then tap Confirm here | *That slot was just taken* with alternatives; tapping one books it | ☐ | ☐ | ☐ |
| 14 | **Check in**: between :00 and :15 past the hour (9 AM–7 PM), book today's current slot, open Bookings, tap **Check In** | *Enjoy your session.* | ☐ | ☐ | ☐ |
| 15 | **Cancel** a booking → confirm | Toast *Booking canceled.*; it leaves the list | ☐ | ☐ | ☐ |
| 16 | Profile | Reliability ring at 50, *Building back up*; **How reliability works** opens a dialog | ☐ | ☐ | ☐ |
| 17 | Home → Recommended for You → See all | A list of books | ☐ | ☐ | ☐ |
| 18 | **Relaunch** (web: reload the page; Windows: close the window and run again; Android: swipe it away from Recents and reopen) | Splash, then Home, **without logging in** | ☐ | ☐ | ☐ |
| 19 | **Expired session**: restart the backend with a throwaway secret (below), then type in Search | Back on Log in with *Your session has expired. Please log in again.* | ☐ | ☐ | ☐ |
| 20 | Restart the backend normally and log in again | Home | ☐ | ☐ | ☐ |

**Steps 11 and 13 need two clients.** A held copy needs a second student
to return a book you're queued for. And the picker greys out slots that are
already taken, so a conflict only happens when someone else books the slot
while you're on the confirm screen. A second browser tab works for both.

**Step 19** invalidates every issued token without touching any file. The
backend loads `.env` with `dotenv`, which never overrides a variable that's
already set:

```powershell
# in backend/, after stopping the running server
$env:JWT_SECRET = 'acceptance-throwaway'; npm run dev
# step 20: stop it, then
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
    ├── catalog/               # search, book detail, borrow
    ├── waitlist/              # join/leave, place in line, copies held for you
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

- **No notifications.** When a copy comes back for you, it's held for 48 hours.
  The app shows the hold in My Loans and on the book, but nothing tells you
  while the app is closed. The backend has no notification channel yet.
- **Search sends a request on every keystroke**, with no debounce.
- **The app is student-only.** It receives the user's `role`, but librarian
  tools are planned as a separate web console.
