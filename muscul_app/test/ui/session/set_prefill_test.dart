import 'package:flutter_test/flutter_test.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/progression_target.dart';
import 'package:reps/domain/models/session.dart';
import 'package:reps/domain/models/user_settings.dart';
import 'package:reps/domain/models/workout_template.dart';
import 'package:reps/domain/progression/progression_engine.dart';
import 'package:reps/ui/session/pending_set.dart';
import 'package:reps/ui/session/set_prefill.dart';

const _settings = UserSettings();

Exercise _exercise({
  int min = 8,
  int max = 12,
  double startingWeight = 44,
  double increment = 2.0,
}) {
  return Exercise(
    id: 'ex-1',
    name: 'Bench',
    category: ExerciseCategory.push,
    primaryMuscle: MuscleGroup.chest,
    secondaryMuscles: const [],
    equipment: Equipment.barbell,
    isCustom: false,
    progressiveOverloadEnabled: true,
    minimumRpeThreshold: null,
    targetRepRangeMin: min,
    targetRepRangeMax: max,
    startingWeightKg: startingWeight,
    defaultIncrementKg: increment,
    updatedAt: DateTime(2026, 1, 1),
  );
}

SetEntry _set({required int idx, required int reps, required double weight}) {
  return SetEntry(
    id: 's$idx-$reps-$weight',
    sessionExerciseId: 'se-hist',
    setIndex: idx,
    reps: reps,
    weightKg: weight,
    restSeconds: 120,
    completedAt: DateTime(2026, 1, 1),
  );
}

SessionExerciseWithSets _pastSession(List<SetEntry> sets) {
  return SessionExerciseWithSets(
    sessionExercise: const SessionExercise(
      id: 'se-hist',
      sessionId: 'sess-hist',
      exerciseId: 'ex-1',
      orderIndex: 0,
    ),
    sets: sets,
  );
}

TemplateExerciseSet _planSet({
  required int idx,
  required int reps,
  double? weight,
}) {
  return TemplateExerciseSet(
    id: 'p$idx',
    templateExerciseId: 'te-1',
    setIndex: idx,
    plannedReps: reps,
    plannedWeightKg: weight,
  );
}

