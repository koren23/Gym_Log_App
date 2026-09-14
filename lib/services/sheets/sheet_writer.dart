import 'package:googleapis/sheets/v4.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/constants/sheet_layout.dart';
import '../../models/exercise.dart';
import '../../models/rating_relevance.dart';
import '../../models/set_feedback.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';

/// Converts a 0-based column index to A1 column letters (0 -> A, 1 -> B,
/// 26 -> AA, ...).
String columnLetter(int index) {
  var n = index;
  var result = '';
  do {
    result = String.fromCharCode(65 + (n % 26)) + result;
    n = (n ~/ 26) - 1;
  } while (n >= 0);
  return result;
}

/// Formats [date] as `YYYY-MM-DD`, matching what the sheet parser expects
/// back via `DateTime.parse`.
String formatDateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// A resolved row assignment for one exercise in a visit: either an
/// existing row, or a freshly planned insertion point.
class ResolvedExerciseRow {
  const ResolvedExerciseRow({
    required this.exercise,
    required this.row,
    required this.isNewRow,
  });
  final Exercise exercise;
  final int row;
  final bool isNewRow;
}

/// A brand-new section header row created mid-plan for a muscle group that
/// had no existing section anywhere in the tab yet.
typedef NewSectionHeader = ({int row, MuscleGroup group});

/// Everything needed to write one [WorkoutVisit] into a year's matrix tab.
class VisitWritePlan {
  const VisitWritePlan({
    required this.structuralRequests,
    required this.cellValueRanges,
    required this.resolvedRows,
    required this.targetColumnIndex,
    required this.isNewColumn,
    this.newSectionHeaders = const [],
  });

  /// Row-insertion requests; must be sent via `spreadsheets.batchUpdate`
  /// and awaited BEFORE [cellValueRanges] is written, since the latter
  /// depends on the row positions insertion produces.
  final List<Request> structuralRequests;

  /// Cell writes (week header + per-exercise weight); send via
  /// `spreadsheets.values.batchUpdate` with USER_ENTERED input, after the
  /// structural requests (if any) have completed.
  final List<ValueRange> cellValueRanges;

  final List<ResolvedExerciseRow> resolvedRows;
  final int targetColumnIndex;
  final bool isNewColumn;

  /// Brand-new section header rows this plan creates (grouped-format tabs
  /// only), for a muscle group with no existing section in the tab. The
  /// header text ([MuscleGroup.sheetHeader]) is already included in
  /// [cellValueRanges] — this is exposed separately only for callers/tests
  /// that want to assert on it directly.
  final List<NewSectionHeader> newSectionHeaders;
}

class SheetWriter {
  const SheetWriter();

