// test/models/reservation_json_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/models/reservation.dart';
import '../support/fixtures.dart';

void main() {
  List<Reservation> mine() => (fixture('reservations_me') as List)
      .map((j) => Reservation.fromJson(j as Map<String, dynamic>))
      .toList();

  test('parses a held copy: no place in line, and a deadline in local time', () {
    // The backend calls a live claim 'fulfilled'; to the student it means a
    // copy is being held for them.
    final held = mine().singleWhere((r) => r.bookId == 'b9');
    expect(held.status, ReservationStatus.held);
    expect(held.queuePosition, isNull);
    expect(held.claimExpiresAt, isNotNull);
    expect(held.claimExpiresAt!.isUtc, isFalse);
  });

  test('parses a waiting entry with its place in line', () {
    final waiting = mine().singleWhere((r) => r.bookId == 'b2');
    expect(waiting.status, ReservationStatus.waiting);
    expect(waiting.queuePosition, 3);
    expect(waiting.claimExpiresAt, isNull);
  });

  test('parses POST /reservations', () {
    final r = Reservation.fromJson(fixture('reservation_created') as Map<String, dynamic>);
    expect(r.bookId, 'b9');
    expect(r.status, ReservationStatus.waiting);
    expect(r.queuePosition, 1);
  });
}
