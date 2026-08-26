import '../../models/exercise.dart';
import '../../models/year_sheet_data.dart';

/// Suggests alternative exercises for the same muscle group, derived
/// entirely from the user's own (parsed) exercise list — no external
/// exercise database.
class AlternativeExerciseMap {
  const AlternativeExerciseMap(this._sheetData);

  final YearSheetData _sheetData;

  /// Returns other exercise names in [exercise]'s muscle group, ordered to
  /// prefer ones not logged recently (least-recently-used first).
  List<String> alternativesFor(
    Exercise exercise, {
    Map<String, DateTime>? lastLoggedDate,
  }) {
    final group = exercise.muscleGroup;
    final siblings = (_sheetData.muscleGroupSections[group] ?? const [])
        .where((e) => e.name.toLowerCase() != exercise.name.toLowerCase())
        .toList();

    if (lastLoggedDate == null) return siblings.map((e) => e.name).toList();

    siblings.sort((a, b) {
      final da = lastLoggedDate[a.name];
      final db = lastLoggedDate[b.name];
      if (da == null && db == null) return 0;
      if (da == null) return -1;
      if (db == null) return 1;
      return da.compareTo(db);
    });
    return siblings.map((e) => e.name).toList();
  }
}
