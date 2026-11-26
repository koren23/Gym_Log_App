import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/models/history_entry.dart';
import 'package:gym_tracker/models/rating_relevance.dart';
import 'package:gym_tracker/models/workout_day_def.dart';
import 'package:gym_tracker/models/year_sheet_data.dart';
import 'package:gym_tracker/providers/analysis_providers.dart';
import 'package:gym_tracker/services/analysis/xp_engine.dart';
import 'package:gym_tracker/services/widget/home_widget_service.dart';

HistoryEntry _visit(
  DateTime date,
  String dayId, {
  double? rating,
  RatingRelevance relevance = RatingRelevance.normal,
}) {
  final metaRow = MetaRow(
    rowIndex: 1,
    visitId: '$dayId-${date.toIso8601String()}',
    date: date,
    isoWeek: 1,
    isoYear: date.year,
    muscleGroups: const [],
    exercises: const [],
    sourceTab: '${date.year}',
    workoutDayId: dayId,
    rating: rating,
    ratingRelevance: relevance,
  );
  return HistoryEntry(
    date: date,
    isoWeek: 1,
    isoYear: date.year,
    exerciseNames: const [],
    muscleGroups: const [],
    metaRow: metaRow,
  );
}

const _push = WorkoutDayDef(id: 'push', label: 'Push', muscleGroups: []);
const _pull = WorkoutDayDef(id: 'pull', label: 'Pull', muscleGroups: []);
const _legs = WorkoutDayDef(id: 'legs', label: 'Legs', muscleGroups: []);

void main() {
  group('nextWorkoutDay', () {
    test('is the day after the most recent visit', () {
      final next = nextWorkoutDay(
        [
          _visit(DateTime(2026, 1, 1), 'legs'),
          _visit(DateTime(2026, 1, 3), 'push'),
        ],
        const [_push, _pull, _legs],
      );

      expect(next?.label, 'Pull');
    });

    test('wraps from the last day back to the first', () {
      final next = nextWorkoutDay(
        [_visit(DateTime(2026, 1, 3), 'legs')],
        const [_push, _pull, _legs],
      );

      expect(next?.label, 'Push');
    });

    test('follows the user-set day order', () {
      final next = nextWorkoutDay(
        [_visit(DateTime(2026, 1, 3), 'push')],
        const [_legs, _push, _pull],
      );

      expect(next?.label, 'Pull');
    });

    test('falls back to the first day with no history', () {
      expect(nextWorkoutDay(const [], const [_pull, _push])?.label, 'Pull');
    });

    test('is null with no workout days', () {
      expect(nextWorkoutDay(const [], const []), isNull);
    });
  });

  group('league tiers', () {
    test('every tier has an icon', () {
      for (final tier in kXpTiers) {
        expect(tier.icon, isNotEmpty, reason: tier.name);
      }
    });

    test('nextTierAfter walks up the ladder and stops at the top', () {
      expect(nextTierAfter(kXpTiers.first)?.name, kXpTiers[1].name);
      expect(nextTierAfter(kXpTiers.last), isNull);
    });

    test('computeWidgetStats carries the league through', () {
      final snap = computeWidgetStats(
        const [],
        league: xpTierFor(2300),
        nextWorkout: 'Pull',
      );

      expect(snap.leagueName, 'Gold');
      expect(snap.leagueIcon, '🥇');
      expect(snap.nextWorkout, 'Pull');
    });
  });

  group('averageRatingByDay', () {
    test('averages every rated visit per day, including "not 100%"', () {
      final ratings = averageRatingByDay(
        [
          _visit(DateTime(2026, 1, 1), 'push', rating: 4),
          _visit(
            DateTime(2026, 1, 8),
            'push',
            rating: 2,
            relevance: RatingRelevance.values.last,
          ),
          _visit(DateTime(2026, 1, 2), 'legs', rating: 5),
          _visit(DateTime(2026, 1, 3), 'pull'),
        ],
        const [_push, _pull, _legs],
      );

      expect(ratings.map((r) => r.day.label), ['Push', 'Legs']);
      expect(ratings.first.average, 3);
      expect(ratings.first.count, 2);
      expect(ratings.last.average, 5);
    });
  });
}
