/// Cible calculée par le moteur de surcharge progressive pour la prochaine
/// séance. Les valeurs sont strictement déterministes et dérivent uniquement
/// de la dernière séance + de la configuration de l'exercice.
class ProgressionTarget {
  final int targetSets;
  final int targetReps;
  final double targetWeightKg;
  final String reason;

  const ProgressionTarget({
    required this.targetSets,
    required this.targetReps,
    required this.targetWeightKg,
    required this.reason,
  });

  @override
  String toString() =>
      'ProgressionTarget(sets:$targetSets, reps:$targetReps, weight:$targetWeightKg, reason:"$reason")';
}
