// test/features/bookings/http_booking_repository_test.dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_client.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/core/auth/token_store.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/fake_token_store.dart';
import '../../support/fixtures.dart';
import '../../support/stub_http_adapter.dart';

void main() {
  (HttpBookingRepository, StubHttpAdapter) repo(FutureOr<StubResponse> Function(RequestOptions) respond) {
    final dio = buildApiClient(TokenStore(InMemoryTokenPersistence()));
    final stub = StubHttpAdapter(respond);
    dio.httpClientAdapter = stub;
    return (HttpBookingRepository(dio), stub);
  }

  const desk3 = Resource(id: 's3', name: 'Silent Zone · Desk 3', type: ResourceType.seat, takenSlotsToday: []);

  test('resources asks for the type and the calendar date of the chosen day', () async {
    final (bookings, stub) = repo((_) => StubResponse(200, fixture('resources_availability_rooms')));
    final rooms = await bookings.resources(ResourceType.room, 2);
    expect(stub.requests.single.path, '/resources/availability');
    expect(stub.requests.single.queryParameters, {'type': 'room', 'date': apiDate(2)});
    expect(rooms.map((r) => r.id), containsAll(['r1', 'r2', 'r3']));
  });

  test('createBooking sends the exact window as UTC, and returns the booking', () async {
    final (bookings, stub) = repo((_) => StubResponse(201, fixture('booking_created')));
    final start = DateTime(2026, 10, 11, 10);
    final created = await bookings.createBooking(resource: desk3, start: start, end: start.add(const Duration(hours: 1)));

    expect(stub.requests.single.path, '/bookings');
    expect(stub.requests.single.data, {
      'resourceId': 's3',
      'startTime': start.toUtc().toIso8601String(),
      'endTime': start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
    });
    expect((stub.requests.single.data as Map)['startTime'], endsWith('Z'));
    expect(created.resourceName, 'Silent Zone · Desk 3');
  });

  test('a taken slot becomes a BookingConflictException carrying the server\'s alternatives', () async {
    final (bookings, _) = repo((_) => StubResponse(409, fixture('booking_conflict_409')));
    final start = DateTime(2026, 10, 10, 14);
    try {
      await bookings.createBooking(resource: desk3, start: start, end: start.add(const Duration(hours: 1)));
      fail('expected a BookingConflictException');
    } on BookingConflictException catch (e) {
      expect(e.alternatives.map((a) => a.resourceId), ['r1', 'r3']);
    }
  });

  test('a 409 without alternatives stays a plain conflict', () async {
    final (bookings, _) = repo((_) => const StubResponse(409, {'error': 'Something else clashed.'}));
    final start = DateTime(2026, 10, 10, 14);
    await expectLater(
      bookings.createBooking(resource: desk3, start: start, end: start.add(const Duration(hours: 1))),
      throwsA(isA<ConflictException>()),
    );
  });

  test('myBookings fetches the user\'s bookings', () async {
    final (bookings, stub) = repo((_) => StubResponse(200, fixture('bookings_me')));
    expect(await bookings.myBookings(), hasLength(2));
    expect(stub.requests.single.path, '/bookings/me');
  });

  test('checkIn posts to the booking and returns it checked in', () async {
    final (bookings, stub) = repo((_) => StubResponse(200, fixture('booking_checked_in')));
    final b = await bookings.checkIn('bk-1');
    expect(stub.requests.single.path, '/bookings/bk-1/checkin');
    expect(b.status, BookingStatus.checkedIn);
  });

  test('cancelBooking posts the cancellation', () async {
    final (bookings, stub) = repo((_) => StubResponse(200, fixture('booking_created')));
    await bookings.cancelBooking('bk-1');
    expect(stub.requests.single.method, 'POST');
    expect(stub.requests.single.path, '/bookings/bk-1/cancel');
  });
}
