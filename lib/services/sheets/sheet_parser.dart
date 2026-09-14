import '../../core/constants/muscle_groups.dart';
import '../../core/constants/sheet_layout.dart';
import '../../models/body_weight_entry.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/rating_relevance.dart';
import '../../models/set_feedback.dart';
import '../../models/workout_day_def.dart';
import '../../models/year_sheet_data.dart';

/// Classification of a spreadsheet's tabs into the roles the app cares
/// about. See [SheetLayout] docs for the naming conventions.
class ClassifiedTabs {
  ClassifiedTabs({
    required this.matrixTabsByYear,
    required this.metaTabByYear,
    required this.hasBodyWeightTab,
    required this.hasExercisesTab,
    required this.hasWorkoutDaysTab,
  });

  /// year -> matrix tab names, sorted so the base `<year>` tab comes first
  /// and overflow tabs (`<year>_2`, `<year>_3`, ...) follow in order.
  final Map<int, List<String>> matrixTabsByYear;

  /// year -> `<year>_meta` tab name, if it exists yet.
  final Map<int, String> metaTabByYear;

  final bool hasBodyWeightTab;
  final bool hasExercisesTab;
  final bool hasWorkoutDaysTab;

  /// The currently-writable matrix tab name for [year] (last in sorted
  /// order), or null if no tab exists yet for that year.
  String? writableTabFor(int year) {
    final tabs = matrixTabsByYear[year];
    if (tabs == null || tabs.isEmpty) return null;
    return tabs.last;
  }
}

class SheetParser {
  const SheetParser();

  ClassifiedTabs classifyTabs(List<String> tabNames) {
    final matrixTabsByYear = <int, List<String>>{};
    final metaTabByYear = <int, String>{};
    var hasBodyWeightTab = false;
    var hasExercisesTab = false;
    var hasWorkoutDaysTab = false;

    for (final name in tabNames) {
      if (name == kBodyWeightTabName) {
        hasBodyWeightTab = true;
        continue;
      }
      if (name == kExercisesTabName) {
        hasExercisesTab = true;
        continue;
      }
      if (name == kWorkoutDaysTabName) {
        hasWorkoutDaysTab = true;
        continue;
      }
      final metaMatch = kYearMetaTabPattern.firstMatch(name);
      if (metaMatch != null) {
        metaTabByYear[int.parse(metaMatch.group(1)!)] = name;
        continue;
      }
      final overflowMatch = kYearOverflowTabPattern.firstMatch(name);
      if (overflowMatch != null) {
        final year = int.parse(overflowMatch.group(1)!);
        (matrixTabsByYear[year] ??= []).add(name);
        continue;
      }
      final yearMatch = kYearTabPattern.firstMatch(name);
      if (yearMatch != null) {
        final year = int.parse(yearMatch.group(1)!);
        (matrixTabsByYear[year] ??= []).add(name);
      }
    }

    for (final tabs in matrixTabsByYear.values) {
      tabs.sort((a, b) => _overflowIndex(a).compareTo(_overflowIndex(b)));
    }

    return ClassifiedTabs(
      matrixTabsByYear: matrixTabsByYear,
      metaTabByYear: metaTabByYear,
      hasBodyWeightTab: hasBodyWeightTab,
      hasExercisesTab: hasExercisesTab,
      hasWorkoutDaysTab: hasWorkoutDaysTab,
    );
  }

  int _overflowIndex(String tabName) {
    final match = kYearOverflowTabPattern.firstMatch(tabName);
    if (match == null) return 1; // base "<year>" tab sorts first.
    return int.parse(match.group(2)!);
  }

  /// A [MatrixTabFormat.legacyGrouped] tab always has at least one legacy
  /// section-header row in column A (it was seeded that way). A
  /// [MatrixTabFormat.currentGrouped] tab (the user's own hand-maintained
  /// 2026+ layout) has at least one current-muscle section-header row
  /// instead, and no legacy ones. A [MatrixTabFormat.flatV2] tab (including
  /// a brand-new/empty one) has neither, since it has no header rows at
  /// all. Legacy takes priority so a hypothetical mixed tab still classifies
  /// as legacy, matching the pre-existing guarantee that legacy tabs are
  /// never mis-detected.
  MatrixTabFormat detectMatrixFormat(List<List<Object?>> rows) {
    var sawCurrentHeader = false;
    for (var row = 1; row < rows.length; row++) {
      final r = rows[row];
      if (r.isEmpty) continue;
      final colA = _asString(r[0]);
      if (colA == null || colA.trim().isEmpty) continue;
      final currentMatch = currentMuscleFromSheetHeader(colA);
      if (currentMatch != null) {
        // A handful of current muscle names (see ambiguousLegacyMuscleGroups,
        // e.g. "triceps"/"biceps") are textually identical to a legacy
        // header — that alone must not force a legacyGrouped verdict, or a
        // hand-maintained current-format tab that happens to use one of
        // these names gets misdetected. Keep scanning: a later genuinely
        // unambiguous legacy header can still flip this.
        sawCurrentHeader = true;
        continue;
      }
      if (muscleGroupFromSheetHeader(colA) != null) {
        return MatrixTabFormat.legacyGrouped;
      }
    }
    return sawCurrentHeader
        ? MatrixTabFormat.currentGrouped
        : MatrixTabFormat.flatV2;
  }

