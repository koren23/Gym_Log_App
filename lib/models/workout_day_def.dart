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
