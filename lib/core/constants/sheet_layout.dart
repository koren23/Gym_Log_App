/// Layout constants for how data is arranged in the user's spreadsheet.
///
/// Visible year matrix tabs: named `<year>` (e.g. "2026") or, once a year's
/// base tab fills up, an overflow tab named `<year>_<n>` (e.g. "2026_2",
/// "2026_3", ...). Column A = exercise name (or, for a [MatrixTabFormat
/// .legacyGrouped] tab, a muscle-group section header). Row 1, columns B
/// onward = week numbers. Data cells = the average weight logged for that
/// exercise in that week.
library;

/// Which matrix-tab layout a given year tab uses, detected per tab (see
/// `SheetParser.detectMatrixFormat`) — all three are supported forever side
/// by side, since old tabs are never migrated.
enum MatrixTabFormat {
  /// Pre-2026 layout: column A alternates between legacy Push/Chest/...
  /// section-header rows and the exercise rows beneath them.
  legacyGrouped,

  /// 2026-onward layout the user hand-maintains directly on the year tab:
  /// column A alternates between current-muscle section-header rows (e.g.
  /// "upper chest", "triceps") and the exercise rows beneath them. Uses the
  /// exact same section-tracking algorithm as [legacyGrouped], just matched
  /// against the current muscle taxonomy's header text
  /// ([currentMuscleFromSheetHeader]) instead of the legacy one.
  currentGrouped,

  /// Column A is exercise rows only, no section headers at all. An
  /// exercise's muscle comes from a name->muscle map built from other
  /// years' own headers and/or the optional legacy "Exercises" reference
  /// tab, falling back to "unknown" if nothing resolves it.
  flatV2,
}

/// Max week-number columns allowed per year tab before an overflow tab is
/// created.
const int kMaxWeekColumnsPerTab = 52;

/// Regex matching a base-year matrix tab name, e.g. "2026".
final RegExp kYearTabPattern = RegExp(r'^(\d{4})$');

/// Regex matching an overflow year matrix tab name, e.g. "2026_2".
final RegExp kYearOverflowTabPattern = RegExp(r'^(\d{4})_(\d+)$');

/// Regex matching a hidden per-year metadata tab, e.g. "2026_meta".
final RegExp kYearMetaTabPattern = RegExp(r'^(\d{4})_meta$');

/// Fixed name of the body-weight tracking tab.
const String kBodyWeightTabName = 'BodyWeight';

/// Fixed name of the optional legacy exercise -> muscle reference tab (one
/// column per current [MuscleGroup], header row = that muscle's exact name,
/// exercise names listed downward starting row 2). No longer the primary
/// source of exercise->muscle categorization — a [MatrixTabFormat
/// .currentGrouped] year tab's own section headers are authoritative now.
/// This tab is entirely optional and may not exist at all; when present
/// it's used only as a fallback name->muscle source.
const String kExercisesTabName = 'Exercises';

/// Fixed name of the sheet-backed workout-day-definitions tab.
const String kWorkoutDaysTabName = 'WorkoutDays';

/// Column order for the WorkoutDays tab.
const List<String> kWorkoutDaysTabColumns = ['id', 'label', 'muscleGroups'];

/// Column order for a year's metadata tab. Columns I (ratingRelevance), J
/// (note), and K (workoutDayId) were added after columns A-H already
/// existed in the wild — older rows simply lack them and parse as their
/// defaults.
const List<String> kMetaTabColumns = [
  'visitId',
  'date',
  'isoWeek',
  'isoYear',
  'muscleGroups',
  'exercises',
  'sourceTab',
  'rating',
  'ratingRelevance',
  'note',
  'workoutDayId',
];

/// Column order for the BodyWeight tab.
const List<String> kBodyWeightTabColumns = ['date', 'weightKg'];

/// Default set/rep scheme offered when logging a new exercise entry with no
/// usable history of its own.
const int kDefaultSetCount = 3;
const int kDefaultRepRangeLow = 6;
const int kDefaultRepRangeHigh = 8;
