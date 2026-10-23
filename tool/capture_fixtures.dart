// tool/capture_fixtures.dart
//
// Captures real backend responses into test/fixtures/ so the model
// serialization tests parse bytes that actually came off the wire, rather
// than a hand-typed guess at the DTOs. Re-run it whenever a backend DTO
// changes.
//
// It MUTATES the dev database -- creates bookings and requests, checks in,
// renews a loan, and has an admin decide requests -- so run it against a
// freshly seeded backend and re-seed afterwards. The decisions need an admin
// account. Its password is read from a file, so it never appears in a command
// line or a log:
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

  _client.close();
  stdout.writeln('Done. Now re-seed the backend: cd ../backend && npm run seed');
}
