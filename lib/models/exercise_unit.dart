/// A resolved unit + optional custom label, e.g. `(custom, 'floors')` or
/// `(kg, null)`.
typedef ExerciseUnitAssignment = ({ExerciseUnit unit, String? customLabel});

/// One row of the "Exercises" tab's flat `Exercise`/`Unit` side-table (see
/// `SheetParser.parseExerciseUnitsTab`), including its row index so an
/// update-in-place is possible.
typedef ExerciseUnitRow =
    ({ExerciseUnit unit, String? customLabel, int rowIndex});

/// The parsed "Exercises" tab `Exercise`/`Unit` side-table: per-exercise
/// assignments plus where the table itself lives, so a writer can either
/// update an existing row or append a new one (and create the header pair
/// on first use). [exerciseColumnIndex]/[unitColumnIndex] are null when the
/// header pair doesn't exist yet on the sheet.
class ExerciseUnitsTable {
  const ExerciseUnitsTable({
    this.assignments = const {},
    this.exerciseColumnIndex,
    this.unitColumnIndex,
    this.headerRowLength = 0,
  });

  final Map<String, ExerciseUnitRow> assignments;
  final int? exerciseColumnIndex;
  final int? unitColumnIndex;

  /// Number of cells in the tab's header row — where a not-yet-existing
  /// `Exercise`/`Unit` pair should be placed (appended after everything
  /// else already there).
  final int headerRowLength;
}

/// What a logged value for an exercise actually means. Most exercises use
/// plain [kg], but some are better tracked as bodyweight (an optional added
/// weight on top of the user's own body weight), a duration held, or a
/// free-text custom unit (e.g. "floors" for a stairmaster) — see
/// `AddNewExerciseDialog` for where this is chosen and
/// `formatExerciseValue` for how it's displayed.
enum ExerciseUnit { kg, bodyweight, time, custom }

extension ExerciseUnitX on ExerciseUnit {
  /// Exact token stored in the "Exercises" tab's Unit column (see
  /// `SheetParser.parseExerciseUnitsTab`/`SheetWriter.buildExerciseUnitAppendRow`).
  /// [custom] is combined with its label by the caller (`custom:<label>`).
  String get sheetToken => switch (this) {
    ExerciseUnit.kg => 'kg',
    ExerciseUnit.bodyweight => 'bw',
    ExerciseUnit.time => 'time',
    ExerciseUnit.custom => 'custom',
  };

  /// True only for [bodyweight], whose "added weight" of exactly 0 is a
  /// real, meaningful logged value — unlike every other unit, where a
  /// parsed 0 means "cell was never filled in" (see the matrix-tab zero
  /// convention in `SheetParser.parseMatrixTab`).
  bool get allowsZeroAsRealValue => this == ExerciseUnit.bodyweight;

  /// Short parenthesized hint for a weight-entry field's label, e.g.
  /// "Set 1 (kg)" / "Set 1 (+kg)" / "Set 1 (sec)" / "Set 1 (floors)".
  String labelSuffix({String? customLabel}) => switch (this) {
    ExerciseUnit.kg => 'kg',
    ExerciseUnit.bodyweight => '+kg',
    ExerciseUnit.time => 'sec',
    ExerciseUnit.custom => customLabel ?? 'unit',
  };
}

/// Parses just the unit (dropping any custom label) from a sheet token —
/// blank/unrecognized defaults to [ExerciseUnit.kg], so exercises added
/// before this feature existed (or rows with no Unit cell at all) keep
/// behaving exactly as before with no migration needed.
ExerciseUnit exerciseUnitFromSheetToken(String raw) =>
    exerciseUnitAssignmentFromSheetToken(raw).unit;

/// Parses a full unit assignment (unit + optional custom label) from a
/// sheet token, e.g. `'custom:floors'` -> `(custom, 'floors')`,
/// `'bw'` -> `(bodyweight, null)`, `''`/`'kg'`/anything unrecognized ->
/// `(kg, null)`.
ExerciseUnitAssignment exerciseUnitAssignmentFromSheetToken(String raw) {
  final trimmed = raw.trim();
  if (trimmed.toLowerCase().startsWith('custom:')) {
    final label = trimmed.substring('custom:'.length).trim();
    return (unit: ExerciseUnit.custom, customLabel: label.isEmpty ? null : label);
  }
  switch (trimmed.toLowerCase()) {
    case 'bw':
      return (unit: ExerciseUnit.bodyweight, customLabel: null);
    case 'time':
      return (unit: ExerciseUnit.time, customLabel: null);
    default:
      return (unit: ExerciseUnit.kg, customLabel: null);
  }
}

/// Inverse of [exerciseUnitAssignmentFromSheetToken] — produces the exact
/// sheet cell value to write.
String exerciseUnitToSheetToken(ExerciseUnit unit, {String? customUnitLabel}) {
  if (unit == ExerciseUnit.custom) {
    return 'custom:${customUnitLabel ?? ''}';
  }
  return unit.sheetToken;
}
