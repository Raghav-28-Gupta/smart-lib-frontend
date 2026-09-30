// test/features/bookings/time_slots_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/time_format.dart';
import 'package:smartlib_frontend/features/bookings/time_slots.dart';

void main() {
  group('slot vocabulary', () {
    test('is 11 consecutive one-hour slots from 9 AM to 7 PM', () {
      // Mirrors TIME_SLOTS in backend/src/config/constants.ts. The
      // availability endpoint reports taken slots by these exact labels, so a
      // drift here silently marks the wrong hour as taken -- or books it.
      expect(kTimeSlots, hasLength(11));
      expect(kTimeSlots.map((l) => kSlotHours[l]).toList(), List.generate(11, (i) => 9 + i));
    });

    test('every label is exactly what clockLabel produces for its hour', () {
      // Labels built from real timestamps (a conflict alternative's start
      // time, say) must match a slot chip, or selecting it silently fails.
      for (final label in kTimeSlots) {
        expect(clockLabel(DateTime(2026, 9, 30, kSlotHours[label]!)), label);
      }
    });
  });

  group('apiDate', () {
    test('formats today as zero-padded YYYY-MM-DD', () {
      expect(apiDate(0, now: DateTime(2026, 9, 5, 23, 59)), '2026-09-05');
    });

    test('rolls over month and year boundaries', () {
      expect(apiDate(1, now: DateTime(2026, 12, 31, 10)), '2027-01-01');
      expect(apiDate(2, now: DateTime(2026, 2, 27, 10)), '2026-03-01');
    });
  });

  group('slotWindow', () {
    test('is the one-hour local window for that day and slot', () {
      final w = slotWindow(1, '5:00 PM', now: DateTime(2026, 9, 30, 20));
      expect(w.start, DateTime(2026, 10, 1, 17));
      expect(w.end, DateTime(2026, 10, 1, 18));
      expect(w.start.isUtc, false);
    });

    test('rejects a label outside the vocabulary', () {
      expect(() => slotWindow(0, '8:00 PM'), throwsArgumentError);
    });
  });

  group('slotWindowIso', () {
    test('sends UTC with a Z suffix at the same instant as the local window', () {
      // POST /bookings validates with z.iso.datetime({ offset: true }); a
      // local toIso8601String() carries no offset and gets a 400.
      final now = DateTime(2026, 9, 30, 8);
      final iso = slotWindowIso(0, '9:00 AM', now: now);
      final local = slotWindow(0, '9:00 AM', now: now);
      expect(iso.start, endsWith('Z'));
      expect(iso.end, endsWith('Z'));
      expect(DateTime.parse(iso.start).isAtSameMomentAs(local.start), true);
      expect(DateTime.parse(iso.end).isAtSameMomentAs(local.end), true);
    });
  });
}
