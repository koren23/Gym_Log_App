import '../../core/constants/muscle_groups.dart';
import '../../core/constants/sheet_layout.dart';
import '../../models/body_weight_entry.dart';
import '../../models/exercise.dart';
import '../../models/exercise_muscle_info.dart';
import '../../models/exercise_unit.dart';
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
    Map<String, ExerciseUnitAssignment>? exerciseUnitOverrides,
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
        final unitAssignment = exerciseUnitOverrides?[colA.trim().toLowerCase()];
        final exercise = Exercise(
          name: colA.trim(),
          muscleGroup: resolvedGroup,
          sheetRow: row,
          muscleGroupKnown: override != null,
          unit: unitAssignment?.unit ?? ExerciseUnit.kg,
          customUnitLabel: unitAssignment?.customLabel,
        );
        muscleGroupSections[resolvedGroup]!.add(exercise);

        for (var col = 1; col < rowValues.length; col++) {
          final weight = _asDouble(rowValues[col]);
          if (weight != null && (weight != 0 || exercise.unit.allowsZeroAsRealValue)) {
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
      final unitAssignment = exerciseUnitOverrides?[colA.trim().toLowerCase()];
      final exercise = Exercise(
        name: colA.trim(),
        muscleGroup: resolvedGroup,
        sheetRow: row,
        unit: unitAssignment?.unit ?? ExerciseUnit.kg,
        customUnitLabel: unitAssignment?.customLabel,
      );
      muscleGroupSections[resolvedGroup]!.add(exercise);

      for (var col = 1; col < rowValues.length; col++) {
        final weight = _asDouble(rowValues[col]);
        // A "0" cell is never a real logged weight in this sheet (unless
        // this exercise's unit allows a genuine 0, e.g. bodyweight with no
        // added weight) — treat it as an unfilled placeholder rather than
        // actual data, otherwise blank-but-zero-filled cells masquerade as
        // a phantom first entry.
        if (weight != null && (weight != 0 || exercise.unit.allowsZeroAsRealValue)) {
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

  /// Parses the "Exercises" tab's optional `Exercise`/`Unit` side-table (a
  /// flat, name-keyed 2-column table appended somewhere on the tab,
  /// independent of the per-muscle columns [parseExercisesTab] reads) —
  /// header cells matched by case-insensitive text, not position. Returns
  /// an empty map when the header pair doesn't exist yet (tab predates this
  /// feature, or the user hasn't set any non-kg units) — every exercise
  /// then defaults to [ExerciseUnit.kg], no migration needed.
  ExerciseUnitsTable parseExerciseUnitsTab(List<List<Object?>> rows) {
    if (rows.isEmpty) return const ExerciseUnitsTable();
    final header = rows.first;

    int? exerciseCol;
    int? unitCol;
    for (var col = 0; col < header.length; col++) {
      final text = _asString(header[col])?.trim().toLowerCase();
      if (text == 'exercise') exerciseCol = col;
      if (text == 'unit') unitCol = col;
    }
    if (exerciseCol == null || unitCol == null) {
      return ExerciseUnitsTable(headerRowLength: header.length);
    }

    final result = <String, ExerciseUnitRow>{};
    for (var row = 1; row < rows.length; row++) {
      final r = rows[row];
      if (exerciseCol >= r.length) continue;
      final name = _asString(r[exerciseCol])?.trim();
      if (name == null || name.isEmpty) continue;
      final token = unitCol < r.length ? (_asString(r[unitCol]) ?? '') : '';
      final assignment = exerciseUnitAssignmentFromSheetToken(token);
      result[name.toLowerCase()] = (
        unit: assignment.unit,
        customLabel: assignment.customLabel,
        rowIndex: row,
      );
    }
    return ExerciseUnitsTable(
      assignments: result,
      exerciseColumnIndex: exerciseCol,
      unitColumnIndex: unitCol,
      headerRowLength: header.length,
    );
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
  /// `Exercise Name:low-high:r1,r2,r3:w1,w2,w3` (reps + per-set weight),
  /// `Exercise Name:low-high:r1,r2,r3:w1,w2,w3:t1,t2,t3` (adds a 5th segment
  /// for optional per-set thumbs-up/down feedback, `u`, `d`, or empty per
  /// set), `...:tl1-th1,tl2-th2,` (adds a 6th segment: per-set target
  /// rep-range override, `low-high` or empty per set), or `...:tw1,,tw3`
  /// (adds a 7th segment: per-set target weight override, a number or
  /// empty per set). A rep token may be prefixed `~` (e.g. `~8`) to mark
  /// that set's reps as approximate. Each of segments 5-7 is only ever
  /// present when at least one set actually needs it — but once a later
  /// segment (6 or 7) is present, every segment before it must also be
  /// present (even all-empty), since segment *count* alone determines which
  /// fields are present; a sparse/gapped set of segments would be ambiguous
  /// (a 5-segment cell could otherwise mean either "has feedback, no
  /// targets" or "no feedback, has an omitted-then-present target
  /// segment"). So most cells stay 2-5 segments, and only exercises with an
  /// actual per-set target override ever reach 6 or 7.
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

      final hasTargetWeight = segments.length >= 7;
      final hasTargetRange = segments.length >= 6;
      final hasFeedback = segments.length >= 5;
      final hasWeights = segments.length >= 4;
      final hasReps = segments.length >= 3;
      final trailingCount = hasTargetWeight
          ? 6
          : (hasTargetRange
                ? 5
                : (hasFeedback ? 4 : (hasWeights ? 3 : (hasReps ? 2 : 1))));
      final rangeIndex = segments.length - trailingCount;
      final name = segments.sublist(0, rangeIndex).join(':').trim();
      final rangePart = segments[rangeIndex].trim();
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
            in segments[rangeIndex + 1]
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
          ? segments[rangeIndex + 2]
                .split(',')
                .map((s) => double.tryParse(s.trim()))
                .whereType<double>()
                .toList()
          : const <double>[];

      // Positions must stay aligned with actualReps/actualWeights, so empty
      // tokens are kept (unlike the reps segment above, which drops them).
      final setFeedback = hasFeedback
          ? segments[rangeIndex + 3]
                .split(',')
                .map((t) => setFeedbackFromSheetToken(t.trim()))
                .toList()
          : const <SetFeedback>[];

      var targetLowPerSet = const <int?>[];
      var targetHighPerSet = const <int?>[];
      if (hasTargetRange) {
        final lows = <int?>[];
        final highs = <int?>[];
        for (final token in segments[rangeIndex + 4].split(',')) {
          final t = token.trim();
          final dash = t.indexOf('-');
          if (t.isEmpty || dash == -1) {
            lows.add(null);
            highs.add(null);
            continue;
          }
          lows.add(int.tryParse(t.substring(0, dash)));
          highs.add(int.tryParse(t.substring(dash + 1)));
        }
        targetLowPerSet = lows;
        targetHighPerSet = highs;
      }

      final targetWeightPerSet = hasTargetWeight
          ? segments[rangeIndex + 5]
                .split(',')
                .map((t) => double.tryParse(t.trim()))
                .toList()
          : const <double?>[];

      result.add(
        LoggedExerciseRepRange(
          exerciseName: name,
          repRangeLow: low,
          repRangeHigh: high,
          actualReps: actualReps,
          approxReps: approxReps,
          actualWeights: actualWeights,
          setFeedback: setFeedback,
          targetLowPerSet: targetLowPerSet,
          targetHighPerSet: targetHighPerSet,
          targetWeightPerSet: targetWeightPerSet,
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