  /// Plans the write for [visit] against [yearData] (must be freshly
  /// parsed — do not reuse a stale copy, since row indices must be exact).
  /// [sheetGridId] is the numeric Sheets grid ID (Sheet.properties.sheetId)
  /// of [yearData.tabName], required for row-insertion requests.
  VisitWritePlan planVisitWrite({
    required YearSheetData yearData,
    required WorkoutVisit visit,
    required int sheetGridId,
  }) {
    final isNewColumn = !yearData.weekColumns.containsKey(visit.isoWeek);
    final targetColumn = isNewColumn
        ? yearData.nextFreeColumnIndex
        : yearData.weekColumns[visit.isoWeek]!;

    final structuralRequests = <Request>[];
    final resolvedRows = <ResolvedExerciseRow>[];

    if (yearData.format == MatrixTabFormat.flatV2) {
      // Flat layout: no sections to keep in order — a new exercise's row is
      // simply appended after the last row currently used in the tab.
      var nextRow =
          yearData.allExercises
              .map((e) => e.sheetRow ?? 0)
              .fold(0, (a, b) => a > b ? a : b) +
          1;
      for (final entry in visit.entries) {
        final existing = yearData.findExercise(entry.exercise.name);
        if (existing != null && existing.sheetRow != null) {
          resolvedRows.add(
            ResolvedExerciseRow(
              exercise: existing,
              row: existing.sheetRow!,
              isNewRow: false,
            ),
          );
          continue;
        }
        final newRow = nextRow;
        nextRow += 1;
        structuralRequests.add(_insertRowsRequest(sheetGridId, newRow));
        resolvedRows.add(
          ResolvedExerciseRow(
            exercise: entry.exercise,
            row: newRow,
            isNewRow: true,
          ),
        );
      }

      return _finishVisitWritePlan(
        yearData: yearData,
        visit: visit,
        targetColumn: targetColumn,
        isNewColumn: isNewColumn,
        structuralRequests: structuralRequests,
        resolvedRows: resolvedRows,
      );
    }

    // Physical order of sections as they appear in the sheet, so inserted
    // rows land after the right group's existing rows.
    final orderedGroups = yearData.sectionHeaderRows.keys.toList()
      ..sort(
        (a, b) => yearData.sectionHeaderRows[a]!.compareTo(
          yearData.sectionHeaderRows[b]!,
        ),
      );

    // Working copy of "row to insert the next new exercise for group G
    // after" — starts at (last known exercise row in G) or (G's header
    // row) and is bumped as insertions are planned within this batch.
    final insertAfterRow = <MuscleGroup, int>{};
    for (final group in orderedGroups) {
      final exercises = yearData.muscleGroupSections[group] ?? const [];
      final lastRow = exercises.isEmpty
          ? yearData.sectionHeaderRows[group]!
          : exercises.map((e) => e.sheetRow!).reduce((a, b) => a > b ? a : b);
      insertAfterRow[group] = lastRow;
    }

    final newSectionHeaders = <NewSectionHeader>[];

    for (final entry in visit.entries) {
      final existing = yearData.findExercise(entry.exercise.name);
      if (existing != null && existing.sheetRow != null) {
        resolvedRows.add(
          ResolvedExerciseRow(
            exercise: existing,
            row: existing.sheetRow!,
            isNewRow: false,
          ),
        );
        continue;
      }

      final group = entry.exercise.muscleGroup;

      if (!orderedGroups.contains(group)) {
        // No section for this muscle exists anywhere in the tab yet — create
        // a brand-new header+exercise block appended at the tab's current
        // end, rather than guessing a "logical" position among existing
        // sections. Appending at the end means no other group's bookkeeping
        // needs to shift.
        final endOfTabRow = insertAfterRow.values.isEmpty
            ? 0
            : insertAfterRow.values.reduce((a, b) => a > b ? a : b);
        final headerRow = endOfTabRow + 1;
        final exerciseRow = endOfTabRow + 2;

        structuralRequests.add(
          _insertRowsRequest(sheetGridId, headerRow, count: 2),
        );
        newSectionHeaders.add((row: headerRow, group: group));
        orderedGroups.add(group);
        insertAfterRow[group] = exerciseRow;

        resolvedRows.add(
          ResolvedExerciseRow(
            exercise: entry.exercise,
            row: exerciseRow,
            isNewRow: true,
          ),
        );
        continue;
      }

      final insertionRow = insertAfterRow[group]!;
      final newRow = insertionRow + 1;

      structuralRequests.add(_insertRowsRequest(sheetGridId, newRow));

      resolvedRows.add(
        ResolvedExerciseRow(
          exercise: entry.exercise,
          row: newRow,
          isNewRow: true,
        ),
      );

      // Every subsequent insertion (any group) that targets a row at or
      // after `newRow` must shift down by one to account for this insert.
      insertAfterRow[group] = newRow;
      for (final other in orderedGroups) {
        if (other == group) continue;
        final current = insertAfterRow[other];
        if (current != null && current >= newRow) {
          insertAfterRow[other] = current + 1;
        }
      }
    }

    return _finishVisitWritePlan(
      yearData: yearData,
      visit: visit,
      targetColumn: targetColumn,
      isNewColumn: isNewColumn,
      structuralRequests: structuralRequests,
      resolvedRows: resolvedRows,
      newSectionHeaders: newSectionHeaders,
    );
  }

  Request _insertRowsRequest(int sheetGridId, int startIndex, {int count = 1}) {
    return Request(
      insertDimension: InsertDimensionRequest(
        range: DimensionRange(
          sheetId: sheetGridId,
          dimension: 'ROWS',
          startIndex: startIndex,
          endIndex: startIndex + count,
        ),
        inheritFromBefore: true,
      ),
    );
  }

