import 'muscle_groups.dart';

/// A simplified 8-zone grouping of the 18 current [MuscleGroup] values for
/// the body diagram (item 7) — tapping a zone drills down to its exact
/// [MuscleGroup]s. A clean partition: every non-legacy [MuscleGroup]
/// belongs to exactly one zone.
enum BodyZone {
  chest,
  shoulders,
  bicepsForearm,
  triceps,
  core,
  back,
  quads,
  glutesHamsCalves,
}

/// Which [MuscleGroup]s make up each [BodyZone].
const Map<BodyZone, List<MuscleGroup>> kMuscleGroupsByBodyZone = {
  BodyZone.chest: [MuscleGroup.upperChest, MuscleGroup.lowerChest],
  BodyZone.shoulders: [
    MuscleGroup.lateralDelt,
    MuscleGroup.frontDelt,
    MuscleGroup.rearDelt,
  ],
  BodyZone.bicepsForearm: [
    MuscleGroup.biceps,
    MuscleGroup.brachialis,
    MuscleGroup.forearm,
  ],
  BodyZone.triceps: [MuscleGroup.triceps],
  BodyZone.core: [MuscleGroup.abdominals, MuscleGroup.obliques],
  BodyZone.back: [MuscleGroup.upperBack, MuscleGroup.lats, MuscleGroup.lowerBack],
  BodyZone.quads: [MuscleGroup.quads],
  BodyZone.glutesHamsCalves: [
    MuscleGroup.glutes,
    MuscleGroup.hamstrings,
    MuscleGroup.calves,
  ],
};

/// True if [zone] is shown on the body's front silhouette (a zone can be
/// shown on both — e.g. shoulders).
bool bodyZoneShowsFront(BodyZone zone) => switch (zone) {
  BodyZone.chest => true,
  BodyZone.shoulders => true,
  BodyZone.bicepsForearm => true,
  BodyZone.triceps => false,
  BodyZone.core => true,
  BodyZone.back => false,
  BodyZone.quads => true,
  BodyZone.glutesHamsCalves => false,
};

/// True if [zone] is shown on the body's back silhouette.
bool bodyZoneShowsBack(BodyZone zone) => switch (zone) {
  BodyZone.shoulders => true,
  BodyZone.triceps => true,
  BodyZone.back => true,
  BodyZone.glutesHamsCalves => true,
  _ => false,
};

const Map<BodyZone, String> kBodyZoneLabels = {
  BodyZone.chest: 'Chest',
  BodyZone.shoulders: 'Shoulders',
  BodyZone.bicepsForearm: 'Biceps & forearm',
  BodyZone.triceps: 'Triceps',
  BodyZone.core: 'Core',
  BodyZone.back: 'Back',
  BodyZone.quads: 'Quads',
  BodyZone.glutesHamsCalves: 'Glutes, hams & calves',
};
