/// Estimation du 1RM (répétition maximale) par la formule d'Epley :
///
///   1RM ≈ poids × (1 + reps / 30)
///
/// Pour une série à 1 rep, le 1RM est le poids lui-même. Renvoie `null`
/// quand l'estimation n'a pas de sens (poids ≤ 0 ou reps ≤ 0) — typiquement
/// pour un exercice au poids du corps sans charge additionnelle.
double? estimateOneRepMax(double weightKg, int reps) {
  if (weightKg <= 0 || reps <= 0) return null;
  if (reps == 1) return weightKg;
  return weightKg * (1 + reps / 30.0);
}
