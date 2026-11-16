/// Curated starter exercises sourced from the user's own real Google Sheet
/// history: a name, its correct muscle group, tracked unit, and a suggested
/// rep range + set count for a brand-new entry with no logging history yet.
/// Everything here is a starting point only -- fully editable per-exercise
/// via Settings > Manage exercises.
///
/// Grouped by muscle group (alphabetical by [MuscleGroup.sheetHeader]) to
/// make this file easier to scan/edit by hand.
library;

import '../core/constants/muscle_groups.dart';
import '../models/exercise_unit.dart';

/// One curated starter exercise: a name, its muscle group, tracked unit, and
/// an optional suggested rep range + set count (see [kDefaultExercisesSeed]).
class DefaultExerciseSeed {
  const DefaultExerciseSeed({
    required this.name,
    required this.muscleGroup,
    this.unit = ExerciseUnit.kg,
    this.customUnitLabel,
    this.repRangeLow,
    this.repRangeHigh,
    this.setCount,
  });

  final String name;
  final MuscleGroup muscleGroup;
  final ExerciseUnit unit;
  final String? customUnitLabel;
  final int? repRangeLow;
  final int? repRangeHigh;
  final int? setCount;
}

const List<DefaultExerciseSeed> kDefaultExercisesSeed = [
  // --- abdominals ---
  DefaultExerciseSeed(
    name: 'Crunches machine',
    muscleGroup: MuscleGroup.abdominals,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Knee raises',
    muscleGroup: MuscleGroup.abdominals,
    unit: ExerciseUnit.bodyweight,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Cable crunches',
    muscleGroup: MuscleGroup.abdominals,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Seated crunches machine',
    muscleGroup: MuscleGroup.abdominals,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),

  // --- biceps ---
  DefaultExerciseSeed(
    name: 'EZ bar preacher curl',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell bicep curls',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'EZ bar bicep curls',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Cable curls',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell preacher curl',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Bicep curl machine',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell concentration curl',
    muscleGroup: MuscleGroup.biceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- brachialis ---
  DefaultExerciseSeed(
    name: 'Dumbbell hammer curls',
    muscleGroup: MuscleGroup.brachialis,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'EZ bar reverse curls',
    muscleGroup: MuscleGroup.brachialis,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- calves ---
  DefaultExerciseSeed(
    name: 'Standing calf press',
    muscleGroup: MuscleGroup.calves,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Parallel leg press calf press',
    muscleGroup: MuscleGroup.calves,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),

  // --- forearm ---
  DefaultExerciseSeed(
    name: 'Cable low forearm raises',
    muscleGroup: MuscleGroup.forearm,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell forearm curls',
    muscleGroup: MuscleGroup.forearm,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),

  // --- front delt ---
  DefaultExerciseSeed(
    name: 'Cable front raises',
    muscleGroup: MuscleGroup.frontDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell front raises',
    muscleGroup: MuscleGroup.frontDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Seated barbell shoulder press',
    muscleGroup: MuscleGroup.frontDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Shoulder press machine',
    muscleGroup: MuscleGroup.frontDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell shoulder press',
    muscleGroup: MuscleGroup.frontDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Barbell military press',
    muscleGroup: MuscleGroup.frontDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- glutes ---
  DefaultExerciseSeed(
    name: 'Hip adduction',
    muscleGroup: MuscleGroup.glutes,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 15,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Hip abduction',
    muscleGroup: MuscleGroup.glutes,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 15,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Glutes kickback',
    muscleGroup: MuscleGroup.glutes,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 15,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Hip thrust',
    muscleGroup: MuscleGroup.glutes,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Barbell deadlift',
    muscleGroup: MuscleGroup.glutes,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),

  // --- hamstrings ---
  DefaultExerciseSeed(
    name: 'Barbell RDL',
    muscleGroup: MuscleGroup.hamstrings,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Seated leg curls',
    muscleGroup: MuscleGroup.hamstrings,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Lying leg curls',
    muscleGroup: MuscleGroup.hamstrings,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- lateral delt ---
  DefaultExerciseSeed(
    name: 'Machine lateral raises',
    muscleGroup: MuscleGroup.lateralDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Cable lateral raises',
    muscleGroup: MuscleGroup.lateralDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell lateral raises',
    muscleGroup: MuscleGroup.lateralDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- lats ---
  DefaultExerciseSeed(
    name: 'Cable pullovers',
    muscleGroup: MuscleGroup.lats,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Lat pulldown',
    muscleGroup: MuscleGroup.lats,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Lat pulldown (red cables)',
    muscleGroup: MuscleGroup.lats,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- lower back ---
  DefaultExerciseSeed(
    name: 'Hyperextensions',
    muscleGroup: MuscleGroup.lowerBack,
    unit: ExerciseUnit.bodyweight,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Good mornings',
    muscleGroup: MuscleGroup.lowerBack,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- lower chest ---
  DefaultExerciseSeed(
    name: 'Barbell bench press',
    muscleGroup: MuscleGroup.lowerChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell bench press',
    muscleGroup: MuscleGroup.lowerChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Chest press',
    muscleGroup: MuscleGroup.lowerChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'High cable chest fly',
    muscleGroup: MuscleGroup.lowerChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Chest machine fly',
    muscleGroup: MuscleGroup.lowerChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Machine bench press',
    muscleGroup: MuscleGroup.lowerChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),

  // --- quads ---
  DefaultExerciseSeed(
    name: 'Leg press',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 15,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Barbell squats',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Leg extension',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Hack squat',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Barbell bulgarian split squat',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell bulgarian split squat',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 12,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Smith squats',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Parallel leg press',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 15,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Single leg press',
    muscleGroup: MuscleGroup.quads,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),

  // --- rear delt ---
  DefaultExerciseSeed(
    name: 'Cable rear delt fly',
    muscleGroup: MuscleGroup.rearDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Rope face pulls',
    muscleGroup: MuscleGroup.rearDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Reverse machine flys',
    muscleGroup: MuscleGroup.rearDelt,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- triceps ---
  DefaultExerciseSeed(
    name: 'EZ bar skull crushers',
    muscleGroup: MuscleGroup.triceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Cable tricep pushdown',
    muscleGroup: MuscleGroup.triceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Cable tricep extension',
    muscleGroup: MuscleGroup.triceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Dips machine',
    muscleGroup: MuscleGroup.triceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Single tricep pushdown',
    muscleGroup: MuscleGroup.triceps,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),

  // --- upper back ---
  DefaultExerciseSeed(
    name: 'Cable seated rows',
    muscleGroup: MuscleGroup.upperBack,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Lever row machine',
    muscleGroup: MuscleGroup.upperBack,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Barbell bent over rows',
    muscleGroup: MuscleGroup.upperBack,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 10,
    setCount: 3,
  ),

  // --- upper chest ---
  DefaultExerciseSeed(
    name: 'Incline barbell bench press',
    muscleGroup: MuscleGroup.upperChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Incline dumbbell bench press',
    muscleGroup: MuscleGroup.upperChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
  DefaultExerciseSeed(
    name: 'Incline chest press',
    muscleGroup: MuscleGroup.upperChest,
    unit: ExerciseUnit.kg,
    repRangeLow: 6,
    repRangeHigh: 8,
    setCount: 3,
  ),
];
