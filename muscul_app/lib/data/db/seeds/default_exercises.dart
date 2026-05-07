import '../../../domain/models/enums.dart';

class SeedExercise {
  final String id;
  final String name;
  final ExerciseCategory category;
  final MuscleGroup primary;
  final List<MuscleGroup> secondary;
  final Equipment equipment;
  final int repMin;
  final int repMax;
  final double startingWeight;

  const SeedExercise(
    this.id,
    this.name,
    this.category,
    this.primary,
    this.secondary,
    this.equipment,
    this.repMin,
    this.repMax,
    this.startingWeight,
  );
}

const defaultExerciseSeeds = <SeedExercise>[
  // Push
  SeedExercise('seed-bench-barbell', 'Développé couché barre', ExerciseCategory.push,
      MuscleGroup.chest, [MuscleGroup.triceps, MuscleGroup.shoulders],
      Equipment.barbell, 5, 10, 20),
  SeedExercise('seed-bench-dumbbell', 'Développé couché haltères',
      ExerciseCategory.push, MuscleGroup.chest,
      [MuscleGroup.triceps, MuscleGroup.shoulders], Equipment.dumbbell, 8, 12, 10),
  SeedExercise('seed-incline-bench', 'Développé incliné', ExerciseCategory.push,
      MuscleGroup.chest, [MuscleGroup.shoulders, MuscleGroup.triceps],
      Equipment.barbell, 6, 10, 20),
  SeedExercise('seed-ohp', 'Développé militaire', ExerciseCategory.push,
      MuscleGroup.shoulders, [MuscleGroup.triceps], Equipment.barbell, 5, 8, 20),
  SeedExercise('seed-lateral-raise', 'Élévations latérales', ExerciseCategory.push,
      MuscleGroup.shoulders, [], Equipment.dumbbell, 10, 15, 5),
  SeedExercise('seed-dips', 'Dips', ExerciseCategory.push, MuscleGroup.chest,
      [MuscleGroup.triceps, MuscleGroup.shoulders], Equipment.bodyweight, 5, 12, 0),
  SeedExercise('seed-tricep-pushdown', 'Extensions triceps poulie',
      ExerciseCategory.push, MuscleGroup.triceps, [], Equipment.cable, 8, 12, 10),
  SeedExercise('seed-pushups', 'Pompes', ExerciseCategory.push, MuscleGroup.chest,
      [MuscleGroup.triceps, MuscleGroup.shoulders], Equipment.bodyweight, 10, 25, 0),
  // Pull
  SeedExercise('seed-deadlift', 'Soulevé de terre', ExerciseCategory.pull,
      MuscleGroup.lowerBack,
      [MuscleGroup.hamstrings, MuscleGroup.glutes, MuscleGroup.upperBack],
      Equipment.barbell, 3, 6, 40),
  SeedExercise('seed-pullup', 'Tractions', ExerciseCategory.pull, MuscleGroup.lats,
      [MuscleGroup.biceps, MuscleGroup.upperBack], Equipment.bodyweight, 5, 10, 0),
  SeedExercise('seed-row-barbell', 'Rowing barre', ExerciseCategory.pull,
      MuscleGroup.upperBack, [MuscleGroup.lats, MuscleGroup.biceps],
      Equipment.barbell, 6, 10, 20),
  SeedExercise('seed-row-dumbbell', 'Rowing haltère', ExerciseCategory.pull,
      MuscleGroup.upperBack, [MuscleGroup.lats, MuscleGroup.biceps],
      Equipment.dumbbell, 8, 12, 10),
  SeedExercise('seed-lat-pulldown', 'Tirage vertical', ExerciseCategory.pull,
      MuscleGroup.lats, [MuscleGroup.biceps], Equipment.cable, 8, 12, 30),
  SeedExercise('seed-seated-row', 'Tirage horizontal', ExerciseCategory.pull,
      MuscleGroup.upperBack, [MuscleGroup.lats, MuscleGroup.biceps],
      Equipment.cable, 8, 12, 30),
  SeedExercise('seed-curl-barbell', 'Curl barre', ExerciseCategory.pull,
      MuscleGroup.biceps, [MuscleGroup.forearms], Equipment.barbell, 8, 12, 15),
  SeedExercise('seed-curl-dumbbell', 'Curl haltères', ExerciseCategory.pull,
      MuscleGroup.biceps, [MuscleGroup.forearms], Equipment.dumbbell, 8, 12, 7.5),
  SeedExercise('seed-face-pull', 'Face pull', ExerciseCategory.pull,
      MuscleGroup.rearDelts, [MuscleGroup.upperBack], Equipment.cable, 12, 20, 15),
  // Legs
  SeedExercise('seed-squat-barbell', 'Squat barre', ExerciseCategory.legs,
      MuscleGroup.quads, [MuscleGroup.glutes, MuscleGroup.hamstrings],
      Equipment.barbell, 5, 8, 20),
  SeedExercise('seed-front-squat', 'Front squat', ExerciseCategory.legs,
      MuscleGroup.quads, [MuscleGroup.glutes, MuscleGroup.abs],
      Equipment.barbell, 5, 8, 20),
  SeedExercise('seed-bulgarian-split', 'Squat bulgare', ExerciseCategory.legs,
      MuscleGroup.quads, [MuscleGroup.glutes, MuscleGroup.hamstrings],
      Equipment.dumbbell, 8, 12, 5),
  SeedExercise('seed-leg-press', 'Presse à cuisses', ExerciseCategory.legs,
      MuscleGroup.quads, [MuscleGroup.glutes, MuscleGroup.hamstrings],
      Equipment.machine, 8, 15, 40),
  SeedExercise('seed-leg-curl', 'Leg curl', ExerciseCategory.legs,
      MuscleGroup.hamstrings, [], Equipment.machine, 10, 15, 20),
  SeedExercise('seed-leg-extension', 'Leg extension', ExerciseCategory.legs,
      MuscleGroup.quads, [], Equipment.machine, 10, 15, 20),
  SeedExercise('seed-hip-thrust', 'Hip thrust', ExerciseCategory.legs,
      MuscleGroup.glutes, [MuscleGroup.hamstrings], Equipment.barbell, 8, 12, 30),
  SeedExercise('seed-standing-calf', 'Mollets debout', ExerciseCategory.legs,
      MuscleGroup.calves, [], Equipment.machine, 10, 20, 30),
  SeedExercise('seed-seated-calf', 'Mollets assis', ExerciseCategory.legs,
      MuscleGroup.calves, [], Equipment.machine, 10, 20, 20),
  // Core
  SeedExercise('seed-plank', 'Gainage', ExerciseCategory.core, MuscleGroup.abs,
      [MuscleGroup.obliques], Equipment.bodyweight, 1, 1, 0),
  SeedExercise('seed-weighted-crunch', 'Crunch lesté', ExerciseCategory.core,
      MuscleGroup.abs, [], Equipment.cable, 12, 20, 10),
  SeedExercise('seed-ab-wheel', 'Roue abdominale', ExerciseCategory.core,
      MuscleGroup.abs, [MuscleGroup.obliques], Equipment.other, 8, 15, 0),
];
