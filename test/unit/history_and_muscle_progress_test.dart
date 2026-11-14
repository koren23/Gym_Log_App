import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/core/utils/iso_week.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/history_entry.dart';
import 'package:gym_tracker/models/workout_day_def.dart';
import 'package:gym_tracker/models/year_sheet_data.dart';
import 'package:gym_tracker/providers/analysis_providers.dart';

/// Builds a [MetaRow] with sensible placeholder defaults, so each test only
/// has to spell out the fields it actually cares about.
MetaRow _visit({
  required String visitId,
  required DateTime date,
  required int isoWeek,
  required int isoYear,
  List<String> muscleGroups = const [],
  List<LoggedExerciseRepRange> exercises = const [],
  String? workoutDayId,
  bool isSynthetic = false,
  bool exactDateKnown = true,
}) => MetaRow(
  rowIndex: 0,
  visitId: visitId,
  date: date,
  isoWeek: isoWeek,
  isoYear: isoYear,
  muscleGroups: muscleGroups,
  exercises: exercises,
  sourceTab: '2026',
  workoutDayId: workoutDayId,
  isSynthetic: isSynthetic,
  exactDateKnown: exactDateKnown,
);

/// A placeholder [MetaRow] for [HistoryEntry] tests that only exercise
/// [HistoryEntry]'s own fields plus [MetaRow.workoutDayId].
MetaRow _dummyMetaRow({String? workoutDayId}) => _visit(
  visitId: 'dummy',
  date: DateTime(2000, 1, 1),
  isoWeek: 1,
  isoYear: 2000,
  workoutDayId: workoutDayId,
);

