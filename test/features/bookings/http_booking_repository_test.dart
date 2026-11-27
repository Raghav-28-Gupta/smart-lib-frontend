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

  test('the seats request sends includeOffline=true', () async {
    final (bookings, stub) = repo((_) => StubResponse(200, fixture('resources_availability_seats')));
    final seats = await bookings.resources(ResourceType.seat, 1);
    expect(stub.requests.single.path, '/resources/availability');
    expect(stub.requests.single.queryParameters, {'type': 'seat', 'date': apiDate(1), 'includeOffline': 'true'});
    expect(seats, isNotEmpty);
  });

  test('the rooms request has no includeOffline', () async {
    final (bookings, stub) = repo((_) => StubResponse(200, fixture('resources_availability_rooms')));
    await bookings.resources(ResourceType.room, 0);
    expect(stub.requests.single.queryParameters.containsKey('includeOffline'), false);
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
    // The two the capture made, and the demo student's seeded no-show.
    expect(await bookings.myBookings(), hasLength(3));
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

  group('POST /reports', () {
    test('POST /reports sends the resource, category and note', () async {
      final (bookings, stub) = repo((_) => const StubResponse(201, {'id': 'rep-1'}));
      await bookings.reportResource('s3', ResourceReportCategory.notWorking, 'The desk lamp does not switch on.');

      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/reports');
      expect(request.data, {
        'resourceId': 's3',
        'category': 'not_working',
        'note': 'The desk lamp does not switch on.',
      });
    });

    test('a report with no note sends no note key, not null and not an empty string', () async {
      final (bookings, stub) = repo((_) => const StubResponse(201, {'id': 'rep-1'}));
      await bookings.reportResource('r1', ResourceReportCategory.dirty, null);

      expect(stub.requests.single.data, {'resourceId': 'r1', 'category': 'dirty'});
      expect((stub.requests.single.data as Map).containsKey('note'), false);
    });

    test('each category goes out in the server\'s spelling', () async {
      final sent = <Object?>[];
      final (bookings, _) = repo((options) {
        sent.add((options.data as Map)['category']);
        return const StubResponse(201, {'id': 'rep-1'});
      });
      for (final category in ResourceReportCategory.values) {
        await bookings.reportResource('s3', category, category == ResourceReportCategory.other ? 'Something else.' : null);
      }
      expect(sent, ['not_working', 'dirty', 'other']);
    });

    test('a resource id is sent as given, whatever it holds', () async {
      final (bookings, stub) = repo((_) => const StubResponse(201, {'id': 'rep-1'}));
      await bookings.reportResource('a/b c', ResourceReportCategory.dirty, null);
      expect((stub.requests.single.data as Map)['resourceId'], 'a/b c');
      expect(stub.requests.single.path, '/reports');
    });

    test('a second report answers 409 with the server\'s message', () async {
      final (bookings, _) = repo((_) => const StubResponse(409, {'error': 'You already reported this. The library is looking into it.'}));
      await expectLater(
        bookings.reportResource('s3', ResourceReportCategory.dirty, null),
        throwsA(isA<ConflictException>().having((e) => e.message, 'message', 'You already reported this. The library is looking into it.')),
      );
    });

    test('a seat the student never booked answers 403 with the server\'s message', () async {
      final (bookings, _) = repo((_) => const StubResponse(403, {'error': 'You can only report a seat or room you have booked.'}));
      await expectLater(
        bookings.reportResource('s3', ResourceReportCategory.dirty, null),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'You can only report a seat or room you have booked.')),
      );
    });

    test('a network failure is an ApiException with status 0', () async {
      final (bookings, _) = repo((options) => throw DioException.connectionError(requestOptions: options, reason: 'offline'));
      await expectLater(
        bookings.reportResource('s3', ResourceReportCategory.dirty, null),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', true)),
      );
    });

    test('GET /bookings/me carries canReport and reportOpen, as captured', () async {
      final (bookings, _) = repo((_) => StubResponse(200, fixture('bookings_me_reported')));
      final listed = await bookings.myBookings();
      expect(listed.where((b) => b.resourceId == 's3' && b.reportOpen && !b.canReport), isNotEmpty);
    });
  });

  group('POST /bookings/:id/dispute', () {
    test('disputeNoShow posts {reason} to the booking', () async {
      final (bookings, stub) = repo((_) => const StubResponse(201, {'id': 'nsd-1', 'status': 'open'}));
      await bookings.disputeNoShow('bk-1', 'The desk scanner was down when I arrived.');

      final request = stub.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/bookings/bk-1/dispute');
      expect(request.data, {'reason': 'The desk scanner was down when I arrived.'});
    });

    test('the booking id is encoded into the path, the reason is sent as given', () async {
      final (bookings, stub) = repo((_) => const StubResponse(201, {'id': 'nsd-1', 'status': 'open'}));
      await bookings.disputeNoShow('a/b c', 'I was there.');
      expect(stub.requests.single.path, '/bookings/a%2Fb%20c/dispute');
      expect(stub.requests.single.data, {'reason': 'I was there.'});
    });

    test("a 409 is a ConflictException carrying the server's own message", () async {
      for (final message in [
        'This booking is not a recorded no-show.',
        "You've already disputed this no-show.",
        'The 7 days to dispute this no-show have passed.',
      ]) {
        final (bookings, _) = repo((_) => StubResponse(409, {'error': message}));
        await expectLater(
          bookings.disputeNoShow('bk-1', 'I was there.'),
          throwsA(isA<ConflictException>().having((e) => e.message, 'message', message)),
          reason: message,
        );
      }
    });

    test("a 404 and a 400 carry the server's message too", () async {
      final (gone, _) = repo((_) => const StubResponse(404, {'error': 'Booking not found'}));
      await expectLater(
        gone.disputeNoShow('someone-elses', 'I was there.'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404).having((e) => e.message, 'message', 'Booking not found')),
      );

      // The captured 400 (a bad body): the app shows the server's own text.
      final (bad, _) = repo((_) => StubResponse(400, fixture('error_400')));
      await expectLater(
        bad.disputeNoShow('bk-1', 'x' * 301),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', (fixture('error_400') as Map)['error'])),
      );
    });

    test('a network failure is an ApiException with status 0', () async {
      final (bookings, _) = repo((options) => throw DioException.connectionError(requestOptions: options, reason: 'offline'));
      await expectLater(
        bookings.disputeNoShow('bk-1', 'I was there.'),
        throwsA(isA<ApiException>().having((e) => e.isNetworkError, 'isNetworkError', true)),
      );
    });

    test('GET /bookings/me carries noShow, as captured', () async {
      final (bookings, _) = repo((_) => StubResponse(200, fixture('bookings_me_no_show')));
      final listed = await bookings.myBookings();
      final missed = listed.singleWhere((b) => b.noShow?.canDispute == true);
      expect(missed.status, BookingStatus.released);
      expect(missed.noShow!.dispute, isNull);
    });
  });
}
