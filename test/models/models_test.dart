import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/theme/smartlib_theme.dart';
import 'package:smartlib_frontend/models/book.dart';
import 'package:smartlib_frontend/models/loan.dart';
import 'package:smartlib_frontend/models/resource_booking.dart';

void main() {
  test('Book.initial is the uppercased first letter of the title', () {
    final b = Book(
      id: 'b1',
      title: 'atomic habits',
      author: 'James Clear',
      genre: 'Non-fiction',
      description: 'd',
      totalCopies: 3,
      availableCopies: 2,
      waitlistCount: 0,
      coverPalette: CoverPalette.neutral,
    );
    expect(b.initial, 'A');
  });

  test('Loan.copyWith overrides only the given fields', () {
    final l = Loan(
      id: 'loan1',
      bookId: 'b1',
      dueDate: DateTime(2026, 8, 30),
      status: LoanStatus.normal,
      fineAmount: 0,
      canRenew: true,
    );
    final renewed =
        l.copyWith(dueDate: DateTime(2026, 9, 5), justRenewed: true);
    expect(renewed.id, 'loan1');
    expect(renewed.dueDate, DateTime(2026, 9, 5));
    expect(renewed.justRenewed, true);
    expect(renewed.canRenew, true);
  });

  test('ResourceBooking.copyWith overrides only the given fields', () {
    final b = ResourceBooking(
      id: 'bk2',
      resourceName: 'Group Room 201',
      type: ResourceType.room,
      startTime: DateTime(2026, 8, 22, 12),
      timeSlot: '12:00 - 1:00 PM',
      status: BookingStatus.inWindow,
      graceRemainingSeconds: 587,
    );
    final ticked = b.copyWith(graceRemainingSeconds: 586);
    expect(ticked.graceRemainingSeconds, 586);
    expect(ticked.status, BookingStatus.inWindow);
    expect(ticked.resourceName, 'Group Room 201');
  });
}
