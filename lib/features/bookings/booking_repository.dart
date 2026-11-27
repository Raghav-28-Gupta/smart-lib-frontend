// lib/features/bookings/booking_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/time_format.dart';
import '../../models/booking_alternative.dart';
import '../../models/resource_booking.dart';
import 'demo_seat_layout.dart';
import 'time_slots.dart';

const _roomSeed = [
  Resource(id: 'r1', name: 'Group Room 201 · 4 seats', type: ResourceType.room, takenSlotsToday: ['2:00 PM', '3:00 PM']),
  Resource(id: 'r2', name: 'Group Room 202 · 6 seats', type: ResourceType.room, takenSlotsToday: kTimeSlots),
  Resource(id: 'r3', name: 'Discussion Pod 1 · 2 seats', type: ResourceType.room, takenSlotsToday: ['10:00 AM', '11:00 AM']),
];

/// The slot was taken; [alternatives] are what the server says is still free.
/// May be empty when nothing similar is open.
class BookingConflictException implements Exception {
  BookingConflictException(this.alternatives);
  final List<BookingAlternative> alternatives;
}

abstract class BookingRepository {
  Future<List<Resource>> resources(ResourceType type, int dateIndex);

  /// Books [resource] for exactly [start]–[end]. Takes the window rather than
  /// a slot label so a conflict alternative can be booked at the server's own
  /// instants, unchanged.
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end});
  Future<List<ResourceBooking>> myBookings();
  Future<ResourceBooking> checkIn(String bookingId);
  Future<void> cancelBooking(String bookingId);

  /// Tells the library what is wrong with a seat or room the student booked
  /// (`POST /reports`). [note] is already trimmed and at most 300 characters (the
  /// server counts UTF-16 code units), or null for none; `other` needs one. Refused
  /// with a 403 for a resource the student has no qualifying booking on, and a 409
  /// when they already have an open report on it.
  Future<void> reportResource(String resourceId, ResourceReportCategory category, String? note);

  /// Disputes a booking the library recorded as a no-show (`POST /bookings/:id/dispute`),
  /// once, with the [reason] the student gives (1 to 300 characters, trimmed; the server
  /// counts UTF-16 code units). The answer carries nothing the app needs: the dispute
  /// comes back with the bookings (`ResourceBooking.noShow`). Refused with a 409 and the
  /// server's own message when the booking is not a recorded no-show, was disputed
  /// before, or its 7 days have passed; with a 404 for a booking that is not the
  /// student's.
  Future<void> disputeNoShow(String bookingId, String reason);
}

