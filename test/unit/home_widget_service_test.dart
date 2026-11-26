import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/services/widget/home_widget_service.dart';

void main() {
  group('computeWidgetStats', () {
    test('both stats are zero with no visits at all', () {
      final snap = computeWidgetStats(const []);

      expect(snap.streakWeeks, 0);
      expect(snap.bestStreakWeeks, 0);
    });

    test('a single visit this week counts as a 1-week streak', () {
      final now = DateTime.now();
      final snap = computeWidgetStats([now]);

      expect(snap.streakWeeks, 1);
      expect(snap.bestStreakWeeks, 1);
    });

    test(
      'bestStreakWeeks stays at a past peak after the current streak breaks',
      () {
        final now = DateTime.now();
        final weekStart = DateTime(2024, 1, 1); // a Monday, long past.
        final visitDates = [
          now,
          weekStart,
          weekStart.add(const Duration(days: 7)),
          weekStart.add(const Duration(days: 14)),
        ];

        final snap = computeWidgetStats(visitDates);

        expect(snap.streakWeeks, 1);
        expect(snap.bestStreakWeeks, 3);
      },
    );
  });
}
