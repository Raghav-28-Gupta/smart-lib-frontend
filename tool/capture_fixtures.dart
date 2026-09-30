// tool/capture_fixtures.dart
//
// Captures real backend responses into test/fixtures/ so the model
// serialization tests parse bytes that actually came off the wire, rather
// than a hand-typed guess at the DTOs. Re-run it whenever a backend DTO
// changes.
//
// It MUTATES the dev database -- creates bookings, checks in, renews a loan,
// borrows a book -- so run it against a freshly seeded backend and re-seed
// afterwards:
//
//   cd ../backend && npm run seed && npm run dev      # separate terminal
//   dart run tool/capture_fixtures.dart               # from frontend/
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
  if (r.status != expect) {
    throw StateError('$method $path returned ${r.status}, expected $expect: ${r.body}');
  }
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

  // --- Catalog ------------------------------------------------------------
  await _save('books_search', 'GET', '/books/search', expect: 200);
  await _save('book_by_id', 'GET', '/books/b1', expect: 200);

  // --- Loans (read first, so the list reflects the untouched seed) -------
  final loans = await _save('loans_me', 'GET', '/loans/me', expect: 200, token: token);

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
  if (inWindow.status != 201) throw StateError('in-window booking failed: ${inWindow.body}');
  await _save('bookings_me', 'GET', '/bookings/me', expect: 200, token: token);

  // r1 (Group Room 201) is seeded as taken at 2 PM and 3 PM today, so this
  // conflicts -- and yields both alternative kinds: r1 at another hour, and
  // another room at 2 PM.
  await _save('booking_conflict_409', 'POST', '/bookings',
      expect: 409,
      token: token,
      body: {
        'resourceId': 'r1',
        'startTime': _iso(today.add(const Duration(hours: 14))),
        'endTime': _iso(today.add(const Duration(hours: 15))),
      });

  final inWindowId = (inWindow.body! as Map<String, dynamic>)['id'];
  await _save('booking_checked_in', 'POST', '/bookings/$inWindowId/checkin', expect: 200, token: token);

  // --- Loan mutations -----------------------------------------------------
  final b1Loan = (loans! as List).cast<Map<String, dynamic>>().firstWhere((l) => l['bookId'] == 'b1');
  await _save('loan_renewed', 'POST', '/loans/${b1Loan['id']}/renew', expect: 200, token: token);
  await _save('loan_created', 'POST', '/loans', expect: 201, token: token, body: {'bookId': 'b12'});

  // --- Profile & recommendations (after the check-in, so history carries
  // both an 'ok' and a 'miss') ------------------------------------------
  await _save('profile_reliability', 'GET', '/profile/reliability', expect: 200, token: token);
  await _save('recommendations_me', 'GET', '/recommendations/me', expect: 200, token: token);

  // --- Error shapes -------------------------------------------------------
  await _save('error_400', 'POST', '/bookings', expect: 400, token: token, body: <String, dynamic>{});
  await _save('error_401', 'GET', '/loans/me', expect: 401);
  await _save('error_404', 'GET', '/books/does-not-exist', expect: 404);
  await _save('error_409', 'POST', '/loans', expect: 409, token: token, body: {'bookId': 'b1'});

  _client.close();
  stdout.writeln('Done. Now re-seed the backend: cd ../backend && npm run seed');
}
