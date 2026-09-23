import 'package:googleapis/sheets/v4.dart';

import '../../core/constants/muscle_groups.dart';
import '../../core/constants/sheet_layout.dart';
import '../../core/utils/result.dart';
import '../../models/body_weight_entry.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/exercise_unit.dart';
import '../../models/rating_relevance.dart';
import '../../models/workout_day_def.dart';
import '../../models/workout_visit.dart';
import '../../models/year_sheet_data.dart';
import 'sheet_parser.dart';
import 'sheet_writer.dart';

/// Everything read from the spreadsheet in one load, scoped to the year(s)
/// the app currently needs.
class SpreadsheetSnapshot {
  SpreadsheetSnapshot({
    required this.classifiedTabs,
    required this.gridIdsByTabName,
    required this.yearData,
    required this.bodyWeightEntries,
    this.exerciseMuscleInfo = const [],
    this.workoutDayDefs = const [],
    this.exerciseUnitsTable = const ExerciseUnitsTable(),
  });

  final ClassifiedTabs classifiedTabs;
  final Map<String, int> gridIdsByTabName;

  /// Loaded matrix-tab data for the years that were fetched, keyed by year.
  final Map<int, YearSheetData> yearData;
  final List<BodyWeightEntry> bodyWeightEntries;

  /// From the optional "Exercises" reference tab, if present.
  final List<ExerciseMuscleInfo> exerciseMuscleInfo;

  /// From the sheet-backed `WorkoutDays` tab, if present.
  final List<WorkoutDayDef> workoutDayDefs;

  /// From the "Exercises" tab's `Exercise`/`Unit` side-table, if present.
  final ExerciseUnitsTable exerciseUnitsTable;

  SpreadsheetSnapshot copyWith({
    List<ExerciseMuscleInfo>? exerciseMuscleInfo,
    List<WorkoutDayDef>? workoutDayDefs,
    ExerciseUnitsTable? exerciseUnitsTable,
  }) => SpreadsheetSnapshot(
    classifiedTabs: classifiedTabs,
    gridIdsByTabName: gridIdsByTabName,
    yearData: yearData,
    bodyWeightEntries: bodyWeightEntries,
    exerciseMuscleInfo: exerciseMuscleInfo ?? this.exerciseMuscleInfo,
    workoutDayDefs: workoutDayDefs ?? this.workoutDayDefs,
    exerciseUnitsTable: exerciseUnitsTable ?? this.exerciseUnitsTable,
  );
}

/// All reads and writes against the user's single spreadsheet. This is the
/// only place that talks to the Sheets API directly.
class SheetsRepository {
  SheetsRepository({
    required SheetsApi api,
    required String spreadsheetId,
    SheetParser? parser,
    SheetWriter? writer,
  }) : _api = api,
       _spreadsheetId = spreadsheetId,
       _parser = parser ?? const SheetParser(),
       _writer = writer ?? const SheetWriter();

  final SheetsApi _api;
  final String _spreadsheetId;
  final SheetParser _parser;
  final SheetWriter _writer;

