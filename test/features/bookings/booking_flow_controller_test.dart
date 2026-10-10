// test/features/bookings/booking_flow_controller_test.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/features/bookings/booking_flow_controller.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/bookings_controller.dart';
import 'package:smartlib_frontend/models/booking_alternative.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../../support/mock_overrides.dart';

/// Refuses the first booking with one alternative, then records every window
/// it's asked to book.
class _ConflictOnceRepository extends MockBookingRepository {
  _ConflictOnceRepository(this.alternative);
  final BookingAlternative alternative;
  final requested = <({String resourceId, DateTime start, DateTime end})>[];

  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async {
    requested.add((resourceId: resource.id, start: start, end: end));
    if (requested.length == 1) throw BookingConflictException([alternative]);
    return super.createBooking(resource: resource, start: start, end: end);
  }
}

/// Every createBooking waits on [gate], then succeeds or throws [error].
class _GatedBookingRepository extends MockBookingRepository {
  final gate = Completer<void>();
  Object? error;
  int calls = 0;

  @override
  Future<ResourceBooking> createBooking({required Resource resource, required DateTime start, required DateTime end}) async {
    calls++;
    await gate.future;
    if (error != null) throw error!;
    return super.createBooking(resource: resource, start: start, end: end);
  }
}

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
    notifier.setDateIndex(1); // the mock's scripted conflict is tomorrow at 5 PM
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
    notifier.setDateIndex(1); // the mock's scripted conflict is tomorrow at 5 PM
    notifier.pickSlot(const Resource(id: 's1', name: 'Reading Room A · Desk 12', type: ResourceType.seat, takenSlotsToday: []), '5:00 PM');
    notifier.goToConfirm();
    await notifier.confirm();
    final alt = container.read(bookingFlowControllerProvider).conflictAlternatives!.first;

    notifier.pickAlternative(alt);
    final state = container.read(bookingFlowControllerProvider);
    expect(state.selectedSlot, alt.timeSlot);
    expect(state.conflictAlternatives, isNull);
  });

  test("taking an alternative books the server's exact window, not one rebuilt from its label", () async {
    // Off the hour on purpose: a window rebuilt from the label '6:30 PM' via
    // the slot table would fail, since no such slot exists.
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final altStart = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 30);
    final alt = BookingAlternative(
      resourceId: 's3', resourceName: 'Silent Zone · Desk 3', resourceType: ResourceType.seat,
      startTime: altStart, endTime: altStart.add(const Duration(hours: 1)),
    );
    final repo = _ConflictOnceRepository(alt);
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);

    notifier.setDateIndex(1);
    notifier.pickSlot(const Resource(id: 's1', name: 'Reading Room A · Desk 12', type: ResourceType.seat, takenSlotsToday: []), '5:00 PM');
    notifier.goToConfirm();
    await notifier.confirm();
    notifier.pickAlternative(container.read(bookingFlowControllerProvider).conflictAlternatives!.single);
    await notifier.confirm();

    expect(repo.requested.last.resourceId, 's3');
    expect(repo.requested.last.start, altStart);
    expect(repo.requested.last.end, altStart.add(const Duration(hours: 1)));
    expect(container.read(bookingFlowControllerProvider).result, isNotNull);
  });

  test("picking a slot after an alternative goes back to the slot's own window", () async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final altStart = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18, 30);
    final repo = _ConflictOnceRepository(BookingAlternative(
      resourceId: 's3', resourceName: 'Silent Zone · Desk 3', resourceType: ResourceType.seat,
      startTime: altStart, endTime: altStart.add(const Duration(hours: 1)),
    ));
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);
    const desk12 = Resource(id: 's1', name: 'Reading Room A · Desk 12', type: ResourceType.seat, takenSlotsToday: []);

    notifier.setDateIndex(1);
    notifier.pickSlot(desk12, '5:00 PM');
    notifier.goToConfirm();
    await notifier.confirm();
    notifier.pickAlternative(container.read(bookingFlowControllerProvider).conflictAlternatives!.single);
    notifier.backToPicker();
    notifier.pickSlot(desk12, '9:00 AM');
    notifier.goToConfirm();
    await notifier.confirm();

    expect(repo.requested.last.start, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9));
  });

  test('a double tap on Confirm books once', () async {
    // A second request would come back as a conflict with the first, and
    // replace the success screen with "that slot was just taken".
    final repo = _GatedBookingRepository();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);
    notifier.setDateIndex(1);
    notifier.pickSlot(const Resource(id: 's3', name: 'Silent Zone · Desk 3', type: ResourceType.seat, takenSlotsToday: []), '9:00 AM');
    notifier.goToConfirm();

    final first = notifier.confirm();
    final second = notifier.confirm();
    repo.gate.complete();
    await Future.wait([first, second]);
    expect(repo.calls, 1);
    expect(container.read(bookingFlowControllerProvider).result, isNotNull);
  });

  test('a refusal that is not a conflict is reported, not swallowed', () async {
    // e.g. the slot passed while the user sat on the confirm screen.
    final repo = _GatedBookingRepository()..error = const ApiException(400, 'That time slot has already passed. Pick a later one.');
    repo.gate.complete();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    final notifier = container.read(bookingFlowControllerProvider.notifier);
    notifier.setDateIndex(1);
    notifier.pickSlot(const Resource(id: 's3', name: 'Silent Zone · Desk 3', type: ResourceType.seat, takenSlotsToday: []), '9:00 AM');
    notifier.goToConfirm();

    await expectLater(notifier.confirm(), throwsA(isA<ApiException>()));
    final state = container.read(bookingFlowControllerProvider);
    expect(state.result, isNull);
    expect(state.conflictAlternatives, isNull);
    // The guard was released: confirming again goes back to the server.
    await expectLater(notifier.confirm(), throwsA(isA<ApiException>()));
    expect(repo.calls, 2);
  });
}
