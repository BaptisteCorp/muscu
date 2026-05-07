import '../../models/exercise.dart';
import '../../models/progression_target.dart';
import '../../models/session.dart';
import '../../models/user_settings.dart';

/// Double-progression strategy — pure function, no I/O.
///
/// Algo (per the design doc):
///   - working set = set with isWarmup == false
///   - lastTopReps = the working set with the LEAST reps in the most recent session
///   - lastWeight = the most-used weight among working sets
///   - effectiveRpe = max RPE across working sets (null treated as 8)
///   1. lastTopReps >= max  AND rpe <= 9    → +increment, reps = min
///   2. else lastTopReps >= prevTarget AND rpe <= 9 → same weight, reps = min(lastTopReps + 1, max)
///   3. else (failure or rpe == 10)         → same weight, reps = lastTopReps (retry)
///   4. no history                           → starting weight, reps = min
class DoubleProgressionStrategy {
  const DoubleProgressionStrategy();

  ProgressionTarget compute({
    required Exercise exercise,
    required int plannedSets,
    required List<SessionExerciseWithSets> history,
    required UserSettings settings,
  }) {
    final increment = exercise.effectiveIncrementKg(settings.defaultIncrementKg);
    final repMin = exercise.targetRepRangeMin;
    final repMax = exercise.targetRepRangeMax;

    // Find the most recent session that actually has working sets.
    SessionExerciseWithSets? lastWithWork;
    for (final s in history) {
      if (s.sets.any((set) => !set.isWarmup)) {
        lastWithWork = s;
        break;
      }
    }

    if (lastWithWork == null) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: repMin,
        targetWeightKg: exercise.startingWeightKg,
        reason: 'Première fois, on démarre tranquille',
      );
    }

    final workingSets = lastWithWork.sets.where((s) => !s.isWarmup).toList();
    final lastTopReps =
        workingSets.map((s) => s.reps).reduce((a, b) => a < b ? a : b);

    // Most-used weight (mode). Tie → prefer the heaviest.
    final weightCounts = <double, int>{};
    for (final s in workingSets) {
      weightCounts[s.weightKg] = (weightCounts[s.weightKg] ?? 0) + 1;
    }
    final maxCount = weightCounts.values.reduce((a, b) => a > b ? a : b);
    final lastWeight = weightCounts.entries
        .where((e) => e.value == maxCount)
        .map((e) => e.key)
        .reduce((a, b) => a > b ? a : b);

    final maxRpe = workingSets
        .map((s) => s.rpe ?? 8)
        .reduce((a, b) => a > b ? a : b);

    final atTopOfRange = lastTopReps >= repMax;
    final crushedIt = maxRpe <= 9;
    final hardFail = maxRpe >= 10;

    if (atTopOfRange && crushedIt) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: repMin,
        targetWeightKg: lastWeight + increment,
        reason: '+${_fmt(increment)}kg car ${plannedSets}×$repMax réussi',
      );
    }
    if (!hardFail && lastTopReps >= repMin) {
      final nextReps = (lastTopReps + 1).clamp(repMin, repMax);
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: nextReps,
        targetWeightKg: lastWeight,
        reason: '+1 rep, on monte vers $repMax',
      );
    }
    return ProgressionTarget(
      targetSets: plannedSets,
      targetReps: lastTopReps,
      targetWeightKg: lastWeight,
      reason: 'On retente les mêmes valeurs',
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}
