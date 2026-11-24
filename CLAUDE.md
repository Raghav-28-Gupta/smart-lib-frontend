# SmartLib — Frontend (Flutter + Riverpod)

The SmartLib student app for **Web, Android, and Windows Desktop**: catalog and
borrowing, waitlist, loans, fines (and disputing them), library notices, seat/room
booking with check-in, problem reports, reliability, and recommendations. It talks
only to the Node backend (`../backend`, port 3000).
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
  `LoansController._renewing` and `_returning`, `BookingFlowController._confirming`).
- **Availability: use `Book.freeCopies`, not `availableCopies`.** A copy held
  for a waitlisted student's claim (`heldCopies`) is on the shelf but refused
  to everyone else. The one exception is the claimant: when the student's own
  `Reservation` is `held`, offer Request to borrow.
- **Per-user state is keyed on the user.** Controllers holding a user's data
  `watch` `authControllerProvider.select((s) => s.user?.id)`, so logging in as
  someone else refetches instead of showing the previous user's data. Riverpod
  keeps the previous user's value on the reloading state (`isReloading`) and beside
  the error of a failed refetch, so a screen must not render `.value` then (My Loans
  reads both as not loaded: `own()` in `LoansScreen`, and the same guard inline in
  `FinesSection` and `NoticesSection`). Controllers with a `refreshQuietly`
  (`LoansController`, `FinesController`, `NoticesController`, `BookingsController`)
  bump a generation in `build()`, drop a result begun under an older one, and never
  join an older generation's fetch in flight, so a refresh started for the last user
  cannot land in the next one's state.
- **Screens showing a pending request wrap their body in `PendingRefresh`**
  (`lib/widgets/pending_refresh.dart`). It re-checks on open and every 30 s
  through the controllers' `refreshQuietly()`, which keeps the current list
  when the network fails.
- **Outcomes the student didn't cause arrive when My Bookings is opened.** A
  librarian's cancel (`BookingStatus.cancelledByLibrary`, with `cancelReason`)
  and move (`ResourceBooking.movedFrom`, the old resource's name) show because
  `BookingsScreen` makes one `refreshQuietly()` after its first frame
  (`_refreshOnOpen`); the list was usually loaded earlier, on Home. The tabs are
  a plain `ShellRoute` and each tab visit builds a fresh screen, so this runs on
  every visit; re-tapping the open tab does not (`context.go` to the same
  location is a no-op). It is skipped while the list is still loading, since
  that load is itself fresh. `refreshQuietly()` joins a fetch already in flight,
  so the open plus `PendingRefresh`'s own on-open tick fetch once. Beyond that
  only a pending request is polled (every 30 s); nothing is pushed while the
  student is on another screen, and there is no push notification. The server
  lists these outcomes for 7 days. `cancelledByLibrary` has no buttons and sits
  outside `_progress`, so `advancedTo` never changes it. A new `BookingStatus`
  goes into `_statusLines` (an exhaustive switch), and a new `ResourceBooking`
  field must be carried through `copyWith`.
- **My Loans refreshes on open like My Bookings.** A payment, waive or
  adjustment of a fine, the answer to a dispute, a new library notice, or a loan a
  librarian marked lost, happens while the student is elsewhere, so `LoansScreen`
  makes one `refreshQuietly()` on each of **three** lists, the loans, the fines and
  the notices, after its first frame (`_refreshOnOpen`), on every tab visit and not
  on re-tapping the open tab. Each is skipped only while *that* list is still
  loading (the fines and the notices are first loaded by this screen, while the
  loans were usually loaded long before on Home, so a joint skip would leave the
  loans stale). `LoansController`, `FinesController` and `NoticesController`
  `refreshQuietly()` all join a fetch in flight (their `_refreshing` future) and
  keep the data on a network error.
  A successful return or renew also makes `LoansController` call the fines'
  `refreshQuietly()` (`_refreshFines`, skipped when the fines were never read),
  because a late one makes the server write the overdue fine, which the student
  must see on the same screen. So does a refusal that means stale state (409/404:
  the loan was closed elsewhere, for example marked lost by a librarian, which wrote
  fines), but not a network error.
  The Fines section (`features/fines/fines_section.dart`) sits below the loans:
  "Outstanding: ₹X" when the total is above 0, one card per fine
  (`₹20, was ₹30` once lowered, and "Library note: ..." when there is one), and
  "No fines." when empty. Amounts are whole rupees. `FineStatus.unknown` shows
  "Update the app to see this item's status." in place of the amount and status
  (the same fallback as loans and requests), and an unknown `FineReason` is simply
  left unlabelled, so a value a later server adds never breaks the list (a dispute
  is no fine status for the student: the fine keeps its four statuses and carries
  `dispute`, below). A student with fines but no loans, requests or waitlist sees
  the section, not the "No active loans" empty state, which waits until the fines
  (and the notices, below) are known to be empty.
  The "On loan" heading is always shown, because the Fines section is always
  below. Nothing is pushed while the student is on another screen.
  **Disputing a fine** (`Fine.dispute`: `FineDispute { DisputeStatus status, String?
  note }`, `DisputeStatus { open, waived, adjusted, upheld, unknown }`, null when the
  student never disputed it or the server predates disputes): an outstanding or
  adjusted fine with no dispute shows a **Dispute** button (its screen-reader label
  names the fine, "Dispute fine of ₹30 for Operating System Concepts", while the visible
  text stays "Dispute"), which opens "Dispute this
  fine" (one multi-line field, "Why do you think this fine is wrong?", at most 300,
  Send off until there is text and while it is over the limit). The field is the shared
  `NoteField` (below), so the 300 is counted as the server counts it, not as Flutter's
  `maxLength` does. The write is `FinesController.dispute` (repository
  `POST /fines/:id/dispute { reason }`) through `UiController.attempt` with the toast
  "Dispute sent." It mirrors `BookingsController._readAfterWrite`: after the write it
  waits for any fetch already in flight (that fetch began before the write and may answer
  without it), marks that fine `dispute: open` itself so the card reads "Under review" at
  once and survives a failed re-read, then `refreshQuietly()`; a 409/404 re-reads too, a
  network error does not, and nothing is done once a different student has logged in since
  (`_generation`). On a refusal the dialog stays with the typed text and the server's
  message; Send is off while the request is in flight (a second tap sends nothing). The
  fine's own `status` is unchanged by a dispute (a disputed fine is still outstanding),
  so the card adds one line from `dispute`: open reads "Under review" in place of the
  button, upheld adds "The library kept this fine." and the note, and waived, adjusted
  and an unknown status add nothing (waived and adjusted already read from the fine's
  own status and "Library note"). The button never returns once a dispute exists. It
  is gated by the same `isReloading || hasError` guard as the rest of the section, so
  one student's dispute state or button never shows for the next.
  The **Library notices** section (`features/notices/notices_section.dart`, from
  `GET /notices/me`: `Notice { id, kind, title, body, createdAt }`, the last 7 days,
  at most 20, newest first) sits above Requests: each notice's title in bold, its
  body and its date (`20 Nov 2026`, as the fines), a `NoticeKind.overdueEscalation`
  in the accent colour (`colorScheme.primary`). A `NoticeKind.unknown` still shows its
  title and body. Notices are secondary, so the section is **absent** when there are
  none, while they load and when they fail to load (no error text and no Retry; the
  next open asks again). `NoticesController` follows the fines' rules (keyed on the
  user id, a generation in `build()`, `refreshQuietly()` joining a fetch in flight of
  the same generation and keeping the data on a network error), and `LoansScreen`
  makes one `refreshQuietly()` on notices in `_refreshOnOpen`, skipped while they load.
  Because a student's only news can be a notice (the outcome of a report on a book
  they returned), the empty state waits for the notices too: it shows once they are
  known empty or failed, never while they load. The library's reminder, a
  dispute outcome and a report outcome all arrive this way; the text is the server's,
  never rebuilt in the app.
