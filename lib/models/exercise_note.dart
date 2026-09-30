/// A free-text note attached to one exercise (or one specific set within an
/// exercise) on a logged visit — stored in the separate `Notes` tab (see
/// `kNotesTabName`), one row per note, so it never has to share a cell's
/// delimiter scheme with the meta tab's dense `exercises` column.
class ExerciseNote {
  const ExerciseNote({
    required this.visitId,
    required this.exerciseName,
    this.setIndex,
    required this.text,
    this.rowIndex,
  });

  final String visitId;
  final String exerciseName;

  /// 0-based set index this note belongs to, or null for a note on the
  /// exercise as a whole.
  final int? setIndex;

  final String text;

  /// 0-based row index in the Notes tab, if this note has already been
  /// written to the sheet (null for a note that only exists locally so
  /// far).
  final int? rowIndex;
}
