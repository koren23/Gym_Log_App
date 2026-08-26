import 'sheet_layout.dart';

/// Muscle taxonomy used across two eras of the user's Google Sheet:
///
/// - **Legacy** (`legacy: true`) values are the 8 section-header labels used
///   in pre-2026 year matrix tabs (e.g. "Push", "Chest", ...). They only
///   ever appear as column-A header rows in an old-format (`legacyGrouped`)
///   matrix tab — see [MatrixTabFormat] in `sheet_layout.dart`. Kept
///   permanently so that old history stays readable forever; never used for
///   anything about current data.
/// - **Current** (`legacy: false`) values are the exact column headers in
///   the live "Exercises" reference tab (verified directly against the
///   user's real spreadsheet), used for every exercise logged from 2026
///   onward. If the user adds another muscle column to that tab, a new
///   value needs to be added here to match.
///
/// The two sets never collide: legacy detection ([muscleGroupFromSheetHeader])
/// only ever scans the legacy subset, and current-tab parsing only ever
/// scans the non-legacy subset, so the same lowercase text (e.g. "triceps"
/// vs "Triceps") can't be misclassified across eras.
enum MuscleGroup {
  // --- Legacy (pre-2026 matrix tab section headers only) ---
  legacyPush('Push', legacy: true),
  legacyChest('Chest', legacy: true),
  legacyShoulders('Shoulders', legacy: true),
  legacyTriceps('Triceps', legacy: true),
  legacyPull('Pull', legacy: true),
  legacyBack('Back', legacy: true),
  legacyBiceps('Biceps', legacy: true),
  legacyLegs('Legs', legacy: true),

  // --- Current (2026+ "Exercises" tab columns) ---
  upperChest('upper chest'),
  lowerChest('lower chest'),
  triceps('triceps'),
  lateralDelt('lateral delt'),
  frontDelt('front delt'),
  abdominals('abdominals'),
  obliques('obliques'),
  upperBack('upper back'),
  lats('lats'),
  biceps('biceps'),
  brachialis('brachialis'),
  rearDelt('rear delt'),
  forearm('forearm'),
  quads('quads'),
  glutes('glutes'),
  hamstrings('hamstrings'),
  calves('calves'),
  lowerBack('lower back');

  const MuscleGroup(this.sheetHeader, {this.legacy = false});

  /// The exact string expected in the sheet for this value (a legacy
  /// matrix-tab section header, or a current Exercises-tab column header).
  final String sheetHeader;

  /// True for the 8 pre-2026 section-header values.
  final bool legacy;
}

/// Every current (non-legacy) muscle — the full "Full Body" set, and the
/// pool custom workout days are built from.
List<MuscleGroup> get kCurrentMuscleGroups =>
    MuscleGroup.values.where((g) => !g.legacy).toList(growable: false);

/// A training day, as the user actually thinks about their split — used
/// historically to drive the "Log workout" day picker and to interpret
/// pre-2026 history. Current-era workout days are fully user-defined (see
/// `WorkoutDayDef`); this enum and [kMuscleGroupsByWorkoutDay] are kept only
/// for legacy-format interpretation.
enum WorkoutDay {
  push('Push'),
  pull('Pull'),
  legs('Legs');

  const WorkoutDay(this.label);

  final String label;
}

/// Legacy-only: which of the 8 legacy [MuscleGroup] sections belonged to
/// each classic day, used to interpret pre-2026 matrix tabs.
const Map<WorkoutDay, List<MuscleGroup>> kMuscleGroupsByWorkoutDay = {
  WorkoutDay.push: [
    MuscleGroup.legacyPush,
    MuscleGroup.legacyChest,
    MuscleGroup.legacyShoulders,
    MuscleGroup.legacyTriceps,
  ],
  WorkoutDay.pull: [
    MuscleGroup.legacyPull,
    MuscleGroup.legacyBack,
    MuscleGroup.legacyBiceps,
  ],
  WorkoutDay.legs: [MuscleGroup.legacyLegs],
};

