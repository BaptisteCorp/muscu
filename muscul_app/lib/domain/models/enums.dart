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

enum Equipment { barbell, dumbbell, machine, cable, rope, bodyweight, other }

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
      case Equipment.rope:
        return 'Corde';
      case Equipment.bodyweight:
        return 'Poids du corps';
      case Equipment.other:
        return 'Autre';
    }
  }
}

enum WeightUnit { kg, lb }

// Mode clair / sombre uniquement. Le mode « système » a été retiré (il
// dupliquait le sombre dans la pratique) — défaut = sombre.
enum AppThemeMode { light, dark }

/// Accent colour palette for the app theme. [ocean] (bleu) est le défaut ;
/// [crimson] (rouge) et les autres restent disponibles en variation. Stored
/// as a device-local preference.
enum AppPalette { crimson, ocean, emerald, violet, amber }

enum SyncStatus { pending, synced, conflict }

T enumByName<T extends Enum>(List<T> values, String name, {T? fallback}) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  if (fallback != null) return fallback;
  throw ArgumentError('Unknown enum value "$name" for ${T.toString()}');
}
