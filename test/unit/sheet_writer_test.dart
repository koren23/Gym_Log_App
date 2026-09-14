import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/constants/muscle_groups.dart';
import 'package:gym_tracker/core/constants/sheet_layout.dart';
import 'package:gym_tracker/models/exercise.dart';
import 'package:gym_tracker/models/set_feedback.dart';
import 'package:gym_tracker/models/workout_day_def.dart';
import 'package:gym_tracker/models/workout_visit.dart';
import 'package:gym_tracker/models/year_sheet_data.dart';
import 'package:gym_tracker/services/sheets/sheet_writer.dart';

void main() {
  const writer = SheetWriter();

  test(
    'averages with an already-existing same-week value instead of overwriting it',
    () {
      // Regression case: logging the same exercise twice in one week (e.g.
      // Crunches from Push day, then again from Legs day, since abdominals
      // is a shared muscle) must average into the cell, not silently
      // discard the first session's weight.
      final crunches = Exercise(
        name: 'Crunches',
        muscleGroup: MuscleGroup.legacyLegs,
        sheetRow: 5,
      );
      final yearData = YearSheetData(
        year: 2026,
        tabName: '2026',
        muscleGroupSections: {
          MuscleGroup.legacyLegs: [crunches],
        },
        weekColumns: {33: 2},
        cellValues: {
          const CellKey(5, 2): 5.0,
        }, // logged earlier this week from a different day
      );

      final visit = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: crunches,
            sets: const [SetEntry(weight: 7, reps: 10)],
            targetRepRangeLow: 8,
            targetRepRangeHigh: 12,
          ),
        ],
      );

      final plan = writer.planVisitWrite(
        yearData: yearData,
        visit: visit,
        sheetGridId: 0,
      );

      expect(
        plan.structuralRequests,
        isEmpty,
      ); // existing row, existing column — no inserts
      final weightRange = plan.cellValueRanges.singleWhere(
        (r) => r.range == "'2026'!C6",
      );
      expect(weightRange.values, [
        [6.0], // (5.0 existing + 7.0 new) / 2
      ]);
    },
  );

  test(
    'writes the plain session average when no prior value exists that week',
    () {
      final crunches = Exercise(
        name: 'Crunches',
        muscleGroup: MuscleGroup.legacyLegs,
        sheetRow: 5,
      );
      final yearData = YearSheetData(
        year: 2026,
        tabName: '2026',
        muscleGroupSections: {
          MuscleGroup.legacyLegs: [crunches],
        },
        weekColumns: {33: 2},
        cellValues: const {},
      );

      final visit = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: crunches,
            sets: const [
              SetEntry(weight: 7, reps: 10),
              SetEntry(weight: 9, reps: 8),
            ],
            targetRepRangeLow: 8,
            targetRepRangeHigh: 12,
          ),
        ],
      );

      final plan = writer.planVisitWrite(
        yearData: yearData,
        visit: visit,
        sheetGridId: 0,
      );

      final weightRange = plan.cellValueRanges.singleWhere(
        (r) => r.range == "'2026'!C6",
      );
      expect(weightRange.values, [
        [8.0], // plain average of 7 and 9 — no prior value to blend with
      ]);
    },
  );

  test(
    'buildMetaAppendRow writes the reps and per-set weights, marking approximate reps with ~',
    () {
      final exercise = Exercise(
        name: 'Bench press',
        muscleGroup: MuscleGroup.legacyPush,
      );
      final visit = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: exercise,
            sets: const [
              SetEntry(weight: 60, reps: 8),
              SetEntry(weight: 60, reps: 7, approxReps: true),
              SetEntry(weight: 62.5, reps: 6),
            ],
            targetRepRangeLow: 6,
            targetRepRangeHigh: 8,
          ),
        ],
      );

      final range = writer.buildMetaAppendRow(
        metaTabName: '2026_meta',
        visit: visit,
      );
      final exercisesCell = range.values!.single[5] as String;
      expect(exercisesCell, 'Bench press:6-8:8,~7,6:60.0,60.0,62.5');
    },
  );

  test(
    'buildMetaAppendRow appends a 5th segment for per-set thumbs feedback, '
    'omitted entirely when no set has any',
    () {
      final exercise = Exercise(
        name: 'Bench press',
        muscleGroup: MuscleGroup.legacyPush,
      );
      final visitWithFeedback = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: exercise,
            sets: const [
              SetEntry(weight: 60, reps: 8),
              SetEntry(weight: 60, reps: 7, feedback: SetFeedback.up),
              SetEntry(weight: 62.5, reps: 6, feedback: SetFeedback.down),
            ],
            targetRepRangeLow: 6,
            targetRepRangeHigh: 8,
          ),
        ],
      );
      final rangeWithFeedback = writer.buildMetaAppendRow(
        metaTabName: '2026_meta',
        visit: visitWithFeedback,
      );
      expect(
        rangeWithFeedback.values!.single[5] as String,
        'Bench press:6-8:8,7,6:60.0,60.0,62.5:,u,d',
      );

      final visitNoFeedback = WorkoutVisit(
        visitId: 'v2',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: exercise,
            sets: const [SetEntry(weight: 60, reps: 8)],
            targetRepRangeLow: 6,
            targetRepRangeHigh: 8,
          ),
        ],
      );
      final rangeNoFeedback = writer.buildMetaAppendRow(
        metaTabName: '2026_meta',
        visit: visitNoFeedback,
      );
      expect(
        rangeNoFeedback.values!.single[5] as String,
        'Bench press:6-8:8:60.0',
      );
    },
  );

  test(
    'currentGrouped: inserts a new exercise directly below its existing section',
    () {
      final legPress = Exercise(
        name: 'Leg press',
        muscleGroup: MuscleGroup.quads,
        sheetRow: 5,
      );
      final yearData = YearSheetData(
        year: 2026,
        tabName: '2026',
        format: MatrixTabFormat.currentGrouped,
        muscleGroupSections: {
          MuscleGroup.quads: [legPress],
        },
        weekColumns: {33: 2},
        cellValues: const {},
        sectionHeaderRows: {MuscleGroup.quads: 4},
        primaryGroupHeaderRow: {MuscleGroup.quads: 4},
      );

      final hackSquat = Exercise(
        name: 'Hack squat',
        muscleGroup: MuscleGroup.quads,
      );
      final visit = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: hackSquat,
            sets: const [SetEntry(weight: 100, reps: 8)],
            targetRepRangeLow: 6,
            targetRepRangeHigh: 8,
          ),
        ],
      );

      final plan = writer.planVisitWrite(
        yearData: yearData,
        visit: visit,
        sheetGridId: 0,
      );

      expect(plan.newSectionHeaders, isEmpty);
      expect(plan.structuralRequests, hasLength(1));
      final insert = plan.structuralRequests.single.insertDimension!.range!;
      expect(insert.startIndex, 6);
      expect(insert.endIndex, 7);
      expect(plan.resolvedRows.single.row, 6);
      expect(
        plan.cellValueRanges.singleWhere((r) => r.range == "'2026'!A7").values,
        [
          ['Hack squat'],
        ],
      );
    },
  );

  test(
    'currentGrouped: a muscle with no existing section gets a new header+exercise block appended at the tab end',
    () {
      final legPress = Exercise(
        name: 'Leg press',
        muscleGroup: MuscleGroup.quads,
        sheetRow: 5,
      );
      final hipThrust = Exercise(
        name: 'Hip thrust',
        muscleGroup: MuscleGroup.glutes,
        sheetRow: 8,
      );
      final yearData = YearSheetData(
        year: 2026,
        tabName: '2026',
        format: MatrixTabFormat.currentGrouped,
        muscleGroupSections: {
          MuscleGroup.quads: [legPress],
          MuscleGroup.glutes: [hipThrust],
        },
        weekColumns: {33: 2},
        cellValues: const {},
        sectionHeaderRows: {MuscleGroup.quads: 4, MuscleGroup.glutes: 7},
        primaryGroupHeaderRow: {MuscleGroup.quads: 4, MuscleGroup.glutes: 7},
      );

      final cableCrunch = Exercise(
        name: 'Cable ab crunch',
        muscleGroup: MuscleGroup.obliques,
      );
      final visit = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: cableCrunch,
            sets: const [SetEntry(weight: 20, reps: 12)],
            targetRepRangeLow: 10,
            targetRepRangeHigh: 15,
          ),
        ],
      );

      final plan = writer.planVisitWrite(
        yearData: yearData,
        visit: visit,
        sheetGridId: 0,
      );

      expect(plan.newSectionHeaders, hasLength(1));
      expect(plan.newSectionHeaders.single.row, 9);
      expect(plan.newSectionHeaders.single.group, MuscleGroup.obliques);

      expect(plan.structuralRequests, hasLength(1));
      final insert = plan.structuralRequests.single.insertDimension!.range!;
      expect(insert.startIndex, 9);
      expect(insert.endIndex, 11); // 2-row block: header + exercise

      expect(plan.resolvedRows.single.row, 10);
      expect(plan.resolvedRows.single.isNewRow, isTrue);

      expect(
        plan.cellValueRanges.singleWhere((r) => r.range == "'2026'!A10").values,
        [
          ['obliques'],
        ],
      );
      expect(
        plan.cellValueRanges.singleWhere((r) => r.range == "'2026'!A11").values,
        [
          ['Cable ab crunch'],
        ],
      );
    },
  );

  test(
    'currentGrouped: two new exercises in one visit under the same brand-new muscle reuse one section',
    () {
      final legPress = Exercise(
        name: 'Leg press',
        muscleGroup: MuscleGroup.quads,
        sheetRow: 5,
      );
      final hipThrust = Exercise(
        name: 'Hip thrust',
        muscleGroup: MuscleGroup.glutes,
        sheetRow: 8,
      );
      final yearData = YearSheetData(
        year: 2026,
        tabName: '2026',
        format: MatrixTabFormat.currentGrouped,
        muscleGroupSections: {
          MuscleGroup.quads: [legPress],
          MuscleGroup.glutes: [hipThrust],
        },
        weekColumns: {33: 2},
        cellValues: const {},
        sectionHeaderRows: {MuscleGroup.quads: 4, MuscleGroup.glutes: 7},
        primaryGroupHeaderRow: {MuscleGroup.quads: 4, MuscleGroup.glutes: 7},
      );

      final wristCurls = Exercise(
        name: 'Wrist curls',
        muscleGroup: MuscleGroup.forearm,
      );
      final reverseWristCurls = Exercise(
        name: 'Reverse wrist curls',
        muscleGroup: MuscleGroup.forearm,
      );
      final visit = WorkoutVisit(
        visitId: 'v1',
        date: DateTime(2026, 8, 14),
        isoWeek: 33,
        isoYear: 2026,
        entries: [
          ExerciseEntry(
            exercise: wristCurls,
            sets: const [SetEntry(weight: 10, reps: 15)],
            targetRepRangeLow: 12,
            targetRepRangeHigh: 15,
          ),
          ExerciseEntry(
            exercise: reverseWristCurls,
            sets: const [SetEntry(weight: 8, reps: 15)],
            targetRepRangeLow: 12,
            targetRepRangeHigh: 15,
          ),
        ],
      );

      final plan = writer.planVisitWrite(
        yearData: yearData,
        visit: visit,
        sheetGridId: 0,
      );

      // Only one new header row for the whole visit, not one per exercise.
      expect(plan.newSectionHeaders, hasLength(1));
      expect(plan.newSectionHeaders.single.group, MuscleGroup.forearm);

      expect(plan.resolvedRows, hasLength(2));
      expect(plan.resolvedRows.every((r) => r.isNewRow), isTrue);
      expect(plan.resolvedRows.map((r) => r.row), [10, 11]);

      expect(
        plan.cellValueRanges.singleWhere((r) => r.range == "'2026'!A10").values,
        [
          ['forearm'],
        ],
      );
    },
  );

  test(
    'buildWorkoutDayUpdateRange targets B/C of the row and leaves id untouched',
    () {
      final def = WorkoutDayDef(
        id: 'push',
        label: 'Push A',
        muscleGroups: const [MuscleGroup.upperChest, MuscleGroup.triceps],
        legacyDay: WorkoutDay.push,
        sheetRowIndex: 3,
      );
      final range = writer.buildWorkoutDayUpdateRange(def);
      expect(range.range, "'WorkoutDays'!B4:C4");
      expect(range.values, [
        ['Push A', 'upperChest,triceps'],
      ]);
    },
  );

  test(
    'buildExercisesOrderUpdateRange round-trips actualWeights/approxReps',
    () {
      final range = writer.buildExercisesOrderUpdateRange(
        metaTabName: '2026_meta',
        metaRowIndex: 3,
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Bench press',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualReps: [8, 7, 6],
            approxReps: [false, true, false],
            actualWeights: [60.0, 60.0, 62.5],
          ),
        ],
      );
      expect(range.range, "'2026_meta'!F4");
      expect(
        range.values!.single.single,
        'Bench press:6-8:8,~7,6:60.0,60.0,62.5',
      );
    },
  );

  test(
    'buildExercisesOrderUpdateRange round-trips setFeedback, preserving '
    'empty-token positions',
    () {
      final range = writer.buildExercisesOrderUpdateRange(
        metaTabName: '2026_meta',
        metaRowIndex: 3,
        exercises: const [
          LoggedExerciseRepRange(
            exerciseName: 'Bench press',
            repRangeLow: 6,
            repRangeHigh: 8,
            actualReps: [8, 7, 6],
            approxReps: [false, true, false],
            actualWeights: [60.0, 60.0, 62.5],
            setFeedback: [SetFeedback.none, SetFeedback.up, SetFeedback.none],
          ),
        ],
      );
      expect(range.range, "'2026_meta'!F4");
      expect(
        range.values!.single.single,
        'Bench press:6-8:8,~7,6:60.0,60.0,62.5:,u,',
      );
    },
  );
}