  /// Parses one matrix tab's raw grid ([rows], as returned by
  /// `values.get`/`batchGet`, row-major) into a [YearSheetData].
  YearSheetData parseMatrixTab({
    required String tabName,
    required int year,
    required List<List<Object?>> rows,
    Map<String, MuscleGroup>? exerciseGroupOverrides,
  }) {
    final format = detectMatrixFormat(rows);
    final weekColumns = <int, int>{};
    final muscleGroupSections = <MuscleGroup, List<Exercise>>{
      for (final g in MuscleGroup.values) g: [],
    };
    final cellValues = <CellKey, double>{};
    final sectionHeaderRows = <MuscleGroup, int>{};
    final primaryGroupHeaderRow = <MuscleGroup, int>{};
    final weekNotes = <int, String>{};
    final weekNotesByGroup = <MuscleGroup, Map<int, String>>{};

    if (rows.isEmpty) {
      return YearSheetData(
        year: year,
        tabName: tabName,
        format: format,
        muscleGroupSections: muscleGroupSections,
        weekColumns: weekColumns,
        cellValues: cellValues,
        sectionHeaderRows: sectionHeaderRows,
        primaryGroupHeaderRow: primaryGroupHeaderRow,
        weekNotes: weekNotes,
        weekNotesByGroup: weekNotesByGroup,
      );
    }

    final headerRow = rows.first;
    for (var col = 1; col < headerRow.length; col++) {
      final weekNumber = _asInt(headerRow[col]);
      if (weekNumber != null) weekColumns[weekNumber] = col;
    }
    final weekByColumn = {for (final e in weekColumns.entries) e.value: e.key};

    if (format == MatrixTabFormat.flatV2) {
      for (var row = 1; row < rows.length; row++) {
        final rowValues = rows[row];
        if (rowValues.isEmpty) continue;
        final colA = _asString(rowValues.isNotEmpty ? rowValues[0] : null);
        if (colA == null || colA.trim().isEmpty) continue;

        final override = exerciseGroupOverrides?[colA.trim().toLowerCase()];
        final resolvedGroup = override ?? kCurrentMuscleGroups.first;
        final exercise = Exercise(
          name: colA.trim(),
          muscleGroup: resolvedGroup,
          sheetRow: row,
          muscleGroupKnown: override != null,
        );
        muscleGroupSections[resolvedGroup]!.add(exercise);

        for (var col = 1; col < rowValues.length; col++) {
          final weight = _asDouble(rowValues[col]);
          if (weight != null && weight != 0) {
            cellValues[CellKey(row, col)] = weight;
          }
        }
      }

      return YearSheetData(
        year: year,
        tabName: tabName,
        format: format,
        muscleGroupSections: muscleGroupSections,
        weekColumns: weekColumns,
        cellValues: cellValues,
        sectionHeaderRows: sectionHeaderRows,
        primaryGroupHeaderRow: primaryGroupHeaderRow,
        weekNotes: weekNotes,
        weekNotesByGroup: weekNotesByGroup,
      );
    }

    MuscleGroup? currentGroup;
    for (var row = 1; row < rows.length; row++) {
      final rowValues = rows[row];
      if (rowValues.isEmpty) continue;
      final colA = _asString(rowValues.isNotEmpty ? rowValues[0] : null);
      if (colA == null || colA.trim().isEmpty) continue;

      final headerGroup = sheetHeaderMuscleGroupForFormat(colA, format);
      if (headerGroup != null) {
        currentGroup = headerGroup;
        sectionHeaderRows[headerGroup] = row;
        if (colA.trim().toLowerCase() ==
            headerGroup.sheetHeader.toLowerCase()) {
          primaryGroupHeaderRow[headerGroup] = row;
        }
        for (var col = 1; col < rowValues.length; col++) {
          final week = weekByColumn[col];
          if (week == null) continue;
          final text = _asString(rowValues[col])?.trim();
          if (text == null || text.isEmpty) continue;
          if (_asDouble(text) != null) continue; // a stray number, not a note.
          weekNotes[week] = weekNotes.containsKey(week)
              ? '${weekNotes[week]}; $text'
              : text;
          final groupNotes = weekNotesByGroup.putIfAbsent(
            headerGroup,
            () => {},
          );
          groupNotes[week] = groupNotes.containsKey(week)
              ? '${groupNotes[week]}; $text'
              : text;
        }
        continue;
      }

      // Prefer the canonical (cross-year) muscle group for this exercise
      // name when one is known, so a year whose own section headers don't
      // match [MuscleGroup.sheetHeader] (e.g. an old, differently-labeled
      // routine) still gets its exercises classified correctly.
      final resolvedGroup =
          exerciseGroupOverrides?[colA.trim().toLowerCase()] ?? currentGroup;
      if (resolvedGroup == null) continue; // stray row before any header.
      final exercise = Exercise(
        name: colA.trim(),
        muscleGroup: resolvedGroup,
        sheetRow: row,
      );
      muscleGroupSections[resolvedGroup]!.add(exercise);

      for (var col = 1; col < rowValues.length; col++) {
        final weight = _asDouble(rowValues[col]);
        // A "0" cell is never a real logged weight in this sheet — treat it
        // as an unfilled placeholder rather than actual data, otherwise
        // blank-but-zero-filled cells masquerade as a phantom first entry.
        if (weight != null && weight != 0) {
          cellValues[CellKey(row, col)] = weight;
        }
      }
    }

    return YearSheetData(
      year: year,
      tabName: tabName,
      format: format,
      muscleGroupSections: muscleGroupSections,
      weekColumns: weekColumns,
      cellValues: cellValues,
      sectionHeaderRows: sectionHeaderRows,
      primaryGroupHeaderRow: primaryGroupHeaderRow,
      weekNotes: weekNotes,
      weekNotesByGroup: weekNotesByGroup,
    );
  }

