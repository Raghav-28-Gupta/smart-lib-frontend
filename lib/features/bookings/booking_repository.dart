// lib/features/bookings/booking_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/resource_booking.dart';

const kTimeSlots = [
  '9:00 AM', '10:00 AM', '11:00 AM', '12:00 PM', '1:00 PM', '2:00 PM',
  '3:00 PM', '4:00 PM', '5:00 PM', '6:00 PM', '7:00 PM',
];

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

class BookingAlternative {
  BookingAlternative({required this.resource, required this.timeSlot});
  final Resource resource;
  final String timeSlot;
}

class BookingConflictException implements Exception {
  BookingConflictException(this.alternatives);
  final List<BookingAlternative> alternatives;
}

abstract class BookingRepository {
  Future<List<Resource>> resources(ResourceType type, int dateIndex);
  Future<ResourceBooking> createBooking({required Resource resource, required int dateIndex, required String timeSlot});
  Future<List<ResourceBooking>> myBookings();
  Future<ResourceBooking> checkIn(String bookingId);
  Future<void> cancelBooking(String bookingId);
}

class MockBookingRepository implements BookingRepository {
  MockBookingRepository() {
    final now = DateTime.now();
    _bookings = [
      ResourceBooking(id: 'bk1', resourceName: 'Reading Room A · Desk 4', type: ResourceType.seat, startTime: now.add(const Duration(hours: 2, minutes: 15)), timeSlot: '3:00 – 5:00 PM', status: BookingStatus.upcomingFar),
      ResourceBooking(id: 'bk2', resourceName: 'Group Room 201', type: ResourceType.room, startTime: now, timeSlot: '12:00 – 1:00 PM', status: BookingStatus.inWindow, graceRemainingSeconds: 587),
    ];
  }

  late List<ResourceBooking> _bookings;
  final Set<String> _extraTaken = {};

  String _key(String resourceId, int dateIndex, String slot) => '$resourceId|$dateIndex|$slot';

  @override
  Future<List<Resource>> resources(ResourceType type, int dateIndex) async {
    if (type == ResourceType.room && dateIndex >= 2) return [];
    final seed = type == ResourceType.seat ? _seatSeed : _roomSeed;
    return seed.map((r) {
      if (dateIndex != 0) return Resource(id: r.id, name: r.name, type: r.type, takenSlotsToday: []);
      final extra = kTimeSlots.where((s) => _extraTaken.contains(_key(r.id, dateIndex, s)));
      return Resource(id: r.id, name: r.name, type: r.type, takenSlotsToday: [...r.takenSlotsToday, ...extra]);
    }).toList();
  }

  @override
  Future<ResourceBooking> createBooking({required Resource resource, required int dateIndex, required String timeSlot}) async {
    if (resource.id == 's1' && dateIndex == 0 && timeSlot == '5:00 PM') {
      _extraTaken.add(_key('s1', 0, '5:00 PM'));
      throw BookingConflictException([
        BookingAlternative(resource: _seatSeed.firstWhere((r) => r.id == 's1'), timeSlot: '6:00 PM'),
        BookingAlternative(resource: _seatSeed.firstWhere((r) => r.id == 's3'), timeSlot: '5:00 PM'),
      ]);
    }
    final booking = ResourceBooking(
      id: 'bk-${DateTime.now().microsecondsSinceEpoch}', resourceName: resource.name, type: resource.type,
      startTime: DateTime.now().add(Duration(days: dateIndex)), timeSlot: timeSlot, status: BookingStatus.upcomingFar,
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

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => MockBookingRepository());
