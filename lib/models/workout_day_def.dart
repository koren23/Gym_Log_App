import '../core/constants/muscle_groups.dart';

/// Sentinel id for the "Full Body" pseudo-day (every current muscle group).
const String kFullBodyDayId = '__full_body__';

/// A day shown in the Log Workout day picker. Fully user-defined and
/// sheet-backed (see `WorkoutDayDefsNotifier`/the `WorkoutDays` tab) — there
/// is no "built-in, protected" day anymore; Push/Pull/Legs/Full Body are
/// just the one-time seed a fresh sheet starts with (see
/// [kWorkoutDaySeed]), renameable/deletable like any other.
class WorkoutDayDef {
  const WorkoutDayDef({
    required this.id,
    required this.label,
    required this.muscleGroups,
    this.legacyDay,
    this.sheetRowIndex,
  });

  /// Stable id: a fixed string for the seeded Push/Pull/Legs/Full Body rows,
  /// a timestamp for anything the user creates afterward.
  final String id;

  /// User-facing name — fully free text.
  final String label;

  final List<MuscleGroup> muscleGroups;

  /// The [WorkoutDay] this maps to for legacy pre-2026 history lookups.
  /// Only ever set on the seeded Push/Pull/Legs rows, and only for as long
  /// as the user hasn't replaced them — a renamed/recreated day loses this
  /// link, which just means it no longer shows pre-2026 history under it.
  final WorkoutDay? legacyDay;

  /// 0-based row index within the `WorkoutDays` sheet tab this was parsed
  /// from — null if not yet confirmed synced to the sheet (a locally
  /// pending add) or for the never-persisted seed rows.
  final int? sheetRowIndex;

  bool get isFullBody => id == kFullBodyDayId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'muscleGroups': [for (final g in muscleGroups) g.name],
  };

  factory WorkoutDayDef.fromJson(Map<String, dynamic> json) => WorkoutDayDef(
    id: json['id'] as String,
    label: json['label'] as String,
    muscleGroups: [
      for (final n in (json['muscleGroups'] as List).cast<String>())
        MuscleGroup.values.firstWhere((g) => g.name == n),
    ],
  );
}

/// Collapses duplicate [WorkoutDayDef]s sharing the same [id] into one:
/// unions their muscle groups (so nothing already-added is lost) and keeps
/// the label from the entry with the highest [WorkoutDayDef.sheetRowIndex]
/// — the most recently written, matching this codebase's existing "later
/// wins" convention (see `allKnownExercisesProvider`). An entry with no
/// `sheetRowIndex` (a locally-pending add not yet confirmed synced) counts
/// as more recent than any synced row. The merged entry's `sheetRowIndex`
/// is the *lowest* of the group's — the row a one-time sheet cleanup keeps
/// and overwrites, deleting the rest. Non-duplicated entries pass through
/// unchanged, and relative order is preserved.
List<WorkoutDayDef> mergeDuplicateWorkoutDays(List<WorkoutDayDef> defs) {
  final order = <String>[];
  final byId = <String, List<WorkoutDayDef>>{};
  for (final d in defs) {
    if (!byId.containsKey(d.id)) order.add(d.id);
    byId.putIfAbsent(d.id, () => []).add(d);
  }
  return [
    for (final id in order)
      if (byId[id]!.length == 1)
        byId[id]!.single
      else
        _mergeGroup(byId[id]!),
  ];
}

WorkoutDayDef _mergeGroup(List<WorkoutDayDef> group) {
  final sorted = [...group]..sort((a, b) {
    final ar = a.sheetRowIndex;
    final br = b.sheetRowIndex;
    if (ar == null && br == null) return 0;
    if (ar == null) return 1; // pending sorts as most recent.
    if (br == null) return -1;
    return ar.compareTo(br);
  });
  final latest = sorted.last;
  final mergedGroups = <MuscleGroup>[];
  for (final d in group) {
    for (final g in d.muscleGroups) {
      if (!mergedGroups.contains(g)) mergedGroups.add(g);
    }
  }
  WorkoutDay? legacyDay;
  for (final d in group) {
    if (d.legacyDay != null) {
      legacyDay = d.legacyDay;
      break;
    }
  }
  final rowIndices = [
    for (final d in group)
      if (d.sheetRowIndex != null) d.sheetRowIndex!,
  ];
  return WorkoutDayDef(
    id: latest.id,
    label: latest.label,
    muscleGroups: mergedGroups,
    legacyDay: legacyDay,
    sheetRowIndex: rowIndices.isEmpty
        ? null
        : rowIndices.reduce((a, b) => a < b ? a : b),
  );
}

/// One-time seed used only when the sheet has no `WorkoutDays` tab data yet
/// (e.g. a brand-new spreadsheet, or upgrading from the old local-only
/// custom-day feature): Push/Pull/Legs (best-effort mapped onto the current
/// fine-muscle taxonomy) plus Full Body (every current muscle). Once
/// written to the sheet these become ordinary rows — nothing regenerates or
/// protects them afterward.
final List<WorkoutDayDef> kWorkoutDaySeed = [
  WorkoutDayDef(
    id: WorkoutDay.push.name,
    label: WorkoutDay.push.label,
    muscleGroups: kSeedPushMuscles,
    legacyDay: WorkoutDay.push,
  ),
  WorkoutDayDef(
    id: WorkoutDay.pull.name,
    label: WorkoutDay.pull.label,
    muscleGroups: kSeedPullMuscles,
    legacyDay: WorkoutDay.pull,
  ),
  WorkoutDayDef(
    id: WorkoutDay.legs.name,
    label: WorkoutDay.legs.label,
    muscleGroups: kSeedLegsMuscles,
    legacyDay: WorkoutDay.legs,
  ),
  WorkoutDayDef(
    id: kFullBodyDayId,
    label: 'Full Body',
    muscleGroups: kCurrentMuscleGroups,
  ),
];