  List<MetaRow> parseMetaTab(List<List<Object?>> rows) {
    final result = <MetaRow>[];
    for (var row = 1; row < rows.length; row++) {
      final r = rows[row];
      if (r.isEmpty) continue;
      String cell(int i) => i < r.length ? (_asString(r[i]) ?? '') : '';

      final visitId = cell(0);
      if (visitId.isEmpty) continue;
      final date = DateTime.tryParse(cell(1));
      final isoWeek = int.tryParse(cell(2));
      final isoYear = int.tryParse(cell(3));
      if (date == null || isoWeek == null || isoYear == null) continue;

      result.add(
        MetaRow(
          rowIndex: row,
          visitId: visitId,
          date: date,
          isoWeek: isoWeek,
          isoYear: isoYear,
          muscleGroups: _splitCsv(cell(4)),
          exercises: _parseExercisesCell(cell(5)),
          sourceTab: cell(6),
          rating: double.tryParse(cell(7)),
          ratingRelevance: ratingRelevanceFromSheetValue(cell(8)),
          note: cell(9).isEmpty ? null : cell(9),
          workoutDayId: cell(10).isEmpty ? null : cell(10),
        ),
      );
    }
    return result;
  }

  /// Parses the "Exercises" reference tab (2026-onward layout): one column
  /// per current [MuscleGroup], header row = that muscle's exact name,
  /// exercise names listed downward under each column starting row 2.
  List<ExerciseMuscleInfo> parseExercisesTab(List<List<Object?>> rows) {
    if (rows.isEmpty) return const [];
    final header = rows.first;

    final groupByColumn = <int, MuscleGroup>{};
    for (var col = 0; col < header.length; col++) {
      final text = _asString(header[col])?.trim();
      if (text == null || text.isEmpty) continue;
      final group = currentMuscleFromSheetHeader(text);
      if (group != null) groupByColumn[col] = group;
    }

    final result = <ExerciseMuscleInfo>[];
    for (final entry in groupByColumn.entries) {
      final col = entry.key;
      for (var row = 1; row < rows.length; row++) {
        final rowValues = rows[row];
        if (col >= rowValues.length) continue;
        final name = _asString(rowValues[col])?.trim();
        if (name == null || name.isEmpty) continue;
        result.add(
          ExerciseMuscleInfo(
            exerciseName: name,
            muscleGroup: entry.value,
            columnIndex: col,
          ),
        );
      }
    }
    return result;
  }

