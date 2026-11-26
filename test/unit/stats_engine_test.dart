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

    test('a run crossing New Year stays consecutive', () {
      expect(
        longestStreakWeeks([
          DateTime(2025, 12, 22),
          DateTime(2025, 12, 31),
          DateTime(2026, 1, 7),
        ]),
        3,
      );
    });
  });

  group('longestStreakRun', () {
    test('reports the first and last Monday of the run', () {
      final run = longestStreakRun([
        DateTime(2024, 1, 3), // Wed, week of Mon Jan 1.
        DateTime(2024, 1, 12), // Fri, week of Mon Jan 8.
        DateTime(2024, 2, 1),
      ])!;

      expect(run.weeks, 2);
      expect(run.firstMonday, DateTime(2024, 1, 1));
      expect(run.lastMonday, DateTime(2024, 1, 8));
    });

    test('the most recent run wins a tie', () {
      final run = longestStreakRun([
        DateTime(2024, 1, 1),
        DateTime(2024, 1, 8),
        DateTime(2024, 3, 4),
        DateTime(2024, 3, 11),
      ])!;

      expect(run.weeks, 2);
      expect(run.lastMonday, DateTime(2024, 3, 11));
    });

    test('is null with no visits', () {
      expect(longestStreakRun(const []), isNull);
    });
  });
}