/// One-time seed lists (current-taxonomy muscles) used only when creating
/// the very first Push/Pull/Legs rows in the sheet-backed `WorkoutDays` tab
/// — a best-effort mapping from the 18 current muscles into the 3 classic
/// buckets. Purely a starting point: once created, these are ordinary
/// user-editable workout days like any other.
const List<MuscleGroup> kSeedPushMuscles = [
  MuscleGroup.upperChest,
  MuscleGroup.lowerChest,
  MuscleGroup.triceps,
  MuscleGroup.lateralDelt,
  MuscleGroup.frontDelt,
  MuscleGroup.rearDelt,
];
const List<MuscleGroup> kSeedPullMuscles = [
  MuscleGroup.upperBack,
  MuscleGroup.lats,
  MuscleGroup.biceps,
  MuscleGroup.brachialis,
  MuscleGroup.forearm,
];
const List<MuscleGroup> kSeedLegsMuscles = [
  MuscleGroup.quads,
  MuscleGroup.glutes,
  MuscleGroup.hamstrings,
  MuscleGroup.calves,
  MuscleGroup.lowerBack,
];

/// The legacy day whose exercise list includes [group], if any (legacy-only
/// — always null for a current/non-legacy [group]).
WorkoutDay? workoutDayForMuscleGroup(MuscleGroup group) {
  for (final entry in kMuscleGroupsByWorkoutDay.entries) {
    if (entry.value.contains(group)) return entry.key;
  }
  return null;
}

/// The group whose header row is where a legacy [day]'s note gets
/// written/read (e.g. the literal "Push" row, not "Chest"/"Shoulders").
MuscleGroup primaryGroupForDay(WorkoutDay day) =>
    kMuscleGroupsByWorkoutDay[day]!.first;

/// Seed exercise names per legacy muscle group — only used when creating a
/// brand-new *legacy-format* tab (there is no such path going forward; kept
/// only in case a legacy-format overflow/backfill tab is ever needed).
const Map<MuscleGroup, List<String>> kSeedExercisesByMuscleGroup = {
  MuscleGroup.legacyPush: [
    'Barbell bench press',
    'Incline chest press',
    'Dumbbell shoulder press',
    'Dumbbell lateral raises',
    'Chest machine fly',
    'Cable tricep extension',
    'Cable crunches',
  ],
  MuscleGroup.legacyChest: [
    'Incline barbell bench press',
    'Incline dumbbell bench press',
    'Dumbbell bench press',
    'Chest press',
    'High cable chest fly',
  ],
  MuscleGroup.legacyShoulders: [
    'Dumbbell front raises',
    'Shoulder press machine',
    'Machine lateral raises',
    'Cable front raises',
    'Cable lateral raises',
    'Seated barbell shoulder press',
  ],
  MuscleGroup.legacyTriceps: ['EZ bar skull crushers', 'Cable tricep pushdown'],
  MuscleGroup.legacyPull: [
    'Barbell bent over rows',
    'Lat pulldown',
    'Cable seated rows',
    'Reverse machine flys',
    'Dumbbell preacher curl',
    'EZ bar reverse curls',
    'Knee raises',
  ],
  MuscleGroup.legacyBack: [
    'Cable pullovers',
    'Lever row machine',
    'Rope face pulls',
    'Cable rear delt fly',
  ],
  MuscleGroup.legacyBiceps: [
    'Bicep curl machine',
    'EZ bar preacher curl',
    'Dumbbell hammer curls',
    'Dumbbell bicep curls',
    'EZ bar bicep curls',
    'Cable curls',
  ],
  MuscleGroup.legacyLegs: [
    'Barbell RDL',
    'Parallel leg press calf press',
    'Leg extension',
    'Lying leg curls',
    'Crunches machine',
    'Leg press',
    'Barbell squats',
    'Hack squat',
    'Seated leg curls',
    'Stair master',
    'Standing calf press',
    'Barbell deadlift',
  ],
};

/// Matches a column-A section header in a matrix tab to its legacy
/// [MuscleGroup] — only ever matches the 8 legacy values, so this is also
/// how a matrix tab is recognized as [MatrixTabFormat.legacyGrouped] (see
/// `SheetParser.detectMatrixFormat`). Also recognizes bonus/overflow section
/// headers like "Extra Push", "Other Push Exercises", "Additional Pull
/// Exercises" (typos like "exercies" included) as aliases for their base
/// group.
MuscleGroup? muscleGroupFromSheetHeader(String value) {
  final trimmed = value.trim().toLowerCase();
  final legacyValues = MuscleGroup.values.where((g) => g.legacy);
  for (final group in legacyValues) {
    if (group.sheetHeader.toLowerCase() == trimmed) {
      return group;
    }
  }

  var core = trimmed;
  core = core.replaceFirst(RegExp(r'^(extra|additional|bonus|other)\s+'), '');
  core = core
      .replaceFirst(RegExp(r'\s+(exercises|exercise|exercies)$'), '')
      .trim();
  if (core != trimmed) {
    for (final group in legacyValues) {
      if (group.sheetHeader.toLowerCase() == core) {
        return group;
      }
    }
  }
  return null;
}