  /// Loads tab structure plus the given [years]' matrix data and the
  /// BodyWeight tab. Pass `null` (the default) to auto-discover and load
  /// every year found in the spreadsheet, for full-history graphing.
  Future<Result<SpreadsheetSnapshot>> loadSnapshot({List<int>? years}) async {
    try {
      final meta = await _api.spreadsheets.get(
        _spreadsheetId,
        $fields: 'sheets.properties',
      );
      final sheets = meta.sheets ?? [];
      final tabNames = sheets
          .map((s) => s.properties?.title ?? '')
          .where((t) => t.isNotEmpty)
          .toList();
      final gridIdsByTabName = <String, int>{
        for (final s in sheets)
          if (s.properties?.title != null)
            s.properties!.title!: s.properties!.sheetId ?? 0,
      };

      final classified = _parser.classifyTabs(tabNames);
      final resolvedYears = years ?? classified.matrixTabsByYear.keys.toList();

      final rangesToFetch = <String>[];
      for (final year in resolvedYears) {
        final tab = classified.writableTabFor(year);
        if (tab != null) rangesToFetch.add("'$tab'!A1:CZ2000");
        final metaTab = classified.metaTabByYear[year];
        if (metaTab != null) rangesToFetch.add("'$metaTab'!A1:H2000");
      }
      if (classified.hasBodyWeightTab) {
        rangesToFetch.add("'$kBodyWeightTabName'!A1:B5000");
      }
      if (classified.hasExercisesTab) {
        rangesToFetch.add("'$kExercisesTabName'!A1:AZ2000");
      }
      if (classified.hasWorkoutDaysTab) {
        rangesToFetch.add("'$kWorkoutDaysTabName'!A1:C500");
      }

      final yearData = <int, YearSheetData>{};
      var bodyWeightEntries = <BodyWeightEntry>[];
      var exerciseMuscleInfo = <ExerciseMuscleInfo>[];
      var workoutDayDefs = <WorkoutDayDef>[];
      var exerciseUnitsTable = const ExerciseUnitsTable();

      if (rangesToFetch.isNotEmpty) {
        final batch = await _api.spreadsheets.values.batchGet(
          _spreadsheetId,
          ranges: rangesToFetch,
        );
        final valueRanges = batch.valueRanges ?? [];

        if (classified.hasExercisesTab) {
          final vr = _findValueRangeForTab(valueRanges, kExercisesTabName);
          exerciseMuscleInfo = _parser.parseExercisesTab(
            vr?.values ?? const [],
          );
          exerciseUnitsTable = _parser.parseExerciseUnitsTab(
            vr?.values ?? const [],
          );
        }

        if (classified.hasWorkoutDaysTab) {
          final vr = _findValueRangeForTab(valueRanges, kWorkoutDaysTabName);
          workoutDayDefs = _parser.parseWorkoutDaysTab(vr?.values ?? const []);
        }

        // First pass: parse each year using its own section headers, to
        // build a canonical exercise-name -> muscle-group map. Later years
        // win on name conflicts, since they represent the current routine.
        // Seeded from the "Exercises" reference tab first — the
        // authoritative source for current (2026+, flat-format) data,
        // since a flat tab has no section headers of its own to contribute.
        final rowsByYear = <int, List<List<Object?>>>{};
        final canonicalGroupByExerciseName = <String, MuscleGroup>{
          for (final info in exerciseMuscleInfo)
            info.exerciseName.toLowerCase(): info.muscleGroup,
        };
        final exerciseUnitOverrides = <String, ExerciseUnitAssignment>{
          for (final e in exerciseUnitsTable.assignments.entries)
            e.key: (unit: e.value.unit, customLabel: e.value.customLabel),
        };
        final sortedYears = resolvedYears.toList()..sort();
        for (final year in sortedYears) {
          final tab = classified.writableTabFor(year);
          if (tab == null) continue;
          final rows =
              _findValueRangeForTab(valueRanges, tab)?.values ?? const [];
          rowsByYear[year] = rows;
          final firstPass = _parser.parseMatrixTab(
            tabName: tab,
            year: year,
            rows: rows,
            exerciseUnitOverrides: exerciseUnitOverrides,
          );
          for (final exercise in firstPass.allExercises) {
            canonicalGroupByExerciseName[exercise.name.toLowerCase()] =
                exercise.muscleGroup;
          }
        }

        // Second pass: re-parse with the canonical map as a fallback, so a
        // year whose own section headers don't match (e.g. an old routine
        // with different day labels) still gets its exercises classified
        // by name instead of being dropped entirely.
        for (final year in resolvedYears) {
          final tab = classified.writableTabFor(year);
          if (tab == null) continue;
          final parsed = _parser.parseMatrixTab(
            tabName: tab,
            year: year,
            rows: rowsByYear[year] ?? const [],
            exerciseGroupOverrides: canonicalGroupByExerciseName,
            exerciseUnitOverrides: exerciseUnitOverrides,
          );

          final metaTab = classified.metaTabByYear[year];
          final metaRows = metaTab == null
              ? <MetaRow>[]
              : _parser.parseMetaTab(
                  _findValueRangeForTab(valueRanges, metaTab)?.values ??
                      const [],
                );

          yearData[year] = YearSheetData(
            year: parsed.year,
            tabName: parsed.tabName,
            format: parsed.format,
            muscleGroupSections: parsed.muscleGroupSections,
            weekColumns: parsed.weekColumns,
            cellValues: parsed.cellValues,
            sectionHeaderRows: parsed.sectionHeaderRows,
            primaryGroupHeaderRow: parsed.primaryGroupHeaderRow,
            weekNotes: parsed.weekNotes,
            weekNotesByGroup: parsed.weekNotesByGroup,
            metaRows: metaRows,
          );
        }

        if (classified.hasBodyWeightTab) {
          final vr = _findValueRangeForTab(valueRanges, kBodyWeightTabName);
          bodyWeightEntries = _parser.parseBodyWeightTab(
            vr?.values ?? const [],
          );
        }
      }

      return Result.ok(
        SpreadsheetSnapshot(
          classifiedTabs: classified,
          gridIdsByTabName: gridIdsByTabName,
          yearData: yearData,
          bodyWeightEntries: bodyWeightEntries,
          exerciseMuscleInfo: exerciseMuscleInfo,
          workoutDayDefs: workoutDayDefs,
          exerciseUnitsTable: exerciseUnitsTable,
        ),
      );
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  ValueRange? _findValueRangeForTab(List<ValueRange> ranges, String tab) {
    for (final vr in ranges) {
      final range = vr.range ?? '';
      // range looks like "'2026'!A1:BA400" or "2026!A1:BA400".
      if (range.startsWith("'$tab'!") || range.startsWith('$tab!')) {
        return vr;
      }
    }
    return null;
  }

  /// Creates the base `<year>` matrix tab (flat layout — just a header row,
  /// no muscle-group section headers, matching [MatrixTabFormat.flatV2])
  /// and its `<year>_meta` tab. Call only when the matrix tab itself
  /// doesn't exist yet (a brand-new year) — for an existing year (e.g. one
  /// the user already hand-tracked) that's just missing its metadata tab,
  /// use [ensureMetaTabForYear] instead so the user's existing matrix data
  /// is never touched/reseeded.
  Future<Result<void>> ensureTabsForNewYear(int year) async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              addSheet: AddSheetRequest(
                properties: SheetProperties(title: '$year'),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );

      await _api.spreadsheets.values.update(
        ValueRange(
          range: "'$year'!A1",
          values: [
            ['exercise name'],
          ],
        ),
        _spreadsheetId,
        "'$year'!A1",
        valueInputOption: 'USER_ENTERED',
      );

      final metaResult = await ensureMetaTabForYear(year);
      if (metaResult.isErr) return metaResult;

      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Creates the hidden `<year>_meta` tab (with its header row) if it
  /// doesn't already exist. Safe to call for a year whose matrix tab
  /// already existed before this app touched it.
  Future<Result<void>> ensureMetaTabForYear(int year) async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              addSheet: AddSheetRequest(
                properties: SheetProperties(
                  title: '${year}_meta',
                  hidden: true,
                ),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      await _api.spreadsheets.values.update(
        ValueRange(range: "'${year}_meta'!A1", values: [kMetaTabColumns]),
        _spreadsheetId,
        "'${year}_meta'!A1",
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  Future<Result<void>> ensureBodyWeightTab() async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              addSheet: AddSheetRequest(
                properties: SheetProperties(title: kBodyWeightTabName),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      await _api.spreadsheets.values.update(
        ValueRange(
          range: "'$kBodyWeightTabName'!A1",
          values: [kBodyWeightTabColumns],
        ),
        _spreadsheetId,
        "'$kBodyWeightTabName'!A1",
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  Future<Result<void>> ensureWorkoutDaysTab() async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              addSheet: AddSheetRequest(
                properties: SheetProperties(title: kWorkoutDaysTabName),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      await _api.spreadsheets.values.update(
        ValueRange(
          range: "'$kWorkoutDaysTabName'!A1",
          values: [kWorkoutDaysTabColumns],
        ),
        _spreadsheetId,
        "'$kWorkoutDaysTabName'!A1",
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Creates the "Exercises" reference tab when it doesn't exist yet — the
  /// tab is documented as optional, so nothing creates it automatically
  /// until the first write (a non-kg unit) actually needs it. No header row
  /// is written here: [setExerciseUnit] already creates the `Exercise`/
  /// `Unit` header pair itself once the tab exists.
  Future<Result<void>> ensureExercisesTab() async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              addSheet: AddSheetRequest(
                properties: SheetProperties(title: kExercisesTabName),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  Future<Result<void>> appendWorkoutDay(WorkoutDayDef def) async {
    try {
      final row = _writer.buildWorkoutDayAppendRow(def);
      await _api.spreadsheets.values.append(
        row,
        _spreadsheetId,
        "'$kWorkoutDaysTabName'!A1",
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Overwrites an existing `WorkoutDays` row's label + muscleGroups
  /// in place (id column untouched) — safe to call even if a durable retry
  /// races with a later edit, since it always writes the row's full current
  /// desired state rather than a delta. Requires [def.sheetRowIndex].
  Future<Result<void>> updateWorkoutDay(WorkoutDayDef def) async {
    if (def.sheetRowIndex == null) {
      return Result.err(StateError('WorkoutDayDef has no sheetRowIndex yet.'));
    }
    try {
      final range = _writer.buildWorkoutDayUpdateRange(def);
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Deletes a workout day's row from the `WorkoutDays` tab by its known
  /// row index — fire-and-forget only (not offline-queued), since a queued
  /// delete replayed later against a since-shifted row layout is unsafe.
  Future<Result<void>> deleteWorkoutDay({
    required int rowIndex,
    required int workoutDaysGridId,
  }) async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              deleteDimension: DeleteDimensionRequest(
                range: DimensionRange(
                  sheetId: workoutDaysGridId,
                  dimension: 'ROWS',
                  startIndex: rowIndex,
                  endIndex: rowIndex + 1,
                ),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Creates the next overflow tab (`<year>_2`, `<year>_3`, ...) mirroring
  /// [previousTabData]'s column-A layout, when the current matrix tab for
  /// that year is full ([kMaxWeekColumnsPerTab] week columns).
  Future<Result<String>> createOverflowTab({
    required int year,
    required int overflowIndex,
    required YearSheetData previousTabData,
  }) async {
    try {
      final tabName = '${year}_$overflowIndex';
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              addSheet: AddSheetRequest(
                properties: SheetProperties(title: tabName),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      final seedRows = _writer.buildColumnASeed(previousTabData);
      await _api.spreadsheets.values.update(
        ValueRange(range: "'$tabName'!A1", values: seedRows),
        _spreadsheetId,
        "'$tabName'!A1",
        valueInputOption: 'USER_ENTERED',
      );
      return Result.ok(tabName);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Writes a full workout visit: cell data into the year matrix tab, and
  /// an appended row into that year's metadata tab. Assumes tabs already
  /// exist (call [ensureTabsForNewYear]/[createOverflowTab] first if
  /// needed) and [yearData]/[sheetGridId] reflect the tab being written to.
  ///
  /// On success, returns the 0-based row index of the appended metadata
  /// row (needed to write the rating back to the right row afterwards).
  Future<Result<int>> writeVisit({
    required YearSheetData yearData,
    required int sheetGridId,
    required WorkoutVisit visit,
    required String metaTabName,
  }) async {
    final plan = _writer.planVisitWrite(
      yearData: yearData,
      visit: visit,
      sheetGridId: sheetGridId,
    );
    final planResult = await applyVisitWritePlan(plan);
    if (planResult.isErr) {
      return Result.err(
        (planResult as Err<void>).error,
        planResult.stackTrace,
      );
    }
    return appendMetaRow(metaTabName: metaTabName, visit: visit);
  }

  Future<Result<void>> writeNote({
    required String matrixTabName,
    required int headerRow,
    required int weekColumnIndex,
    required String note,
  }) async {
    try {
      final range = _writer.buildNoteWriteRange(
        tabName: matrixTabName,
        headerRow: headerRow,
        weekColumnIndex: weekColumnIndex,
        note: note,
      );
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Writes [note] into the meta tab's own column (J) for [metaRowIndex] —
  /// the canonical per-visit note location, used for every visit regardless
  /// of matrix-tab format.
  Future<Result<void>> updateVisitNote({
    required String metaTabName,
    required int metaRowIndex,
    required String note,
  }) async {
    try {
      final range = _writer.buildNoteUpdateRange(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        note: note,
      );
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  Future<Result<void>> updateRatingRelevance({
    required String metaTabName,
    required int metaRowIndex,
    required RatingRelevance value,
  }) async {
    try {
      final range = _writer.buildRatingRelevanceUpdateRange(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        value: value,
      );
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Updates just the date/isoWeek/isoYear columns of a metadata row —
  /// used when a visit's date change stays within the same year's meta tab
  /// (the matrix-cell re-filing itself is handled separately by the
  /// caller, since it spans potentially multiple exercise rows/tabs).
  Future<Result<void>> updateVisitDateInPlace({
    required String metaTabName,
    required int metaRowIndex,
    required DateTime date,
    required int isoWeek,
    required int isoYear,
  }) async {
    try {
      final range = _writer.buildDateUpdateRange(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        date: date,
        isoWeek: isoWeek,
        isoYear: isoYear,
      );
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Appends a full metadata row built from [visit] to [metaTabName] and
  /// returns its 0-based row index — used when a date change moves a visit
  /// into a different year's meta tab (append-before-delete: the caller
  /// deletes the old row only after this succeeds).
  Future<Result<int>> appendMetaRow({
    required String metaTabName,
    required WorkoutVisit visit,
  }) async {
    try {
      final metaRow = _writer.buildMetaAppendRow(
        metaTabName: metaTabName,
        visit: visit,
      );
      final appendResponse = await _api.spreadsheets.values.append(
        metaRow,
        _spreadsheetId,
        "'$metaTabName'!A1",
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
      final updatedRange = appendResponse.updates?.updatedRange;
      final rowIndex = updatedRange == null
          ? null
          : _parseFirstRowIndex(updatedRange);
      if (rowIndex == null) {
        return Result.err(
          StateError(
            'Could not determine metadata row index from append response '
            '(updatedRange: $updatedRange).',
          ),
        );
      }
      return Result.ok(rowIndex);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Deletes one row from a year's meta tab by index — used to remove the
  /// old row after a cross-year date change has appended its replacement.
  Future<Result<void>> deleteMetaRow({
    required int metaTabGridId,
    required int metaRowIndex,
  }) async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              deleteDimension: DeleteDimensionRequest(
                range: DimensionRange(
                  sheetId: metaTabGridId,
                  dimension: 'ROWS',
                  startIndex: metaRowIndex,
                  endIndex: metaRowIndex + 1,
                ),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Writes/blanks a single matrix cell directly — used by the date-change
  /// flow to recompute (or clear) the (exercise row, week column) cell a
  /// visit is leaving, and to apply structural row-insert requests when
  /// moving a visit's exercises into a tab that doesn't have them yet.
  Future<Result<void>> writeMatrixCell({
    required String matrixTabName,
    required int rowIndex,
    required int columnIndex,
    required Object value,
  }) async {
    try {
      await _api.spreadsheets.values.update(
        ValueRange(
          range:
              "'$matrixTabName'!${columnLetter(columnIndex)}${rowIndex + 1}",
          values: [
            [value],
          ],
        ),
        _spreadsheetId,
        "'$matrixTabName'!${columnLetter(columnIndex)}${rowIndex + 1}",
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Applies a [VisitWritePlan]'s structural row-inserts + cell writes
  /// directly — used by the date-change flow to land a visit's cell data
  /// in a new tab, reusing the exact same row-resolution logic a normal
  /// [writeVisit] uses.
  Future<Result<void>> applyVisitWritePlan(VisitWritePlan plan) async {
    try {
      if (plan.structuralRequests.isNotEmpty) {
        await _api.spreadsheets.batchUpdate(
          BatchUpdateSpreadsheetRequest(requests: plan.structuralRequests),
          _spreadsheetId,
        );
      }
      await _api.spreadsheets.values.batchUpdate(
        BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: plan.cellValueRanges,
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Parses the 0-based row index from an A1 range like
  /// `'2026_meta'!A15:H15` -> 14.
  int? _parseFirstRowIndex(String a1Range) {
    final match = RegExp(r'![A-Z]+(\d+)').firstMatch(a1Range);
    if (match == null) return null;
    final oneBasedRow = int.tryParse(match.group(1)!);
    return oneBasedRow == null ? null : oneBasedRow - 1;
  }

  Future<Result<void>> updateRating({
    required String metaTabName,
    required int metaRowIndex,
    required double rating,
  }) async {
    try {
      final range = _writer.buildRatingUpdateRange(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        rating: rating,
      );
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Rewrites the exercise order of a previously logged visit.
  Future<Result<void>> updateVisitExerciseOrder({
    required String metaTabName,
    required int metaRowIndex,
    required List<LoggedExerciseRepRange> exercises,
  }) async {
    try {
      final range = _writer.buildExercisesOrderUpdateRange(
        metaTabName: metaTabName,
        metaRowIndex: metaRowIndex,
        exercises: exercises,
      );
      await _api.spreadsheets.values.update(
        range,
        _spreadsheetId,
        range.range!,
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Appends [exerciseName] to the bottom of an existing muscle column in
  /// the "Exercises" reference tab (below whatever's already listed there) —
  /// used when the user states a muscle for a newly-added exercise. Only
  /// works for a muscle column that already exists; doesn't create new
  /// columns.
  Future<Result<void>> appendExerciseToMuscleColumn({
    required int columnIndex,
    required String exerciseName,
  }) async {
    try {
      final columnLetter = _columnLetter(columnIndex);
      await _api.spreadsheets.values.append(
        ValueRange(
          values: [
            [exerciseName],
          ],
        ),
        _spreadsheetId,
        "'$kExercisesTabName'!${columnLetter}1",
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Sets [exerciseName]'s unit in the "Exercises" tab's `Exercise`/`Unit`
  /// side-table: updates its row in place if it already has one (per
  /// [currentTable]), otherwise adds a new row — and also adds an explicit
  /// `kg` row for each of [backfillNames] that has none — creating the
  /// `Exercise`/`Unit` header pair first if the table doesn't exist yet on
  /// this sheet at all. [currentTable] must come from the snapshot this
  /// call is based on (row indices must be exact).
  Future<Result<void>> setExerciseUnit({
    required String exerciseName,
    required ExerciseUnit unit,
    String? customLabel,
    required ExerciseUnitsTable currentTable,
    List<String> backfillNames = const [],
  }) async {
    try {
      var exerciseCol = currentTable.exerciseColumnIndex;
      var unitCol = currentTable.unitColumnIndex;
      if (exerciseCol == null || unitCol == null) {
        exerciseCol = currentTable.headerRowLength;
        unitCol = exerciseCol + 1;
        await _api.spreadsheets.values.update(
          ValueRange(
            values: [
              ['Exercise', 'Unit'],
            ],
          ),
          _spreadsheetId,
          "'$kExercisesTabName'!${_columnLetter(exerciseCol)}1:${_columnLetter(unitCol)}1",
          valueInputOption: 'USER_ENTERED',
        );
      }

      final token = exerciseUnitToSheetToken(unit, customUnitLabel: customLabel);
      final existingRow =
          currentTable.assignments[exerciseName.toLowerCase()]?.rowIndex;
      if (existingRow != null) {
        await _api.spreadsheets.values.update(
          ValueRange(
            values: [
              [token],
            ],
          ),
          _spreadsheetId,
          "'$kExercisesTabName'!${_columnLetter(unitCol)}${existingRow + 1}",
          valueInputOption: 'USER_ENTERED',
        );
      }

      // New rows (this exercise if it has none yet, plus an explicit `kg`
      // row for every other known exercise that has none) go in one
      // contiguous block right below the last existing row of the table.
      // Written to an explicit range rather than `values.append`, whose
      // table-detection can land the rows far from the header when other
      // columns of the tab are filled.
      final seen = {exerciseName.toLowerCase()};
      final newRows = <List<Object?>>[
        if (existingRow == null) [exerciseName, token],
        for (final name in backfillNames)
          if (seen.add(name.toLowerCase()) &&
              !currentTable.assignments.containsKey(name.toLowerCase()))
            [name, ExerciseUnit.kg.sheetToken],
      ];
      if (newRows.isNotEmpty) {
        final firstRow = currentTable.assignments.values
                .map((r) => r.rowIndex)
                .fold(0, (a, b) => a > b ? a : b) +
            1;
        final startRow = firstRow + 1;
        final endRow = startRow + newRows.length - 1;
        final startCol = _columnLetter(exerciseCol);
        final endCol = _columnLetter(unitCol);
        await _api.spreadsheets.values.update(
          ValueRange(values: newRows),
          _spreadsheetId,
          "'$kExercisesTabName'!$startCol$startRow:$endCol$endRow",
          valueInputOption: 'USER_ENTERED',
        );
      }
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// 0-based column index -> spreadsheet column letters (0 -> A, 25 -> Z,
  /// 26 -> AA, ...).
  static String _columnLetter(int index) {
    var i = index;
    var letters = '';
    while (i >= 0) {
      letters = String.fromCharCode(65 + (i % 26)) + letters;
      i = (i ~/ 26) - 1;
    }
    return letters;
  }

  Future<Result<void>> appendBodyWeight({
    required DateTime date,
    required double weightKg,
  }) async {
    try {
      final row = _writer.buildBodyWeightAppendRow(
        date: date,
        weightKg: weightKg,
      );
      await _api.spreadsheets.values.append(
        row,
        _spreadsheetId,
        "'$kBodyWeightTabName'!A1",
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Overwrites the weight cell for each (exercise row, week column) pair
  /// already resolved by the caller — used when editing a previously
  /// logged visit's weights.
  Future<Result<void>> updateVisitWeights({
    required String matrixTabName,
    required int weekColumnIndex,
    required Map<int, double> weightByExerciseRow,
  }) async {
    if (weightByExerciseRow.isEmpty) return const Result.ok(null);
    try {
      final ranges = [
        for (final entry in weightByExerciseRow.entries)
          ValueRange(
            range:
                "'$matrixTabName'!${columnLetter(weekColumnIndex)}${entry.key + 1}",
            values: [
              [entry.value],
            ],
          ),
      ];
      await _api.spreadsheets.values.batchUpdate(
        BatchUpdateValuesRequest(
          valueInputOption: 'USER_ENTERED',
          data: ranges,
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  /// Deletes a logged visit entirely: blanks the matrix cells for the rows
  /// it wrote to (at its week column) and removes its row from the
  /// metadata tab. [metaTabGridId] is the metadata tab's own grid ID
  /// (different from the matrix tab's), needed for the row deletion.
  Future<Result<void>> deleteVisit({
    required String matrixTabName,
    required int weekColumnIndex,
    required List<int> exerciseRowsToClear,
    required String metaTabName,
    required int metaTabGridId,
    required int metaRowIndex,
  }) async {
    try {
      if (exerciseRowsToClear.isNotEmpty) {
        final clearRanges = [
          for (final row in exerciseRowsToClear)
            ValueRange(
              range:
                  "'$matrixTabName'!${columnLetter(weekColumnIndex)}${row + 1}",
              values: [
                [''],
              ],
            ),
        ];
        await _api.spreadsheets.values.batchUpdate(
          BatchUpdateValuesRequest(
            valueInputOption: 'USER_ENTERED',
            data: clearRanges,
          ),
          _spreadsheetId,
        );
      }

      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              deleteDimension: DeleteDimensionRequest(
                range: DimensionRange(
                  sheetId: metaTabGridId,
                  dimension: 'ROWS',
                  startIndex: metaRowIndex,
                  endIndex: metaRowIndex + 1,
                ),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  Future<Result<void>> updateBodyWeightEntry({
    required int rowIndex,
    required DateTime date,
    required double weightKg,
  }) async {
    try {
      await _api.spreadsheets.values.update(
        ValueRange(
          values: [
            [formatDateOnly(date), weightKg],
          ],
        ),
        _spreadsheetId,
        "'$kBodyWeightTabName'!A${rowIndex + 1}:B${rowIndex + 1}",
        valueInputOption: 'USER_ENTERED',
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }

  Future<Result<void>> deleteBodyWeightEntry({
    required int rowIndex,
    required int bodyWeightGridId,
  }) async {
    try {
      await _api.spreadsheets.batchUpdate(
        BatchUpdateSpreadsheetRequest(
          requests: [
            Request(
              deleteDimension: DeleteDimensionRequest(
                range: DimensionRange(
                  sheetId: bodyWeightGridId,
                  dimension: 'ROWS',
                  startIndex: rowIndex,
                  endIndex: rowIndex + 1,
                ),
              ),
            ),
          ],
        ),
        _spreadsheetId,
      );
      return const Result.ok(null);
    } catch (e, st) {
      return Result.err(e, st);
    }
  }
}
