import '../core/constants/muscle_groups.dart';
import '../core/constants/sheet_layout.dart';
import 'exercise.dart';
import 'rating_relevance.dart';
import 'set_feedback.dart';

/// A single (exercise row, week column) data point.
class CellKey {
  const CellKey(this.rowIndex, this.columnIndex);
  final int rowIndex;
  final int columnIndex;

  @override
  bool operator ==(Object other) =>
      other is CellKey &&
      other.rowIndex == rowIndex &&
      other.columnIndex == columnIndex;

  @override
  int get hashCode => Object.hash(rowIndex, columnIndex);
}

/// Rep range logged for one exercise within a visit.
class LoggedExerciseRepRange {
  const LoggedExerciseRepRange({
    required this.exerciseName,
    required this.repRangeLow,
    required this.repRangeHigh,
    this.actualReps = const [],
    this.approxReps = const [],
    this.actualWeights = const [],
    this.setFeedback = const [],
  });

  final String exerciseName;
  final int repRangeLow;
  final int repRangeHigh;

  /// Actual reps performed on each set, in order — one entry per set, so
  /// its length is also the number of sets performed. Empty for visits
  /// logged before per-set reps were tracked.
  final List<int> actualReps;

  /// Parallel to [actualReps]: true where that set's rep count was marked
  /// approximate by the user. Empty (all-false) for visits logged before
  /// this was tracked.
  final List<bool> approxReps;

  /// Actual weight lifted per set, in order — parallel to [actualReps].
  /// Empty for visits logged before per-set weight was tracked (the
  /// averaged matrix-tab weight is the only figure available for those).
  final List<double> actualWeights;

  /// Parallel to [actualReps]: optional per-set thumbs-up/down feedback.
  /// Empty for visits logged before this was tracked, or where no set in
  /// this exercise had any feedback marked.
  final List<SetFeedback> setFeedback;

  int? get setCount => actualReps.isEmpty ? null : actualReps.length;

  double? get avgReps => actualReps.isEmpty
      ? null
      : actualReps.reduce((a, b) => a + b) / actualReps.length;

  bool isApprox(int setIndex) =>
      setIndex < approxReps.length && approxReps[setIndex];

  SetFeedback feedbackFor(int setIndex) =>
      setIndex < setFeedback.length ? setFeedback[setIndex] : SetFeedback.none;
}

/// One gym-visit record from a year's `<year>_meta` tab.
class MetaRow {
  const MetaRow({
    required this.rowIndex,
    required this.visitId,
    required this.date,
    required this.isoWeek,
    required this.isoYear,
    required this.muscleGroups,
    required this.exercises,
    required this.sourceTab,
    this.rating,
    this.ratingRelevance = RatingRelevance.normal,
    this.note,
    this.workoutDayId,
  });

  final int rowIndex;
  final String visitId;
  final DateTime date;
  final int isoWeek;
  final int isoYear;
  final List<String> muscleGroups;
  final List<LoggedExerciseRepRange> exercises;
  final String sourceTab;
  final double? rating;

  /// How much [rating] should count toward trend analysis (see
  /// [RatingRelevance]) — e.g. flagged as unrelated because the user felt
  /// sick that day.
  final RatingRelevance ratingRelevance;

  /// Free-text note for this specific visit (column J of the meta tab).
  /// Distinct from [YearSheetData.weekNotes], which is the older
  /// header-row-cell note convention used on [MatrixTabFormat.legacyGrouped]
  /// tabs.
  final String? note;

  /// Id of the `WorkoutDayDef` the user picked when logging this visit
  /// (column K of the meta tab) — null for visits logged before this was
  /// tracked, or hand-typed sheet rows.
  final String? workoutDayId;

  List<String> get exerciseNames =>
      exercises.map((e) => e.exerciseName).toList();
}

/// Parsed representation of one year's data: its matrix tab(s) plus its
/// metadata tab.
class YearSheetData {
  YearSheetData({
    required this.year,
    required this.tabName,
    required this.muscleGroupSections,
    required this.weekColumns,
    required this.cellValues,
    this.format = MatrixTabFormat.flatV2,
    this.sectionHeaderRows = const {},
    this.primaryGroupHeaderRow = const {},
    this.weekNotes = const {},
    this.weekNotesByGroup = const {},
    this.metaRows = const [],
  });

  final int year;

  /// Which layout [tabName] uses — detected per tab, see
  /// `SheetParser.detectMatrixFormat`.
  final MatrixTabFormat format;

  /// Name of the (currently writable) matrix tab for this year — the base
  /// `<year>` tab, or the latest overflow tab if earlier ones are full.
  final String tabName;

  final Map<MuscleGroup, List<Exercise>> muscleGroupSections;

  /// week number -> 0-based column index (within [tabName]).
  final Map<int, int> weekColumns;

  final Map<CellKey, double> cellValues;

  /// 0-based row index of each muscle-group section header row, as they
  /// physically appear in the sheet (order matters for row insertion).
  final Map<MuscleGroup, int> sectionHeaderRows;

  /// Row index of the *exact*-named section header for a group (e.g. the
  /// literal "Push" row, not an "Other Push Exercises" alias row) — this is
  /// where the app writes a new note, so it always lands on the canonical
  /// row the user actually reads.
  final Map<MuscleGroup, int> primaryGroupHeaderRow;

  /// Free-text notes the user writes directly into a section-header row's
  /// week-column cell (e.g. "felt tired" in the "Push" row under a given
  /// week). Combined across all header-row variants (main + "Other ...")
  /// for that week, keyed by week number.
  final Map<int, String> weekNotes;

  /// Same free-text notes as [weekNotes], but kept separate per section
  /// header's [MuscleGroup] instead of merged across every group trained
  /// that week — lets the History screen show a distinct note per
  /// Push/Pull/Legs column instead of one blended string.
  final Map<MuscleGroup, Map<int, String>> weekNotesByGroup;

  final List<MetaRow> metaRows;

  List<Exercise> get allExercises =>
      muscleGroupSections.values.expand((e) => e).toList();

  Exercise? findExercise(String name) {
    for (final exercise in allExercises) {
      if (exercise.name.toLowerCase() == name.toLowerCase()) return exercise;
    }
    return null;
  }

  int get nextFreeColumnIndex => weekColumns.values.isEmpty
      ? 1
      : weekColumns.values.reduce((a, b) => a > b ? a : b) + 1;

  bool get isFull => weekColumns.length >= 52;
}