  VisitWritePlan _finishVisitWritePlan({
    required YearSheetData yearData,
    required WorkoutVisit visit,
    required int targetColumn,
    required bool isNewColumn,
    required List<Request> structuralRequests,
    required List<ResolvedExerciseRow> resolvedRows,
    List<NewSectionHeader> newSectionHeaders = const [],
  }) {
    final cellValueRanges = <ValueRange>[];
    for (final header in newSectionHeaders) {
      cellValueRanges.add(
        ValueRange(
          range: "'${yearData.tabName}'!A${header.row + 1}",
          values: [
            [header.group.sheetHeader],
          ],
        ),
      );
    }
    if (isNewColumn) {
      cellValueRanges.add(
        ValueRange(
          range: "'${yearData.tabName}'!${columnLetter(targetColumn)}1",
          values: [
            [visit.isoWeek],
          ],
        ),
      );
    }
    for (final resolved in resolvedRows) {
      final entry = visit.entries.firstWhere(
        (e) =>
            e.exercise.name.toLowerCase() ==
            resolved.exercise.name.toLowerCase(),
      );
      if (resolved.isNewRow) {
        cellValueRanges.add(
          ValueRange(
            range: "'${yearData.tabName}'!A${resolved.row + 1}",
            values: [
              [resolved.exercise.name],
            ],
          ),
        );
      }
      // A second visit the same week for an exercise already written this
      // week (e.g. logged once from Push day, again from Legs day, for a
      // shared muscle like abdominals) averages with what's already
      // there, matching the sheet's own "cell = average weight for that
      // exercise that week" convention instead of silently overwriting it.
      final existingValue = resolved.isNewRow
          ? null
          : yearData.cellValues[CellKey(resolved.row, targetColumn)];
      final valueToWrite = existingValue == null
          ? entry.averageWeight
          : (existingValue + entry.averageWeight) / 2;
      cellValueRanges.add(
        ValueRange(
          range:
              "'${yearData.tabName}'!${columnLetter(targetColumn)}${resolved.row + 1}",
          values: [
            [valueToWrite],
          ],
        ),
      );
    }

    return VisitWritePlan(
      structuralRequests: structuralRequests,
      cellValueRanges: cellValueRanges,
      resolvedRows: resolvedRows,
      targetColumnIndex: targetColumn,
      isNewColumn: isNewColumn,
      newSectionHeaders: newSectionHeaders,
    );
  }

  /// Builds the metadata-tab row for [visit], including its rating if
  /// already set. Use [buildRatingUpdateRange] separately only when
  /// editing the rating of an already-saved visit.
  ValueRange buildMetaAppendRow({
    required String metaTabName,
    required WorkoutVisit visit,
  }) {
    final muscleGroups = visit.entries
        .map((e) => e.exercise.muscleGroup.sheetHeader)
        .toSet()
        .join(',');
    final exercises = visit.entries
        .map((e) {
          final hasFeedback = e.sets.any((s) => s.feedback != SetFeedback.none);
          final feedbackSegment = hasFeedback
              ? ':${e.sets.map((s) => s.feedback.sheetToken).join(',')}'
              : '';
          return '${e.exercise.name}:${e.targetRepRangeLow}-${e.targetRepRangeHigh}:'
              '${e.sets.map((s) => s.approxReps ? '~${s.reps}' : '${s.reps}').join(',')}:'
              '${e.sets.map((s) => s.weight).join(',')}'
              '$feedbackSegment';
        })
        .join('|');
    final dateOnly = formatDateOnly(visit.date);

    return ValueRange(
      range: "'$metaTabName'!A1",
      values: [
        [
          visit.visitId,
          dateOnly,
          visit.isoWeek,
          visit.isoYear,
          muscleGroups,
          exercises,
          visit.sourceTab ?? '',
          visit.rating ?? '',
          visit.ratingRelevance.sheetValue,
          visit.note ?? '',
          visit.workoutDayId ?? '',
        ],
      ],
    );
  }

  /// Writes [note] into a section-header row's week-column cell, matching
  /// how the user already writes notes by hand (e.g. on the "Push" row).
  /// Only meaningful for a [MatrixTabFormat.legacyGrouped] target tab — a
  /// flat tab has no header row to write into, so the meta-tab column J
  /// (see [buildNoteUpdateRange]) is the only place its note lives.
  ValueRange buildNoteWriteRange({
    required String tabName,
    required int headerRow,
    required int weekColumnIndex,
    required String note,
  }) {
    return ValueRange(
      range: "'$tabName'!${columnLetter(weekColumnIndex)}${headerRow + 1}",
      values: [
        [note],
      ],
    );
  }

  /// Targeted update for the note cell (column J, [kMetaTabColumns] index
  /// 9) of a specific metadata row — the canonical place a visit's note
  /// lives regardless of matrix-tab format.
  ValueRange buildNoteUpdateRange({
    required String metaTabName,
    required int metaRowIndex,
    required String note,
  }) {
    return ValueRange(
      range: "'$metaTabName'!J${metaRowIndex + 1}",
      values: [
        [note],
      ],
    );
  }

  /// Targeted update for the date columns (B:D — date/isoWeek/isoYear) of a
  /// specific metadata row, used when a visit's date changes without moving
  /// it to a different year's meta tab.
  ValueRange buildDateUpdateRange({
    required String metaTabName,
    required int metaRowIndex,
    required DateTime date,
    required int isoWeek,
    required int isoYear,
  }) {
    return ValueRange(
      range: "'$metaTabName'!B${metaRowIndex + 1}:D${metaRowIndex + 1}",
      values: [
        [formatDateOnly(date), isoWeek, isoYear],
      ],
    );
  }

