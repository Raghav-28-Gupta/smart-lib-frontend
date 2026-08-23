// lib/features/bookings/bookings_controller.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/resource_booking.dart';
import 'booking_repository.dart';

class BookingsController extends AsyncNotifier<List<ResourceBooking>> {
  Timer? _timer;

  @override
  Future<List<ResourceBooking>> build() async {
    final bookings = await ref.read(bookingRepositoryProvider).myBookings();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    ref.onDispose(() => _timer?.cancel());
    return bookings;
  }

  void _tick() {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data([
      for (final b in current)
        if (b.status == BookingStatus.inWindow && b.graceRemainingSeconds > 1)
          b.copyWith(graceRemainingSeconds: b.graceRemainingSeconds - 1)
        else if (b.status == BookingStatus.inWindow)
          b.copyWith(status: BookingStatus.released, graceRemainingSeconds: 0)
        else
          b,
    ]);
  }

  Future<void> checkIn(String id) async {
    final updated = await ref.read(bookingRepositoryProvider).checkIn(id);
    final current = state.value ?? [];
    state = AsyncValue.data([for (final b in current) if (b.id == id) updated else b]);
  }

  Future<void> cancel(String id) async {
    await ref.read(bookingRepositoryProvider).cancelBooking(id);
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((b) => b.id != id).toList());
  }

  void prependBooking(ResourceBooking booking) => state = AsyncValue.data([booking, ...(state.value ?? [])]);
}

final bookingsControllerProvider = AsyncNotifierProvider<BookingsController, List<ResourceBooking>>(BookingsController.new);
