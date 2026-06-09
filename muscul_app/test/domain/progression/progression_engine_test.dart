import 'package:flutter_test/flutter_test.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/session.dart';
import 'package:reps/domain/models/user_settings.dart';
import 'package:reps/domain/progression/progression_engine.dart';

const _settings = UserSettings();

Exercise _exercise({
  bool overloadEnabled = true,
  ProgressionPriority priority = ProgressionPriority.repsFirst,
  int? rpeThreshold,
  int min = 8,
  int max = 10,
  double startingWeight = 44,
  double? overrideIncrement = 2.0,
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
    progressionPriority: priority,
    minimumRpeThreshold: rpeThreshold,
    targetRepRangeMin: min,
    targetRepRangeMax: max,
    startingWeightKg: startingWeight,
    defaultIncrementKg: overrideIncrement,
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

  group('WEIGHT_FIRST', () {
    test('3x8 @44kg réussi → 3x8 @46kg', () {
      final ex = _exercise(priority: ProgressionPriority.weightFirst);
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
      expect(t.targetReps, 8);
      expect(t.targetWeightKg, 46);
    });

    test('reps au-dessus du max sont clampées', () {
      final ex = _exercise(
        priority: ProgressionPriority.weightFirst,
        min: 8,
        max: 10,
      );
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 44),
          _set(idx: 1, reps: 12, weight: 44),
          _set(idx: 2, reps: 12, weight: 44),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 10, reason: 'clamp à repMax');
      expect(t.targetWeightKg, 46);
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

    test('s\'applique aussi en mode WEIGHT_FIRST', () {
      final ex = _exercise(
        overloadEnabled: false,
        priority: ProgressionPriority.weightFirst,
      );
      final history = [
        _session([
          _set(idx: 0, reps: 8, weight: 44, rpe: 7),
          _set(idx: 1, reps: 8, weight: 44, rpe: 7),
          _set(idx: 2, reps: 8, weight: 44, rpe: 7),
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
    test('reps en dessous du min → pas de progression', () {
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
      expect(t.targetReps, 8, reason: 'clamp à repMin pour rejouer');
      expect(t.targetWeightKg, 44);
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
      final ex = _exercise(
        priority: ProgressionPriority.weightFirst,
        min: 6,
        max: 10,
      );
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
      // 25% < 40% → fatigue normale, on progresse.
      expect(t.targetWeightKg, 122);
    });

    test('effondrement 10→5 reps (50%) → pas de progression', () {
      // minReps (5) est au-dessus du plancher (5) — c'est la garde drop-off,
      // pas la garde repMin, qui doit attraper ce cas.
      final ex = _exercise(
        priority: ProgressionPriority.weightFirst,
        min: 5,
        max: 12,
      );
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
        'séance loggée réelle : [110x9, 120x8, 120x6, 100x8] → progresse à 122kg',
        () {
      // Mode = 120 (ramp 110 et back-off 100 ignorés). Chute 8→6 = 25% < 40%
      // → fatigue normale, on progresse depuis la charge de travail (120).
      final ex = _exercise(
        priority: ProgressionPriority.weightFirst,
        min: 6,
        max: 10,
      );
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
      expect(t.targetWeightKg, 122,
          reason: 'progresse depuis 120, pas depuis 100/110');
      expect(t.targetReps, 6, reason: 'pire série à 120kg');
    });
  });

  group('Garde charges mixtes (ramp / back-off ignorés)', () {
    test('back-off léger n\'écrase pas la baseline reps', () {
      // 120x8, 120x8, puis back-off 100x5. Sans le filtre charge-de-travail,
      // le 100x5 ferait croire à un échec (min reps = 5). Avec le filtre,
      // seules les séries à 120 comptent → 8 reps propres → progression.
      final ex = _exercise(
        priority: ProgressionPriority.weightFirst,
        min: 6,
        max: 10,
      );
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
      expect(t.targetWeightKg, 122, reason: '120 propre → +incrément');
      expect(t.targetReps, 8);
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
      // Anchor on 44kg/9 → progress to 10×44kg (repsFirst, max=10).
      expect(t.targetWeightKg, 44);
      expect(t.targetReps, 10);
    });

    test(
        'reps inférieures aux reps min sur séance lourde → pas de progression, '
        'mais on garde le poids lourd', () {
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
      // Failed reps (6 < 8) → no progression. Weight stays at 44, reps
      // clamp back to repMin (8).
      expect(t.targetWeightKg, 44);
      expect(t.targetReps, 8);
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
