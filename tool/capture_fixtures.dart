// tool/capture_fixtures.dart
//
// Captures real backend responses into test/fixtures/ so the model
// serialization tests parse bytes that actually came off the wire, rather
// than a hand-typed guess at the DTOs. Re-run it whenever a backend DTO
// changes.
//
// It MUTATES the dev database -- creates bookings and requests, checks in,
// renews a loan, reports a seat, returns an overdue loan, and has an admin decide
// requests, cancel and move a booking, remind an overdue loan, (after the
// student disputes it) adjust and settle a fine, and (after the student disputes
// her seeded no-show) overturn that -- so run it against a freshly seeded
// backend and re-seed afterwards. The admin
// steps need an admin account. Its password is read from
// a file, so it never appears in a command line or a log:
//
//   cd ../backend && npm run seed && npm run dev      # separate terminal
//   SMARTLIB_ADMIN_EMAIL=dev.admin@thapar.edu \
//   SMARTLIB_ADMIN_PASSWORD_FILE=/path/to/password.txt \
//     dart run tool/capture_fixtures.dart             # from frontend/
//   cd ../backend && npm run seed                     # restore demo state
//
// Set SMARTLIB_API_BASE_URL to target something other than localhost:3000.
//
// The login token is redacted before it's written: the demo account has a
// fixed id ('u1'), so a real token would keep working against the dev
// database for its full 7-day lifetime if it were committed.
import 'dart:convert';
import 'dart:io';

final _baseUrl = Platform.environment['SMARTLIB_API_BASE_URL'] ?? 'http://localhost:3000';
final _out = Directory('test/fixtures');
final _client = HttpClient();
const _encoder = JsonEncoder.withIndent('  ');

typedef _Response = ({int status, Object? body});

Future<_Response> _call(String method, String path, {Object? body, String? token}) async {
  final req = await _client.openUrl(method, Uri.parse('$_baseUrl$path'));
  req.headers.contentType = ContentType.json;
  if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  if (body != null) req.write(jsonEncode(body));
  final res = await req.close();
  final text = await res.transform(utf8.decoder).join();
  return (status: res.statusCode, body: text.isEmpty ? null : jsonDecode(text));
}

/// Fails loudly unless [r] came back with [expect].
void _check(String what, _Response r, int expect) {
  if (r.status != expect) throw StateError('$what returned ${r.status}, expected $expect: ${r.body}');
}

String _idOf(_Response r) => (r.body! as Map<String, dynamic>)['id'] as String;

/// Calls the endpoint, fails loudly if the status isn't [expect], and writes
/// the (optionally [redact]ed) body to `test/fixtures/<name>.json`.
Future<Object?> _save(
  String name,
  String method,
  String path, {
  required int expect,
  Object? body,
  String? token,
  Object? Function(Object? body)? redact,
}) async {
  final r = await _call(method, path, body: body, token: token);
  _check('$method $path', r, expect);
  final written = redact == null ? r.body : redact(r.body);
  File('${_out.path}/$name.json').writeAsStringSync('${_encoder.convert(written)}\n');
  stdout.writeln('  $name.json  <- $method $path (${r.status})');
  return r.body;
}

// The backend's zod schema requires an offset, so every outgoing timestamp is
// UTC ('...Z'). Truncated to whole seconds to keep the payloads tidy.
String _iso(DateTime local) =>
    DateTime.fromMillisecondsSinceEpoch(local.millisecondsSinceEpoch ~/ 1000 * 1000).toUtc().toIso8601String();

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Logs in the admin who decides requests during the capture.
Future<String> _adminToken() async {
  final email = Platform.environment['SMARTLIB_ADMIN_EMAIL'];
  final passwordFile = Platform.environment['SMARTLIB_ADMIN_PASSWORD_FILE'];
  if (email == null || passwordFile == null) {
    throw StateError('Set SMARTLIB_ADMIN_EMAIL, and SMARTLIB_ADMIN_PASSWORD_FILE to a file holding that account\'s password.');
  }
  final r = await _call('POST', '/auth/login', body: {'email': email, 'password': File(passwordFile).readAsStringSync().trim()});
  // Only the status: nothing about a failed admin login belongs in a log.
  if (r.status != 200) throw StateError('Admin login returned ${r.status}.');
  return (r.body! as Map<String, dynamic>)['token'] as String;
}

