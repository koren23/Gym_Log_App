import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/utils/iso_week.dart';

void main() {
  group('isoWeekNumber', () {
    test('first Monday of an ISO week-1 year is week 1', () {
      expect(isoWeekNumber(DateTime.utc(2024, 1, 1)), 1);
    });

    test('late December can fall in week 1 of the next iso year', () {
      // 2025-12-29 is a Monday, start of the first full week of 2026.
      expect(isoWeekNumber(DateTime.utc(2025, 12, 29)), 1);
      expect(isoWeekYear(DateTime.utc(2025, 12, 29)), 2026);
    });

    test(
      'early January can fall in the last iso week of the previous year',
      () {
        // 2023-01-01 is a Sunday, belongs to ISO week 52 of 2022.
        expect(isoWeekNumber(DateTime.utc(2023, 1, 1)), 52);
        expect(isoWeekYear(DateTime.utc(2023, 1, 1)), 2022);
      },
    );

    test('mid-year date lands in a sensible week number', () {
      expect(isoWeekNumber(DateTime.utc(2024, 7, 1)), 27);
    });
  });

  group('approximateDateForIsoWeek', () {
    test('round-trips back to the same iso week', () {
      final approx = approximateDateForIsoWeek(2024, 27);
      expect(isoWeekNumber(approx), 27);
      expect(isoWeekYear(approx), 2024);
    });
  });
}
