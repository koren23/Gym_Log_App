/// Curated starter exercises sourced from the user's own real Google Sheet
/// history. Notes and photos were pre-filled once from wger.de
/// (https://wger.de) -- an open, crowd-sourced exercise database -- under
/// CC BY-SA 4.0, for exercises where a good name match existed; everything
/// else ships with null notes/photo for the user to fill in later via
/// Settings.
library;

import '../core/constants/muscle_groups.dart';

/// One curated starter exercise: a name, its muscle group, and optional
/// pre-filled notes/photo (see [kDefaultExercisesSeed]).
class DefaultExerciseSeed {
  const DefaultExerciseSeed({
    required this.name,
    required this.muscleGroup,
    this.notes,
    this.photoAssetKey,
  });

  final String name;
  final MuscleGroup muscleGroup;
  final String? notes;
  final String? photoAssetKey;
}

/// One-line attribution surfaced in Settings -- required by wger.de's
/// CC BY-SA 4.0 license on the notes/photos sourced from it.
const String kWgerAttribution =
    'Exercise notes and photos for some exercises are adapted from '
    'wger.de under CC BY-SA 4.0.';

const List<DefaultExerciseSeed> kDefaultExercisesSeed = [
  DefaultExerciseSeed(
    name: 'Barbell bench press',
    muscleGroup: MuscleGroup.lowerChest,
    notes: 'Lay down on a bench, the bar should be directly above your eyes, the knees are somewhat angled and the feet are firmly on the floor. Concentrate, breath deeply and grab the bar more than shoulder wide. Bring it slowly down till it briefly touches your chest at the height of your nipples. Push the bar up.',
    photoAssetKey: 'assets/exercise_photos/barbell_bench_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell bench press',
    muscleGroup: MuscleGroup.lowerChest,
  ),
  DefaultExerciseSeed(
    name: 'Chest press',
    muscleGroup: MuscleGroup.lowerChest,
    notes: 'Adjust the seat height so that the grips are parallel to your chest. Use your legs to push the foot forward pedal. Bring the handles to the start position. Keep your back in contact with the back pad, press outwards. Press the handles away from your chest and exhale.',
    photoAssetKey: 'assets/exercise_photos/chest_press.webp',
  ),
  DefaultExerciseSeed(
    name: 'High cable chest fly',
    muscleGroup: MuscleGroup.lowerChest,
    notes: 'Execution Start position: Arms extended out to your sides in a “Y” shape. Feel a stretch in your chest (slight bend in elbows — don’t lock them). Movement: Bring your hands downward and together in front of your lower chest or upper abs , in a smooth arc motion. Squeeze your chest hard at the bottom for 1–2 seconds.',
  ),
  DefaultExerciseSeed(
    name: 'Chest machine fly',
    muscleGroup: MuscleGroup.lowerChest,
    notes: 'seated machine, straight back, slow exercise',
    photoAssetKey: 'assets/exercise_photos/chest_machine_fly.png',
  ),
  DefaultExerciseSeed(
    name: 'Machine bench press',
    muscleGroup: MuscleGroup.lowerChest,
  ),
  DefaultExerciseSeed(
    name: 'Incline barbell bench press',
    muscleGroup: MuscleGroup.upperChest,
    notes: 'To do slowly, tempo is 4010',
    photoAssetKey: 'assets/exercise_photos/incline_barbell_bench_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Incline dumbbell bench press',
    muscleGroup: MuscleGroup.upperChest,
    notes: 'This is a variation of the flat bench press designed to emphasize the clavicular head of the pectoralis major (the upper portion).',
    photoAssetKey: 'assets/exercise_photos/incline_dumbbell_bench_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Incline chest press',
    muscleGroup: MuscleGroup.upperChest,
    notes: 'Single arm chest press done with the cable machine. Use the other arm to brace bodyweight to focus on strength of the press, rather than balancing of the body. Start with the hand as close to the chest as possible, and then press against the cable at a slight incline and aiming towards the center of your chest.',
  ),
  DefaultExerciseSeed(
    name: 'Cable front raises',
    muscleGroup: MuscleGroup.frontDelt,
    notes: 'To execute the exercise, the lifter stands with their feet shoulder width apart and weights or resistance handles held by their side with a pronated (overhand) grip. The movement is to bring the arms up in front of the body to eye level and with only a slight bend in the elbow.',
    photoAssetKey: 'assets/exercise_photos/cable_front_raises.png',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell front raises',
    muscleGroup: MuscleGroup.frontDelt,
    notes: 'To execute the exercise, the lifter stands with their feet shoulder width apart and weights or resistance handles held by their side with a pronated (overhand) grip. The movement is to bring the arms up in front of the body to eye level and with only a slight bend in the elbow.',
    photoAssetKey: 'assets/exercise_photos/dumbbell_front_raises.png',
  ),
  DefaultExerciseSeed(
    name: 'Seated barbell shoulder press',
    muscleGroup: MuscleGroup.frontDelt,
    notes: 'Sit on a bench, the back rest should be almost vertical. Take a barbell with a shoulder wide grip and bring it up to chest height. Press the weight up, but don\'t stretch the arms completely. Go slowly down and repeat.',
    photoAssetKey: 'assets/exercise_photos/seated_barbell_shoulder_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Shoulder press machine',
    muscleGroup: MuscleGroup.frontDelt,
    photoAssetKey: 'assets/exercise_photos/shoulder_press_machine.png',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell shoulder press',
    muscleGroup: MuscleGroup.frontDelt,
    notes: 'Press the dumbbell vertically overhead in a controlled motion until your arm is fully extended, without locking the elbow. Slowly lower the dumbbell back to the starting position at shoulder height.',
    photoAssetKey: 'assets/exercise_photos/dumbbell_shoulder_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Barbell military press',
    muscleGroup: MuscleGroup.frontDelt,
    notes: 'Setup: Stand with feet together and grip the bar slightly wider than shoulders. Position: Rest the bar on your upper chest. Press: Brace your core and push the bar straight up until your arms lock out. Finish: Control the bar back down to your chest. https://youtu.be/ZXpdJOLNoWw?si=u27cGyODoblXHBu1',
    photoAssetKey: 'assets/exercise_photos/barbell_military_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Machine lateral raises',
    muscleGroup: MuscleGroup.lateralDelt,
    notes: 'Machine side lateral raises are an isolation exercise for the side (lateral) deltoids, performed on a machine for stability, targeting the outer shoulder by lifting pads or handles out to the sides to shoulder height, then lowering slowly, keeping elbows slightly bent and traps down to focus on the delts.',
    photoAssetKey: 'assets/exercise_photos/machine_lateral_raises.jpg',
  ),
  DefaultExerciseSeed(
    name: 'Cable lateral raises',
    muscleGroup: MuscleGroup.lateralDelt,
    notes: 'The single arm cable lateral raise is a variation of the lateral raise and an exercise used to build the muscles of the shoulders. Position a cable at the lowest position possible and attach a single handle. Reach across your body and grab the handle with a neutral grip.',
    photoAssetKey: 'assets/exercise_photos/cable_lateral_raises.jpg',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell lateral raises',
    muscleGroup: MuscleGroup.lateralDelt,
    notes: 'This exercise works the deltoid muscle of the shoulder. The movement starts with the arms straight, and the hands holding weights at the sides or in front of the body. Body is in a slight forward-leaning position with hips and knees bent a little.',
    photoAssetKey: 'assets/exercise_photos/dumbbell_lateral_raises.png',
  ),
  DefaultExerciseSeed(
    name: 'EZ bar skull crushers',
    muscleGroup: MuscleGroup.triceps,
    notes: 'Hold the SZ-bar and lay down on a flat bench in such a way that around 1/4 of your head is over the edge. Stretch your arms with the bar and bend them so that the bar is lowered. Just before it touches your forehead, push it up.',
    photoAssetKey: 'assets/exercise_photos/ez_bar_skull_crushers.png',
  ),
  DefaultExerciseSeed(
    name: 'Cable tricep pushdown',
    muscleGroup: MuscleGroup.triceps,
    notes: 'The cable rope push-down is a popular exercise targeting the triceps muscles. It\'s easy to learn and perform, making it a favorite for everyone from beginners to advanced lifters. It is usually performed for moderate to high reps, such as 8-12 reps or more per set, as part of an upper-body or arm-focused workout.',
    photoAssetKey: 'assets/exercise_photos/cable_tricep_pushdown.png',
  ),
  DefaultExerciseSeed(
    name: 'Cable tricep extension',
    muscleGroup: MuscleGroup.triceps,
    notes: 'Use rope handle with your back against the cable machine. Straighten your arms until they are filly extended and reverse the motion resisting on the negative.',
  ),
  DefaultExerciseSeed(
    name: 'Dips machine',
    muscleGroup: MuscleGroup.triceps,
    notes: 'Assisted triceps dips is a gym work out exercise that targets triceps and also involves chest.',
  ),
  DefaultExerciseSeed(
    name: 'Single tricep pushdown',
    muscleGroup: MuscleGroup.triceps,
    notes: 'Single-arm cable pushdown is a unilateral isolation exercise that targets the triceps brachii. By working one arm at a time, it helps correct strength imbalances between sides while also engaging the core for stability. Starting position: Stand facing the cable machine with your feet shoulder-width apart.',
  ),
  DefaultExerciseSeed(
    name: 'Crunches machine',
    muscleGroup: MuscleGroup.abdominals,
    notes: 'The procedure is very similar as for regular crunches, only with the additional weight of the machine. Sit on the machine, put both feet firmly on the ground. Grab the to the weights, cables, etc. and do a rolling motion forwards (the spine should ideally lose touch vertebra by vertebra).',
  ),
  DefaultExerciseSeed(
    name: 'Knee raises',
    muscleGroup: MuscleGroup.abdominals,
    notes: 'The 90° leg raise on the bar is a very intense exercise that involves all the abdominal muscles.',
    photoAssetKey: 'assets/exercise_photos/knee_raises.png',
  ),
  DefaultExerciseSeed(
    name: 'Cable crunches',
    muscleGroup: MuscleGroup.abdominals,
    notes: 'Take the cable on your hands and hold it next to your temples. Knee down and hold your upper body straight and bend forward. Go down with a fast movement, rolling your back in (your ellbows point to your knees). Once down, go slowly back to the initial position.',
  ),
  DefaultExerciseSeed(
    name: 'Seated crunches machine',
    muscleGroup: MuscleGroup.abdominals,
    notes: 'The procedure is very similar as for regular crunches, only with the additional weight of the machine. Sit on the machine, put both feet firmly on the ground. Grab the to the weights, cables, etc. and do a rolling motion forwards (the spine should ideally lose touch vertebra by vertebra).',
  ),
  DefaultExerciseSeed(
    name: 'Cable seated rows',
    muscleGroup: MuscleGroup.upperBack,
    notes: 'Take a seat on the machine with your feet planted, a little wider than shoulder width. Drive the heels, and squeeze the glutes. Grab onto the cable handle. Sit up tall with a slight bend through the knees. Tighten up the abs and low back to maintain a perpendicular angle to the floor with your torso.',
    photoAssetKey: 'assets/exercise_photos/cable_seated_rows.png',
  ),
  DefaultExerciseSeed(
    name: 'Lever row machine',
    muscleGroup: MuscleGroup.upperBack,
    notes: 'Keep your chest up and squeeze your shoulder blades at the end. Don’t hunch forward or round your back during the pull.',
    photoAssetKey: 'assets/exercise_photos/lever_row_machine.png',
  ),
  DefaultExerciseSeed(
    name: 'Barbell bent over rows',
    muscleGroup: MuscleGroup.upperBack,
    notes: 'Holding a barbell with a pronated grip (palms facing down), bend your knees slightly and bring your torso forward, by bending at the waist, while keeping the back straight until it is almost parallel to the floor. Tip: Make sure that you keep the head up.',
    photoAssetKey: 'assets/exercise_photos/barbell_bent_over_rows.png',
  ),
  DefaultExerciseSeed(
    name: 'Cable pullovers',
    muscleGroup: MuscleGroup.lats,
    notes: 'Stand facing the machine, feet slightly apart, gripping the bar with an overhand grip, arms extended, hands shoulder-width apart. Keeping your back fixed and your abdominal muscles contracted, inhale and bring the bar down to your thighs while keeping your arms extended (or your elbows slightly bent).',
    photoAssetKey: 'assets/exercise_photos/cable_pullovers.png',
  ),
  DefaultExerciseSeed(
    name: 'Lat pulldown',
    muscleGroup: MuscleGroup.lats,
    notes: 'Downward movement: Pull the bar down so that it passes close to your chin and touches the upper part of your chest. Keep the rest of your body still.',
  ),
  DefaultExerciseSeed(
    name: 'Lat pulldown (red cables)',
    muscleGroup: MuscleGroup.lats,
  ),
  DefaultExerciseSeed(
    name: 'Cable rear delt fly',
    muscleGroup: MuscleGroup.rearDelt,
    notes: 'The reverse cable fly, also known as the cable rear delt fly, is a deltoid muscle strengthening and definition exercise. It’s one of the best isolation exercises for your back and posterior deltoid.This workout targets your posterior (back) deltoids while using a range of upper body muscles.',
    photoAssetKey: 'assets/exercise_photos/cable_rear_delt_fly.png',
  ),
  DefaultExerciseSeed(
    name: 'Rope face pulls',
    muscleGroup: MuscleGroup.rearDelt,
    notes: 'Face pulls with band – standing horizontal pull. Grab the band at face height, pull elbows high and wide towards your face while squeezing shoulder blades together. Trains upper back, rear shoulders and improves posture.',
    photoAssetKey: 'assets/exercise_photos/rope_face_pulls.jpg',
  ),
  DefaultExerciseSeed(
    name: 'Reverse machine flys',
    muscleGroup: MuscleGroup.rearDelt,
    notes: 'Attach D-Handles to two cable pulleys in the upper position. Grab the left on with your right hand and vice-versa.',
  ),
  DefaultExerciseSeed(
    name: 'EZ bar preacher curl',
    muscleGroup: MuscleGroup.biceps,
    notes: 'Place the EZ curl bar on the rest handles in front of the preacher bench. Lean over the bench and grab the EZ curl bar with palms up. Sit down on the preacher bench seat so your upper arms rest on top of the pad and your chest is pressed against the pad.',
    photoAssetKey: 'assets/exercise_photos/ez_bar_preacher_curl.png',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell bicep curls',
    muscleGroup: MuscleGroup.biceps,
    notes: 'The Dumbbell Curl is a classic isolation exercise for the arms. Unlike the Hammer Curl, it involves rotating your wrists (supination) as you lift the weights, which allows for a full contraction of the biceps.',
  ),
  DefaultExerciseSeed(
    name: 'EZ bar bicep curls',
    muscleGroup: MuscleGroup.biceps,
    notes: 'Hold the SZ-bar shoulder-wide, the back is straight, the shoulders slightly back, the arms are streched. Bend the arms, bringing the weight up, with a fast movement. Without pausing, let down the bar with a slow and controlled movement.',
    photoAssetKey: 'assets/exercise_photos/ez_bar_bicep_curls.png',
  ),
  DefaultExerciseSeed(
    name: 'Cable curls',
    muscleGroup: MuscleGroup.biceps,
    notes: 'Bicep Curls using cables. Can be seated or standing',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell preacher curl',
    muscleGroup: MuscleGroup.biceps,
    notes: 'Place the EZ curl bar on the rest handles in front of the preacher bench. Lean over the bench and grab the EZ curl bar with palms up. Sit down on the preacher bench seat so your upper arms rest on top of the pad and your chest is pressed against the pad.',
    photoAssetKey: 'assets/exercise_photos/dumbbell_preacher_curl.png',
  ),
  DefaultExerciseSeed(
    name: 'Bicep curl machine',
    muscleGroup: MuscleGroup.biceps,
    notes: 'The biceps curl machine is designed to isolate the biceps muscles and provide a controlled range of motion. Sit on the machine with your back against the pad and adjust the seat so your arms are aligned with the machine\'s handles or pads.',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell concentration curl',
    muscleGroup: MuscleGroup.biceps,
    notes: 'Sit on bench. Grasp dumbbell between feet. Place back of upper arm to inner thigh. Lean into leg to raise elbow slightly.',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell hammer curls',
    muscleGroup: MuscleGroup.brachialis,
    notes: 'Start: Hold dumbbells at your sides with palms facing your torso. Curl: Lift the weights toward your shoulders while maintaining the neutral grip (like holding a hammer). Squeeze: Contract the biceps at the top without moving your elbows forward. Lower: Slowly return to the starting position with full control.',
    photoAssetKey: 'assets/exercise_photos/dumbbell_hammer_curls.png',
  ),
  DefaultExerciseSeed(
    name: 'EZ bar reverse curls',
    muscleGroup: MuscleGroup.brachialis,
    notes: 'The reverse-grip barbell curl is a variation on the biceps curl where the palms face downward. The switch from an underhand to an overhand grip brings the forearm and brachialis muscles more into the exercise.',
  ),
  DefaultExerciseSeed(
    name: 'Leg press',
    muscleGroup: MuscleGroup.quads,
    notes: 'The leg press is a weight training exercise in which the individual pushes a weight or resistance away from them using their legs.',
    photoAssetKey: 'assets/exercise_photos/leg_press.webp',
  ),
  DefaultExerciseSeed(
    name: 'Barbell squats',
    muscleGroup: MuscleGroup.quads,
    notes: 'Place a barbell in a rack just below shoulder-height. Dip under the bar to put it behind the neck across the top of the back, and grip the bar with the hands wider than shoulder-width apart. Lift the chest up and squeeze the shoulder blades together to keep the straight back throughout the entire movement.',
  ),
  DefaultExerciseSeed(
    name: 'Leg extension',
    muscleGroup: MuscleGroup.quads,
    notes: 'The leg extension is a resistance weight training exercise that targets the quadriceps muscle in the legs. The exercise is done using a machine called the Leg Extension Machine. There are various manufacturers of these machines and each one is slightly different.',
    photoAssetKey: 'assets/exercise_photos/leg_extension.png',
  ),
  DefaultExerciseSeed(
    name: 'Hack squat',
    muscleGroup: MuscleGroup.quads,
    notes: 'Hack squats target the lower body and are performed on a hack squat machine or with a barbell. For the machine variation, position yourself on the platform with your shoulders under the pads and feet slightly forward.',
  ),
  DefaultExerciseSeed(
    name: 'Barbell bulgarian split squat',
    muscleGroup: MuscleGroup.quads,
    notes: 'Stand tall in front of a chair and take a large step. Put the upper part of one of your feet on the chair. Bend the front knee, balancing with arms until the back knee almost touches the ground. Push back to the starting position and repeat.',
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell bulgarian split squat',
    muscleGroup: MuscleGroup.quads,
    notes: 'Controlled execution No momentum Execute slowly',
  ),
  DefaultExerciseSeed(
    name: 'Smith squats',
    muscleGroup: MuscleGroup.quads,
    notes: 'Technique and Execution The Smith machine squat is a variation of the traditional barbell squat that uses a guided, fixed-path barbell.',
    photoAssetKey: 'assets/exercise_photos/smith_squats.jpg',
  ),
  DefaultExerciseSeed(
    name: 'Parallel leg press',
    muscleGroup: MuscleGroup.quads,
    notes: 'The leg press is a weight training exercise in which the individual pushes a weight or resistance away from them using their legs.',
    photoAssetKey: 'assets/exercise_photos/parallel_leg_press.webp',
  ),
  DefaultExerciseSeed(
    name: 'Single leg press',
    muscleGroup: MuscleGroup.quads,
    notes: 'Strength training exercise where you push a weight away from your body using one leg at a time on a leg press machine. It helps to improve leg strength, balance, and muscular symmetry by isolating each leg individually.',
  ),
  DefaultExerciseSeed(
    name: 'Barbell RDL',
    muscleGroup: MuscleGroup.hamstrings,
    notes: 'Execution Hinge at the hips: Push your hips backward , keeping a slight bend in the knees (soft knees). Lower the barbell along the front of your thighs/shins while maintaining a neutral spine . Keep the bar close to your body .',
  ),
  DefaultExerciseSeed(
    name: 'Seated leg curls',
    muscleGroup: MuscleGroup.hamstrings,
    photoAssetKey: 'assets/exercise_photos/seated_leg_curls.png',
  ),
  DefaultExerciseSeed(
    name: 'Lying leg curls',
    muscleGroup: MuscleGroup.hamstrings,
    notes: 'Lay on a bench and put your calves behind the leg holder (better if they are hold on around the lower calves). Hold a grip on the bars to make sure the body is firmly in place. Bend your legs bringing the weight up, go slowly back. During the exercise the body should not move, all work is done by the legs.',
    photoAssetKey: 'assets/exercise_photos/lying_leg_curls.png',
  ),
  DefaultExerciseSeed(
    name: 'Standing calf press',
    muscleGroup: MuscleGroup.calves,
    notes: 'Get onto the calf raises machine, you should able to completely push your calves down. Stand straight, don\'t make a hollow back and don\'t bend your legs. Pull yourself up as high as you can. Make a small pause of 1 - 2 seconds and go slowly down.',
    photoAssetKey: 'assets/exercise_photos/standing_calf_press.jpeg',
  ),
  DefaultExerciseSeed(
    name: 'Parallel leg press calf press',
    muscleGroup: MuscleGroup.calves,
    notes: 'Put the balls of your feet on an extended leg press pad. Use your calves to press the weight by flexing your feet/toes into a pointed position, and releasing back into a relaxed position. This exercise builds mass and strength in the Gastrocnemius and Soleus muscles as well, if not better, than any calf exercise.',
    photoAssetKey: 'assets/exercise_photos/parallel_leg_press_calf_press.png',
  ),
  DefaultExerciseSeed(
    name: 'Hip adduction',
    muscleGroup: MuscleGroup.glutes,
    notes: 'Starting Position: Sit on the machine with your knees inward and against the pads. Pull the pin to release the pads. Grab the handles on the sides.b',
    photoAssetKey: 'assets/exercise_photos/hip_adduction.webp',
  ),
  DefaultExerciseSeed(
    name: 'Hip abduction',
    muscleGroup: MuscleGroup.glutes,
    notes: 'Technique and Execution Starting Position Seated Positioning: Sit in the machine with back against the pad Leg Placement: Inner thighs against the machine\'s padded resistance points Adjust Machine: Set seat position to align your hip joint with the machine\'s pivot point Movement Technique Start with legs together or slightly pressed against the inner pads Slowly push legs outward, spreading them a',
    photoAssetKey: 'assets/exercise_photos/hip_abduction.jpg',
  ),
  DefaultExerciseSeed(
    name: 'Glutes kickback',
    muscleGroup: MuscleGroup.glutes,
    notes: 'Drive through your heel, not your toes, to hit the glute. Don’t hyperextend your lower back at the top.',
  ),
  DefaultExerciseSeed(
    name: 'Hip thrust',
    muscleGroup: MuscleGroup.glutes,
    notes: 'The bar should go directly on your upper thigh, directly below your crotch. Your feet should be directly under your knees. Push your hips up so that you form a straight line from your knees to your shoulders. Use a pad for comfort.',
  ),
  DefaultExerciseSeed(
    name: 'Barbell deadlift',
    muscleGroup: MuscleGroup.glutes,
    notes: 'Stand firmly, with your feet slightly more than shoulder wide apart. Stand directly behind the bar where it should barely touch your shin, your feet pointing a bit out. Bend down with a straight back, the knees also pointing somewhat out. Grab the bar with a shoulder wide grip, one overhand, one underhand (mixed grip).',
    photoAssetKey: 'assets/exercise_photos/barbell_deadlift.jpeg',
  ),
  DefaultExerciseSeed(
    name: 'Cable low forearm raises',
    muscleGroup: MuscleGroup.forearm,
  ),
  DefaultExerciseSeed(
    name: 'Dumbbell forearm curls',
    muscleGroup: MuscleGroup.forearm,
    notes: 'Engage the muscles Don\'t use momentum Controlled movement Slow movement',
    photoAssetKey: 'assets/exercise_photos/dumbbell_forearm_curls.webp',
  ),
  DefaultExerciseSeed(
    name: 'Hyperextensions',
    muscleGroup: MuscleGroup.lowerBack,
    notes: 'Lie on the hyperextension pillow with your navel at the front edge, allowing your upper body to hang freely. Tighten all your back muscles and raise your torso until you\'re horizontal, but no higher. Lower yourself slowly, maintaining a steady flow of muscles.',
    photoAssetKey: 'assets/exercise_photos/hyperextensions.png',
  ),
  DefaultExerciseSeed(
    name: 'Good mornings',
    muscleGroup: MuscleGroup.lowerBack,
    notes: 'Stand with your feet more than shoulder-width apart (wider stance) and place your hands on your hips. Hinge at your hips and lower your upper body towards the ground while keeping your back straight then come back up.',
    photoAssetKey: 'assets/exercise_photos/good_mornings.png',
  ),
];
