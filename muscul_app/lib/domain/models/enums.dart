enum ExerciseCategory { push, pull, legs, core, cardio }

enum MuscleGroup {
  chest,
  upperBack,
  lats,
  lowerBack,
  shoulders,
  rearDelts,
  biceps,
  triceps,
  forearms,
  quads,
  hamstrings,
  glutes,
  calves,
  abs,
  obliques,
  cardio,
}

enum Equipment { barbell, dumbbell, machine, cable, bodyweight, other }

extension EquipmentLabel on Equipment {
  String get label {
    switch (this) {
      case Equipment.barbell:
        return 'Barre';
      case Equipment.dumbbell:
        return 'Haltères';
      case Equipment.machine:
        return 'Machine';
      case Equipment.cable:
        return 'Poulie';
      case Equipment.bodyweight:
        return 'Poids du corps';
      case Equipment.other:
        return 'Autre';
    }
  }
}

enum ProgressionPriority { repsFirst, weightFirst }

enum WeightUnit { kg, lb }

enum AppThemeMode { system, light, dark }

enum SyncStatus { pending, synced, conflict }

T enumByName<T extends Enum>(List<T> values, String name, {T? fallback}) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  if (fallback != null) return fallback;
  throw ArgumentError('Unknown enum value "$name" for ${T.toString()}');
}