class HttpBookingRepository implements BookingRepository {
  HttpBookingRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    // Seats ask for the offline ones too, so the map can show a desk that is out of
    // service. A server that predates the parameter ignores it and sends the
    // available seats, as before.
    final res = await guardApi(() => _dio.get<List<dynamic>>('/resources/availability', queryParameters: {
          'type': type.name,
          'date': apiDate(dateIndex),
          if (type == ResourceType.seat) 'includeOffline': 'true',
        }));
    return res.data!.map((j) => Resource.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async {
    try {
      // UTC with a Z: the backend's zod schema rejects a timestamp without an
      // offset, which is what a local DateTime serializes to.
      final res = await guardApi(() => _dio.post<Map<String, dynamic>>('/bookings', data: {
            'resourceId': resource.id,
            'startTime': start.toUtc().toIso8601String(),
            'endTime': end.toUtc().toIso8601String(),
          }));
      return ResourceBooking.fromJson(res.data!);
    } on ConflictException catch (e) {
      // The database's no-overlap constraint rejected it; the 409 carries
      // what's still free.
      final alternatives = (e.details as Map?)?['alternatives'];
      if (alternatives is! List) rethrow;
      throw BookingConflictException(
          alternatives.map((j) => BookingAlternative.fromJson(j as Map<String, dynamic>)).toList());
    }
  }

  @override
  Future<List<ResourceBooking>> myBookings() async {
    final res = await guardApi(() => _dio.get<List<dynamic>>('/bookings/me'));
    return res.data!.map((j) => ResourceBooking.fromJson(j as Map<String, dynamic>)).toList();
  }

  @override
  Future<ResourceBooking> checkIn(String bookingId) async {
    final res = await guardApi(() => _dio.post<Map<String, dynamic>>('/bookings/${Uri.encodeComponent(bookingId)}/checkin'));
    return ResourceBooking.fromJson(res.data!);
  }

  @override
  Future<void> cancelBooking(String bookingId) async {
    await guardApi(() => _dio.post<Object?>('/bookings/${Uri.encodeComponent(bookingId)}/cancel'));
  }

  @override
  Future<void> reportResource(String resourceId, ResourceReportCategory category, String? note) async {
    // No `note` key without a note: the server reads a missing key as none.
    await guardApi(() => _dio.post<Object?>('/reports', data: {
          'resourceId': resourceId,
          'category': category.wireName,
          if (note != null) 'note': note,
        }));
  }

  @override
  Future<void> disputeNoShow(String bookingId, String reason) async {
    await guardApi(() => _dio.post<Object?>('/bookings/${Uri.encodeComponent(bookingId)}/dispute', data: {'reason': reason}));
  }
}

/// Test double. Serves the two seeded bookings, or exactly [bookings] when a test gives
/// its own (as [MockFineRepository] takes its fines). A no-show dispute is refused as
/// the server refuses it and otherwise recorded in [noShowDisputes] and on the booking
/// as an open dispute. Its seats are the demo layout's 128 desks ([demoSeats]), the
/// same as the backend seed.
class MockBookingRepository implements BookingRepository {
  MockBookingRepository({List<ResourceBooking>? bookings}) {
    if (bookings != null) {
      _bookings = List.of(bookings);
      return;
    }
    final now = DateTime.now();
    final farStart = now.add(const Duration(hours: 2, minutes: 15));
    // Started 313s ago, so its 587s of grace (900 - 313) is consistent with
    // its start time -- the bookings controller recomputes grace from it.
    final inWindowStart = now.subtract(const Duration(seconds: 313));
    _bookings = [
      // Both start within the report window (the next 24 hours, the last 7 days), so
      // the server would mark each `canReport`.
      ResourceBooking(id: 'bk1', resourceId: 's1', resourceName: 'Reading Room A · Desk 4', type: ResourceType.seat, startTime: farStart, endTime: farStart.add(const Duration(hours: 2)), status: BookingStatus.upcomingFar, canReport: true),
      ResourceBooking(id: 'bk2', resourceId: 'r1', resourceName: 'Group Room 201', type: ResourceType.room, startTime: inWindowStart, endTime: inWindowStart.add(const Duration(hours: 1)), status: BookingStatus.inWindow, graceRemainingSeconds: 587, canReport: true),
    ];
  }

  late List<ResourceBooking> _bookings;
  final Set<String> _extraTaken = {};
  final List<Resource> _seatSeed = demoSeats();

  /// Every report that was accepted, in order.
  final reports = <({String resourceId, ResourceReportCategory category, String? note})>[];

  /// What the student sent, in order, for the no-show disputes the "server" accepted.
  final noShowDisputes = <({String bookingId, String reason})>[];

  /// When set, [disputeNoShow] throws it (a refusal, a network failure) and records
  /// nothing; a test clears it to let the next dispute through.
  Object? disputeError;

  String _key(String resourceId, int dateIndex, String slot) => '$resourceId|$dateIndex|$slot';

