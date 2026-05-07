import 'package:flutter_test/flutter_test.dart';
import 'package:muscul_app/domain/models/enums.dart';
import 'package:muscul_app/domain/models/exercise.dart';
import 'package:muscul_app/domain/models/session.dart';
import 'package:muscul_app/domain/models/user_settings.dart';
import 'package:muscul_app/domain/progression/e1rm.dart';
import 'package:muscul_app/domain/progression/progression_engine.dart';

const _settings = UserSettings();

Exercise _exercise({
  ProgressionStrategyKind strategy = ProgressionStrategyKind.doubleProgression,
  int min = 8,
  int max = 12,
  double startingWeight = 20,
  double? overrideIncrement,
}) {
  return Exercise(
    id: 'ex-1',
    name: 'Bench',
    category: ExerciseCategory.push,
    primaryMuscle: MuscleGroup.chest,
    secondaryMuscles: const [],
    equipment: Equipment.barbell,
    isCustom: false,
    progressionStrategy: strategy,
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
    id: 's$idx-${DateTime.now().microsecondsSinceEpoch}',
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
  group('Double progression', () {
    test('hits top of range at RPE 9 → +increment, reps reset to min', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 60, rpe: 8),
          _set(idx: 1, reps: 12, weight: 60, rpe: 9),
          _set(idx: 2, reps: 12, weight: 60, rpe: 9),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 62.5);
      expect(t.targetReps, 8);
      expect(t.targetSets, 3);
    });

    test('hits top of range but RPE 10 → no increment, retry same values', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 60, rpe: 9),
          _set(idx: 1, reps: 12, weight: 60, rpe: 10),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 60);
      expect(t.targetReps, 12); // last top reps
    });

    test('incomplete reps below min → retry same values', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 7, weight: 60, rpe: 8),
          _set(idx: 1, reps: 6, weight: 60, rpe: 9),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 6);
      expect(t.targetWeightKg, 60);
    });

    test('no history → starting weight at min reps', () {
      final ex = _exercise(startingWeight: 30);
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: const [],
        settings: _settings,
      );
      expect(t.targetWeightKg, 30);
      expect(t.targetReps, 8);
    });

    test('+1 rep when all sets done and inside range', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 9, weight: 60, rpe: 8),
          _set(idx: 1, reps: 9, weight: 60, rpe: 8),
          _set(idx: 2, reps: 9, weight: 60, rpe: 8),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 10);
      expect(t.targetWeightKg, 60);
    });

    test('warmup sets are ignored', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 5, weight: 30, rpe: 6, warmup: true),
          _set(idx: 1, reps: 12, weight: 60, rpe: 8),
          _set(idx: 2, reps: 12, weight: 60, rpe: 8),
          _set(idx: 3, reps: 12, weight: 60, rpe: 9),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 62.5);
      expect(t.targetReps, 8);
    });

    test('exercise increment override beats global setting', () {
      final ex = _exercise(overrideIncrement: 1.0);
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 60, rpe: 8),
          _set(idx: 1, reps: 12, weight: 60, rpe: 9),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings, // global default 2.5
      );
      expect(t.targetWeightKg, 61.0);
    });

    test('null RPE treated as 8 → progression OK', () {
      final ex = _exercise();
      final history = [
        _session([
          _set(idx: 0, reps: 12, weight: 60),
          _set(idx: 1, reps: 12, weight: 60),
        ]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetWeightKg, 62.5);
    });

    test('targetSets is always = plannedSets (engine never changes set count)',
        () {
      final ex = _exercise();
      final history = [
        _session([_set(idx: 0, reps: 8, weight: 60, rpe: 8)]),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 5,
        history: history,
        settings: _settings,
      );
      expect(t.targetSets, 5);
    });
  });

  group('RPE auto-regulated', () {
    test('<2 sessions → fallback double progression with explicit message', () {
      final ex = _exercise(strategy: ProgressionStrategyKind.rpeAutoregulated);
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: const [],
        settings: _settings,
      );
      expect(t.reason, contains('Pas assez d\'historique'));
    });

    test('e1RM rising → RPE target 8', () {
      final ex = _exercise(strategy: ProgressionStrategyKind.rpeAutoregulated);
      // history is most-recent-first
      final history = [
        _session([_set(idx: 0, reps: 5, weight: 100, rpe: 8)], id: 'newest'),
        _session([_set(idx: 0, reps: 5, weight: 95, rpe: 8)], id: 'middle'),
        _session([_set(idx: 0, reps: 5, weight: 90, rpe: 8)], id: 'oldest'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetRpe, 8);
    });

    test('e1RM falling → RPE 7 (deload)', () {
      final ex = _exercise(strategy: ProgressionStrategyKind.rpeAutoregulated);
      final history = [
        _session([_set(idx: 0, reps: 5, weight: 90, rpe: 9)], id: 'newest'),
        _session([_set(idx: 0, reps: 5, weight: 95, rpe: 8)], id: 'middle'),
        _session([_set(idx: 0, reps: 5, weight: 100, rpe: 8)], id: 'oldest'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetRpe, 7);
    });

    test('reps target = mid of range, rounded', () {
      final ex = _exercise(
        strategy: ProgressionStrategyKind.rpeAutoregulated,
        min: 6,
        max: 10,
      );
      final history = [
        _session([_set(idx: 0, reps: 6, weight: 100, rpe: 8)], id: 'a'),
        _session([_set(idx: 0, reps: 6, weight: 95, rpe: 8)], id: 'b'),
      ];
      final t = ProgressionEngine.computeNextTarget(
        exercise: ex,
        plannedSets: 3,
        history: history,
        settings: _settings,
      );
      expect(t.targetReps, 8);
    });
  });

  group('Helpers', () {
    test('roundToStep rounds to nearest multiple', () {
      expect(roundToStep(47.3, 2.5), 47.5);
      expect(roundToStep(48.8, 2.5), 50.0); // 1.2 vs 1.3 → 50
      expect(roundToStep(46.4, 2.5), 47.5);
      expect(roundToStep(60, 2.5), 60);
    });

    test('estimate1RM matches formula', () {
      // 60 × (1 + (5 + (10-8))/30) = 60 × (1 + 7/30) = 60 × 1.2333... = 74
      expect(estimate1RM(weightKg: 60, reps: 5, rpe: 8), closeTo(74, 0.001));
    });
  });
}
