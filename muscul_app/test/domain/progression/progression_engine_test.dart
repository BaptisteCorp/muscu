import 'package:flutter_test/flutter_test.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/session.dart';
import 'package:reps/domain/models/user_settings.dart';
import 'package:reps/domain/progression/progression_engine.dart';

const _settings = UserSettings();

Exercise _exercise({
  bool overloadEnabled = true,
  int? rpeThreshold,
  int min = 8,
  int max = 10,
  double startingWeight = 44,
  double? overrideIncrement = 2.0,
  bool useBodyweight = false,
}) {
  return Exercise(
    id: 'ex-1',
    name: 'Bench',
    category: ExerciseCategory.push,
    primaryMuscle: MuscleGroup.chest,
    secondaryMuscles: const [],
    equipment: Equipment.barbell,
    isCustom: false,
    progressiveOverloadEnabled: overloadEnabled,
    minimumRpeThreshold: rpeThreshold,
    targetRepRangeMin: min,
    targetRepRangeMax: max,
    startingWeightKg: startingWeight,
    defaultIncrementKg: overrideIncrement,
    useBodyweight: useBodyweight,
    updatedAt: DateTime(2026, 1, 1),
  );
}

SetEntry _set({
  required int idx,
  required int reps,
  required double weight,
  int? rpe,
  bool warmup = false,
}) {
  return SetEntry(
    id: 's$idx-${DateTime.now().microsecondsSinceEpoch}-$reps',
    sessionExerciseId: 'se-1',
    setIndex: idx,
    reps: reps,
    weightKg: weight,
    rpe: rpe,
    restSeconds: 120,
    isWarmup: warmup,
    completedAt: DateTime(2026, 1, 1),
  );
}

SessionExerciseWithSets _session(List<SetEntry> sets, {String id = 'se-1'}) {
  return SessionExerciseWithSets(
    sessionExercise: SessionExercise(
      id: id,
      sessionId: 'sess-$id',
      exerciseId: 'ex-1',
      orderIndex: 0,
    ),
    sets: sets,
  );
}