void main() {
  group('approximateDateForWorkoutDay', () {
    test(
      'assigns Sunday/Tuesday/Thursday for legacy weeks with no exact date',
      () {
        // 2024-01-01 is a Monday and the start of ISO week 1 2024.
        expect(
          approximateDateForWorkoutDay(2024, 1, WorkoutDay.push).weekday,
          DateTime.sunday,
        );
        expect(
          approximateDateForWorkoutDay(2024, 1, WorkoutDay.pull).weekday,
          DateTime.tuesday,
        );
        expect(
          approximateDateForWorkoutDay(2024, 1, WorkoutDay.legs).weekday,
          DateTime.thursday,
        );

        expect(
          approximateDateForWorkoutDay(2024, 1, WorkoutDay.push),
          DateTime.utc(2024, 1, 7),
        );
        expect(
          approximateDateForWorkoutDay(2024, 1, WorkoutDay.pull),
          DateTime.utc(2024, 1, 2),
        );
        expect(
          approximateDateForWorkoutDay(2024, 1, WorkoutDay.legs),
          DateTime.utc(2024, 1, 4),
        );
      },
    );
  });

  group('buildHistoryEntries', () {
    // The sheet-matrix synthetic-reconstruction behavior this group used to
    // exercise has moved to a one-time import pass — see
    // SheetImportService._importCurrentGroupedSynthetic/_importLegacySynthetic
    // — since buildHistoryEntries now just wraps already-materialized
    // MetaRows. These tests cover what it actually does today.
    test(
      'wraps each MetaRow into a HistoryEntry, sorted most-recent first',
      () {
        final older = _visit(
          visitId: 'v1',
          date: DateTime(2026, 7, 20),
          isoWeek: 30,
          isoYear: 2026,
          muscleGroups: const ['Push'],
          exercises: const [
            LoggedExerciseRepRange(
              exerciseName: 'Barbell bench press',
              repRangeLow: 6,
              repRangeHigh: 8,
            ),
          ],
        );
        final newer = _visit(
          visitId: 'v2',
          date: DateTime(2026, 7, 27),
          isoWeek: 31,
          isoYear: 2026,
          muscleGroups: const ['Legs'],
          exercises: const [
            LoggedExerciseRepRange(
              exerciseName: 'Barbell squats',
              repRangeLow: 6,
              repRangeHigh: 8,
            ),
          ],
        );

        final entries = buildHistoryEntries([older, newer]);

        expect(entries, hasLength(2));
        expect(entries[0].metaRow.visitId, 'v2');
        expect(entries[1].metaRow.visitId, 'v1');
        expect(entries[0].exerciseNames, ['Barbell squats']);
        expect(entries[1].exerciseNames, ['Barbell bench press']);
      },
    );

    test(
      'preserves isSynthetic/exactDateKnown from the underlying MetaRow',
      () {
        final real = _visit(
          visitId: 'v1',
          date: DateTime(2026, 7, 20),
          isoWeek: 30,
          isoYear: 2026,
        );
        final synthetic = _visit(
          visitId: 'synthetic_2026_w31_legs',
          date: DateTime(2026, 7, 30),
          isoWeek: 31,
          isoYear: 2026,
          isSynthetic: true,
          exactDateKnown: false,
        );

        final entries = buildHistoryEntries([real, synthetic]);

        final realEntry = entries.firstWhere((e) => e.metaRow.visitId == 'v1');
        final syntheticEntry = entries.firstWhere(
          (e) => e.metaRow.visitId == 'synthetic_2026_w31_legs',
        );
        expect(realEntry.isSynthetic, isFalse);
        expect(realEntry.exactDateKnown, isTrue);
        expect(syntheticEntry.isSynthetic, isTrue);
        expect(syntheticEntry.exactDateKnown, isFalse);
      },
    );
  });

  group('historyEntryBelongsToDay', () {
    test('legacy-linked day requires an exact legacyDay match', () {
      final entry = HistoryEntry(
        date: DateTime(2026, 1, 1),
        isoWeek: 1,
        isoYear: 2026,
        exerciseNames: const ['Barbell bench press'],
        muscleGroups: const ['Push'],
        metaRow: _dummyMetaRow(),
      );
      final push = WorkoutDayDef(
        id: 'push',
        label: 'Push',
        muscleGroups: const [MuscleGroup.upperChest],
        legacyDay: WorkoutDay.push,
      );
      final legs = WorkoutDayDef(
        id: 'legs',
        label: 'Legs',
        muscleGroups: const [MuscleGroup.quads],
        legacyDay: WorkoutDay.legs,
      );

      expect(historyEntryBelongsToDay(entry, push, [push, legs]), isTrue);
      expect(historyEntryBelongsToDay(entry, legs, [push, legs]), isFalse);
    });

    test(
      'a custom day requires every trained muscle to be within its '
      'declared set',
      () {
        final entry = HistoryEntry(
          date: DateTime(2026, 1, 1),
          isoWeek: 1,
          isoYear: 2026,
          exerciseNames: const ['Barbell bench press', 'Cable tricep extension'],
          muscleGroups: const ['upper chest', 'triceps'],
          metaRow: _dummyMetaRow(),
        );
        final pushWide = WorkoutDayDef(
          id: 'push',
          label: 'Push',
          muscleGroups: const [MuscleGroup.upperChest, MuscleGroup.triceps],
        );
        final tricepsOnly = WorkoutDayDef(
          id: 'triceps_only',
          label: 'Triceps only',
          muscleGroups: const [MuscleGroup.triceps],
        );

        expect(
          historyEntryBelongsToDay(entry, pushWide, [pushWide, tricepsOnly]),
          isTrue,
        );
        expect(
          historyEntryBelongsToDay(entry, tricepsOnly, [pushWide, tricepsOnly]),
          isFalse,
        );
      },
    );

    test(
      'legacy-linked day matches a current-format visit via subset match, '
      'even with no exercise whose tag collides with legacy header text',
      () {
        final entry = HistoryEntry(
          date: DateTime(2026, 3, 3),
          isoWeek: 10,
          isoYear: 2026,
          exerciseNames: const ['Lat pulldown', 'Cable seated rows'],
          muscleGroups: const ['upper back', 'lats'],
          metaRow: _dummyMetaRow(),
        );
        final pull = WorkoutDayDef(
          id: 'pull',
          label: 'Pull',
          muscleGroups: const [
            MuscleGroup.upperBack,
            MuscleGroup.lats,
            MuscleGroup.biceps,
            MuscleGroup.brachialis,
            MuscleGroup.forearm,
          ],
          legacyDay: WorkoutDay.pull,
        );
        final push = WorkoutDayDef(
          id: 'push',
          label: 'Push',
          muscleGroups: const [
            MuscleGroup.upperChest,
            MuscleGroup.lowerChest,
            MuscleGroup.triceps,
          ],
          legacyDay: WorkoutDay.push,
        );

        expect(historyEntryBelongsToDay(entry, pull, [pull, push]), isTrue);
        expect(historyEntryBelongsToDay(entry, push, [pull, push]), isFalse);
      },
    );

    test('a genuine legacy-format visit still matches only its own legacy day', () {
      final entry = HistoryEntry(
        date: DateTime(2025, 5, 5),
        isoWeek: 19,
        isoYear: 2025,
        exerciseNames: const ['Incline dumbbell bench press'],
        muscleGroups: const ['Chest'],
        metaRow: _dummyMetaRow(),
      );
      final push = WorkoutDayDef(
        id: 'push',
        label: 'Push',
        muscleGroups: const [MuscleGroup.upperChest],
        legacyDay: WorkoutDay.push,
      );
      final pull = WorkoutDayDef(
        id: 'pull',
        label: 'Pull',
        muscleGroups: const [MuscleGroup.lats],
        legacyDay: WorkoutDay.pull,
      );

      expect(historyEntryBelongsToDay(entry, push, [push, pull]), isTrue);
      expect(historyEntryBelongsToDay(entry, pull, [push, pull]), isFalse);
    });

    test(
      'an ambiguous legacy/current-colliding label alone (e.g. "Biceps") '
      'still resolves a legacy-linked day via the legacy match',
      () {
        final entry = HistoryEntry(
          date: DateTime(2025, 6, 1),
          isoWeek: 22,
          isoYear: 2025,
          exerciseNames: const ['Dumbbell bicep curls'],
          muscleGroups: const ['Biceps'],
          metaRow: _dummyMetaRow(),
        );
        final pull = WorkoutDayDef(
          id: 'pull',
          label: 'Pull',
          muscleGroups: const [MuscleGroup.lats, MuscleGroup.biceps],
          legacyDay: WorkoutDay.pull,
        );

        expect(historyEntryBelongsToDay(entry, pull, [pull]), isTrue);
      },
    );
  });

  group('mostRecentRealVisitForDay', () {
    test('prefers an earlier real visit over a more recent synthetic one', () {
      final push = WorkoutDayDef(
        id: 'push',
        label: 'Push',
        muscleGroups: const [MuscleGroup.upperChest],
      );

      final real = _visit(
        visitId: 'v1',
        date: DateTime(2026, 5, 11),
        isoWeek: 20,
        isoYear: 2026,
        muscleGroups: const ['Push'],
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Barbell bench press',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualReps: [8, 8, 7],
            actualWeights: [80.0, 80.0, 80.0],
          ),
        ],
        workoutDayId: 'push',
      );
      final synthetic = _visit(
        visitId: 'synthetic_2026_w25_push',
        date: DateTime(2026, 6, 18),
        isoWeek: 25,
        isoYear: 2026,
        muscleGroups: const ['Push'],
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Barbell bench press',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualWeights: [85.0],
          ),
        ],
        workoutDayId: 'push',
        isSynthetic: true,
        exactDateKnown: false,
      );

      final entries = buildHistoryEntries([real, synthetic]);
      final result = mostRecentRealVisitForDay(entries, push, [push]);

      expect(result, isNotNull);
      expect(result!.isSynthetic, isFalse);
      expect(result.date, DateTime(2026, 5, 11));
    });

    test('returns null when only synthetic entries exist for the day', () {
      final legs = WorkoutDayDef(
        id: 'legs',
        label: 'Legs',
        muscleGroups: const [MuscleGroup.quads],
      );

      final synthetic = _visit(
        visitId: 'synthetic_2026_w12_legs',
        date: DateTime(2026, 3, 23),
        isoWeek: 12,
        isoYear: 2026,
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Barbell squats',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualWeights: [100.0],
          ),
        ],
        workoutDayId: 'legs',
        isSynthetic: true,
        exactDateKnown: false,
      );

      final entries = buildHistoryEntries([synthetic]);

      expect(mostRecentRealVisitForDay(entries, legs, [legs]), isNull);
    });
  });

  group('buildMuscleProgressPoints', () {
    test(
      'computes % volume-change between consecutive real visits of the same '
      'exercise, and continues the series across an exercise switch',
      () {
        // Walks only real, exact-dated visits (MetaRow-backed) and diffs
        // each exercise's own instance volume against its own previous
        // instance — no point for an exercise's very first visit.
        final legPress = Exercise(
          name: 'Leg press',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 20,
        );
        final hackSquat = Exercise(
          name: 'Hack squat',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 21,
        );

        final visits = [
          _visit(
            visitId: 'v1',
            date: DateTime(2026, 7, 20),
            isoWeek: 30,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [100, 100], // volume 1600 (baseline)
              ),
            ],
          ),
          _visit(
            visitId: 'v2',
            date: DateTime(2026, 7, 27),
            isoWeek: 31,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [110, 110], // volume 1760, +10%
              ),
            ],
          ),
          _visit(
            visitId: 'v3',
            date: DateTime(2026, 8, 3),
            isoWeek: 32,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [121, 121], // volume 1936, +10%
              ),
            ],
          ),
          _visit(
            visitId: 'v4',
            date: DateTime(2026, 8, 10),
            isoWeek: 33,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Hack squat',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [100, 100], // switch: own baseline
              ),
            ],
          ),
          _visit(
            visitId: 'v5',
            date: DateTime(2026, 8, 17),
            isoWeek: 34,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Hack squat',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [110, 110], // volume 1760, +10%
              ),
            ],
          ),
        ];

        final points = buildMuscleProgressPoints(
          visits: visits,
          exercises: [legPress, hackSquat],
          muscle: 'quads',
        );

        expect(points, hasLength(3));
        expect(points[0].value, closeTo(10, 0.001));
        expect(points[0].note, 'Leg press');
        expect(points[1].value, closeTo(10, 0.001));
        expect(points[1].note, 'Leg press');
        expect(points[2].value, closeTo(10, 0.001));
        expect(points[2].note, 'Hack squat');
        expect(
          points.map((p) => p.date),
          orderedEquals(points.map((p) => p.date).toList()..sort()),
        );
      },
    );

    test(
      'combines % volume-change points from two different exercises mapped '
      'to the same muscle into one chronological series',
      () {
        final legPress = Exercise(
          name: 'Leg press',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 20,
        );
        final hackSquat = Exercise(
          name: 'Hack squat',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 21,
        );

        final visits = [
          _visit(
            visitId: 'v1',
            date: DateTime(2026, 7, 20),
            isoWeek: 30,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [100, 100], // volume 1600 (baseline)
              ),
            ],
          ),
          _visit(
            visitId: 'v2',
            date: DateTime(2026, 7, 22),
            isoWeek: 30,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Hack squat',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [200, 200], // volume 3200 (baseline)
              ),
            ],
          ),
          _visit(
            visitId: 'v3',
            date: DateTime(2026, 7, 27),
            isoWeek: 31,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [120, 120], // volume 1920, +20%
              ),
            ],
          ),
          _visit(
            visitId: 'v4',
            date: DateTime(2026, 8, 3),
            isoWeek: 32,
            isoYear: 2026,
            muscleGroups: const ['Legs'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Hack squat',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [220, 220], // volume 3520, +10%
              ),
            ],
          ),
        ];

        final points = buildMuscleProgressPoints(
          visits: visits,
          exercises: [legPress, hackSquat],
          muscle: 'quads',
        );

        expect(points, hasLength(2));
        expect(points[0].note, 'Leg press');
        expect(points[0].value, closeTo(20, 0.001));
        expect(points[1].note, 'Hack squat');
        expect(points[1].value, closeTo(10, 0.001));
      },
    );

    test(
      'sources muscle tags from the exercise\'s own current tag when no '
      'Exercises reference tab exists (empty exerciseMuscleInfo)',
      () {
        // Regression: the "Muscles" graph category must keep working from
        // an exercise's own current-era muscle tag alone, with no Exercises
        // reference tab needed.
        final legPress = Exercise(
          name: 'Leg press',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 20,
        );

        final visits = [
          _visit(
            visitId: 'v1',
            date: DateTime(2026, 7, 20),
            isoWeek: 30,
            isoYear: 2026,
            muscleGroups: const ['quads'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [100, 100], // volume 1600 (baseline)
              ),
            ],
          ),
          _visit(
            visitId: 'v2',
            date: DateTime(2026, 7, 27),
            isoWeek: 31,
            isoYear: 2026,
            muscleGroups: const ['quads'],
            exercises: const [
              LoggedExerciseRepRange(
                exerciseName: 'Leg press',
                repRangeLow: 6,
                repRangeHigh: 8,
                actualReps: [8, 8],
                actualWeights: [110, 110], // volume 1760, +10%
              ),
            ],
          ),
        ];

        final points = buildMuscleProgressPoints(
          visits: visits,
          exercises: [legPress],
          muscle: 'quads',
        );

        expect(points, hasLength(1));
        expect(points.single.value, closeTo(10, 0.001));
      },
    );

    test('returns nothing for a muscle with no matching exercises', () {
      final points = buildMuscleProgressPoints(
        visits: const [],
        exercises: const [],
        muscle: 'quads',
      );

      expect(points, isEmpty);
    });
  });

  group('previousActualWeights', () {
    test(
      "returns the most recent visit's weights even when an earlier visit "
      'shares the same ISO week',
      () {
        // Regression test: logging 100kg early in a week then 120kg later
        // the same week must surface 120 as "last time" — buildHistoryEntries
        // sorts by true visit date, not by week bucket.
        final earlier = _visit(
          visitId: 'v1',
          date: DateTime(2026, 7, 20),
          isoWeek: 30,
          isoYear: 2026,
          muscleGroups: const ['Push'],
          exercises: const [
            LoggedExerciseRepRange(
              exerciseName: 'Barbell bench press',
              repRangeLow: 6,
              repRangeHigh: 8,
              actualReps: [8, 8],
              actualWeights: [100, 100],
            ),
          ],
        );
        final later = _visit(
          visitId: 'v2',
          date: DateTime(2026, 7, 22),
          isoWeek: 30,
          isoYear: 2026,
          muscleGroups: const ['Push'],
          exercises: const [
            LoggedExerciseRepRange(
              exerciseName: 'Barbell bench press',
              repRangeLow: 6,
              repRangeHigh: 8,
              actualReps: [8, 8],
              actualWeights: [120, 120],
            ),
          ],
        );

        final weights = previousActualWeights(
          visits: [earlier, later],
          exerciseName: 'Barbell bench press',
        );

        expect(weights, [120, 120]);
      },
    );

    test('beforeDate excludes a visit on or after that date', () {
      final earlier = _visit(
        visitId: 'v1',
        date: DateTime(2026, 7, 20),
        isoWeek: 30,
        isoYear: 2026,
        muscleGroups: const ['Push'],
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Barbell bench press',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualReps: [8, 8],
            actualWeights: [100, 100],
          ),
        ],
      );
      final later = _visit(
        visitId: 'v2',
        date: DateTime(2026, 7, 27),
        isoWeek: 31,
        isoYear: 2026,
        muscleGroups: const ['Push'],
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Barbell bench press',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualReps: [8, 8],
            actualWeights: [120, 120],
          ),
        ],
      );

      final weights = previousActualWeights(
        visits: [earlier, later],
        exerciseName: 'Barbell bench press',
        beforeDate: DateTime(2026, 7, 27),
      );

      expect(weights, [100, 100]);
    });

    test(
      'returns an empty list when the matching visit logged no per-set '
      'weights',
      () {
        final visit = _visit(
          visitId: 'v1',
          date: DateTime(2026, 7, 20),
          isoWeek: 30,
          isoYear: 2026,
          muscleGroups: const ['Push'],
          exercises: const [
            LoggedExerciseRepRange(
              exerciseName: 'Barbell bench press',
              repRangeLow: 6,
              repRangeHigh: 8,
            ),
          ],
        );

        final weights = previousActualWeights(
          visits: [visit],
          exerciseName: 'Barbell bench press',
        );

        expect(weights, isEmpty);
      },
    );
  });
}