  /// Parses the sheet-backed `WorkoutDays` tab: one row per user-defined
  /// day, columns id/label/muscleGroups (comma-joined [MuscleGroup] enum
  /// names).
  List<WorkoutDayDef> parseWorkoutDaysTab(List<List<Object?>> rows) {
    final result = <WorkoutDayDef>[];
    for (var row = 1; row < rows.length; row++) {
      final r = rows[row];
      if (r.length < 3) continue;
      final id = _asString(r[0])?.trim();
      final label = _asString(r[1])?.trim();
      final groupsRaw = _asString(r[2]) ?? '';
      if (id == null || id.isEmpty || label == null || label.isEmpty) {
        continue;
      }
      final groups = <MuscleGroup>[
        for (final name in _splitCsv(groupsRaw))
          for (final g in MuscleGroup.values)
            if (g.name == name) g,
      ];
      if (groups.isEmpty) continue;
      // Restores the legacy link for the seeded Push/Pull/Legs rows (whose
      // `id` is the WorkoutDay enum name — see kWorkoutDaySeed) so it
      // survives a sheet round-trip instead of only ever existing on the
      // in-memory seed constants.
      WorkoutDay? legacyDay;
      for (final d in WorkoutDay.values) {
        if (d.name == id) {
          legacyDay = d;
          break;
        }
      }
      result.add(
        WorkoutDayDef(
          id: id,
          label: label,
          muscleGroups: groups,
          legacyDay: legacyDay,
          sheetRowIndex: row,
        ),
      );
    }
    return result;
  }

  List<BodyWeightEntry> parseBodyWeightTab(List<List<Object?>> rows) {
    final result = <BodyWeightEntry>[];
    for (var row = 1; row < rows.length; row++) {
      final r = rows[row];
      if (r.length < 2) continue;
      final date = DateTime.tryParse(_asString(r[0]) ?? '');
      final weight = _asDouble(r[1]);
      if (date == null || weight == null) continue;
      result.add(BodyWeightEntry(date: date, weightKg: weight, rowIndex: row));
    }
    return result;
  }

  /// Parses the `exercises` cell, formatted as
  /// `Exercise Name:low-high` (legacy, no per-set data),
  /// `Exercise Name:low-high:r1,r2,r3` (reps-only, last session's format),
  /// `Exercise Name:low-high:r1,r2,r3:w1,w2,w3` (reps + per-set weight), or
  /// `Exercise Name:low-high:r1,r2,r3:w1,w2,w3:t1,t2,t3` (current format —
  /// adds a 5th segment for optional per-set thumbs-up/down feedback, `u`,
  /// `d`, or empty per set). A rep token may be prefixed `~` (e.g. `~8`) to
  /// mark that set's reps as approximate. The feedback segment is only ever
  /// present when at least one set in the exercise has feedback set, so
  /// most cells stay 2-4 segments exactly as before.
  List<LoggedExerciseRepRange> _parseExercisesCell(String value) {
    final result = <LoggedExerciseRepRange>[];
    for (final part in value.split('|')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final segments = trimmed.split(':');
      if (segments.length < 2) {
        result.add(
          LoggedExerciseRepRange(
            exerciseName: trimmed,
            repRangeLow: 0,
            repRangeHigh: 0,
          ),
        );
        continue;
      }

      final hasFeedback = segments.length >= 5;
      final hasWeights = segments.length >= 4;
      final hasReps = segments.length >= 3;
      final trailingCount = hasFeedback ? 4 : (hasWeights ? 3 : (hasReps ? 2 : 1));
      final name = segments
          .sublist(0, segments.length - trailingCount)
          .join(':')
          .trim();
      final rangePart = segments[segments.length - trailingCount].trim();
      final dashIndex = rangePart.indexOf('-');
      final low =
          int.tryParse(
            dashIndex == -1 ? rangePart : rangePart.substring(0, dashIndex),
          ) ??
          0;
      final high =
          int.tryParse(
            dashIndex == -1 ? rangePart : rangePart.substring(dashIndex + 1),
          ) ??
          low;

      var actualReps = const <int>[];
      var approxReps = const <bool>[];
      if (hasReps) {
        final reps = <int>[];
        final approx = <bool>[];
        for (final token
            in segments[segments.length - trailingCount + 1]
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)) {
          final isApprox = token.startsWith('~');
          final parsed = int.tryParse(isApprox ? token.substring(1) : token);
          if (parsed == null) continue;
          reps.add(parsed);
          approx.add(isApprox);
        }
        actualReps = reps;
        approxReps = approx;
      }

      final actualWeights = hasWeights
          ? segments[segments.length - trailingCount + 2]
                .split(',')
                .map((s) => double.tryParse(s.trim()))
                .whereType<double>()
                .toList()
          : const <double>[];

      // Positions must stay aligned with actualReps/actualWeights, so empty
      // tokens are kept (unlike the reps segment above, which drops them).
      final setFeedback = hasFeedback
          ? segments.last
                .split(',')
                .map((t) => setFeedbackFromSheetToken(t.trim()))
                .toList()
          : const <SetFeedback>[];

      result.add(
        LoggedExerciseRepRange(
          exerciseName: name,
          repRangeLow: low,
          repRangeHigh: high,
          actualReps: actualReps,
          approxReps: approxReps,
          actualWeights: actualWeights,
          setFeedback: setFeedback,
        ),
      );
    }
    return result;
  }

  List<String> _splitCsv(String value) =>
      value.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  String? _asString(Object? value) => value?.toString();

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }
}
