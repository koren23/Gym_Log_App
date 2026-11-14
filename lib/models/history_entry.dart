import 'year_sheet_data.dart';

/// One row for the History screen / recent-workouts summary, backed by a
/// local [MetaRow] — either a real app-logged visit or (see
/// [MetaRow.isSynthetic]) one materialized at import time from matrix cells
/// typed directly into the sheet with no metadata row. A synthetic entry
/// only knows the week (not an exact date, see [exactDateKnown]) and never
/// carries a rating/note/per-set data.
class HistoryEntry {
  const HistoryEntry({
    required this.date,
    required this.isoWeek,
    required this.isoYear,
    required this.exerciseNames,
    required this.muscleGroups,
    required this.metaRow,
  });

  final DateTime date;
  final int isoWeek;
  final int isoYear;
  final List<String> exerciseNames;
  final List<String> muscleGroups;
  final MetaRow metaRow;

  bool get isSynthetic => metaRow.isSynthetic;
  bool get exactDateKnown => metaRow.exactDateKnown;
}
