class ProgressionTarget {
  final int targetSets;
  final int targetReps;
  final double targetWeightKg;
  final int? targetRpe;
  final String reason;

  const ProgressionTarget({
    required this.targetSets,
    required this.targetReps,
    required this.targetWeightKg,
    required this.reason,
    this.targetRpe,
  });

  @override
  String toString() =>
      'ProgressionTarget(sets:$targetSets, reps:$targetReps, weight:$targetWeightKg, rpe:$targetRpe, reason:"$reason")';
}
