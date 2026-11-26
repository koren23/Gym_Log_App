import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/models/app_colors.dart';
import 'package:gym_tracker/services/widget/home_widget_service.dart';

void main() {
  group('computeWidgetStats', () {
    test('everything is zero/empty with no visits at all', () {
      final snap = computeWidgetStats(const []);

      expect(snap.streakWeeks, 0);
      expect(snap.bestStreakWeeks, 0);
      expect(snap.bestStreakEnded, '');
    });

    test('a single visit this week counts as an ongoing 1-week streak', () {
      final snap = computeWidgetStats([DateTime.now()]);

      expect(snap.streakWeeks, 1);
      expect(snap.bestStreakWeeks, 1);
      expect(snap.bestStreakEnded, '');
    });

    test('a broken best streak reports the Sunday its missed week ended', () {
      final weekStart = DateTime(2024, 1, 1); // a Monday, long past.
      final visitDates = [
        DateTime.now(),
        weekStart,
        weekStart.add(const Duration(days: 7)),
        weekStart.add(const Duration(days: 14)),
      ];

      final snap = computeWidgetStats(visitDates);

      expect(snap.streakWeeks, 1);
      expect(snap.bestStreakWeeks, 3);
      // Last streak week starts Mon Jan 15; Jan 22-28 was missed.
      expect(snap.bestStreakEnded, 'Jan 28, 2024');
    });

    test('a best streak that reached last week is still ongoing', () {
      final now = DateTime(2024, 3, 13); // a Wednesday.
      final visitDates = [
        DateTime(2024, 2, 26),
        DateTime(2024, 3, 4), // last week; nothing logged this week yet.
      ];

      final snap = computeWidgetStats(visitDates, now: now);

      expect(snap.bestStreakWeeks, 2);
      expect(snap.bestStreakEnded, '');
    });
  });

  group('widgetPaletteFor', () {
    test('light themes get dark text, dark themes get light text', () {
      for (final preset in kAppThemePresets) {
        final palette = widgetPaletteFor(preset.colors);
        final bgIsDark =
            ThemeData.estimateBrightnessForColor(preset.colors.background) ==
            Brightness.dark;
        final textIsDark =
            ThemeData.estimateBrightnessForColor(palette.text) ==
            Brightness.dark;
        expect(textIsDark, !bgIsDark, reason: preset.name);
      }
    });

    test('buttons use the theme hero and dashboard colors', () {
      final palette = widgetPaletteFor(AppColors.defaults);

      expect(palette.button, AppColors.kDefaultLogWorkoutHero);
      expect(palette.button2, AppColors.kDefaultDashboardButtons);
      expect(palette.background, AppColors.kDefaultBackground);
    });
  });
}
