// test/features/waitlist/http_waitlist_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/waitlist/waitlist_repository.dart';
import 'package:smartlib_frontend/models/reservation.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpWaitlistRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpWaitlistRepository(dio), stub);
  }

  test("mine fetches the student's waitlist entries", () async {
    final (waitlist, stub) = repo((_) => StubResponse(200, fixture('reservations_me')));
    final result = await waitlist.mine();
    expect(stub.requests.single.path, '/reservations/me');
    expect(result.map((r) => r.status), [ReservationStatus.held, ReservationStatus.waiting]);
  });

  test('join creates a reservation and returns it as the server sent it', () async {
    final (waitlist, stub) = repo((_) => StubResponse(201, fixture('reservation_created')));
    final r = await waitlist.join('b9');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/reservations');
    expect(stub.requests.single.data, {'bookId': 'b9'});
    expect(r.queuePosition, 1);
  });

  test("join surfaces the server's reason when it refuses", () async {
    final (waitlist, _) = repo((_) => const StubResponse(409, {'error': "You're already on the waitlist for this title."}));
    await expectLater(
      waitlist.join('b2'),
      throwsA(isA<ConflictException>().having((e) => e.message, 'message', "You're already on the waitlist for this title.")),
    );
  });

  test('leave deletes the reservation', () async {
    final (waitlist, stub) = repo((_) => const StubResponse(200, {'id': 'res-1', 'status': 'cancelled'}));
    await waitlist.leave('res-1');
    expect(stub.requests.single.method, 'DELETE');
    expect(stub.requests.single.path, '/reservations/res-1');
  });
}
