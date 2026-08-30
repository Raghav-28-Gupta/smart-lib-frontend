// test/features/bookings/booking_flow_controller_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/booking_flow_controller.dart';
import 'package:smartlib_frontend/features/bookings/bookings_controller.dart';
import 'package:smartlib_frontend/models/resource.dart';
import '../../support/mock_overrides.dart';

void main() {
  test('confirming a normal slot succeeds and appears in bookingsControllerProvider', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);
    notifier.pickSlot(const Resource(id: 's3', name: 'Silent Zone · Desk 3', type: ResourceType.seat, takenSlotsToday: []), '9:00 AM');
    notifier.goToConfirm();
    await notifier.confirm();

    final state = container.read(bookingFlowControllerProvider);
    expect(state.result, isNotNull);
    expect(state.conflictAlternatives, isNull);

    final bookings = await container.read(bookingsControllerProvider.future);
    expect(bookings.any((b) => b.resourceName == 'Silent Zone · Desk 3'), true);
  });

  test('confirming the scripted conflict slot surfaces alternatives instead of a result', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);
    notifier.pickSlot(const Resource(id: 's1', name: 'Reading Room A · Desk 12', type: ResourceType.seat, takenSlotsToday: []), '5:00 PM');
    notifier.goToConfirm();
    await notifier.confirm();

    final state = container.read(bookingFlowControllerProvider);
    expect(state.result, isNull);
    expect(state.conflictAlternatives, isNotNull);
    expect(state.conflictAlternatives!.map((a) => a.timeSlot), containsAll(['6:00 PM', '5:00 PM']));
  });

  test('pickAlternative selects the alternative and clears the conflict', () async {
    final container = ProviderContainer(overrides: mockRepositoryOverrides());
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);
    notifier.pickSlot(const Resource(id: 's1', name: 'Reading Room A · Desk 12', type: ResourceType.seat, takenSlotsToday: []), '5:00 PM');
    notifier.goToConfirm();
    await notifier.confirm();
    final alt = container.read(bookingFlowControllerProvider).conflictAlternatives!.first;

    notifier.pickAlternative(alt);
    final state = container.read(bookingFlowControllerProvider);
    expect(state.selectedSlot, alt.timeSlot);
    expect(state.conflictAlternatives, isNull);
  });
}
