// lib/features/bookings/booking_repository.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/time_format.dart';
import '../../models/booking_alternative.dart';
import '../../models/resource_booking.dart';
import 'time_slots.dart';

const _seatSeed = [
  Resource(id: 's1', name: 'Reading Room A · Desk 12', type: ResourceType.seat, takenSlotsToday: ['11:00 AM', '12:00 PM']),
  Resource(id: 's2', name: 'Reading Room A · Desk 14', type: ResourceType.seat, takenSlotsToday: ['9:00 AM', '10:00 AM', '3:00 PM', '4:00 PM']),
  Resource(id: 's3', name: 'Silent Zone · Desk 3', type: ResourceType.seat, takenSlotsToday: []),
  Resource(id: 's4', name: 'Silent Zone · Desk 7', type: ResourceType.seat, takenSlotsToday: ['1:00 PM', '2:00 PM', '6:00 PM']),
];

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
}

class HttpBookingRepository implements BookingRepository {
  HttpBookingRepository(this._dio);

  final Dio _dio;

  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    final res = await guardApi(() => _dio.get<List<dynamic>>('/resources/availability',
        queryParameters: {'type': type.name, 'date': apiDate(dateIndex)}));
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
}

class MockBookingRepository implements BookingRepository {
  MockBookingRepository() {
    final now = DateTime.now();
    final farStart = now.add(const Duration(hours: 2, minutes: 15));
    // Started 313s ago, so its 587s of grace (900 - 313) is consistent with
    // its start time -- the bookings controller recomputes grace from it.
    final inWindowStart = now.subtract(const Duration(seconds: 313));
    _bookings = [
      ResourceBooking(id: 'bk1', resourceName: 'Reading Room A · Desk 4', type: ResourceType.seat, startTime: farStart, endTime: farStart.add(const Duration(hours: 2)), status: BookingStatus.upcomingFar),
      ResourceBooking(id: 'bk2', resourceName: 'Group Room 201', type: ResourceType.room, startTime: inWindowStart, endTime: inWindowStart.add(const Duration(hours: 1)), status: BookingStatus.inWindow, graceRemainingSeconds: 587),
    ];
  }

  late List<ResourceBooking> _bookings;
  final Set<String> _extraTaken = {};

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
      return Resource(id: r.id, name: r.name, type: r.type, takenSlotsToday: [...seeded, ...extra]);
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
      id: 'bk-${DateTime.now().microsecondsSinceEpoch}', resourceName: resource.name, type: resource.type,
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
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => HttpBookingRepository(ref.watch(apiClientProvider)));
