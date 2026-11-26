import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/analysis/stats_engine.dart';

void main() {
  group('longestStreakWeeks', () {
    test('three visits in three consecutive weeks form a 3-week streak', () {
      final weekStart = DateTime(2024, 1, 1); // a Monday.
      final visitDates = [
        weekStart,
        weekStart.add(const Duration(days: 7)),
        weekStart.add(const Duration(days: 14)),
      ];

      expect(longestStreakWeeks(visitDates), 3);
    });

    test('a gap week splits the run instead of extending it', () {
      final weekStart = DateTime(2024, 1, 1);
      final visitDates = [
        weekStart,
        weekStart.add(const Duration(days: 7)),
        weekStart.add(const Duration(days: 21)), // skips one week.
      ];

      expect(longestStreakWeeks(visitDates), 2);
    });

    test('a single visit is a 1-week streak', () {
      expect(longestStreakWeeks([DateTime(2024, 3, 4)]), 1);
    });

    test('no visits is a 0-week streak', () {
      expect(longestStreakWeeks(const []), 0);
    });
  });
}