Future<void> main() async {
  _out.createSync(recursive: true);
  stdout.writeln('Capturing from $_baseUrl into ${_out.path}/');

  // --- Auth ---------------------------------------------------------------
  final login = await _save('auth_login', 'POST', '/auth/login',
      expect: 200,
      body: {'email': 'aditi.sharma@thapar.edu', 'password': 'password123'},
      redact: (b) => {...b! as Map<String, dynamic>, 'token': '<redacted-jwt>'});
  final token = (login! as Map<String, dynamic>)['token'] as String;
  await _save('auth_me', 'GET', '/auth/me', expect: 200, token: token);
  final adminToken = await _adminToken();

  // --- Catalog ------------------------------------------------------------
  await _save('books_search', 'GET', '/books/search', expect: 200);
  await _save('book_by_id', 'GET', '/books/b1', expect: 200);

  // --- Loans (read first, so the list reflects the untouched seed) -------
  final loans = await _save('loans_me', 'GET', '/loans/me', expect: 200, token: token);

  // --- Borrow requests ------------------------------------------------------
  // b12 stays pending. b5 is declined by the admin, with a reason.
  await _save('borrow_request_created', 'POST', '/borrow-requests', expect: 201, token: token, body: {'bookId': 'b12'});
  final b5 = await _call('POST', '/borrow-requests', token: token, body: {'bookId': 'b5'});
  _check('requesting b5', b5, 201);
  _check('declining it', await _call('POST', '/admin/requests/borrow/${_idOf(b5)}/decline',
      token: adminToken, body: {'reason': 'This copy is set aside for a course reserve.'}), 200);
  await _save('borrow_requests_me', 'GET', '/borrow-requests/me', expect: 200, token: token);

  // --- Resources ----------------------------------------------------------
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));
  await _save('resources_availability_seats', 'GET', '/resources/availability?type=seat&date=${_ymd(today)}',
      expect: 200);
  await _save('resources_availability_rooms', 'GET', '/resources/availability?type=room&date=${_ymd(today)}',
      expect: 200);

  // --- Bookings -----------------------------------------------------------
  // s3 (Silent Zone Desk 3) has no seeded bookings, so both of these land.
  // One far in the future (upcomingFar); one that started two minutes ago so
  // it reads as inWindow with a live graceRemainingSeconds.
  await _save('booking_created', 'POST', '/bookings',
      expect: 201,
      token: token,
      body: {
        'resourceId': 's3',
        'startTime': _iso(tomorrow.add(const Duration(hours: 10))),
        'endTime': _iso(tomorrow.add(const Duration(hours: 11))),
      });
  final inWindow = await _call('POST', '/bookings', token: token, body: {
    'resourceId': 's3',
    'startTime': _iso(now.subtract(const Duration(minutes: 2))),
    'endTime': _iso(now.add(const Duration(minutes: 58))),
  });
  _check('in-window booking', inWindow, 201);
  await _save('bookings_me', 'GET', '/bookings/me', expect: 200, token: token);

  // --- Room requests --------------------------------------------------------
  // Rooms are requests now. The conflict holder (r1, tomorrow 2 PM) stays
  // pending; asking for the same slot again is the 409, which yields both
  // alternative kinds: r1 at another hour, and another room at 2 PM. Made
  // tomorrow so it works at any time of day.
  final conflictSlot = {
    'resourceId': 'r1',
    'startTime': _iso(tomorrow.add(const Duration(hours: 14))),
    'endTime': _iso(tomorrow.add(const Duration(hours: 15))),
  };
  await _save('booking_room_requested', 'POST', '/bookings', expect: 201, token: token, body: conflictSlot);
  await _save('booking_conflict_409', 'POST', '/bookings', expect: 409, token: token, body: conflictSlot);

  // r1 tomorrow at 10 AM, declined without a reason.
  final toDecline = await _call('POST', '/bookings', token: token, body: {
    'resourceId': 'r1',
    'startTime': _iso(tomorrow.add(const Duration(hours: 10))),
    'endTime': _iso(tomorrow.add(const Duration(hours: 11))),
  });
  _check('requesting r1 at 10 AM', toDecline, 201);
  _check('declining it', await _call('POST', '/admin/requests/room/${_idOf(toDecline)}/decline',
      token: adminToken, body: <String, dynamic>{}), 200);

  // An expired request: its slot started 14 min 55 s ago, so its 15-minute
  // grace period runs out 5 s later. Today the seed holds r1 from 2 to 4 PM
  // and r3 from 10 AM to noon; an hour-long window overlaps at most one.
  final lapseStart = DateTime.now().subtract(const Duration(minutes: 14, seconds: 55));
  final lapseEnd = lapseStart.add(const Duration(hours: 1));
  bool overlaps(int fromHour, int toHour) =>
      lapseStart.isBefore(today.add(Duration(hours: toHour))) && lapseEnd.isAfter(today.add(Duration(hours: fromHour)));
  final lapsing = await _call('POST', '/bookings', token: token, body: {
    'resourceId': overlaps(14, 16) ? 'r3' : 'r1',
    'startTime': _iso(lapseStart),
    'endTime': _iso(lapseEnd),
  });
  _check('requesting a room about to lapse', lapsing, 201);
  await Future<void>.delayed(const Duration(seconds: 7));
  await _save('bookings_me_requests', 'GET', '/bookings/me', expect: 200, token: token);

  final inWindowId = _idOf(inWindow);
  await _save('booking_checked_in', 'POST', '/bookings/$inWindowId/checkin', expect: 200, token: token);

  // --- Loan mutations -----------------------------------------------------
  final b1Loan = (loans! as List).cast<Map<String, dynamic>>().firstWhere((l) => l['bookId'] == 'b1');
  await _save('loan_renewed', 'POST', '/loans/${b1Loan['id']}/renew', expect: 200, token: token);

  // --- Waitlist -----------------------------------------------------------
  // A held copy needs someone else to return one while Aditi is first in
  // line: a seed student requests b9's last copy and the admin approves it,
  // Aditi queues for b9, and the student returns it -- the backend then holds
  // that copy for Aditi. The seed's history may already have lent b9 to some
  // seed students, so the first one who can request it is used. b2 has no
  // copies free and two students already queued, so Aditi joins that one third.
  String? studentToken;
  String? studentRequestId;
  for (var i = 1; i <= 6 && studentRequestId == null; i++) {
    final student = await _call('POST', '/auth/login',
        body: {'email': 'seed.student$i@thapar.edu', 'password': 'password123'});
    _check('seed student $i login', student, 200);
    final t = (student.body! as Map<String, dynamic>)['token'] as String;
    final asked = await _call('POST', '/borrow-requests', token: t, body: {'bookId': 'b9'});
    if (asked.status == 201) {
      studentToken = t;
      studentRequestId = _idOf(asked);
    }
  }
  if (studentToken == null || studentRequestId == null) throw StateError('No seed student could request b9.');
  _check('approving it', await _call('POST', '/admin/requests/borrow/$studentRequestId/approve', token: adminToken), 200);
  await _save('reservation_created', 'POST', '/reservations', expect: 201, token: token, body: {'bookId': 'b9'});
  final studentLoans = await _call('GET', '/loans/me', token: studentToken);
  _check('student loans', studentLoans, 200);
  final studentLoanId =
      (studentLoans.body! as List).cast<Map<String, dynamic>>().firstWhere((l) => l['bookId'] == 'b9')['id'];
  _check('student return', await _call('POST', '/loans/$studentLoanId/return', token: studentToken), 200);
  final queued = await _call('POST', '/reservations', token: token, body: {'bookId': 'b2'});
  _check('joining b2', queued, 201);
  await _save('reservations_me', 'GET', '/reservations/me', expect: 200, token: token);
  await _save('book_held', 'GET', '/books/b9', expect: 200);

  // --- Profile & recommendations (after the check-in, so history carries
  // both an 'ok' and a 'miss') ------------------------------------------
  await _save('profile_reliability', 'GET', '/profile/reliability', expect: 200, token: token);
  await _save('recommendations_me', 'GET', '/recommendations/me', expect: 200, token: token);

  // --- Error shapes -------------------------------------------------------
  await _save('error_400', 'POST', '/bookings', expect: 400, token: token, body: <String, dynamic>{});
  await _save('error_401', 'GET', '/loans/me', expect: 401);
  await _save('error_404', 'GET', '/books/does-not-exist', expect: 404);
  // Aditi already has b1 on loan.
  await _save('error_409', 'POST', '/borrow-requests', expect: 409, token: token, body: {'bookId': 'b1'});
  // What an older app version gets when it tries to borrow.
  await _save('loans_create_409', 'POST', '/loans', expect: 409, token: token, body: {'bookId': 'b1'});

  // --- Library cancel and move ----------------------------------------------
  // Last, so nothing captured above sees these bookings. Seats are booked at
  // once, which is what a librarian can then manage. Two seat bookings made
  // tomorrow, an hour apart: the admin cancels the first with a reason and moves
  // the second to another seat, so the student's list shows a library-cancelled
  // booking and a moved one. The seed's history may already hold a seat at that
  // hour, so each booking takes the first seat that is free; the move takes
  // whichever seat the server offers.
  Future<String> bookFirstFreeSeat(int hour) async {
    for (final seat in ['s1', 's2', 's3', 's4']) {
      final r = await _call('POST', '/bookings', token: token, body: {
        'resourceId': seat,
        'startTime': _iso(tomorrow.add(Duration(hours: hour))),
        'endTime': _iso(tomorrow.add(Duration(hours: hour + 1))),
      });
      if (r.status == 201) return _idOf(r);
      _check('booking $seat at $hour:00 (409 means taken, so the next seat is tried)', r, 409);
    }
    throw StateError('No seat was free at $hour:00 tomorrow.');
  }

  final toCancel = await bookFirstFreeSeat(15);
  _check('library cancel', await _call('POST', '/admin/bookings/$toCancel/cancel',
      token: adminToken, body: {'reason': 'Room closed for maintenance'}), 200);
  final toMove = await bookFirstFreeSeat(16);
  final options = await _call('GET', '/admin/bookings/$toMove/reassign-options', token: adminToken);
  _check('reassign options', options, 200);
  final targets = (options.body! as List).cast<Map<String, dynamic>>();
  if (targets.isEmpty) throw StateError('No seat is free to move the booking to.');
  _check('library reassign', await _call('POST', '/admin/bookings/$toMove/reassign',
      token: adminToken, body: {'resourceId': targets.first['id']}), 200);
  await _save('bookings_me_library', 'GET', '/bookings/me', expect: 200, token: token);

  // --- A problem report -------------------------------------------------------
  // The last of the booking steps, so no list captured above sees an open report.
  // Aditi checked into s3 (Silent Zone Desk 3) a moment ago (booking_checked_in), a
  // booking that started within the week, which entitles her to report that desk. The
  // report is on the resource, so every booking of hers on it then reads `reportOpen`
  // and none offers `canReport`.
  final report = await _call('POST', '/reports', token: token,
      body: {'resourceId': 's3', 'category': 'not_working', 'note': 'The desk lamp does not switch on.'});
  _check('reporting s3', report, 201);
  final reported = await _save('bookings_me_reported', 'GET', '/bookings/me', expect: 200, token: token);
  final onS3 = reported is List ? reported.cast<Map<String, dynamic>>().where((b) => b['resourceId'] == 's3') : const <Map<String, dynamic>>[];
  if (onS3.isEmpty || onS3.any((b) => b['reportOpen'] != true || b['canReport'] != false)) {
    throw StateError('GET /bookings/me does not read reportOpen (and not canReport) on every s3 booking: $reported');
  }

  // --- Fines ----------------------------------------------------------------
  // Last, so nothing captured above sees the loan gone. Aditi's overdue loan (b4,
  // due 3 days ago) is first reminded by the admin, which writes the library
  // notice captured at the end: only an open loan can be reminded, and the return
  // below closes it. Returning it then writes a 30-rupee overdue fine (the seed
  // leaves her with none). The student disputes it (an open dispute), then the
  // admin lowers it to 20 with a reason, naming the dispute they read in the fines
  // list, which closes it, and records it paid: the states a student sees.
  final b4Loan = (loans as List).cast<Map<String, dynamic>>().firstWhere((l) => l['bookId'] == 'b4');
  _check('reminding b4', await _call('POST', '/admin/loans/${b4Loan['id']}/remind', token: adminToken), 200);
  _check('returning b4', await _call('POST', '/loans/${b4Loan['id']}/return', token: token), 200);
  Map<String, dynamic> overdueFine(Object? body) => ((body! as Map<String, dynamic>)['fines'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((f) => f['reason'] == 'overdue');
  final fineId = overdueFine(await _save('fines_me', 'GET', '/fines/me', expect: 200, token: token))['id'] as String;
  _check('disputing the fine', await _call('POST', '/fines/$fineId/dispute',
      token: token, body: {'reason': 'The desk scanned my return a day late.'}), 201);
  final disputed = overdueFine(await _save('fines_me_disputed', 'GET', '/fines/me', expect: 200, token: token));
  final openDispute = disputed['dispute'];
  if (openDispute is! Map<String, dynamic> || openDispute['status'] != 'open') {
    throw StateError('GET /fines/me holds no open dispute on the fine: $openDispute');
  }
  // The dispute's id is the librarian's to read: it comes with the fine in the
  // admin's list, and the adjustment must name it to close it.
  final adminFines = await _call('GET', '/admin/fines?status=disputed&pageSize=100', token: adminToken);
  _check('listing the disputed fines', adminFines, 200);
  final adminRow = ((adminFines.body! as Map<String, dynamic>)['fines'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((f) => f['id'] == fineId, orElse: () => throw StateError('The admin list has no disputed fine $fineId.'));
  final disputeId = (adminRow['dispute']! as Map<String, dynamic>)['id'] as String;
  _check('adjusting the fine', await _call('POST', '/admin/fines/$fineId/adjust',
      token: adminToken, body: {'amount': 20, 'reason': 'Returned during exam week', 'disputeId': disputeId}), 200);
  final adjusted = overdueFine(await _save('fines_me_adjusted', 'GET', '/fines/me', expect: 200, token: token));
  final closedDispute = adjusted['dispute'];
  if (closedDispute is! Map<String, dynamic> || closedDispute['status'] != 'adjusted') {
    throw StateError('GET /fines/me holds no adjusted dispute on the fine: $closedDispute');
  }
  _check('marking it paid', await _call('POST', '/admin/fines/$fineId/paid',
      token: adminToken, body: {'amount': 20}), 200);
  await _save('fines_me_paid', 'GET', '/fines/me', expect: 200, token: token);

  // --- Library notices ------------------------------------------------------
  // The reminder the admin sent above. Its email status is 'skipped' only because the
  // demo student's address is a placeholder, which the mailer never sends to; a dev
  // backend can have email configured (it was found enabled), so run this capture only
  // as a placeholder student, never as one with a real address. The student's list
  // carries no email status.
  final notices = await _save('notices_me', 'GET', '/notices/me', expect: 200, token: token);
  if (notices is! List || !notices.any((n) => (n as Map<String, dynamic>)['kind'] == 'overdue_reminder')) {
    throw StateError('GET /notices/me holds no overdue_reminder notice: $notices');
  }

  // --- A no-show and its dispute ---------------------------------------------
  // Last: the seed gives the demo student one recent no-show she can still dispute (a
  // room booking of hers, Group Room 201, the sweep released), so it is in every GET /bookings/me
  // captured above too, as a `released` booking with `noShow`. Here she disputes it
  // (`bookings_me_no_show` is the list before, `bookings_me_no_show_disputed` after: an
  // open dispute), then the admin overturns it, by the dispute id the Needs attention
  // queue lists for that booking, which writes the `no_show_outcome` notice captured as
  // `notices_me_no_show_outcome` (it holds the earlier notices too). The `no_show` and
  // `booking_reminder` notice kinds are written by the sweep, which does not run here, so
  // tests build those two payloads themselves (notice_json_test.dart says so).
  Map<String, dynamic>? bookingById(Object? body, String id) {
    if (body is! List) return null;
    for (final b in body.cast<Map<String, dynamic>>()) {
      if (b['id'] == id) return b;
    }
    return null;
  }

  final beforeDispute = await _save('bookings_me_no_show', 'GET', '/bookings/me', expect: 200, token: token);
  final missedBooking = (beforeDispute is List ? beforeDispute.cast<Map<String, dynamic>>() : const <Map<String, dynamic>>[])
      .where((b) => (b['noShow'] as Map<String, dynamic>?)?['canDispute'] == true)
      .toList();
  if (missedBooking.length != 1) {
    throw StateError('Expected exactly one booking with noShow.canDispute true (the seed gives the demo student one; '
        're-seed, its 7 days may have passed), found ${missedBooking.length}: $beforeDispute');
  }
  final missedId = missedBooking.single['id'] as String;
  final disputeAnswer = await _call('POST', '/bookings/$missedId/dispute',
      token: token, body: {'reason': 'The desk scanner was down when I arrived.'});
  _check('disputing the no-show', disputeAnswer, 201);
  if ((disputeAnswer.body! as Map<String, dynamic>)['status'] != 'open') {
    throw StateError('POST /bookings/$missedId/dispute did not answer an open dispute: ${disputeAnswer.body}');
  }
  final afterDispute = await _save('bookings_me_no_show_disputed', 'GET', '/bookings/me', expect: 200, token: token);
  final noShowNow = bookingById(afterDispute, missedId)?['noShow'];
  final openNoShow = noShowNow is Map<String, dynamic> ? noShowNow['dispute'] : null;
  if (noShowNow is! Map<String, dynamic> ||
      noShowNow['canDispute'] != false ||
      openNoShow is! Map<String, dynamic> ||
      openNoShow['status'] != 'open') {
    throw StateError('GET /bookings/me holds no open no-show dispute on $missedId: $noShowNow');
  }
  final attention = await _call('GET', '/admin/attention', token: adminToken);
  _check('listing the Needs attention queue', attention, 200);
  final noShowItems = ((attention.body! as Map<String, dynamic>)['items'] as List)
      .cast<Map<String, dynamic>>()
      .where((i) => i['kind'] == 'no_show_dispute' && (i['noShow'] as Map<String, dynamic>)['bookingId'] == missedId)
      .toList();
  if (noShowItems.length != 1) {
    throw StateError('The queue holds ${noShowItems.length} no_show_dispute items for booking $missedId, expected 1.');
  }
  _check('overturning the no-show', await _call('POST', '/admin/no-show-disputes/${noShowItems.single['id']}/overturn',
      token: adminToken, body: {'reason': 'The desk scanner was down that morning'}), 200);
  final outcomeNotices = await _save('notices_me_no_show_outcome', 'GET', '/notices/me', expect: 200, token: token);
  if (outcomeNotices is! List || !outcomeNotices.any((n) => (n as Map<String, dynamic>)['kind'] == 'no_show_outcome')) {
    throw StateError('GET /notices/me holds no no_show_outcome notice: $outcomeNotices');
  }

  _client.close();
  stdout.writeln('Done. Now re-seed the backend: cd ../backend && npm run seed');
}
