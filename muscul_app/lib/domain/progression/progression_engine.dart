import '../../core/utils/formatters.dart';
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
///   4. Double progression (l'unique modèle, celui utilisé partout) : on monte
///      les reps jusqu'au haut de la fourchette, puis +incrément kg et retour
///      au plancher de reps.
///   5. Recalibrage e1RM : si l'échec vient du fait que les reps sont tombées
///      SOUS le plancher de la fourchette à la charge de travail (la charge
///      est trop lourde pour tenir la fourchette sur toutes les séries), on ne
///      réimpose pas le même poids — on estime via Epley une charge tenable à
///      partir de la perf réelle (1RM estimé de la série la PLUS FATIGUÉE, pour
///      que la charge tienne sur toutes les séries) et on la prescrit
///      (cf. `_recalibratedWeight`). C'est le cas "j'ai fait 8 puis 6 à 120,
///      inutile de me redemander 4×8 à 120".
///   6. Deload : si l'échec persiste pour une autre raison (séries
///      incomplètes, RPE, effondrement de reps) `_deloadStallThreshold`
///      séances de suite au même poids, on recule de `_deloadFactor` (charge
///      allégée, reps au max) pour accumuler du volume. Le poids changeant, le
///      compteur d'échecs repart de zéro.
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

    // Poids du corps : on ne prescrit JAMAIS de charge — la surcharge passe
    // uniquement par les reps. Toute la machinerie poids (mode, ratchet,
    // deload) est court-circuitée et le poids cible reste à 0.
    if (exercise.useBodyweight) {
      return _bodyweightTarget(
        exercise: exercise,
        plannedSets: plannedSets,
        history: history,
        repMin: repMin,
      );
    }

    // Anchor for the next target: the most recent session whose mode weight
    // matches the highest weight seen across recent history. This makes
    // progression "ratchet up only" — a single under-load day (e.g. user
    // dropped from 44 to 40kg because they were tired) does NOT pull the
    // baseline down. The user keeps the higher anchor and retries it next
    // session.
    final lastWithWork = _ratchetAnchor(history, repMin: repMin);

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
      repMax: repMax,
      rpeThreshold: exercise.minimumRpeThreshold,
    );

    if (!validation.passed) {
      // Charge trop lourde pour TENIR le plancher de reps sur toutes les séries
      // → recalibrage e1RM plutôt que de réimposer un poids qu'on sait
      // intenable. On vise le haut de la fourchette (plus léger, plus de reps),
      // cohérent avec la double progression : on accumule du volume à charge
      // gérable, puis on remonte les reps puis le poids. Si le calcul ne propose
      // pas une charge plus légère, on retombe sur la logique hold / deload.
      if (validation.kind == _FailKind.repsBelowRange) {
        final recalReps = repMax;
        final recalWeight = _recalibratedWeight(
          workingWeightSets: workingWeightSets,
          currentWeight: lastWeight,
          targetReps: recalReps,
          increment: increment,
        );
        if (recalWeight != null) {
          return ProgressionTarget(
            targetSets: plannedSets,
            targetReps: recalReps,
            targetWeightKg: recalWeight,
            reason: 'Trop lourd pour tenir $recalReps reps sur toutes les '
                'séries à ${fmtKg(lastWeight)}kg — on recale à '
                '${fmtKg(recalWeight)}kg (estimé d\'après ta perf) pour '
                'valider toutes les séries, puis on remonte',
          );
        }
      }
      // Stall → deload. Si l'athlète a échoué le poids de travail plusieurs
      // séances d'affilée, le grinder encore est contre-productif : on recule
      // de ~10% et on vise le haut de la fourchette pour accumuler du volume
      // à charge gérable, puis on re-grimpe ("the reset").
      final failures = _consecutiveFailuresAtWeight(
        history: history,
        weight: lastWeight,
        plannedSets: plannedSets,
        repMin: repMin,
        repMax: repMax,
        rpeThreshold: exercise.minimumRpeThreshold,
      );
      if (failures >= _deloadStallThreshold) {
        final deloadWeight = _deloadWeight(lastWeight, increment);
        return ProgressionTarget(
          targetSets: plannedSets,
          targetReps: repMax,
          targetWeightKg: deloadWeight,
          reason: 'Bloqué $failures séances à ${fmtKg(lastWeight)}kg — '
              'deload à ${fmtKg(deloadWeight)}kg ($repMax reps) pour '
              'accumuler du volume et repartir plus fort',
        );
      }
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: lastTopReps.clamp(repMin, repMax),
        targetWeightKg: lastWeight,
        reason: '$ratchetNote${validation.reason}',
      );
    }

    // Double progression : tant qu'on n'est pas au plafond de reps, on monte
    // d'une rep ; une fois le plafond atteint, +incrément kg et retour au
    // plancher de reps.
    if (lastTopReps >= repMax) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: repMin,
        targetWeightKg: lastWeight + increment,
        reason: '$ratchetNote+${fmtKg(increment)}kg, retour à $repMin reps',
      );
    }
    final nextReps = (lastTopReps + 1).clamp(repMin, repMax);
    return ProgressionTarget(
      targetSets: plannedSets,
      targetReps: nextReps,
      targetWeightKg: lastWeight,
      reason: '$ratchetNote+1 rep, on monte vers $repMax',
    );
  }

  /// Cible "poids du corps" : surcharge par les reps uniquement, poids = 0.
  ///
  /// On ignore totalement le poids logué (donnée potentiellement sale, ex.
  /// 20kg par défaut) et on progresse sur la pire série de la dernière séance :
  ///   - pas d'historique → fourchette basse ;
  ///   - surcharge désactivée → on rejoue les reps ;
  ///   - séance validée (séries complètes, reps ≥ min, pas d'effondrement,
  ///     RPE ok) → +1 rep (non plafonné : pas de charge à ajouter) ;
  ///   - sinon → on tient les reps.
  static ProgressionTarget _bodyweightTarget({
    required Exercise exercise,
    required int plannedSets,
    required List<SessionExerciseWithSets> history,
    required int repMin,
  }) {
    final last = _mostRecentWithWork(history);
    if (last == null) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: repMin,
        targetWeightKg: 0,
        reason: 'Première séance',
      );
    }
    final working =
        last.sets.where((s) => !s.isWarmup).toList(growable: false);
    final worstReps =
        working.map((s) => s.reps).reduce((a, b) => a < b ? a : b);
    final heldReps = worstReps < repMin ? repMin : worstReps;

    if (!exercise.progressiveOverloadEnabled) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: heldReps,
        targetWeightKg: 0,
        reason: 'Surcharge progressive désactivée',
      );
    }

    // Validation reps-only, avec des messages centrés reps (pas de kg).
    final holdReason = _bodyweightHoldReason(
      working: working,
      plannedSets: plannedSets,
      repMin: repMin,
      worstReps: worstReps,
      rpeThreshold: exercise.minimumRpeThreshold,
    );
    if (holdReason != null) {
      return ProgressionTarget(
        targetSets: plannedSets,
        targetReps: heldReps,
        targetWeightKg: 0,
        reason: holdReason,
      );
    }
    return ProgressionTarget(
      targetSets: plannedSets,
      targetReps: worstReps + 1,
      targetWeightKg: 0,
      reason: '+1 rep',
    );
  }

  /// Raison de tenir les reps sur un exercice au poids du corps, ou null si la
  /// séance valide la progression. Même logique que [_validate] mais formulée
  /// en reps (jamais en kg).
  static String? _bodyweightHoldReason({
    required List<SetEntry> working,
    required int plannedSets,
    required int repMin,
    required int worstReps,
    required int? rpeThreshold,
  }) {
    if (working.length < plannedSets) {
      return 'Séries de travail incomplètes — on garde le même objectif de reps';
    }
    if (worstReps < repMin) {
      // Au poids du corps il n'y a pas de plafond : on ne référence que le
      // plancher (si tu l'as changé dans l'exercice, la cible suit).
      return 'On vise au moins $repMin reps par série avant d\'en ajouter';
    }
    final bestReps = working.map((s) => s.reps).reduce((a, b) => a > b ? a : b);
    if (bestReps > 0 &&
        (bestReps - worstReps) / bestReps >= _maxIntraSessionDropOff) {
      return 'Grosse chute de reps ($bestReps→$worstReps) — signe de fatigue, '
          'on consolide avant d\'ajouter des reps';
    }
    if (rpeThreshold != null) {
      final rated = working.where((s) => s.rpe != null).toList();
      if (rated.isNotEmpty) {
        final maxRpe = rated.map((s) => s.rpe!).reduce((a, b) => a > b ? a : b);
        if (maxRpe > rpeThreshold) {
          return 'RPE trop haut — on garde le même objectif de reps';
        }
      }
    }
    return null;
  }

  /// Séance la plus récente ayant au moins une série de travail (hors warm-up).
  static SessionExerciseWithSets? _mostRecentWithWork(
      List<SessionExerciseWithSets> history) {
    for (final s in history) {
      if (s.sets.any((set) => !set.isWarmup)) return s;
    }
    return null;
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
  ///
  /// EXCEPTION « pic abandonné » : si la séance la plus lourde a raté le
  /// plancher de reps ([_failedRepFloor]) ET qu'une séance PLUS RÉCENTE existe
  /// à une charge strictement plus légère, ce pic est considéré comme
  /// délibérément abandonné (l'athlète est descendu après l'avoir échoué, p.ex.
  /// suite à un recalibrage e1RM) — on l'exclut et on cherche l'ancre parmi les
  /// charges restantes. Sans ça, le pic raté resterait l'ancre pendant ~5
  /// séances et bloquerait la progression sur la charge plus légère effectivement
  /// travaillée. Un pic RÉUSSI plus lourd, lui, reste l'ancre (on retente la
  /// charge même après un jour « léger » : c'est le ratchet up-only d'origine).
  static SessionExerciseWithSets? _ratchetAnchor(
    List<SessionExerciseWithSets> history, {
    required int repMin,
  }) {
    const window = 5;
    final sessions = history
        .take(window)
        .where((s) => s.sets.any((set) => !set.isWarmup))
        .toList(growable: false);
    if (sessions.isEmpty) return null;

    final excluded = <double>{};
    while (true) {
      double maxWeight = -1;
      for (final s in sessions) {
        final w = _modeWeight(
            s.sets.where((set) => !set.isWarmup).toList(growable: false));
        if (excluded.contains(w)) continue;
        if (w > maxWeight) maxWeight = w;
      }
      if (maxWeight < 0) return null;

      // Indice (most-recent-first) de la séance la plus récente à maxWeight.
      final anchorIdx = sessions.indexWhere((s) =>
          _modeWeight(
              s.sets.where((set) => !set.isWarmup).toList(growable: false)) ==
          maxWeight);
      final anchor = sessions[anchorIdx];

      final supersededByLighter = sessions.take(anchorIdx).any((s) =>
          _modeWeight(
              s.sets.where((set) => !set.isWarmup).toList(growable: false)) <
          maxWeight);
      if (_failedRepFloor(anchor, repMin) && supersededByLighter) {
        excluded.add(maxWeight);
        continue;
      }
      return anchor;
    }
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

  /// Nombre d'échecs consécutifs au même poids de travail avant de déclencher
  /// un deload. À 2, on recule dès le 2e échec d'affilée — plus réactif que le
  /// standard 3 séances ("mauvais jour"), choix assumé pour ne pas laisser
  /// l'athlète s'enliser à grinder une charge.
  static const int _deloadStallThreshold = 2;

  /// Proportion retirée de la charge lors d'un deload — 10%, le "reset"
  /// classique : assez pour repasser le mur sans perdre trop de terrain.
  static const double _deloadFactor = 0.10;

  /// Poids de deload : -[_deloadFactor] arrondi à l'incrément, garanti
  /// strictement sous la charge de travail (jamais négatif).
  static double _deloadWeight(double workingWeight, double increment) {
    final inc = increment > 0 ? increment : 1.0;
    var w = (workingWeight * (1 - _deloadFactor) / inc).round() * inc;
    if (w >= workingWeight) w = workingWeight - inc;
    // Cas dégénéré (barre ultra-légère) : on ne descend pas en négatif.
    if (w < 0) w = workingWeight;
    return w;
  }

  /// 1RM estimé (formule d'Epley) : `1RM = poids × (1 + reps/30)`.
  ///
  /// Fiable sur ~1-10 reps ; au-delà elle surestime légèrement la force, mais
  /// nos fourchettes de travail restent dans cette plage. Elle nous sert à
  /// comparer la difficulté de séries faites à des couples (poids, reps)
  /// différents et à en déduire une charge cible.
  static double _epley1RM(double weightKg, int reps) =>
      weightKg * (1 + reps / 30.0);

  /// Charge théorique permettant [reps] répétitions pour un 1RM estimé
  /// [e1rm] (Epley inversé), arrondie à l'incrément de la barre.
  static double _loadForReps(double e1rm, int reps, double increment) {
    final inc = increment > 0 ? increment : 1.0;
    final raw = e1rm / (1 + reps / 30.0);
    return (raw / inc).round() * inc;
  }

  /// Recalibrage e1RM : quand la charge de travail est trop lourde pour tenir
  /// la fourchette de reps sur TOUTES les séries prévues, on ne réimpose pas
  /// bêtement le même poids (l'athlète sait déjà qu'il échouera) — on estime
  /// un poids réellement tenable à partir de sa perf.
  ///
  /// On part du 1RM estimé de la série la PLUS FATIGUÉE à la charge de travail
  /// (e1RM le plus bas), puis on en déduit la charge permettant [targetReps]
  /// reps. Utiliser la pire série — et non la moyenne — rend la charge tenable
  /// sur TOUTES les séries, y compris la dernière : la fatigue intra-séance fait
  /// chuter les reps set après set, donc viser la moyenne laisserait les
  /// dernières séries sous la cible (surtout en haut de fourchette où Epley
  /// surestime déjà la charge tenable). C'est l'application directe de deux
  /// résultats :
  ///   * pour l'hypertrophie la charge est flexible — on peut aller plus léger
  ///     et faire plus de reps sans perdre en stimulus tant qu'on pousse près
  ///     de l'échec ;
  ///   * on baisse la charge dès qu'on ne tient plus la fourchette cible.
  ///
  /// Retourne null si aucune série exploitable ou si le calcul ne propose pas
  /// une charge strictement plus légère — dans ce cas on laisse la logique
  /// hold / deload classique reprendre la main.
  static double? _recalibratedWeight({
    required List<SetEntry> workingWeightSets,
    required double currentWeight,
    required int targetReps,
    required double increment,
  }) {
    if (workingWeightSets.isEmpty) return null;
    final minE1rm = workingWeightSets
        .map((s) => _epley1RM(s.weightKg, s.reps))
        .reduce((a, b) => a < b ? a : b);
    var w = _loadForReps(minE1rm, targetReps, increment);
    // Pas plus léger que la charge actuelle → ce n'est pas un vrai problème de
    // charge (fatigue, mauvais jour) : on laisse hold / deload décider.
    if (w >= currentWeight) return null;
    final inc = increment > 0 ? increment : 1.0;
    if (w < inc) w = inc; // jamais sous un incrément (charge plancher plausible)
    return w;
  }

  /// Vrai si, à la charge de travail (mode) de [session], l'athlète n'a pas
  /// atteint le plancher de reps sur toutes ses séries — i.e. la séance a raté
  /// le plancher de la fourchette. Sert à l'ancrage : un pic de charge raté de
  /// la sorte peut être « abandonné » au profit d'une séance plus légère.
  static bool _failedRepFloor(SessionExerciseWithSets session, int repMin) {
    final working =
        session.sets.where((s) => !s.isWarmup).toList(growable: false);
    if (working.isEmpty) return false;
    final mode = _modeWeight(working);
    final atWeight = working.where((s) => s.weightKg == mode);
    final minReps = atWeight.map((s) => s.reps).reduce((a, b) => a < b ? a : b);
    return minReps < repMin;
  }

  /// Nombre de séances les plus récentes, CONSÉCUTIVES, dont le poids de
  /// travail (mode) vaut [weight] et qui ont échoué la validation. S'arrête au
  /// premier succès ou au premier poids de travail différent (un recul
  /// volontaire ou une progression cassent la série d'échecs).
  static int _consecutiveFailuresAtWeight({
    required List<SessionExerciseWithSets> history,
    required double weight,
    required int plannedSets,
    required int repMin,
    required int repMax,
    required int? rpeThreshold,
  }) {
    var count = 0;
    for (final s in history) {
      final working =
          s.sets.where((set) => !set.isWarmup).toList(growable: false);
      if (working.isEmpty) continue;
      if (_modeWeight(working) != weight) break;
      final atWeight = working
          .where((set) => set.weightKg == weight)
          .toList(growable: false);
      final passed = _validate(
        allWorkingSets: working,
        workingWeightSets: atWeight,
        workingWeightKg: weight,
        plannedSets: plannedSets,
        repMin: repMin,
        repMax: repMax,
        rpeThreshold: rpeThreshold,
      ).passed;
      if (passed) break;
      count++;
    }
    return count;
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
    required int repMax,
    required int? rpeThreshold,
  }) {
    // Volume : on compte TOUTES les séries de travail (ramp/back-off inclus) —
    // une montée en charge légère ne doit pas faire échouer ce contrôle.
    if (allWorkingSets.length < plannedSets) {
      return const _Validation(
        false,
        'Toutes les séries n\'ont pas été validées à la dernière séance, '
        'on reste au même poids',
        _FailKind.incompleteSets,
      );
    }
    // À partir d'ici, on ne juge que les séries à la charge de travail.
    final minReps =
        workingWeightSets.map((s) => s.reps).reduce((a, b) => a < b ? a : b);
    if (minReps < repMin) {
      // On référence la fourchette pour que, si elle a changé dans l'exercice,
      // l'utilisateur voie tout de suite la nouvelle cible.
      return _Validation(
        false,
        'Reps sous ta fourchette ($repMin-$repMax) — on vise $repMin reps '
        'à ${fmtKg(workingWeightKg)}kg avant d\'ajouter de la charge',
        _FailKind.repsBelowRange,
      );
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
          _FailKind.dropOff,
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
          return const _Validation(
            false,
            'RPE trop haut à la dernière séance pour augmenter à celle-ci',
            _FailKind.rpe,
          );
        }
      }
    }
    return const _Validation(true, '');
  }
}

/// Pourquoi la validation a échoué — sert à décider du correctif :
/// seul [repsBelowRange] (la charge est trop lourde pour tenir le plancher
/// de reps) déclenche le recalibrage e1RM. Les autres cas gardent la logique
/// hold / deload classique.
enum _FailKind { none, incompleteSets, repsBelowRange, dropOff, rpe }

class _Validation {
  final bool passed;
  final String reason;
  final _FailKind kind;
  const _Validation(this.passed, this.reason, [this.kind = _FailKind.none]);
}
