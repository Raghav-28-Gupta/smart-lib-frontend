# SmartLib — Frontend (Flutter + Riverpod)

The SmartLib student app: catalog search, borrowing and the waitlist, loans and
renewals, fines (and disputing them), library notices, seat and room booking with
check-in, problem reports, missed-booking (no-show) disputes, reliability, and
recommendations. One codebase for
**web, Android, and Windows**.

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
SMARTLIB_ADMIN_EMAIL=you@thapar.edu SMARTLIB_ADMIN_PASSWORD_FILE=/path/to/password.txt   dart run tool/capture_fixtures.dart           # from frontend/
cd ../backend && npm run seed                   # restore the demo data
```

The capture has an admin approve and decline requests, cancel and move a
booking, remind the demo student's overdue loan (the library notice saved as
`notices_me`) and answer the student's dispute of the fine that loan's return
wrote (saved as `fines_me_disputed`, `fines_me_adjusted`), and has the student
report the seat they checked into (saved as `bookings_me_reported`, where every
booking on that seat reads `reportOpen`), and, last, has the student dispute the
no-show the seed gives them (`bookings_me_no_show` before and
`bookings_me_no_show_disputed` after) and the admin overturn it from the Needs
attention queue (the outcome notice is saved in `notices_me_no_show_outcome`; every
`GET /bookings/me` it captures also lists that seeded no-show as a `released`
booking with `noShow`), so it needs an admin account (`cd ../backend && npm run create-admin`). Its password is read from a
file so it never lands in your shell history. In PowerShell, set the two
variables first:

```powershell
$env:SMARTLIB_ADMIN_EMAIL = 'you@thapar.edu'
$env:SMARTLIB_ADMIN_PASSWORD_FILE = 'C:\path\to\password.txt'
dart run tool/capture_fixtures.dart
```

The availability fixtures depend on the time of day (a seeded "taken" booking that
is already over becomes a no-show and stops holding its slot), so if
`resource_json_test.dart` says room `r2` has no taken slots ("captured too late in
the day"), re-capture earlier in the day.

A key the backend adds to a response (a fine's `dispute`, a booking's `canReport`,
`reportOpen` and `noShow`) is additive: an older app ignores it, and the models read it as
optional or with a default, so an older server's response still parses (the
booking's `resourceId`, which the backend already sent, is likewise read with a
default, `''`).

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
| 6 | Search for a title, open a book with copies available, **Request to borrow** | *Requested — waiting for a librarian. Expires …*; Search shows one fewer copy available; My Loans lists it under **Requests** | ☐ | ☐ | ☐ |
| 7 | In the admin console, **Approve** that request; keep the book open | Within 30 seconds: *Borrowed — see My Loans…*, and the loan is in My Loans | ☐ | ☐ | ☐ |
| 8 | **Request to borrow** another book; in the console, **Decline** it with a reason | Within 30 seconds: *Your request was declined: …* and **Request again** | ☐ | ☐ | ☐ |
| 9 | **Renew** a renewable loan | *Renewed — now due …* | ☐ | ☐ | ☐ |
| 10 | **Return** a loan → confirm. Then return another, this time ticking **Report a problem with this copy** and choosing *Damaged* | Toast *Returned.*; the loan leaves the list. The second reads *Returned. Thanks for the report.* (choosing *Other* keeps **Return** off until you write a note) | ☐ | ☐ | ☐ |
| 11 | Open *Operating System Concepts* (no copies free) → **Join Waitlist**; go back, then open it again | *You're #3 in line.* is still there; My Loans lists it under **Waitlist** | ☐ | ☐ | ☐ |
| 12 | On that book, **Leave waitlist** | Toast *You've left the waitlist.*; *Join Waitlist* is back | ☐ | ☐ | ☐ |
| 13 | **Held copy**: on another client, log in as `seed.student1@thapar.edu` (same password), request *The Midnight Library*, and approve it in the console. As Aditi, join its waitlist. Then return it as the other student | Aditi's My Loans shows *Held for you until …* and the book offers **Request to borrow**; the other student sees *Every copy on the shelf is held for a student on the waitlist.* | ☐ | ☐ | ☐ |
| 14 | Bookings → New → Seats → Tomorrow → pick a slot → Continue → **Confirm booking** | *Booked*; it appears under Bookings with *check-in opens at the start time* | ☐ | ☐ | ☐ |
| 15 | Bookings → New → Rooms → Tomorrow → pick a slot → Continue → **Send request**; then approve it in the console | *Request sent*; My Bookings shows *Waiting for a librarian · held until …*, then within 30 seconds *check-in opens at the start time* | ☐ | ☐ | ☐ |
| 16 | **Conflict**: on this platform, get to the confirm screen for a seat and slot. On another platform or browser tab, book that same seat and slot first. Then tap Confirm here | *That slot was just taken* with alternatives; tapping one books it | ☐ | ☐ | ☐ |
| 17 | **Check in**: between :00 and :15 past the hour (9 AM–7 PM), book today's current slot, open Bookings, tap **Check In**. Then tap **Report a problem** on that card, choose *Other* (**Send** stays off until you write a note), write one, and send | *Enjoy your session.* After sending, the toast reads *Thanks, the library has your report.* and the card shows *Reported* in place of the button | ☐ | ☐ | ☐ |
| 18 | **Cancel** a booking → confirm | Toast *Booking canceled.*; it leaves the list | ☐ | ☐ | ☐ |
| 19 | Profile | Reliability ring at 50, *Building back up*; **How reliability works** opens a dialog | ☐ | ☐ | ☐ |
| 20 | Home → Recommended for You → See all | A list of books | ☐ | ☐ | ☐ |
| 21 | **Relaunch** (web: reload the page; Windows: close the window and run again; Android: swipe it away from Recents and reopen) | Splash, then Home, **without logging in** | ☐ | ☐ | ☐ |
| 22 | **Expired session**: restart the backend with a throwaway secret (below), then type in Search | Back on Log in with *Your session has expired. Please log in again.* | ☐ | ☐ | ☐ |
| 23 | Restart the backend normally and log in again | Home | ☐ | ☐ | ☐ |
| 24 | On a freshly seeded backend, log in as the demo user and open Bookings. On the *Group Room 201* card that reads *Missed. A no-show was recorded.*, tap **Dispute**, write a reason and **Send** | Toast *Dispute sent.*; the button is replaced by *Under review* and stays that way after you leave the tab and come back | ☐ | ☐ | ☐ |

**Steps 13 and 16 need two clients.** A held copy needs a second student
to return a book you're queued for. And the picker greys out slots that are
already taken, so a conflict only happens when someone else books the slot
while you're on the confirm screen. A second browser tab works for both.

**Steps 7, 8, 13 and 15 need the admin console** (`../admin`), logged in with an
admin account. In step 13, if the other student gets *You already have this book
borrowed.* (the seed history can already have lent them the title), use another
title with one free copy.

**Step 22** invalidates every issued token without touching any file. The
backend loads `.env` with `dotenv`, which never overrides a variable that's
already set:

```powershell
# in backend/, after stopping the running server
$env:JWT_SECRET = 'acceptance-throwaway'; npm run dev
# step 23: stop it, then
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
├── widgets/                   # shared widgets (covers, skeletons, empty/error states, the note field)
└── features/
    ├── auth/                  # login/register, session restore, splash
    ├── catalog/               # search, book detail, borrow requests
    ├── borrow_requests/       # borrow requests: repository and controller
    ├── waitlist/              # join/leave, place in line, copies held for you
    ├── loans/                 # active loans, renew, return
    ├── fines/                 # the student's fines (the Fines section of My Loans)
    ├── notices/               # library notices (the Library notices section of My Loans and My Bookings)
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
└── e2e_smoke_test.dart        # login → request → booking conflict, on mocks
tool/capture_fixtures.dart     # refreshes test/fixtures from a live backend
```

## Known limitations

- **No notifications.** When a copy comes back for you, it's held for 48 hours.
  The app shows the hold in My Loans and on the book, but nothing tells you
  while the app is closed. The backend emails only the library's own notices
  (below), not holds.
- **A librarian's answer to a request arrives by re-check.** While a request is
  pending and its screen is open, the app asks the server every 30 seconds;
  nothing tells you while the app is closed. Push notifications are planned.
- **A library cancel or move arrives when you open My Bookings.** When a
  librarian cancels a booking or moves it to another seat or room, My Bookings
  shows *Cancelled by the library* or *Moved from … by the library* the next
  time you open it: each time its tab is selected, the screen does one quiet
  re-check of the list (a failed re-check keeps the list you had). While you
  stay on another screen, or on My Bookings itself, nothing updates, apart from
  the 30-second re-check while a room request is pending. Tapping the tab you
  are already on does not re-check. The server lists these notices for 7 days.
  There are no push notifications yet.
- **Fines, and changes to them, show when you open My Loans.** The Fines section
  lists your fines (outstanding, adjusted, paid or waived, with the librarian's
  note when one lowered or waived it). A fine that is still owed has a **Dispute**
  button: it asks why you think the fine is wrong (at most 300 characters, counted
  as the library counts them: an emoji or a Hindi vowel sign can count as two, so
  the field shows its own count, *n/300*, and says *At most 300 characters* with
  **Send** off when you are over; what you typed is never cut) and
  sends it, once per fine. The card then reads *Under review* in place of the
  button, and the button never returns; while it is open the library cannot
  record a payment for that fine. If the library refuses the dispute (the fine was
  paid or waived meanwhile, or you already disputed it from another device), the
  dialog stays and a toast gives its reason. The library's answer arrives as a
  library notice, and on the card: a waived or lowered fine shows its new status
  and the librarian's note, and an upheld one reads *The library kept this fine.*
  with their note. When a librarian records a payment, answers a dispute, waives
  or lowers a fine, or marks a copy you borrowed as lost (the loan leaves the
  list), My Loans shows it the next time you open it: each time its tab is
  selected, the screen does one quiet re-check of the loans, the fines and the
  library notices (a failed re-check keeps what you had). While you stay on
  another screen, or on My Loans itself, nothing updates, except that returning
  or renewing a late book shows its fine at once. There are no push
  notifications yet.
- **A problem with a book is reported when you return it.** The **Return** dialog
  has an optional **Report a problem with this copy** box: ticking it asks what is
  wrong (*Damaged*, *Missing pages* or *Other*) and for a note of at most 300
  characters (counted as for a dispute), which *Other* requires, and **Return**
  stays off until that is filled in. The report is sent in the same request as the
  return, so you never return a book and lose the report, or the reverse; if the
  return is refused, nothing is reported. While a return is being sent, that loan's
  **Return** button on its card is off, so a second tap cannot be refused as "already
  returned" over the first one's thanks. There is no other way to report a copy, and
  the library's answer arrives as a library notice (below).
- **A problem with a seat or room is reported from My Bookings.** A booking the
  library says you can report (one that started within the last 7 days or starts
  within the next 24, whether or not you checked in; not a cancelled one or a room
  request still waiting) shows a **Report a problem** button. It asks what is wrong
  (*Not working*, *Dirty* or *Other*) and for a note of at most 300 characters (counted
  as for a dispute), which *Other* requires, and **Send** stays off until that is filled in. After sending, every
  booking of yours on that seat or room reads *Reported* in place of the button until
  the library has dealt with it; you cannot report the same seat twice meanwhile (a
  second attempt, say from another device, is refused with the library's own message
  and the card catches up). The library's answer arrives as a library notice (below),
  after which the button comes back for a booking that is still within the window.
- **A missed booking can be disputed from My Bookings.** A booking you did not
  check into is recorded by the library as a no-show within minutes of its grace
  period ending, your reliability score drops, and the card reads *Missed. A no-show
  was recorded.* (the server tells it apart from a plain release, which keeps its old
  text *This booking was released after the grace period.*). While the library says
  you still can (no dispute yet and inside 7 days of the grace period's end; the app
  never works that out itself) a **Dispute** button opens *Dispute this no-show*: one
  multi-line field, *Why do you think this no-show is wrong?*, at most 300
  characters counted as for a fine dispute, **Send** off until there is text. After
  sending (toast *Dispute sent.*) the button is gone for good and a line under the
  missed line reads *Under review*; the library's answer arrives as a library
  notice and on the card: *No-show stands* (with their note) leaves the missed line
  above it, and *No-show removed* (with their note) replaces both lines. If the
  library refuses (the 7 days passed, or you already disputed it from another
  device) the dialog stays and a toast gives its reason. A missed booking stays in
  the list and, within the usual window, can still be reported (**Report a
  problem**), for the student who found the seat broken and left.
- **Library notices show when you open My Loans or My Bookings.** A **Library
  notices** section at the top of My Loans lists the library's messages to you from
  the last 7 days (at most 20, newest first): a librarian's overdue reminder or
  formal notice, or the outcome of a dispute or a report. The three booking kinds
  show at the top of **My Bookings** instead: a *Your booking starts soon* reminder
  (written up to 30 minutes before the start, for a booking made, or a room approved,
  at least 30 minutes before it; it disappears once you check in or cancel, or its
  grace period ends),
  *Missed booking* when a no-show is recorded, and the *No-show removed* or *No-show
  stands* outcome of a dispute. My Bookings re-checks them each time its tab is
  selected, and on its 30-second re-check while a room request is waiting; with an
  ordinary booking and nothing pending, a reminder appears the next time you open the
  tab (nothing is pushed). A section with none of its kinds shows nothing, and an
  older app shows every kind on My Loans. Seats get no reminder email, so this
  section is their only reminder; rooms also get one by email. Each shows its title, text and date, and a formal
  overdue notice is drawn in the accent colour. The section is absent when there
  are none, while they load and when they can't be loaded (no error is shown; the
  next time you open My Loans asks again). Like the loans and the fines, they are
  re-checked quietly each time the tab is selected (a failed re-check keeps what
  you had), and nothing arrives while you stay on another screen. A kind of notice
  this version doesn't know still shows its title and text. The text is also
  emailed when the library has set up email (never to the demo accounts'
  placeholder addresses); there is no push notification and no "mark as read".
- **Search sends a request on every keystroke**, with no debounce.
- **The app is student-only.** It receives the user's `role`, but librarian
  tools are planned as a separate web console.