  // Shapes a scripted alternative the way the real 409 does: a resource plus
  // an exact window, rather than a label.
  BookingAlternative _alternative(String resourceId, int dateIndex, String label) {
    final r = _seatSeed.firstWhere((s) => s.id == resourceId);
    final window = slotWindow(dateIndex, label);
    return BookingAlternative(resourceId: r.id, resourceName: r.name, resourceType: r.type, startTime: window.start, endTime: window.end);
  }

  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    if (type == ResourceType.room && dateIndex >= 2) return [];
    final seed = type == ResourceType.seat ? _seatSeed : _roomSeed;
    return seed.map((r) {
      final seeded = dateIndex == 0 ? r.takenSlotsToday : const <String>[];
      final extra = kTimeSlots.where((s) => _extraTaken.contains(_key(r.id, dateIndex, s)));
      return Resource(
          id: r.id,
          name: r.name,
          type: r.type,
          takenSlotsToday: [...seeded, ...extra],
          location: r.location,
          row: r.row,
          column: r.column,
          zoneFront: r.zoneFront,
          status: r.status);
    }).toList();
  }

  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async {
    // Scripted conflict: Desk 12, tomorrow at 5:00 PM. Tomorrow so it is never
    // a past, greyed-out slot, whatever time of day the tests run.
    if (resource.id == 's1' && start == slotWindow(1, '5:00 PM').start) {
      _extraTaken.add(_key('s1', 1, clockLabel(start)));
      throw BookingConflictException([
        _alternative('s1', 1, '6:00 PM'),
        _alternative('s3', 1, '5:00 PM'),
      ]);
    }
    // Rooms wait for a librarian, as on the server; seats are booked at once.
    final isRoom = resource.type == ResourceType.room;
    final booking = ResourceBooking(
      id: 'bk-${DateTime.now().microsecondsSinceEpoch}', resourceId: resource.id, resourceName: resource.name, type: resource.type,
      startTime: start, endTime: end,
      status: isRoom ? BookingStatus.requested : BookingStatus.upcomingFar,
      expiresAt: isRoom ? start.add(kCheckInGracePeriod) : null,
    );
    _bookings.insert(0, booking);
    return booking;
  }

  @override
  Future<List<ResourceBooking>> myBookings() async => List.of(_bookings);

  @override
  Future<ResourceBooking> checkIn(String bookingId) async {
    final index = _bookings.indexWhere((b) => b.id == bookingId);
    final updated = _bookings[index].copyWith(status: BookingStatus.checkedIn);
    _bookings[index] = updated;
    return updated;
  }

  @override
  Future<void> cancelBooking(String bookingId) async {
    _bookings.removeWhere((b) => b.id == bookingId);
  }

  // Refuses as the server does: a second report is a 409, and a resource with no
  // booking that qualifies (`canReport`) is a 403. Otherwise every booking on that
  // resource reads reported.
  @override
  Future<void> reportResource(String resourceId, ResourceReportCategory category, String? note) async {
    final onIt = _bookings.where((b) => b.resourceId == resourceId);
    if (onIt.any((b) => b.reportOpen)) throw const ConflictException('You already reported this. The library is looking into it.');
    if (!onIt.any((b) => b.canReport)) throw const ApiException(403, 'You can only report a seat or room you have booked.');
    reports.add((resourceId: resourceId, category: category, note: note));
    _bookings = [for (final b in _bookings) b.resourceId == resourceId ? b.copyWith(reportOpen: true, canReport: false) : b];
  }

  // Refuses much as the server does: a booking that is not the student's is a 404, a no-show
  // disputed before (whatever became of the dispute) a 409, and so is a booking that is
  // no recorded no-show or whose 7 days have passed. Otherwise the booking reads as an
  // open dispute, which can no longer be disputed. The order of the checks is not the
  // server's, so a few answers differ: for a dispute that was overturned (the booking is
  // back to a plain release) the server says "not a recorded no-show", and for a
  // disputed one past the 7 days it gives the window message, where this says "already
  // disputed" for both. No test depends on it (the refusal tests inject `disputeError`).
  @override
  Future<void> disputeNoShow(String bookingId, String reason) async {
    final error = disputeError;
    if (error != null) throw error;
    final at = _bookings.indexWhere((b) => b.id == bookingId);
    if (at < 0) throw const ApiException(404, 'Booking not found');
    final noShow = _bookings[at].noShow;
    if (noShow?.dispute != null) throw const ConflictException("You've already disputed this no-show.");
    if (noShow == null) throw const ConflictException('This booking is not a recorded no-show.');
    if (!noShow.canDispute) throw const ConflictException('The 7 days to dispute this no-show have passed.');
    noShowDisputes.add((bookingId: bookingId, reason: reason));
    _bookings[at] = _bookings[at].copyWith(
      noShow: const NoShowInfo(canDispute: false, dispute: NoShowDisputeInfo(status: NoShowDisputeStatus.open)),
    );
  }
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => HttpBookingRepository(ref.watch(apiClientProvider)));
