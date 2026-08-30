// test/features/bookings/bookings_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/bookings_controller.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

void main() {
  test('build() loads the 2 seeded bookings', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final bookings = await container.read(bookingsControllerProvider.future);
    expect(bookings.length, 2);
  });

  test('the timer ticks down graceRemainingSeconds for the in-window booking', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);
    final before = container.read(bookingsControllerProvider).value!.firstWhere((b) => b.id == 'bk2').graceRemainingSeconds;
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final after = container.read(bookingsControllerProvider).value!.firstWhere((b) => b.id == 'bk2').graceRemainingSeconds;
    expect(after, lessThan(before));
  });

  test('checkIn flips the booking to checkedIn in state', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);
    await container.read(bookingsControllerProvider.notifier).checkIn('bk2');
    final booking = container.read(bookingsControllerProvider).value!.firstWhere((b) => b.id == 'bk2');
    expect(booking.status, BookingStatus.checkedIn);
  });

  test('cancel removes the booking from state', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    await container.read(bookingsControllerProvider.future);
    await container.read(bookingsControllerProvider.notifier).cancel('bk1');
    final bookings = container.read(bookingsControllerProvider).value!;
    expect(bookings.any((b) => b.id == 'bk1'), false);
  });
}