  /// Rewrites the exercises cell (column F) of a specific metadata row —
  /// same `name:low-high` pipe-joined format as [buildMetaAppendRow], just
  /// in a new order. Used when the user reorders a previously logged
  /// visit's exercises.
  ValueRange buildExercisesOrderUpdateRange({
    required String metaTabName,
    required int metaRowIndex,
    required List<LoggedExerciseRepRange> exercises,
  }) {
    final value = exercises
        .map(
          (e) =>
              '${e.exerciseName}:${e.repRangeLow}-${e.repRangeHigh}:'
              '${_repsSegment(e)}:'
              '${e.actualWeights.join(',')}'
              '${_feedbackSegment(e)}',
        )
        .join('|');
    return ValueRange(
      range: "'$metaTabName'!F${metaRowIndex + 1}",
      values: [
        [value],
      ],
    );
  }

  /// Comma-joined actual reps for [e], each prefixed `~` where marked
  /// approximate.
  String _repsSegment(LoggedExerciseRepRange e) => [
    for (var i = 0; i < e.actualReps.length; i++)
      e.isApprox(i) ? '~${e.actualReps[i]}' : '${e.actualReps[i]}',
  ].join(',');

  /// Optional 5th colon-segment carrying per-set thumbs-up/down feedback —
  /// omitted entirely when no set in [e] has any feedback marked, so the
  /// common case stays the existing 4-segment format.
  String _feedbackSegment(LoggedExerciseRepRange e) {
    if (e.setFeedback.every((f) => f == SetFeedback.none)) return '';
    return ':${[
      for (var i = 0; i < e.actualReps.length; i++) e.feedbackFor(i).sheetToken,
    ].join(',')}';
  }

  /// Targeted update for the rating cell (column H, [kMetaTabColumns]
  /// index 7) of a specific metadata row.
  ValueRange buildRatingUpdateRange({
    required String metaTabName,
    required int metaRowIndex,
    required double rating,
  }) {
    return ValueRange(
      range: "'$metaTabName'!H${metaRowIndex + 1}",
      values: [
        [rating],
      ],
    );
  }

  /// Targeted update for the ratingRelevance cell (column I,
  /// [kMetaTabColumns] index 8) of a specific metadata row.
  ValueRange buildRatingRelevanceUpdateRange({
    required String metaTabName,
    required int metaRowIndex,
    required RatingRelevance value,
  }) {
    return ValueRange(
      range: "'$metaTabName'!I${metaRowIndex + 1}",
      values: [
        [value.sheetValue],
      ],
    );
  }

  ValueRange buildBodyWeightAppendRow({
    required DateTime date,
    required double weightKg,
  }) {
    return ValueRange(
      range: "'$kBodyWeightTabName'!A1",
      values: [
        [formatDateOnly(date), weightKg],
      ],
    );
  }

  /// One row appended to the sheet-backed `WorkoutDays` tab.
  ValueRange buildWorkoutDayAppendRow(WorkoutDayDef def) {
    return ValueRange(
      range: "'$kWorkoutDaysTabName'!A1",
      values: [
        [def.id, def.label, def.muscleGroups.map((g) => g.name).join(',')],
      ],
    );
  }

  /// Overwrites an existing `WorkoutDays` row's label + muscleGroups columns
  /// in place ([def.sheetRowIndex] must be set) — the id column is untouched.
  ValueRange buildWorkoutDayUpdateRange(WorkoutDayDef def) {
    final rowIndex = def.sheetRowIndex!;
    return ValueRange(
      range: "'$kWorkoutDaysTabName'!B${rowIndex + 1}:C${rowIndex + 1}",
      values: [
        [def.label, def.muscleGroups.map((g) => g.name).join(',')],
      ],
    );
  }

  /// Column-A-only seed rows for creating a new overflow tab that mirrors
  /// [previousTabData]'s layout — section headers + exercise names (in
  /// their existing physical order) for a [MatrixTabFormat.legacyGrouped]
  /// tab, or just the exercise names for a [MatrixTabFormat.flatV2] one.
  List<List<Object?>> buildColumnASeed(YearSheetData previousTabData) {
    if (previousTabData.format == MatrixTabFormat.flatV2) {
      return [
        ['exercise name'],
        for (final exercise in previousTabData.allExercises) [exercise.name],
      ];
    }

    final orderedGroups = previousTabData.sectionHeaderRows.keys.toList()
      ..sort(
        (a, b) => previousTabData.sectionHeaderRows[a]!.compareTo(
          previousTabData.sectionHeaderRows[b]!,
        ),
      );

    final rows = <List<Object?>>[
      ['exercise name'],
    ];
    for (final group in orderedGroups) {
      rows.add([group.sheetHeader]);
      for (final exercise
          in previousTabData.muscleGroupSections[group] ?? const []) {
        rows.add([exercise.name]);
      }
    }
    return rows;
  }
}
