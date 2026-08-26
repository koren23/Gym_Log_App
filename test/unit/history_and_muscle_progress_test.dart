import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/core/constants/sheet_layout.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/exercise_muscle_info.dart';
import 'package:gym_tracker/models/history_entry.dart';
import 'package:gym_tracker/models/workout_day_def.dart';
import 'package:gym_tracker/models/year_sheet_data.dart';
import 'package:gym_tracker/providers/analysis_providers.dart';

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
    test(
      'reconstructs a hand-typed day even when another day that same week is app-logged',
      () {
        // Regression test: an earlier version skipped synthesizing an entire
        // week if ANY visit existed that week, which silently dropped a
        // hand-typed Legs session in a week that also had an app-logged Push
        // visit. Entries must be tracked per (week, day), not just per week.
        final bench = Exercise(
          name: 'Barbell bench press',
          muscleGroup: MuscleGroup.legacyPush,
          sheetRow: 5,
        );
        final squats = Exercise(
          name: 'Barbell squats',
          muscleGroup: MuscleGroup.legacyLegs,
          sheetRow: 10,
        );

        final year = YearSheetData(
          year: 2026,
          tabName: '2026',
          muscleGroupSections: {
            MuscleGroup.legacyPush: [bench],
            MuscleGroup.legacyLegs: [squats],
          },
          weekColumns: {30: 1},
          cellValues: {const CellKey(5, 1): 80, const CellKey(10, 1): 100},
          metaRows: [
            MetaRow(
              rowIndex: 1,
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
              sourceTab: '2026',
            ),
          ],
        );

        final entries = buildHistoryEntries([year]);

        expect(entries, hasLength(2));
        final pushEntry = entries.firstWhere(
          (e) => e.exerciseNames.contains('Barbell bench press'),
        );
        expect(pushEntry.isSynthetic, isFalse);

        final legsEntry = entries.firstWhere(
          (e) => e.exerciseNames.contains('Barbell squats'),
        );
        expect(legsEntry.isSynthetic, isTrue);
        expect(legsEntry.isoWeek, 30);
      },
    );

    test('does not duplicate a day already covered by an app-logged visit', () {
      final bench = Exercise(
        name: 'Barbell bench press',
        muscleGroup: MuscleGroup.legacyPush,
        sheetRow: 5,
      );
      final year = YearSheetData(
        year: 2026,
        tabName: '2026',
        muscleGroupSections: {
          MuscleGroup.legacyPush: [bench],
        },
        weekColumns: {30: 1},
        cellValues: {const CellKey(5, 1): 80},
        metaRows: [
          MetaRow(
            rowIndex: 1,
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
            sourceTab: '2026',
          ),
        ],
      );

      final entries = buildHistoryEntries([year]);
      expect(entries, hasLength(1));
      expect(entries.single.isSynthetic, isFalse);
    });

    test(
      'reconstructs one entry per (week, custom WorkoutDayDef) for a '
      'currentGrouped year with no MetaRows at all',
      () {
        final bench = Exercise(
          name: 'Barbell bench press',
          muscleGroup: MuscleGroup.upperChest,
          sheetRow: 5,
        );
        final squats = Exercise(
          name: 'Barbell squats',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 10,
        );
        final crunches = Exercise(
          name: 'Cable crunches',
          muscleGroup: MuscleGroup.abdominals,
          sheetRow: 15,
        );

        final year = YearSheetData(
          year: 2026,
          tabName: '2026',
          format: MatrixTabFormat.currentGrouped,
          muscleGroupSections: {
            MuscleGroup.upperChest: [bench],
            MuscleGroup.quads: [squats],
            MuscleGroup.abdominals: [crunches],
          },
          weekColumns: {30: 1},
          cellValues: {
            const CellKey(5, 1): 80,
            const CellKey(10, 1): 100,
            const CellKey(15, 1): 30,
          },
        );

        final push = WorkoutDayDef(
          id: 'push',
          label: 'Push',
          muscleGroups: const [MuscleGroup.upperChest, MuscleGroup.abdominals],
        );
        final legs = WorkoutDayDef(
          id: 'legs',
          label: 'Legs',
          muscleGroups: const [MuscleGroup.quads, MuscleGroup.abdominals],
        );

        final entries = buildHistoryEntries(
          [year],
          workoutDays: [push, legs],
        );

        final pushEntry = entries.firstWhere(
          (e) => e.exerciseNames.contains('Barbell bench press'),
        );
        expect(pushEntry.isSynthetic, isTrue);
        expect(
          pushEntry.exerciseNames,
          containsAll(['Barbell bench press', 'Cable crunches']),
        );
        expect(pushEntry.exerciseNames, isNot(contains('Barbell squats')));

        final legsEntry = entries.firstWhere(
          (e) => e.exerciseNames.contains('Barbell squats'),
        );
        expect(legsEntry.isSynthetic, isTrue);
        expect(
          legsEntry.exerciseNames,
          containsAll(['Barbell squats', 'Cable crunches']),
        );
        expect(legsEntry.exerciseNames, isNot(contains('Barbell bench press')));
      },
    );

    test(
      'does not reconstruct a currentGrouped (week, day) already covered by '
      'a real app-logged visit for that day',
      () {
        final bench = Exercise(
          name: 'Barbell bench press',
          muscleGroup: MuscleGroup.upperChest,
          sheetRow: 5,
        );

        final year = YearSheetData(
          year: 2026,
          tabName: '2026',
          format: MatrixTabFormat.currentGrouped,
          muscleGroupSections: {
            MuscleGroup.upperChest: [bench],
          },
          weekColumns: {30: 1},
          cellValues: {const CellKey(5, 1): 80},
          metaRows: [
            MetaRow(
              rowIndex: 1,
              visitId: 'v1',
              date: DateTime(2026, 7, 20),
              isoWeek: 30,
              isoYear: 2026,
              muscleGroups: const ['upper chest'],
              exercises: const [
                LoggedExerciseRepRange(
                  exerciseName: 'Barbell bench press',
                  repRangeLow: 6,
                  repRangeHigh: 8,
                ),
              ],
              sourceTab: '2026',
            ),
          ],
        );

        final push = WorkoutDayDef(
          id: 'push',
          label: 'Push',
          muscleGroups: const [MuscleGroup.upperChest],
        );

        final entries = buildHistoryEntries([year], workoutDays: [push]);

        expect(entries, hasLength(1));
        expect(entries.single.isSynthetic, isFalse);
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

      expect(historyEntryBelongsToDay(entry, push), isTrue);
      expect(historyEntryBelongsToDay(entry, legs), isFalse);
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

        expect(historyEntryBelongsToDay(entry, pushWide), isTrue);
        expect(historyEntryBelongsToDay(entry, tricepsOnly), isFalse);
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

        expect(historyEntryBelongsToDay(entry, pull), isTrue);
        expect(historyEntryBelongsToDay(entry, push), isFalse);
      },
    );

    test('a genuine legacy-format visit still matches only its own legacy day', () {
      final entry = HistoryEntry(
        date: DateTime(2025, 5, 5),
        isoWeek: 19,
        isoYear: 2025,
        exerciseNames: const ['Incline dumbbell bench press'],
        muscleGroups: const ['Chest'],
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

      expect(historyEntryBelongsToDay(entry, push), isTrue);
      expect(historyEntryBelongsToDay(entry, pull), isFalse);
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
        );
        final pull = WorkoutDayDef(
          id: 'pull',
          label: 'Pull',
          muscleGroups: const [MuscleGroup.lats, MuscleGroup.biceps],
          legacyDay: WorkoutDay.pull,
        );

        expect(historyEntryBelongsToDay(entry, pull), isTrue);
      },
    );
  });

  group('buildMuscleProgressPoints', () {
    test(
      'indexes each exercise to its own first session and combines across an exercise switch',
      () {
        final legPress = Exercise(
          name: 'Leg press',
          muscleGroup: MuscleGroup.legacyLegs,
          sheetRow: 20,
        );
        final hackSquat = Exercise(
          name: 'Hack squat',
          muscleGroup: MuscleGroup.legacyLegs,
          sheetRow: 21,
        );

        final year = YearSheetData(
          year: 2026,
          tabName: '2026',
          muscleGroupSections: {
            MuscleGroup.legacyLegs: [legPress, hackSquat],
          },
          weekColumns: {30: 1, 31: 2, 32: 3},
          cellValues: {
            const CellKey(20, 1): 100, // Leg press week 30
            const CellKey(20, 2): 110, // Leg press week 31
            const CellKey(21, 3):
                120, // Hack squat week 32 (switched exercises)
          },
        );

        final info = [
          const ExerciseMuscleInfo(
            exerciseName: 'Leg press',
            muscleGroup: MuscleGroup.quads,
            columnIndex: 0,
          ),
          const ExerciseMuscleInfo(
            exerciseName: 'Hack squat',
            muscleGroup: MuscleGroup.quads,
            columnIndex: 0,
          ),
        ];

        final points = buildMuscleProgressPoints(
          yearsAscending: [year],
          muscle: 'quads',
          exerciseMuscleInfo: info,
        );

        expect(points, hasLength(3));
        expect(
          points[0].value,
          closeTo(100, 0.001),
        ); // week 30: leg press baseline
        expect(points[1].value, closeTo(110, 0.001)); // week 31: leg press +10%
        expect(
          points[2].value,
          closeTo(100, 0.001),
        ); // week 32: hack squat's own baseline
        expect(
          points.map((p) => p.date),
          orderedEquals(points.map((p) => p.date).toList()..sort()),
        );
      },
    );

    test(
      'averages indexed values when two exercises for the same muscle share a week',
      () {
        final legPress = Exercise(
          name: 'Leg press',
          muscleGroup: MuscleGroup.legacyLegs,
          sheetRow: 20,
        );
        final hackSquat = Exercise(
          name: 'Hack squat',
          muscleGroup: MuscleGroup.legacyLegs,
          sheetRow: 21,
        );

        final year = YearSheetData(
          year: 2026,
          tabName: '2026',
          muscleGroupSections: {
            MuscleGroup.legacyLegs: [legPress, hackSquat],
          },
          weekColumns: {30: 1},
          cellValues: {
            const CellKey(20, 1):
                100, // Leg press week 30 -> its own baseline = 100%
            const CellKey(21, 1):
                120, // Hack squat week 30 -> its own baseline = 100%
          },
        );

        final info = [
          const ExerciseMuscleInfo(
            exerciseName: 'Leg press',
            muscleGroup: MuscleGroup.quads,
            columnIndex: 0,
          ),
          const ExerciseMuscleInfo(
            exerciseName: 'Hack squat',
            muscleGroup: MuscleGroup.quads,
            columnIndex: 0,
          ),
        ];

        final points = buildMuscleProgressPoints(
          yearsAscending: [year],
          muscle: 'quads',
          exerciseMuscleInfo: info,
        );

        expect(points, hasLength(1));
        expect(points.single.value, closeTo(100, 0.001));
        expect(points.single.note, contains('Leg press'));
        expect(points.single.note, contains('Hack squat'));
      },
    );

    test(
      'sources muscle tags from the year tab\'s own exercises when no '
      'Exercises reference tab exists (empty exerciseMuscleInfo)',
      () {
        // Regression: the "Muscles" graph category used to hard-depend on
        // the (now often-gone) Exercises reference tab. It must keep
        // working from the year tab's own currentGrouped section headers
        // alone.
        final legPress = Exercise(
          name: 'Leg press',
          muscleGroup: MuscleGroup.quads,
          sheetRow: 20,
        );
        final year = YearSheetData(
          year: 2026,
          tabName: '2026',
          format: MatrixTabFormat.currentGrouped,
          muscleGroupSections: {
            MuscleGroup.quads: [legPress],
          },
          weekColumns: {30: 1},
          cellValues: {const CellKey(20, 1): 100},
        );

        final points = buildMuscleProgressPoints(
          yearsAscending: [year],
          muscle: 'quads',
          exerciseMuscleInfo: const [],
        );

        expect(points, hasLength(1));
        expect(points.single.value, closeTo(100, 0.001));
      },
    );

    test('returns nothing for a muscle with no matching exercises', () {
      final year = YearSheetData(
        year: 2026,
        tabName: '2026',
        muscleGroupSections: const {},
        weekColumns: const {},
        cellValues: const {},
      );

      final points = buildMuscleProgressPoints(
        yearsAscending: [year],
        muscle: 'quads',
        exerciseMuscleInfo: const [],
      );

      expect(points, isEmpty);
    });
  });
}