/// Header text the user has already hand-typed on the live sheet that
/// doesn't exactly match a current [MuscleGroup]'s canonical [sheetHeader]
/// (pluralization/abbreviation only). Extend this list, never rename
/// `sheetHeader` itself — `sheetHeader` is also used as user-facing display
/// text and as what the app writes when it creates a brand-new section
/// header, so it should stay the "nice" canonical form.
const Map<String, MuscleGroup> _kCurrentMuscleHeaderAliases = {
  'front delts': MuscleGroup.frontDelt,
  'lateral delts': MuscleGroup.lateralDelt,
  'abs': MuscleGroup.abdominals,
  'hams': MuscleGroup.hamstrings,
};

/// Matches a column header in the current "Exercises" reference tab (or a
/// current-muscle-grouped year tab's section header) to its current
/// (non-legacy) [MuscleGroup] — only ever matches the current subset, so it
/// never collides with [muscleGroupFromSheetHeader]'s legacy matches even
/// where the text overlaps case-insensitively (e.g. "Triceps" vs "triceps").
/// Falls back to [_kCurrentMuscleHeaderAliases] for known hand-typed
/// variants after an exact match fails.
MuscleGroup? currentMuscleFromSheetHeader(String value) {
  final trimmed = value.trim().toLowerCase();
  for (final group in kCurrentMuscleGroups) {
    if (group.sheetHeader.toLowerCase() == trimmed) {
      return group;
    }
  }
  return _kCurrentMuscleHeaderAliases[trimmed];
}

/// Matches a column-A header cell against EITHER era's muscle-group
/// headers — legacy first (so old tabs are unaffected), then current (exact
/// + alias). Used only by [SheetParser.detectMatrixFormat], where the tab's
/// format isn't known yet. Once a tab's format *is* known, use
/// [sheetHeaderMuscleGroupForFormat] instead — a small number of current
/// muscle names (see [ambiguousLegacyMuscleGroups]) are textually identical
/// to a legacy header, so which era should win depends on which format the
/// tab actually is.
MuscleGroup? anySheetHeaderMuscleGroup(String value) =>
    muscleGroupFromSheetHeader(value) ?? currentMuscleFromSheetHeader(value);

/// Legacy [MuscleGroup] values whose [MuscleGroup.sheetHeader] collides,
/// case-insensitively, with a current (non-legacy) value's — e.g. legacy
/// "Triceps"/"Biceps" vs. current "triceps"/"biceps". Computed generically so
/// a future taxonomy addition can't silently reintroduce this ambiguity
/// without being caught here.
final Set<MuscleGroup> ambiguousLegacyMuscleGroups = {
  for (final legacy in MuscleGroup.values.where((g) => g.legacy))
    if (kCurrentMuscleGroups.any(
      (c) => c.sheetHeader.toLowerCase() == legacy.sheetHeader.toLowerCase(),
    ))
      legacy,
};

/// Resolves a column-A header to its [MuscleGroup] once the enclosing tab's
/// [MatrixTabFormat] is already known — unlike [anySheetHeaderMuscleGroup],
/// this can't be fooled by the handful of current muscle names that are
/// textually identical to a legacy header (see [ambiguousLegacyMuscleGroups]):
/// a `currentGrouped` tab always prefers the current interpretation, a
/// `legacyGrouped` tab always prefers the legacy one.
MuscleGroup? sheetHeaderMuscleGroupForFormat(
  String value,
  MatrixTabFormat format,
) {
  if (format == MatrixTabFormat.currentGrouped) {
    return currentMuscleFromSheetHeader(value) ?? muscleGroupFromSheetHeader(value);
  }
  return muscleGroupFromSheetHeader(value) ?? currentMuscleFromSheetHeader(value);
}
