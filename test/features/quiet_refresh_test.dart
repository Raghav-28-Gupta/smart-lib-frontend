// test/features/quiet_refresh_test.dart
//
// The 30-second re-check refetches quietly: a failure keeps what's on screen.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/api_exception.dart';
import 'package:smartlib_frontend/features/bookings/booking_repository.dart';
import 'package:smartlib_frontend/features/bookings/bookings_controller.dart';
import 'package:smartlib_frontend/features/loans/loan_repository.dart';
import 'package:smartlib_frontend/features/loans/loans_controller.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';
import '../support/mock_overrides.dart';

class _FlakyLoans extends MockLoanRepository {
  bool offline = false;
  @override
  Future<List<Loan>> activeLoans() =>
      offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.activeLoans();
}

class _FlakyBookings extends MockBookingRepository {
  bool offline = false;
  @override
  Future<List<ResourceBooking>> myBookings() =>
      offline ? Future.error(const ApiException(0, ApiException.networkMessage)) : super.myBookings();
}

void main() {
  test('loans: refreshQuietly keeps the list when the network fails', () async {
    final repo = _FlakyLoans();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(loans: repo));
    addTearDown(container.dispose);
    final before = await container.read(loansControllerProvider.future);

    repo.offline = true;
    await container.read(loansControllerProvider.notifier).refreshQuietly();

    final state = container.read(loansControllerProvider);
    expect(state.hasError, false);
    expect(state.value!.map((l) => l.id), before.map((l) => l.id));
  });

  test('bookings: refreshQuietly keeps the list when the network fails', () async {
    final repo = _FlakyBookings();
    final container = ProviderContainer(overrides: mockRepositoryOverrides(bookings: repo));
    addTearDown(container.dispose);
    final before = await container.read(bookingsControllerProvider.future);

    repo.offline = true;
    await container.read(bookingsControllerProvider.notifier).refreshQuietly();

    final state = container.read(bookingsControllerProvider);
    expect(state.hasError, false);
    expect(state.value!.map((b) => b.id), before.map((b) => b.id));
  });
}
