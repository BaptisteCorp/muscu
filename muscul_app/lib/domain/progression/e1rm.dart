/// Estimated 1RM using Epley with RPE adjustment.
///
/// e1RM = weight × (1 + (reps + (10 - rpe)) / 30)
///
/// If [rpe] is null, defaults to 8 (a common conservative assumption).
double estimate1RM({
  required double weightKg,
  required int reps,
  int? rpe,
}) {
  if (reps <= 0 || weightKg <= 0) return 0.0;
  final usedRpe = rpe ?? 8;
  return weightKg * (1 + (reps + (10 - usedRpe)) / 30.0);
}

/// Inverse formula: from a target e1RM, target reps, and target RPE,
/// compute the working weight. Returns 0 when inputs make no sense.
double weightForTargetReps({
  required double e1rm,
  required int reps,
  required int rpe,
}) {
  final divisor = 1 + (reps + (10 - rpe)) / 30.0;
  if (divisor <= 0) return 0.0;
  return e1rm / divisor;
}

/// Round [value] to the nearest multiple of [step]. step must be > 0.
double roundToStep(double value, double step) {
  if (step <= 0) return value;
  return (value / step).round() * step;
}
