import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/db/seeds/default_exercises.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/progression_target.dart';
import 'package:reps/domain/models/session.dart';
import 'package:reps/domain/models/user_settings.dart';
import 'package:reps/domain/progression/progression_engine.dart';

/// Rejoue l'historique RÉEL de l'utilisateur (dump Supabase) à travers le vrai
/// moteur de progression et vérifie des invariants sur CHAQUE prescription, à
/// chaque étape de chaque exercice. C'est le filet « détecte tous les bugs » :
/// si une vraie séquence de séances fait sortir le moteur de ses rails (poids
/// négatif/NaN, reps hors fourchette, targetSets incohérent, crash), un test
/// casse en pointant l'exo et l'étape.
///
/// Le dump (`test/fixtures/muscu_dump.json`) n'est pas committé (données perso).
/// Sans lui, toute la suite est `skip` — la CI reste verte.
void main() {
  final file = File('test/fixtures/muscu_dump.json');
  if (!file.existsSync()) {
    test('real-data replay (skipped: no dump fixture)', () {}, skip: true);
    return;
  }

  const settings = UserSettings();
  final dump = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  List<Map<String, dynamic>> rows(String k) =>
      (dump[k] as List).cast<Map<String, dynamic>>();

  double? asDouble(Object? v) => v == null ? null : (v as num).toDouble();
  DateTime? asDate(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();

  // ---- reconstruction des modèles ----------------------------------------
  Exercise exerciseFrom(Map<String, dynamic> m) => Exercise(
        id: m['id'] as String,
        name: m['name'] as String,
        // Les champs enum n'influencent pas le moteur → valeurs neutres.
        category: ExerciseCategory.push,
        primaryMuscle: MuscleGroup.chest,
        secondaryMuscles: const [],
        equipment: Equipment.other,
        isCustom: (m['is_custom'] as bool?) ?? true,
        progressiveOverloadEnabled:
            (m['progressive_overload_enabled'] as bool?) ?? true,
        minimumRpeThreshold: m['minimum_rpe_threshold'] as int?,
        targetRepRangeMin: (m['target_rep_range_min'] as int?) ?? 8,
        targetRepRangeMax: (m['target_rep_range_max'] as int?) ?? 12,
        startingWeightKg: asDouble(m['starting_weight_kg']) ?? 20,
        defaultIncrementKg: asDouble(m['default_increment_kg']),
        useBodyweight: (m['use_bodyweight'] as bool?) ?? false,
        progressionResetAt: asDate(m['progression_reset_at']),
        updatedAt: asDate(m['updated_at']) ?? DateTime(2026, 1, 1),
        deletedAt: asDate(m['deleted_at']),
      );

  final exercises = {
    for (final m in rows('exercises')) m['id'] as String: exerciseFrom(m),
  };

  // Les exos seed (non édités) ne sont PAS synchronisés → absents du dump. On
  // les reconstruit depuis la définition code, exactement comme onCreate les
  // insère (useBodyweight=false, incrément null → global). Indispensable pour
  // couvrir seed-tricep-pushdown & co. qui apparaissent dans les séances.
  for (final s in defaultExerciseSeeds) {
    exercises.putIfAbsent(
      s.id,
      () => Exercise(
        id: s.id,
        name: s.name,
        category: s.category,
        primaryMuscle: s.primary,
        secondaryMuscles: const [],
        equipment: s.equipment,
        isCustom: false,
        targetRepRangeMin: s.repMin,
        targetRepRangeMax: s.repMax,
        startingWeightKg: s.startingWeight,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
  }

  // sessions terminées & non supprimées, indexées par id → date de fin.
  final sessionEndedAt = <String, DateTime>{};
  for (final s in rows('workout_sessions')) {
    if (s['deleted_at'] != null) continue;
    final ended = asDate(s['ended_at']);
    if (ended == null) continue; // en cours → pas d'historique
    sessionEndedAt[s['id'] as String] = ended;
  }

  // sets groupés par session_exercise_id.
  final setsBySe = <String, List<SetEntry>>{};
  for (final st in rows('set_entries')) {
    final seId = st['session_exercise_id'] as String;
    (setsBySe[seId] ??= []).add(SetEntry(
      id: st['id'] as String,
      sessionExerciseId: seId,
      setIndex: (st['set_index'] as int?) ?? 0,
      reps: (st['reps'] as int?) ?? 0,
      weightKg: asDouble(st['weight_kg']) ?? 0,
      rpe: st['rpe'] as int?,
      restSeconds: (st['rest_seconds'] as int?) ?? 0,
      isWarmup: (st['is_warmup'] as bool?) ?? false,
      completedAt: asDate(st['completed_at']) ?? DateTime(2026, 1, 1),
    ));
  }

  // session_exercises (d'une séance terminée) groupés par exercise_id, avec
  // leur date pour l'ordre chronologique.
  final byExercise = <String, List<({DateTime when, SessionExerciseWithSets se})>>{};
  for (final se in rows('session_exercises')) {
    final sessionId = se['session_id'] as String;
    final when = sessionEndedAt[sessionId];
    if (when == null) continue; // séance non terminée/supprimée
    final exId = se['exercise_id'] as String;
    final seId = se['id'] as String;
    final sets = (setsBySe[seId] ?? [])..sort((a, b) => a.setIndex.compareTo(b.setIndex));
    (byExercise[exId] ??= []).add((
      when: when,
      se: SessionExerciseWithSets(
        sessionExercise: SessionExercise(
          id: seId,
          sessionId: sessionId,
          exerciseId: exId,
          orderIndex: (se['order_index'] as int?) ?? 0,
        ),
        sets: sets,
      ),
    ));
  }

  // Un seul test paramétré par exo : rejoue toutes les étapes et vérifie les
  // invariants. On garde les exos non supprimés ayant au moins une séance.
  for (final entry in byExercise.entries) {
    final exId = entry.key;
    final ex = exercises[exId];
    if (ex == null || ex.isDeleted) continue;
    final timeline = entry.value..sort((a, b) => a.when.compareTo(b.when));
    if (timeline.isEmpty) continue;

    test('replay réel — ${ex.name} (${timeline.length} séances)', () {
      // À chaque étape k, history = toutes les séances STRICTEMENT avant k,
      // most-recent-first — exactement ce que reçoit le moteur en séance.
      for (var k = 0; k <= timeline.length; k++) {
        final history = [
          for (var j = k - 1; j >= 0; j--) timeline[j].se,
        ];
        // plannedSets : on prend le nb de séries de travail de la dernière
        // séance, sinon 3 (comme l'écran).
        final lastWorking = history.isNotEmpty
            ? history.first.sets.where((s) => !s.isWarmup).length
            : 0;
        final plannedSets = lastWorking >= 1 ? lastWorking : 3;

        ProgressionTarget t;
        try {
          t = ProgressionEngine.computeNextTarget(
            exercise: ex,
            plannedSets: plannedSets,
            history: history,
            settings: settings,
          );
        } catch (e, st) {
          fail('CRASH moteur pour ${ex.name} à l\'étape $k : $e\n$st');
        }

        final ctx = '${ex.name} étape $k/${timeline.length}';
        // Invariants universels.
        expect(t.targetWeightKg.isFinite, isTrue,
            reason: '$ctx : poids non fini (${t.targetWeightKg})');
        expect(t.targetWeightKg, greaterThanOrEqualTo(0),
            reason: '$ctx : poids négatif (${t.targetWeightKg})');
        expect(t.targetSets, plannedSets,
            reason: '$ctx : targetSets ${t.targetSets} != plannedSets $plannedSets');
        expect(t.targetReps, greaterThan(0),
            reason: '$ctx : reps <= 0 (${t.targetReps})');
        expect(t.reason.trim(), isNotEmpty, reason: '$ctx : raison vide');

        if (ex.useBodyweight) {
          expect(t.targetWeightKg, 0,
              reason: '$ctx : poids du corps doit prescrire 0kg');
          expect(t.targetReps, greaterThanOrEqualTo(ex.targetRepRangeMin),
              reason: '$ctx : reps sous le plancher au poids du corps');
        } else {
          // Reps cible dans la fourchette [min, max] (le moteur clamp toujours).
          expect(t.targetReps, greaterThanOrEqualTo(ex.targetRepRangeMin),
              reason: '$ctx : reps ${t.targetReps} < min ${ex.targetRepRangeMin}');
          expect(t.targetReps, lessThanOrEqualTo(ex.targetRepRangeMax),
              reason: '$ctx : reps ${t.targetReps} > max ${ex.targetRepRangeMax}');
        }
      }
    });
  }

  // ---- Mutations ancrées sur le VRAI triceps (13/13/16 @20kg) -------------
  // C'est l'exo du bug rapporté. On vérifie chaque type d'édition à partir de
  // son historique réel.
  group('Mutations sur le triceps réel', () {
    final tri = exercises['seed-tricep-pushdown'];
    final tl = byExercise['seed-tricep-pushdown'];
    // history most-recent-first (séances réelles avec séries de travail).
    final history = (tl ?? [])
        .where((e) => e.se.sets.any((s) => !s.isWarmup))
        .toList()
      ..sort((a, b) => b.when.compareTo(a.when));
    final h = [for (final e in history) e.se];

    ProgressionTarget compute(Exercise e) => ProgressionEngine.computeNextTarget(
          exercise: e,
          plannedSets: 3,
          history: h,
          settings: settings,
        );

    test('précondition : 13/13/16 @20kg loggés', () {
      expect(tri, isNotNull);
      expect(h, isNotEmpty);
      final working = h.first.sets.where((s) => !s.isWarmup).toList();
      expect(working.map((s) => s.weightKg).toSet(), {20.0});
      expect(working.map((s) => s.reps).toList(), [13, 13, 16]);
    });

    test('tel quel : 13≥repMax(12) → +incrément 2.5, retour à 8 reps', () {
      final t = compute(tri!);
      expect(t.targetWeightKg, 22.5);
      expect(t.targetReps, 8);
    });

    test('fourchette élargie (max 12→20) : +1 rep, on reste à 20kg', () {
      final t = compute(tri!.copyWith(targetRepRangeMax: 20));
      expect(t.targetWeightKg, 20);
      expect(t.targetReps, 14); // worst working rep 13 +1
    });

    test('poids de départ changé (reset après la dernière séance) → repart de '
        'la valeur saisie', () {
      final reset = history.first.when.add(const Duration(days: 1));
      final t = compute(tri!.copyWith(startingWeightKg: 15, progressionResetAt: reset));
      expect(t.targetWeightKg, 15);
      expect(t.targetReps, tri.targetRepRangeMin);
      expect(t.reason, 'Première séance');
    });

    test('bascule poids-du-corps : 0kg, progression en reps', () {
      final t = compute(tri!.copyWith(useBodyweight: true));
      expect(t.targetWeightKg, 0);
      expect(t.targetReps, 14); // worst rep 13 +1, non plafonné
    });

    test('surcharge désactivée : rejoue le poids de travail', () {
      final t = compute(tri!.copyWith(progressiveOverloadEnabled: false));
      expect(t.targetWeightKg, 20);
    });
  });

  // Méta-test : au moins quelques exos rejoués (sinon le dump est vide/cassé).
  test('le dump contient des séances exploitables', () {
    final usable = byExercise.entries
        .where((e) => exercises[e.key] != null && !exercises[e.key]!.isDeleted)
        .length;
    expect(usable, greaterThan(0));
  });
}
