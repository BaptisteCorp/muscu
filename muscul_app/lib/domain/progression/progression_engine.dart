import '../../core/utils/formatters.dart';
import '../models/enums.dart';
import '../models/exercise.dart';
import '../models/progression_target.dart';
import '../models/session.dart';
import '../models/user_settings.dart';

/// Moteur de surcharge progressive — pure function, sans I/O.
///
/// Modèle simple, déterministe, sans auto-régulation :
///   1. Si l'exercice n'a pas d'historique : on retourne le poids de départ
///      au bas de la fourchette de reps.
///   2. Si la surcharge progressive est désactivée : on rejoue exactement les
///      mêmes valeurs que la dernière séance.
///   3. Sinon, on tente une progression. Elle n'a lieu QUE si :
///        - toutes les séries de travail prévues ont été faites
///        - les reps minimum de la fourchette ont été atteintes sur chaque set
///          à la charge de travail
///        - la chute de reps intra-séance à la charge de travail reste sous
///          `_maxIntraSessionDropOff` (sinon = fatigue, on consolide)
///        - aucun set ne dépasse `minimumRpeThreshold` (les sets sans RPE
///          sont considérés comme validés)
///
///      Toute l'évaluation reps / drop-off / RPE ne porte QUE sur les séries
///      à la charge de travail (le poids "mode"). Les séries plus légères de
///      la même séance — montée en charge (ramp) ou back-off après un échec —
///      ne comptent ni pour ni contre la progression.
///   4. Selon `progressionPriority` :
///        - REPS_FIRST : on monte les reps jusqu'au max, puis +incrément kg
///          et retour au min de reps.
///        - WEIGHT_FIRST : on monte le poids à chaque succès en gardant les
///          reps identiques (clampées dans la fourchette).
///
/// [history] est trié par séance la plus récente en premier.
class ProgressionEngine {
  static ProgressionTarget computeNextTarget({
    required Exercise exercise,
    required int plannedSets,
    required List<SessionExerciseWithSets> history,
    required UserSettings settings,
  }) {
    final increment = exercise.effectiveIncrementKg(settings.defaultIncrementKg);
    final repMin = exercise.targetRepRangeMin;
    final repMax = exercise.targetRepRangeMax;

    // Anchor for the next target: the most recent session whose mode weight
    // matches the highest weight seen across recent history. This makes
    // progression "ratchet up only" — a single under-load day (e.g. user
    // dropped from 44 to 40kg because they were tired) does NOT pull the
    // baseline down. The user keeps the higher anchor and retries it next
    // session.
    final lastWithWork = _ratchetAnchor(history);

    if (lastWithWork == null) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: repMin,
        targetWeightKg: exercise.startingWeightKg,
        reason: 'Première séance',
      );
    }

    final workingSets =
        lastWithWork.sets.where((s) => !s.isWarmup).toList(growable: false);
    final lastWeight = _modeWeight(workingSets);
    // Only the sets AT the working (mode) weight inform progression. Lighter
    // sets in the same session are ramp-ups or back-offs and must not pollute
    // the rep baseline — otherwise a 100kg back-off after working at 120kg
    // would drag the target reps down, and a light ramp set would inflate it.
    final workingWeightSets = workingSets
        .where((s) => s.weightKg == lastWeight)
        .toList(growable: false);
    final lastTopReps = workingWeightSets
        .map((s) => s.reps)
        .reduce((a, b) => a < b ? a : b);

    // Detect "ratchet kicked in": the most recent session's mode weight is
    // below the anchor's. Means the user underloaded and we kept the
    // higher anchor — call it out so the user sees the difference between
    // what they did and what the engine is proposing.
    final mostRecentWeight = _mostRecentModeWeight(history);
    final ratchetedFromUnderload =
        mostRecentWeight != null && mostRecentWeight < lastWeight;
    final ratchetNote = ratchetedFromUnderload
        ? 'Séance précédente plus légère (${fmtKg(mostRecentWeight)}kg) — '
            'on retente ${fmtKg(lastWeight)}kg. '
        : '';

    if (!exercise.progressiveOverloadEnabled) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: lastTopReps.clamp(repMin, repMax),
        targetWeightKg: lastWeight,
        reason: '${ratchetNote}Surcharge progressive désactivée',
      );
    }

    final validation = _validate(
      allWorkingSets: workingSets,
      workingWeightSets: workingWeightSets,
      workingWeightKg: lastWeight,
      plannedSets: plannedSets,
      repMin: repMin,
      rpeThreshold: exercise.minimumRpeThreshold,
    );

    if (!validation.passed) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: lastTopReps.clamp(repMin, repMax),
        targetWeightKg: lastWeight,
        reason: '$ratchetNote${validation.reason}',
      );
    }

    switch (exercise.progressionPriority) {
      case ProgressionPriority.repsFirst:
        if (lastTopReps >= repMax) {
          return ProgressionTarget(
            targetSets: plannedSets,
            targetReps: repMin,
            targetWeightKg: lastWeight + increment,
            reason:
                '$ratchetNote+${fmtKg(increment)}kg, retour à $repMin reps',
          );
        }
        final nextReps = (lastTopReps + 1).clamp(repMin, repMax);
        return ProgressionTarget(
          targetSets: plannedSets,
          targetReps: nextReps,
          targetWeightKg: lastWeight,
          reason: '$ratchetNote+1 rep, on monte vers $repMax',
        );
      case ProgressionPriority.weightFirst:
        return ProgressionTarget(
          targetSets: plannedSets,
          targetReps: lastTopReps.clamp(repMin, repMax),
          targetWeightKg: lastWeight + increment,
          reason: '$ratchetNote+${fmtKg(increment)}kg',
        );
    }
  }

  /// Mode weight of the most recent session that has working sets, or null
  /// if there's no such session. Used to detect "user under-loaded last
  /// time" — the engine then keeps the heavier anchor and surfaces a hint.
  static double? _mostRecentModeWeight(
      List<SessionExerciseWithSets> history) {
    for (final s in history) {
      final working =
          s.sets.where((set) => !set.isWarmup).toList(growable: false);
      if (working.isEmpty) continue;
      return _modeWeight(working);
    }
    return null;
  }

  /// Picks the anchor session for next-target computation under the
  /// "ratchet up only" rule:
  ///
  ///   * scan the most recent N sessions with working sets;
  ///   * find the highest mode weight among them;
  ///   * return the most recent session whose mode weight equals that max.
  ///
  /// We cap at the last 5 sessions so a long-term, deliberate deload
  /// eventually wins — once the user has been training lighter for ~5
  /// sessions in a row, the old peak falls out of the window and the
  /// anchor follows them down.
  static SessionExerciseWithSets? _ratchetAnchor(
      List<SessionExerciseWithSets> history) {
    const window = 5;
    double maxWeight = -1;
    for (final s in history.take(window)) {
      final working =
          s.sets.where((set) => !set.isWarmup).toList(growable: false);
      if (working.isEmpty) continue;
      final w = _modeWeight(working);
      if (w > maxWeight) maxWeight = w;
    }
    if (maxWeight < 0) return null;
    for (final s in history.take(window)) {
      final working =
          s.sets.where((set) => !set.isWarmup).toList(growable: false);
      if (working.isEmpty) continue;
      if (_modeWeight(working) == maxWeight) return s;
    }
    return null;
  }

  /// Mode (poids le plus utilisé). En cas d'égalité on prend le plus lourd.
  ///
  /// Returns 0 on an empty list. Callers already filter out warm-up-only
  /// sessions before calling this, but the guard keeps the function safe
  /// in case a future caller forgets — `.reduce` on an empty iterable
  /// would otherwise crash with "Bad state: No element".
  static double _modeWeight(List<SetEntry> workingSets) {
    if (workingSets.isEmpty) return 0;
    final counts = <double, int>{};
    for (final s in workingSets) {
      counts[s.weightKg] = (counts[s.weightKg] ?? 0) + 1;
    }
    final max = counts.values.reduce((a, b) => a > b ? a : b);
    return counts.entries
        .where((e) => e.value == max)
        .map((e) => e.key)
        .reduce((a, b) => a > b ? a : b);
  }

  /// Chute de reps intra-séance maximale tolérée à la charge de travail avant
  /// que le moteur refuse d'ajouter de la charge.
  ///
  /// Une perte de reps d'une série à l'autre au même poids est NORMALE : la
  /// fatigue s'accumule, et un entraînement mené proche de l'échec avec repos
  /// court produit couramment ~20-35 % de chute entre la 1re et la dernière
  /// série. On ne bloque donc QUE les effondrements nets — pire série ≤ 60 %
  /// de la meilleure (≥ 40 % de chute) — qui trahissent une charge trop lourde
  /// ou une 1re série partie bien trop près de l'échec. En dessous, la chute
  /// fait partie du travail et n'empêche pas la progression. La garde des reps
  /// minimum (`repMin`) couvre déjà le cas « tombé sous la fourchette ».
  static const double _maxIntraSessionDropOff = 0.40;

  static _Validation _validate({
    required List<SetEntry> allWorkingSets,
    required List<SetEntry> workingWeightSets,
    required double workingWeightKg,
    required int plannedSets,
    required int repMin,
    required int? rpeThreshold,
  }) {
    // Volume : on compte TOUTES les séries de travail (ramp/back-off inclus) —
    // une montée en charge légère ne doit pas faire échouer ce contrôle.
    if (allWorkingSets.length < plannedSets) {
      return const _Validation(false,
          'Toutes les séries n\'ont pas été validées à la dernière séance, '
          'on reste au même poids');
    }
    // À partir d'ici, on ne juge que les séries à la charge de travail.
    final minReps =
        workingWeightSets.map((s) => s.reps).reduce((a, b) => a < b ? a : b);
    if (minReps < repMin) {
      return const _Validation(false, 'Reps minimum non atteintes');
    }
    // Garde anti-fatigue : grosse chute de reps à charge constante.
    if (workingWeightSets.length >= 2) {
      final maxReps = workingWeightSets
          .map((s) => s.reps)
          .reduce((a, b) => a > b ? a : b);
      if (maxReps > 0 &&
          (maxReps - minReps) / maxReps >= _maxIntraSessionDropOff) {
        return _Validation(
          false,
          'Grosse chute de reps à ${fmtKg(workingWeightKg)}kg '
          '($maxReps→$minReps) — signe de fatigue, on consolide ce poids '
          'avant d\'ajouter de la charge',
        );
      }
    }
    if (rpeThreshold != null) {
      // Les sets sans RPE renseigné sont considérés validés (on les ignore).
      final ratedSets =
          workingWeightSets.where((s) => s.rpe != null).toList();
      if (ratedSets.isNotEmpty) {
        final maxRpe =
            ratedSets.map((s) => s.rpe!).reduce((a, b) => a > b ? a : b);
        if (maxRpe > rpeThreshold) {
          return const _Validation(false,
              'RPE trop haut à la dernière séance pour augmenter à celle-ci');
        }
      }
    }
    return const _Validation(true, '');
  }
}

class _Validation {
  final bool passed;
  final String reason;
  const _Validation(this.passed, this.reason);
}
