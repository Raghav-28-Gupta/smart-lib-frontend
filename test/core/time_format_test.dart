// test/core/time_format_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smartlib_frontend/core/time_format.dart';

void main() {
  group('clockLabel', () {
    test('formats in the slot vocabulary\'s 12-hour style', () {
      expect(clockLabel(DateTime(2026, 9, 30, 9)), '9:00 AM');
      expect(clockLabel(DateTime(2026, 9, 30, 17)), '5:00 PM');
      expect(clockLabel(DateTime(2026, 9, 30, 13, 5)), '1:05 PM');
    });

    test('handles noon and midnight', () {
      expect(clockLabel(DateTime(2026, 9, 30, 12)), '12:00 PM');
      expect(clockLabel(DateTime(2026, 9, 30, 0)), '12:00 AM');
    });
  });

  group('timeRangeLabel', () {
    test('drops the first meridiem when both ends share one', () {
      // Matches the existing booking copy, e.g. '3:00 – 5:00 PM'.
      expect(timeRangeLabel(DateTime(2026, 9, 30, 15), DateTime(2026, 9, 30, 17)), '3:00 – 5:00 PM');
      expect(timeRangeLabel(DateTime(2026, 9, 30, 12), DateTime(2026, 9, 30, 13)), '12:00 – 1:00 PM');
    });

    test('keeps both meridiems when the range crosses noon', () {
      expect(timeRangeLabel(DateTime(2026, 9, 30, 11), DateTime(2026, 9, 30, 13)), '11:00 AM – 1:00 PM');
    });

    test('formats times that are not on the hour', () {
      // Real bookings can start off the hour; a label built from the
      // timestamp must still render rather than fall back to nothing.
      expect(timeRangeLabel(DateTime(2026, 9, 30, 17, 23), DateTime(2026, 9, 30, 18, 23)), '5:23 – 6:23 PM');
    });
  });

  group('dayTimeLabel', () {
    // Saturday evening.
    final now = DateTime(2026, 10, 10, 20, 30);

    test('says today or tomorrow when it is', () {
      expect(dayTimeLabel(DateTime(2026, 10, 10, 22), now: now), 'today, 10:00 PM');
      expect(dayTimeLabel(DateTime(2026, 10, 11, 9), now: now), 'tomorrow, 9:00 AM');
    });

    test('names the weekday further out', () {
      // A held copy lasts 48 hours, so it can end two days away.
      expect(dayTimeLabel(DateTime(2026, 10, 12, 20, 45), now: now), 'Mon, 8:45 PM');
    });
  });
}
