import 'year_sheet_data.dart';

/// One row for the History screen / recent-workouts summary: either a real
/// app-logged visit (has [metaRow], exact date/rating/exercise list from the
/// hidden metadata tab) or a reconstruction from raw matrix cells for a week
/// that has exercise weights but no metadata row — i.e. numbers typed
/// directly into the sheet instead of through "Log workout". Synthetic
/// entries only know the week (not an exact date) and can't carry a rating,
/// mirroring the `exactDateKnown` fallback the graphs already use for
/// pre-app history.
class HistoryEntry {
  const HistoryEntry({
    required this.date,
    required this.isoWeek,
    required this.isoYear,
    required this.exerciseNames,
    required this.muscleGroups,
    this.metaRow,
    this.exactDateKnown = true,
  });

  final DateTime date;
  final int isoWeek;
  final int isoYear;
  final List<String> exerciseNames;
  final List<String> muscleGroups;

  /// Null for a synthesized entry (typed directly into the sheet).
  final MetaRow? metaRow;
  final bool exactDateKnown;

  bool get isSynthetic => metaRow == null;
}
