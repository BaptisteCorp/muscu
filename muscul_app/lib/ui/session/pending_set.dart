/// Valeurs en cours d'édition pour la prochaine série à valider d'un exo
/// (avant d'être enregistrées). [PendingSet] est purement local à l'écran
/// de session active.
class PendingSet {
  final int reps;
  final double weight;
  final int? rpe;
  const PendingSet({required this.reps, required this.weight, this.rpe});

  PendingSet copyWith({int? reps, double? weight, int? rpe}) => PendingSet(
        reps: reps ?? this.reps,
        weight: weight ?? this.weight,
        rpe: rpe ?? this.rpe,
      );
}