void main() {
  group('computeSetDefault — la prescription du moteur prime sur le plan figé',
      () {
    // Régression du bug : 3×12@44 validé (reps-first, fourchette 8–12), le plan
    // est ratché à 3×12@44. Le moteur prescrit alors 3×8@46 (reset reps +
    // incrément). Le pré-remplissage DOIT suivre le moteur, pas le plan.
    test('3×12@44 réussi → la série 0 se pré-remplit à 8 reps @ 46kg (pas 12@44)',
        () {
      final exercise = _exercise();
      final history = [
        _pastSession([
          _set(idx: 0, reps: 12, weight: 44),
          _set(idx: 1, reps: 12, weight: 44),
          _set(idx: 2, reps: 12, weight: 44),
        ]),
      ];
      final plan = [
        _planSet(idx: 0, reps: 12, weight: 44),
        _planSet(idx: 1, reps: 12, weight: 44),
        _planSet(idx: 2, reps: 12, weight: 44),
      ];

      final target = ProgressionEngine.computeNextTarget(
        exercise: exercise,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      // Sanity : le moteur propose bien le reset + montée de charge.
      expect(target.targetReps, 8);
      expect(target.targetWeightKg, 46);

      final prefill = computeSetDefault(
        pos: 0,
        sessionSets: const [], // séance en cours encore vierge
        hasHistory: true,
        plan: plan,
        target: target,
      );

      expect(prefill.reps, 8, reason: 'reps doivent suivre le moteur, pas le plan');
      expect(prefill.weight, 46, reason: 'poids doit monter d\'un incrément');
    });

    test('reps-first : 3×8@44 réussi → série 0 pré-remplie à 9 reps @ 44kg', () {
      final exercise = _exercise();
      final history = [
        _pastSession([
          _set(idx: 0, reps: 8, weight: 44),
          _set(idx: 1, reps: 8, weight: 44),
          _set(idx: 2, reps: 8, weight: 44),
        ]),
      ];
      final plan = [_planSet(idx: 0, reps: 8, weight: 44)];
      final target = ProgressionEngine.computeNextTarget(
        exercise: exercise,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );

      final prefill = computeSetDefault(
        pos: 0,
        sessionSets: const [],
        hasHistory: true,
        plan: plan,
        target: target,
      );
      expect(prefill.reps, 9, reason: '+1 rep (double progression)');
      expect(prefill.weight, 44);
    });
  });

  group('computeSetDefault — replay par série (surcharge désactivée)', () {
    // Bug : tractions 12/11/9 sans surcharge ressortaient en 9/9/9 (le moteur
    // réduit l'historique à la pire série). Avec replayPerSet on rejoue chaque
    // série telle quelle.
    const target = ProgressionTarget(
      targetSets: 3,
      targetReps: 9, // ce que le moteur collapse (pire série)
      targetWeightKg: 0,
      reason: 'peu importe',
    );
    final previous = [
      _set(idx: 0, reps: 12, weight: 0),
      _set(idx: 1, reps: 11, weight: 0),
      _set(idx: 2, reps: 9, weight: 0),
    ];

    test('chaque série rejoue ses propres reps (12/11/9, pas 9/9/9)', () {
      PendingSet at(int pos) => computeSetDefault(
            pos: pos,
            sessionSets: const [],
            hasHistory: true,
            plan: const [],
            target: target,
            replayPerSet: true,
            previousWorkingSets: previous,
          );
      expect(at(0).reps, 12);
      expect(at(1).reps, 11);
      expect(at(2).reps, 9);
    });

    test('série au-delà de l\'historique → reprend la dernière', () {
      final p = computeSetDefault(
        pos: 5,
        sessionSets: const [],
        hasHistory: true,
        plan: const [],
        target: target,
        replayPerSet: true,
        previousWorkingSets: previous,
      );
      expect(p.reps, 9, reason: 'dernière série de l\'historique');
    });

    test('poids du replay = poids du target (0 au poids du corps)', () {
      final p = computeSetDefault(
        pos: 0,
        sessionSets: const [],
        hasHistory: true,
        plan: const [],
        target: target,
        replayPerSet: true,
        previousWorkingSets: previous,
      );
      expect(p.weight, 0);
    });
  });

  group('computeSetDefault — autres priorités', () {
    const target = ProgressionTarget(
      targetSets: 3,
      targetReps: 8,
      targetWeightKg: 46,
      reason: 'peu importe',
    );

    test('série déjà validée dans la séance → on reprend ses valeurs', () {
      final prefill = computeSetDefault(
        pos: 2,
        sessionSets: [
          _set(idx: 0, reps: 10, weight: 50),
          _set(idx: 1, reps: 9, weight: 50),
        ],
        hasHistory: true,
        plan: [_planSet(idx: 0, reps: 8, weight: 44)],
        target: target,
      );
      expect(prefill.reps, 9, reason: 'reprend la dernière série validée');
      expect(prefill.weight, 50);
    });

    test('warm-up ignoré : seule la dernière série de travail compte', () {
      final warmup = SetEntry(
        id: 'w',
        sessionExerciseId: 'se',
        setIndex: 0,
        reps: 5,
        weightKg: 20,
        restSeconds: 60,
        isWarmup: true,
        completedAt: DateTime(2026, 1, 1),
      );
      final prefill = computeSetDefault(
        pos: 1,
        sessionSets: [warmup, _set(idx: 1, reps: 9, weight: 50)],
        hasHistory: true,
        plan: const [],
        target: target,
      );
      expect(prefill.reps, 9);
      expect(prefill.weight, 50);
    });

    test('première séance (aucun historique) → on amorce depuis le plan', () {
      final prefill = computeSetDefault(
        pos: 0,
        sessionSets: const [],
        hasHistory: false,
        plan: [
          _planSet(idx: 0, reps: 12, weight: 40),
          _planSet(idx: 1, reps: 12, weight: 40),
        ],
        target: target,
      );
      expect(prefill.reps, 12, reason: 'le plan amorce la 1re séance');
      expect(prefill.weight, 40);
    });

    test('plan plus court que la position → on retombe sur la dernière série du plan',
        () {
      final prefill = computeSetDefault(
        pos: 5,
        sessionSets: const [],
        hasHistory: false,
        plan: [_planSet(idx: 0, reps: 10, weight: 30)],
        target: target,
      );
      expect(prefill.reps, 10);
      expect(prefill.weight, 30);
    });

    test('plan sans poids (poids du corps) → fallback sur le poids du target', () {
      final prefill = computeSetDefault(
        pos: 0,
        sessionSets: const [],
        hasHistory: false,
        plan: [_planSet(idx: 0, reps: 12, weight: null)],
        target: target,
      );
      expect(prefill.reps, 12);
      expect(prefill.weight, 46, reason: 'pas de poids planifié → poids du target');
    });

    test('freestyle (ni historique ni plan) → on suit le target', () {
      final prefill = computeSetDefault(
        pos: 0,
        sessionSets: const [],
        hasHistory: false,
        plan: const [],
        target: target,
      );
      expect(prefill.reps, 8);
      expect(prefill.weight, 46);
    });
  });
}
