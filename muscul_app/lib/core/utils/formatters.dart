import '../../domain/models/enums.dart';

/// Helpers de formatage centralisés. Tous les écrans doivent utiliser ces
/// fonctions plutôt que de les redéfinir localement, pour garantir la
/// cohérence des affichages (poids, dates, libellés…) à travers l'app.

// ----- Poids ---------------------------------------------------------------

/// Formate un poids en kg sans décimale si entier, sinon avec 1 décimale.
/// Ex. 60.0 → "60", 62.5 → "62.5"
String fmtKg(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

// ----- Repos ---------------------------------------------------------------

/// Formate une durée de repos en secondes. < 60 → "Xs", sinon "Xmin" ou "XminYs".
String fmtRest(int s) {
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final r = s % 60;
  return r == 0 ? '${m}min' : '${m}min${r}s';
}

// ----- Dates ---------------------------------------------------------------

/// Date au format DD/MM/YYYY.
String fmtDate(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

/// Heure au format HH:MM.
String fmtTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Date + heure au format DD/MM/YYYY HH:MM.
String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTime(d)}';

/// Libellé relatif d'une date passée : aujourd'hui, hier, il y a N jours/semaines,
/// sinon date absolue. Préfixe pris en charge ("Dernière séance le …").
String fmtRelativeDay(DateTime d, {String prefix = ''}) {
  final today = DateTime.now();
  final daysAgo = DateTime(today.year, today.month, today.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  final p = prefix.isEmpty ? '' : '$prefix ';
  if (daysAgo == 0) return "${p}aujourd'hui";
  if (daysAgo == 1) return '${p}hier';
  if (daysAgo < 7) return '${p}il y a $daysAgo j';
  if (daysAgo < 30) {
    final weeks = (daysAgo / 7).round();
    return '${p}il y a $weeks sem';
  }
  return '${p}le ${fmtDate(d)}';
}

// ----- Libellés muscles / catégories --------------------------------------

/// Variante de [muscleLabel] qui prend le nom d'enum sous forme de String
/// (utile quand on lit directement depuis la DB).
String muscleLabelByName(String name) {
  for (final m in MuscleGroup.values) {
    if (m.name == name) return muscleLabel(m);
  }
  return name;
}

String muscleLabel(MuscleGroup m) => switch (m) {
      MuscleGroup.chest => 'Pectoraux',
      MuscleGroup.upperBack => 'Dos (haut)',
      MuscleGroup.lats => 'Grands dorsaux',
      MuscleGroup.lowerBack => 'Lombaires',
      MuscleGroup.shoulders => 'Épaules',
      MuscleGroup.rearDelts => 'Deltoïdes postérieurs',
      MuscleGroup.biceps => 'Biceps',
      MuscleGroup.triceps => 'Triceps',
      MuscleGroup.forearms => 'Avant-bras',
      MuscleGroup.quads => 'Quadriceps',
      MuscleGroup.hamstrings => 'Ischio-jambiers',
      MuscleGroup.glutes => 'Fessiers',
      MuscleGroup.calves => 'Mollets',
      MuscleGroup.abs => 'Abdos',
      MuscleGroup.obliques => 'Obliques',
      MuscleGroup.cardio => 'Cardio',
    };

/// Mappe un muscle vers la catégorie push/pull/legs/core/cardio.
ExerciseCategory categoryFromMuscle(MuscleGroup m) => switch (m) {
      MuscleGroup.chest ||
      MuscleGroup.shoulders ||
      MuscleGroup.triceps =>
        ExerciseCategory.push,
      MuscleGroup.upperBack ||
      MuscleGroup.lats ||
      MuscleGroup.biceps ||
      MuscleGroup.forearms ||
      MuscleGroup.lowerBack ||
      MuscleGroup.rearDelts =>
        ExerciseCategory.pull,
      MuscleGroup.quads ||
      MuscleGroup.hamstrings ||
      MuscleGroup.glutes ||
      MuscleGroup.calves =>
        ExerciseCategory.legs,
      MuscleGroup.abs || MuscleGroup.obliques => ExerciseCategory.core,
      MuscleGroup.cardio => ExerciseCategory.cardio,
    };
