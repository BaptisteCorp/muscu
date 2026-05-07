import '../../models/exercise.dart';
import '../../models/progression_target.dart';
import '../../models/session.dart';
import '../../models/user_settings.dart';
import '../e1rm.dart';
import 'double_progression.dart';

/// RPE-autoregulated progression based on a moving 3-session e1RM.
///
///   slope > 0.5 kg/session  → RPE target 8
///   0 ≤ slope ≤ 0.5         → RPE target 7.5  (rounded to 8 since rpe is int)
///   slope < 0               → RPE target 7    (light deload)
///
/// targetReps = mid of (min..max), rounded
/// weight     = e1RMcurrent / (1 + (targetReps + (10 - rpe)) / 30)
/// rounded to nearest increment.
///
/// Falls back to double-progression with a friendly message when fewer than
/// 2 sessions of working-set history are available.
class RpeAutoregulatedStrategy {
  const RpeAutoregulatedStrategy();

  ProgressionTarget compute({
    required Exercise exercise,
    required int plannedSets,
    required List<SessionExerciseWithSets> history,
    required UserSettings settings,
  }) {
    final increment = exercise.effectiveIncrementKg(settings.defaultIncrementKg);

    final perSessionE1rm = <double>[];
    for (final session in history) {
      final working = session.sets.where((s) => !s.isWarmup).toList();
      if (working.isEmpty) continue;
      final best = working
          .map((s) => estimate1RM(
                weightKg: s.weightKg,
                reps: s.reps,
                rpe: s.rpe,
              ))
          .reduce((a, b) => a > b ? a : b);
      perSessionE1rm.add(best);
    }

    if (perSessionE1rm.length < 2) {
      final fallback = const DoubleProgressionStrategy().compute(
        exercise: exercise,
        plannedSets: plannedSets,
        history: history,
        settings: settings,
      );
      return ProgressionTarget(
        targetSets: fallback.targetSets,
        targetReps: fallback.targetReps,
        targetWeightKg: fallback.targetWeightKg,
        targetRpe: fallback.targetRpe,
        reason:
            'Pas assez d\'historique pour le mode auto-régulé, on reste en double progression',
      );
    }

    // history is most-recent-first, so perSessionE1rm[0] = newest.
    final last3 = perSessionE1rm.take(3).toList();
    final e1rmCurrent = last3.reduce((a, b) => a + b) / last3.length;

    // slope kg/session over up to 3 sessions: (newest - oldest) / span
    final n = perSessionE1rm.length >= 4 ? 3 : (perSessionE1rm.length - 1);
    final slope = (perSessionE1rm.first - perSessionE1rm[n]) / n;

    final int targetRpe;
    if (slope > 0.5) {
      targetRpe = 8;
    } else if (slope >= 0) {
      // 7.5 not representable as int — round up to 8 for the working set.
      targetRpe = 8;
    } else {
      targetRpe = 7;
    }

    final targetReps =
        ((exercise.targetRepRangeMin + exercise.targetRepRangeMax) / 2).round();

    final raw = weightForTargetReps(
      e1rm: e1rmCurrent,
      reps: targetReps,
      rpe: targetRpe,
    );
    final weight = roundToStep(raw, increment);

    return ProgressionTarget(
      targetSets: plannedSets,
      targetReps: targetReps,
      targetWeightKg: weight,
      targetRpe: targetRpe,
      reason:
          'Charge calculée pour $targetReps reps @ RPE $targetRpe (e1RM courant ${e1rmCurrent.toStringAsFixed(1)}kg)',
    );
  }
}