- **A problem with a copy is reported in the Return dialog**, and only there (the
  copy has to be back on the shelf before a librarian can act on it, and there is no
  report button on the On-loan card). `_ReturnDialog` (`core/ui/confirm_dialog.dart`,
  a `StatefulWidget` holding its own choices, so reopening it starts blank) keeps the
  title "Return this book?" and its text and adds a checkbox "Report a problem with
  this copy". Ticking it shows Damaged, Missing pages, Other (none preselected) and a
  note field; Return stays off until the report is valid: a category is chosen, the
  trimmed note is at most 300 and, for Other, not empty. The note field is the shared
  `NoteField` (`widgets/note_field.dart`, the one note field of this app: this dialog, the
  seat or room report and the fine dispute all use it). It counts as the server counts, in
  UTF-16 code units of the trimmed text (`String.length`, one `kMaxNoteLength = 300`;
  `noteTooLong()` is what a dialog gates its button on), not in grapheme clusters as
  Flutter's `maxLength` does, which would let a long Hindi or emoji note through to a
  400. So the field has no `maxLength` and never cuts what the student typed; it shows its
  own `n/300` counter and, over the limit, the counter in the error colour and the
  `errorText` "At most 300 characters", with the dialog's button off. It also draws a
  rounded rectangle (the theme's own outline, radius `radiusMd`) instead of the theme's
  999 px pill, which is for single-line fields: on a multi-line field the pill scales to
  half the field's height and the floating label's gap eats the top edge. A blank note is
  sent as no note, never as an empty string.
  `UiController.confirmReturnLoan(report)` replaces `confirmDialog()` for this dialog
  (the other dialogs still use `confirmDialog()`): it closes the dialog, then runs
  `onConfirmReturnLoan(loanId, report)` through `attempt` with the toast "Returned."
  or "Returned. Thanks for the report."; a refusal toasts the server's message as ever.
  The dialog closes at once, so nothing else shows the return in flight: the loan card's
  **Return** is off while `LoansController.isReturning(loanId)` (a `_returning` set, like
  `_renewing`, which also makes a second `returnLoan` of the same loan send nothing and
  calls `ref.notifyListeners()` when it starts and ends so the card redraws). Without it a
  second return was refused ("already returned") and its toast replaced the first one's
  thanks.
  The report goes `LoansController.returnLoan(id, report:)`, `LoanRepository.returnLoan(id,
  report:)`, then `POST /loans/:id/return` with the body `{ report: { category, note? } }`
  (no body without a report): one request, so the server saves the report and the
  return together or neither, and its answer is unchanged. `ReturnReport { ReportCategory
  category, String? note }` (`models/return_report.dart`; the server's spellings are
  `damaged`, `missing_pages` and `other`) is hand-written and outgoing only, so it needs
  no `build_runner`; its `toJson()` leaves out a null note. The outcome comes back as a
  library notice, like a fine dispute's.
- **A problem with a seat or room is reported from My Bookings** (the copy report's
  counterpart; `POST /reports`). The server marks each `GET /bookings/me` row with
  `canReport` (this booking entitles the student to report its resource: raw status
  booked, checked in or completed, started within 7 days or starting within 24 hours;
  checked in or not) and `reportOpen` (the student has an open report on the resource:
  true for every booking of theirs on it, so `canReport` is then false). The app never
  works either out. `ResourceBooking` gains `resourceId` (`@JsonKey(defaultValue: '')`),
  `canReport` and `reportOpen` (default false, so an older payload parses), all carried
  through `copyWith`, which also takes `canReport` and `reportOpen`. The card
  (`_reportLine` in `bookings_screen.dart`) shows "Reported" when `reportOpen`, else a
  **Report a problem** text button when `canReport` (its semantics label names the
  resource, "Report a problem with Seat A1", because several cards say the same words),
  else nothing. The button opens `_ReportDialog` (a private widget in the screen file,
  like the fine dispute dialog): the resource's name, Not working, Dirty and Other
  (`ResourceReportCategory`, in `models/resource_booking.dart`; wire names `not_working`,
  `dirty`, `other`; none preselected), and a note field. Send is off until a category is
  chosen, the trimmed note is at most 300 and, for Other, not empty, and while a request is
  in flight. The note field is the shared `NoteField` (above, with the Return dialog and the
  fine dispute): the 300 is counted in UTF-16 code units of the trimmed text
  (`String.length`), as the server counts, with the field's own `n/300` counter, the
  "At most 300 characters" `errorText` over the limit and no `maxLength`; the one constant
  is `kMaxNoteLength` (no private copies in the dialogs).
  A blank note is sent as no note (`reportResource` leaves the key out). The write is
  `BookingsController.reportProblem(booking, category, note)` through `UiController.attempt`
  with the toast "Thanks, the library has your report."; on a refusal (409 "You already
  reported this...", 403 "You can only report a seat or room you have booked.", or the
  network) the dialog stays with the student's choices and the server's message, and an
  expired session (401) closes it. After a write that went through, the controller
  waits for any fetch already in flight (it began before the write, so it may answer
  without it), marks every booking on that resource reported itself, and reads the list
  again, so the button cannot be left showing and "Reported" survives a failed re-read; a
  409, 404 or 403 re-reads the list (the picture was out of date) and a network error does
  not. `BookingsController` follows the fines' per-user rules (a generation bumped in
  `build()`, an older generation's refresh and post-write work dropped, never joined) and
  its one-second tick leaves an error state alone, so one student's `canReport` and
  `reportOpen` never show for the next (the screen's `when` shows loading or the error,
  not the last student's list). Its two other writes, `checkIn` and `cancel`, carry the
  same generation check: an answer that lands after a different student has logged in
  writes nothing (Riverpod still holds the last student's list on the next one's loading
  state, which the local update would have put back as data), and a refusal of it no
  longer reloads the next student's list. The outcome of the report arrives as a library notice.
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
- **The backend only adds response fields, so an older app ignores them** (a fine's
  `dispute`, a booking's `canReport` and `reportOpen`; an older app simply never asks
  for `/notices/me`, and email reaches every student whatever app they run). The
  models in turn read each new field as nullable or with a `@JsonKey(defaultValue:
  ...)`, so an older server's payload still parses (the booking's `resourceId`, which
  the backend already sent, is only newly read, with default `''`), and an outgoing
  optional key is left out when unused (no `report` on a return without one, no
  `note` without a note).
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
  The capture has the admin remind the demo student's overdue loan **before** it
  returns that loan (only an open loan can be reminded), to save `notices_me`. The
  fine that return writes is then disputed by the student (`fines_me_disputed`) and
  lowered by the admin **naming the dispute** (read from `GET /admin/fines`
  `dispute.id`), which closes it (`fines_me_adjusted`, a closed dispute), then paid.
  After the booking captures (`bookings_me_library` is the last of them) the student
  reports the desk they checked into, `s3` (`bookings_me_reported`: every booking on it
  reads `reportOpen` and none `canReport`), so no list captured before it holds an open
  report.
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
├── widgets/                   # shared widgets (incl. NoteField: the one multi-line note field)
└── features/                  # auth, catalog, loans, fines, notices, bookings, waitlist, profile,
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