void main() {
  group('Pas d\'historique', () {
    test('retourne le starting weight au bas de la fourchette', () {
      final ex = _exercise(startingWeight: 30, min: 6, max: 10);
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: const [],
        settings: _settings,
      );
      expect(t.targetSets, 3);
      expect(t.targetReps, 6);
      expect(t.targetWeightKg, 30);
    });
  });

  group('REPS_FIRST', () {
    test('3x8 @44kg réussi → 3x9 @44kg', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44, rpe: 8),
          _set(idx: 1, reps: 8, weight: 44, rpe: 8),
          _set(idx: 2, reps: 8, weight: 44, rpe: 8),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 9);
      expect(t.targetWeightKg, 44);
    });

    test('3x9 @44kg réussi → 3x10 @44kg', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 9, weight: 44),
          _set(idx: 1, reps: 9, weight: 44),
          _set(idx: 2, reps: 9, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 10);
      expect(t.targetWeightKg, 44);
    });

    test('3x10 @44kg (max atteint) → 3x8 @46kg', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 44),
          _set(idx: 1, reps: 10, weight: 44),
          _set(idx: 2, reps: 10, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 8);
      expect(t.targetWeightKg, 46);
    });

    test('worst set définit la prochaine progression (3x[8,9,8])', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44),
          _set(idx: 1, reps: 9, weight: 44),
          _set(idx: 2, reps: 8, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 9, reason: 'min=8 → +1 = 9');
      expect(t.targetWeightKg, 44);
    });
  });

  group('Surcharge progressive désactivée', () {
    test('reproduit exactement les dernières valeurs', () {
      final ex = _exercise(overloadEnabled: false);
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 44),
          _set(idx: 1, reps: 10, weight: 44),
          _set(idx: 2, reps: 10, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 10);
      expect(t.targetWeightKg, 44);
      expect(t.reason, contains('désactivée'));
    });
  });

  group('Validation RPE', () {
    test('seuil = 9, RPE 10 → pas de progression', () {
      final ex = _exercise(rpeThreshold: 9);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44, rpe: 8),
          _set(idx: 1, reps: 8, weight: 44, rpe: 9),
          _set(idx: 2, reps: 8, weight: 44, rpe: 10),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 8);
      expect(t.targetWeightKg, 44);
      expect(t.reason, contains('RPE'));
    });

    test('seuil = 9, RPE max = 9 → progression OK', () {
      final ex = _exercise(rpeThreshold: 9);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44, rpe: 8),
          _set(idx: 1, reps: 8, weight: 44, rpe: 9),
          _set(idx: 2, reps: 8, weight: 44, rpe: 9),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 9);
      expect(t.targetWeightKg, 44);
    });

    test('aucun RPE renseigné → considéré validé (progression OK)', () {
      final ex = _exercise(rpeThreshold: 9);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44),
          _set(idx: 1, reps: 8, weight: 44),
          _set(idx: 2, reps: 8, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 9);
    });

    test('RPE renseigné partiellement : seul le max compte', () {
      final ex = _exercise(rpeThreshold: 9);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44),
          _set(idx: 1, reps: 8, weight: 44, rpe: 10),
          _set(idx: 2, reps: 8, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 8, reason: 'pas de progression : RPE 10 > 9');
      expect(t.targetWeightKg, 44);
    });

    test('pas de seuil → tout RPE accepté (même 10)', () {
      final ex = _exercise(rpeThreshold: null);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44, rpe: 10),
          _set(idx: 1, reps: 8, weight: 44, rpe: 10),
          _set(idx: 2, reps: 8, weight: 44, rpe: 10),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 9);
    });
  });

  group('Validation séries/reps', () {
    test('reps sous le min (charge trop lourde) → recalibrage e1RM plus léger',
        () {
      // Fourchette 8-10. 8,7,6 @44 : a tenu 8 sur la 1re série puis a coulé sous
      // le plancher → la charge est trop lourde pour le volume. On ne réimpose
      // pas 44 : on recale via e1RM vers le HAUT de fourchette (plus léger, plus
      // de reps). e1RM moyen ≈ 54,3 → 10 reps ≈ 40.
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44),
          _set(idx: 1, reps: 7, weight: 44),
          _set(idx: 2, reps: 6, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 40, reason: 'recalibré plus léger');
      expect(t.targetReps, 10, reason: 'haut de fourchette');
      expect(t.reason, contains('recale'));
    });

    test('moins de séries que prévu → pas de progression', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 44, rpe: 8),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 44);
      expect(t.targetReps, 10);
      expect(t.reason, contains('Toutes les séries'));
    });

    test('warm-up sets sont ignorés', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 5, weight: 20, warmup: true),
          _set(idx: 1, reps: 8, weight: 44),
          _set(idx: 2, reps: 8, weight: 44),
          _set(idx: 3, reps: 8, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 9);
    });
  });

  group('Sélection du poids historique', () {
    test('mode (poids le plus utilisé) gagne', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 40),
          _set(idx: 1, reps: 8, weight: 44),
          _set(idx: 2, reps: 8, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 44);
      expect(t.targetReps, 9);
    });

    test('égalité → on prend le plus lourd', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 40),
          _set(idx: 1, reps: 8, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 2,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 44);
    });
  });

  group('Garde anti-fatigue (chute de reps intra-séance)', () {
    test('8→6 reps (25%) à charge constante → progresse (fatigue normale)', () {
      final ex = _exercise(min: 6, max: 10);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 120),
          _set(idx: 1, reps: 6, weight: 120),
          _set(idx: 2, reps: 8, weight: 120),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      // 25% < 40% → fatigue normale, on progresse : +1 rep depuis la pire série
      // (6) à charge constante (double progression).
      expect(t.targetWeightKg, 120);
      expect(t.targetReps, 7);
    });

    test('effondrement 10→5 reps (50%) → pas de progression', () {
      // minReps (5) est au-dessus du plancher (5) — c'est la garde drop-off,
      // pas la garde repMin, qui doit attraper ce cas.
      final ex = _exercise(min: 5, max: 12);
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 120),
          _set(idx: 1, reps: 5, weight: 120),
          _set(idx: 2, reps: 6, weight: 120),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      // 50% ≥ 40% → effondrement, on tient 120.
      expect(t.targetWeightKg, 120);
      expect(t.reason, contains('chute de reps'));
    });

    test(
        'séance loggée réelle : [110x9, 120x8, 120x6, 100x8] → +1 rep depuis 120',
        () {
      // Mode = 120 (ramp 110 et back-off 100 ignorés). Chute 8→6 = 25% < 40%
      // → fatigue normale. Plancher 6 atteint → double progression : +1 rep à
      // charge constante (120), depuis la pire série à 120 (6 → 7).
      final ex = _exercise(min: 6, max: 10);
      final history = [
        _session([
          _set(idx: 0, reps: 9, weight: 110),
          _set(idx: 1, reps: 8, weight: 120),
          _set(idx: 2, reps: 6, weight: 120),
          _set(idx: 3, reps: 8, weight: 100),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 4,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 120,
          reason: 'progresse depuis 120, pas depuis 100/110');
      expect(t.targetReps, 7, reason: '+1 depuis la pire série à 120kg (6)');
    });
  });

  group('Garde charges mixtes (ramp / back-off ignorés)', () {
    test('back-off léger n\'écrase pas la baseline reps', () {
      // 120x8, 120x8, puis back-off 100x5. Sans le filtre charge-de-travail,
      // le 100x5 ferait croire à un échec (min reps = 5). Avec le filtre,
      // seules les séries à 120 comptent → 8 reps propres → +1 rep.
      final ex = _exercise(min: 6, max: 10);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 120),
          _set(idx: 1, reps: 8, weight: 120),
          _set(idx: 2, reps: 5, weight: 100),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 120, reason: '120 propre → +1 rep (pas le 100x5)');
      expect(t.targetReps, 9);
    });
  });

  group('Fourchette de reps modifiée dans l\'exercice', () {
    test('range élargie (8-12 → 12-20) : 12 reps ne reset PAS à 8', () {
      // Le bug réel était un provider en cache ; côté moteur, avec la nouvelle
      // range, 12 reps (anciennement le max) ne doit plus déclencher le reset.
      final ex = _exercise(min: 12, max: 20);
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 40),
          _set(idx: 1, reps: 12, weight: 40),
          _set(idx: 2, reps: 12, weight: 40),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 13, reason: '+1 dans la nouvelle fourchette');
      expect(t.targetWeightKg, 40, reason: 'pas de reset/montée de charge');
    });

    test('plancher relevé au-dessus du dernier perf → recalibrage vers la '
        'nouvelle fourchette', () {
      // Range relevée à 12-20 alors que la dernière séance était 3×10 @40.
      // 10 < nouveau plancher 12 → charge trop lourde pour la nouvelle cible.
      // On recale vers le haut (20 reps) : e1RM ≈ 53,3 → 20 reps ≈ 32.
      final ex = _exercise(min: 12, max: 20);
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 40),
          _set(idx: 1, reps: 10, weight: 40),
          _set(idx: 2, reps: 10, weight: 40),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 32, reason: 'recalibré pour tenir la fourchette');
      expect(t.targetReps, 20);
      expect(t.reason, contains('recale'));
    });
  });

  group('Recalibrage e1RM (charge trop lourde pour le volume)', () {
    test('scénario pecs réel [110x9,120x8,120x6,100x8] plancher 8 → recale '
        'plus léger avec plus de reps (~102kg × 12)', () {
      // Le cas qui a motivé la feature : a tenu 8 sur la 1re série à 120 puis a
      // coulé à 6. Plancher 8 → 6 < 8. Au lieu de redemander 4×8 @120 (qu'on
      // sait intenable), on estime via Epley la charge tenable pour le HAUT de
      // fourchette (12 reps) depuis la PIRE série à 120 (6 reps → e1RM 144) ≈ 102.
      final ex = _exercise(min: 8, max: 12, overrideIncrement: 2.0);
      final history = [
        _session([
          _set(idx: 0, reps: 9, weight: 110),
          _set(idx: 1, reps: 8, weight: 120),
          _set(idx: 2, reps: 6, weight: 120),
          _set(idx: 3, reps: 8, weight: 100),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 4,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 102, reason: 'charge tenable pour 12 reps');
      expect(t.targetReps, 12, reason: 'haut de fourchette');
      expect(t.reason, contains('recale'));
    });

    test('curl haut-de-fourchette [14,14,11 @25] plancher 12 → ~20kg × 20 '
        '(tenable, pas 22,5 surestimé)', () {
      // Haut-rep (préacher curl) : a fini à 11 < plancher 12. La PIRE série
      // (11@25 → e1RM 34,2) cadre la charge tenable pour 20 reps sur toutes les
      // séries : ≈ 20 kg. (La moyenne aurait donné 22,5, trop lourd vu la chute
      // 14→11 et la surestimation d'Epley à 20 reps.)
      final ex = _exercise(min: 12, max: 20, overrideIncrement: 2.5);
      final history = [
        _session([
          _set(idx: 0, reps: 14, weight: 25),
          _set(idx: 1, reps: 14, weight: 25),
          _set(idx: 2, reps: 11, weight: 25),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 20, reason: 'cadré sur la pire série (11@25)');
      expect(t.targetReps, 20, reason: 'haut de fourchette');
      expect(t.reason, contains('recale'));
    });

    test('recale dès le 1er échec (pas d\'attente de 2 séances)', () {
      // Différence clé avec l'ancien deload : on n'impose pas de re-grinder le
      // poids une séance de plus, on recale immédiatement.
      final ex = _exercise(min: 6, max: 10, overrideIncrement: 2.0);
      final history = [
        _session([
          _set(idx: 0, reps: 5, weight: 120),
          _set(idx: 1, reps: 5, weight: 120),
          _set(idx: 2, reps: 5, weight: 120),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, lessThan(120));
      expect(t.reason, contains('recale'));
    });

    test('le poids recalibré "tient" : une fois travaillé avec succès, le '
        'ratchet ne rebondit pas vers le pic échoué', () {
      // Séance la plus récente : 4×8 @116 réussi (le poids recalibré). Avant :
      // 8,6 @120 échoué. Le ratchet doit ancrer sur 116 (pic 120 abandonné),
      // donc progresser DEPUIS 116 (double progression : +1 rep), pas
      // re-proposer 120.
      final ex = _exercise(min: 8, max: 12, overrideIncrement: 2.0);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 116),
          _set(idx: 1, reps: 8, weight: 116),
          _set(idx: 2, reps: 8, weight: 116),
          _set(idx: 3, reps: 8, weight: 116),
        ], id: 'recal-success'),
        _session([
          _set(idx: 0, reps: 8, weight: 120),
          _set(idx: 1, reps: 6, weight: 120),
        ], id: 'failed-peak'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 4,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 116, reason: 'ancré sur 116, pas 120');
      expect(t.targetReps, 9, reason: '+1 rep depuis 116 (8→9)');
    });

    test('recale vers le haut de fourchette (plus léger, plus de reps)', () {
      // 5,5,5 @120, fourchette 6-10. e1RM moyen = 140 → 10 reps ≈ 106.
      final ex = _exercise(min: 6, max: 10, overrideIncrement: 2.0);
      final history = [
        _session([
          _set(idx: 0, reps: 5, weight: 120),
          _set(idx: 1, reps: 5, weight: 120),
          _set(idx: 2, reps: 5, weight: 120),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, lessThan(120), reason: 'plus léger');
      expect(t.targetReps, 10, reason: 'haut de fourchette');
      expect(t.reason, contains('recale'));
    });
  });

  group('Deload sur stall (échecs hors plancher de reps : RPE)', () {
    // Le recalibrage e1RM gère les échecs « reps sous le plancher ». Le deload
    // forfaitaire reste le filet pour les autres stalls (ici : RPE trop haut
    // alors que les reps sont dans la fourchette — pas de signal de charge
    // exploitable, on recule de 10%).
    test('2 séances RPE trop haut à 120kg → deload à 108kg au max de reps', () {
      final ex = _exercise(
        min: 6,
        max: 10,
        rpeThreshold: 9,
        overrideIncrement: 2.0,
      );
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 120, rpe: 10),
          _set(idx: 1, reps: 8, weight: 120, rpe: 10),
          _set(idx: 2, reps: 8, weight: 120, rpe: 10),
        ], id: 'fail2'),
        _session([
          _set(idx: 0, reps: 8, weight: 120, rpe: 10),
          _set(idx: 1, reps: 8, weight: 120, rpe: 10),
          _set(idx: 2, reps: 8, weight: 120, rpe: 10),
        ], id: 'fail1'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 108, reason: '120 * 0.9 = 108');
      expect(t.targetReps, 10, reason: 'haut de fourchette = volume');
      expect(t.reason, contains('deload'));
    });

    test('1 seul échec RPE → pas de deload, on tient le poids', () {
      final ex = _exercise(
        min: 6,
        max: 10,
        rpeThreshold: 9,
      );
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 120, rpe: 10),
          _set(idx: 1, reps: 8, weight: 120, rpe: 10),
          _set(idx: 2, reps: 8, weight: 120, rpe: 10),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 120);
      expect(t.reason, isNot(contains('deload')));
    });
  });

  group('Poids du corps (reps only, jamais de charge)', () {
    test('startingWeight 20kg ignoré → première séance à 0kg', () {
      final ex = _exercise(useBodyweight: true, startingWeight: 20, min: 8, max: 12);
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: const [],
        settings: _settings,
      );
      expect(t.targetWeightKg, 0, reason: 'jamais de poids prescrit');
      expect(t.targetReps, 8);
    });

    test('séance validée → +1 rep, poids reste 0', () {
      final ex = _exercise(
        useBodyweight: true,
        startingWeight: 20,
        min: 8,
        max: 12,
      );
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 0),
          _set(idx: 1, reps: 10, weight: 0),
          _set(idx: 2, reps: 10, weight: 0),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 0, reason: 'bodyweight ne doit PAS ajouter de poids');
      expect(t.targetReps, 11, reason: '+1 rep');
    });

    test('reps au-dessus de repMax → continue à grimper (non plafonné)', () {
      final ex = _exercise(useBodyweight: true, min: 8, max: 12);
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 0),
          _set(idx: 1, reps: 12, weight: 0),
          _set(idx: 2, reps: 12, weight: 0),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 0);
      expect(t.targetReps, 13, reason: 'pas de charge à ajouter → on monte les reps');
    });

    test('reps sous le min → on tient, message sans kg', () {
      final ex = _exercise(useBodyweight: true, min: 8, max: 12);
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 0),
          _set(idx: 1, reps: 6, weight: 0),
          _set(idx: 2, reps: 8, weight: 0),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 0);
      expect(t.targetReps, 8, reason: 'on re-vise le min');
      expect(t.reason, isNot(contains('kg')));
      expect(t.reason, contains('reps'));
    });

    test('poids logué sale (20kg) ignoré → progression reps quand même', () {
      // Donnée sale : l'utilisateur a logué 20kg par erreur sur du bodyweight.
      final ex = _exercise(useBodyweight: true, min: 8, max: 12);
      final history = [
        _session([
          _set(idx: 0, reps: 10, weight: 20),
          _set(idx: 1, reps: 10, weight: 20),
          _set(idx: 2, reps: 10, weight: 20),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 0, reason: 'on ignore le poids logué');
      expect(t.targetReps, 11);
    });
  });

  group('Scénario complet REPS_FIRST', () {
    test('3 séances : 3x8→3x9→3x10→3x8 +incrément', () {
      final ex = _exercise(min: 8, max: 10, startingWeight: 44);

      final t1 = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: [
          _session([
            _set(idx: 0, reps: 8, weight: 44),
            _set(idx: 1, reps: 8, weight: 44),
            _set(idx: 2, reps: 8, weight: 44),
          ]),
        ],
        settings: _settings,
      );
      expect((t1.targetReps, t1.targetWeightKg), (9, 44.0));

      final t2 = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: [
          _session([
            _set(idx: 0, reps: 9, weight: 44),
            _set(idx: 1, reps: 9, weight: 44),
            _set(idx: 2, reps: 9, weight: 44),
          ]),
        ],
        settings: _settings,
      );
      expect((t2.targetReps, t2.targetWeightKg), (10, 44.0));

      final t3 = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: [
          _session([
            _set(idx: 0, reps: 10, weight: 44),
            _set(idx: 1, reps: 10, weight: 44),
            _set(idx: 2, reps: 10, weight: 44),
          ]),
        ],
        settings: _settings,
      );
      expect((t3.targetReps, t3.targetWeightKg), (8, 46.0));
    });
  });

  test('targetSets toujours = plannedSets', () {
    final ex = _exercise();
    final t = ProgressionEngine.computeNextTarget(
      exercise: ex,
      plannedSets: 5,
      history: [
        _session([
          _set(idx: 0, reps: 8, weight: 44),
          _set(idx: 1, reps: 8, weight: 44),
          _set(idx: 2, reps: 8, weight: 44),
          _set(idx: 3, reps: 8, weight: 44),
          _set(idx: 4, reps: 8, weight: 44),
        ]),
      ],
      settings: _settings,
    );
    expect(t.targetSets, 5);
  });

  group('Ratchet UP only (deload safety)', () {
    test('séance plus légère que la précédente n\'écrase pas la baseline', () {
      // Most recent first: yesterday user underloaded at 40kg, the week
      // before they were at 44kg/9 reps. Engine should anchor on the 44kg
      // session, not the 40kg one.
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 40),
          _set(idx: 1, reps: 8, weight: 40),
          _set(idx: 2, reps: 8, weight: 40),
        ], id: 'recent'),
        _session([
          _set(idx: 0, reps: 9, weight: 44),
          _set(idx: 1, reps: 9, weight: 44),
          _set(idx: 2, reps: 9, weight: 44),
        ], id: 'previous'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      // Anchor on 44kg/9 → progress to 10×44kg (+1 rep, max=10).
      expect(t.targetWeightKg, 44);
      expect(t.targetReps, 10);
    });

    test('reps sous le min sur séance lourde → recalibrage plus léger '
        '(plus de re-grind du poids intenable)', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 6, weight: 44),
          _set(idx: 1, reps: 6, weight: 44),
          _set(idx: 2, reps: 6, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      // 6 < 8 → charge trop lourde. On recale vers le haut de fourchette :
      // e1RM 52,8 → 10 reps ≈ 40.
      expect(t.targetWeightKg, 40, reason: 'recalibré plus léger');
      expect(t.targetReps, 10);
      expect(t.reason, contains('recale'));
    });

    test('deload prolongé (5+ séances légères) finit par baisser la baseline',
        () {
      final ex = _exercise();
      // Window is 5 sessions. Once the lone heavy day falls out of the
      // window, the lighter sessions become the new anchor.
      final history = [
        for (var i = 0; i < 5; i++)
          _session([
            _set(idx: 0, reps: 8, weight: 40),
            _set(idx: 1, reps: 8, weight: 40),
            _set(idx: 2, reps: 8, weight: 40),
          ], id: 'light-$i'),
        _session([
          _set(idx: 0, reps: 9, weight: 44),
          _set(idx: 1, reps: 9, weight: 44),
          _set(idx: 2, reps: 9, weight: 44),
        ], id: 'heavy-old'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      // Heavy session is past the 5-window cutoff → baseline now 40kg.
      expect(t.targetWeightKg, 40);
      expect(t.targetReps, 9);
    });
  });
}
