import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/db/database.dart';
import 'package:reps/data/repositories/exercise_repository.dart';
import 'package:reps/data/repositories/session_repository.dart';
import 'package:reps/data/repositories/template_repository.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/progression_target.dart';
import 'package:reps/domain/models/session.dart';
import 'package:reps/domain/models/user_settings.dart';
import 'package:reps/domain/models/workout_template.dart';
import 'package:reps/domain/progression/progression_engine.dart';

/// Tests de bout-en-bout du cycle de vie d'un exercice : on pilote les VRAIS
/// repositories (Drift en mémoire) + le moteur de progression, à travers le
/// flux réel template → séance loggée → édition d'exo → cible recalculée.
///
/// C'est là que vivent les bugs « j'édite et la prescription part en vrille » :
/// renommage, changement de fourchette de reps, changement de poids de départ
/// (+reset), bascule poids-du-corps, remplacement d'exo dans un modèle.
void main() {
  late AppDatabase db;
  late LocalExerciseRepository exo;
  late LocalSessionRepository sessions;
  late LocalTemplateRepository templates;

  const settings = UserSettings(); // incrément global 2.5kg

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    exo = LocalExerciseRepository(db);
    sessions = LocalSessionRepository(db);
    templates = LocalTemplateRepository(db);
  });

  tearDown(() async => db.close());

  // ---- builders -----------------------------------------------------------

  Exercise makeExo({
    String id = 'ex-tri',
    String name = 'Extension triceps',
    bool custom = true,
    int min = 8,
    int max = 12,
    double startWeight = 20,
    double? increment = 2.5,
    bool bodyweight = false,
    int? rpeThreshold,
    DateTime? resetAt,
    DateTime? updatedAt,
  }) {
    return Exercise(
      id: id,
      name: name,
      category: ExerciseCategory.push,
      primaryMuscle: MuscleGroup.triceps,
      secondaryMuscles: const [],
      equipment: Equipment.cable,
      isCustom: custom,
      targetRepRangeMin: min,
      targetRepRangeMax: max,
      startingWeightKg: startWeight,
      defaultIncrementKg: increment,
      useBodyweight: bodyweight,
      minimumRpeThreshold: rpeThreshold,
      progressionResetAt: resetAt,
      updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    );
  }

  var _seq = 0;

  /// Logge une séance TERMINÉE pour [exerciseId] : N séries (reps/poids), à la
  /// date [endedAt]. Renvoie l'id du session_exercise.
  Future<String> logSession(
    String exerciseId,
    List<({int reps, double weight})> sets, {
    required DateTime endedAt,
    int? rpe,
  }) async {
    _seq++;
    final sessionId = 'sess-$_seq';
    final seId = 'se-$_seq';
    await sessions.upsertSession(WorkoutSession(
      id: sessionId,
      startedAt: endedAt,
      endedAt: endedAt,
      updatedAt: endedAt,
    ));
    await sessions.upsertSessionExercise(SessionExercise(
      id: seId,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: 0,
    ));
    for (var i = 0; i < sets.length; i++) {
      await sessions.upsertSet(SetEntry(
        id: '$seId-s$i',
        sessionExerciseId: seId,
        setIndex: i,
        reps: sets[i].reps,
        weightKg: sets[i].weight,
        rpe: rpe,
        restSeconds: 120,
        completedAt: endedAt,
      ));
    }
    return seId;
  }

  /// Calcule la cible que l'app prescrirait MAINTENANT pour [ex] (lit l'historique
  /// réel via le repository, comme l'écran de séance).
  Future<ProgressionTarget> nextTarget(Exercise ex, {int plannedSets = 3}) async {
    final history = await sessions.historyForExercise(ex.id);
    return ProgressionEngine.computeNextTarget(
      exercise: ex,
      plannedSets: plannedSets,
      history: history,
      settings: settings,
    );
  }

  List<({int reps, double weight})> uniform(int n, int reps, double weight) =>
      [for (var i = 0; i < n; i++) (reps: reps, weight: weight)];

  // =========================================================================
  group('Renommage (cosmétique, même id)', () {
    test('renommer ne touche pas la progression : historique conservé',
        () async {
      await exo.upsert(makeExo());
      await logSession('ex-tri', uniform(3, 12, 20),
          endedAt: DateTime(2026, 2, 1)); // top de fourchette atteint

      // L'utilisateur renomme l'exo.
      final before = (await exo.getById('ex-tri'))!;
      await exo.upsert(before.copyWith(
          name: 'Pushdown corde', updatedAt: DateTime(2026, 2, 2)));

      final ex = (await exo.getById('ex-tri'))!;
      expect(ex.name, 'Pushdown corde');
      final t = await nextTarget(ex);
      // 12 reps = repMax → +incrément, retour au plancher.
      expect(t.targetWeightKg, 22.5);
      expect(t.targetReps, 8);
    });
  });

  // =========================================================================
  group('Le bug rapporté : exo entraîné lourd, on baisse le poids de départ',
      () {
    test(
        'sans reset → le ratchet rappelle l\'ancien poids (comportement actuel)',
        () async {
      await exo.upsert(makeExo(startWeight: 20));
      await logSession('ex-tri', uniform(3, 10, 30),
          endedAt: DateTime(2026, 2, 1)); // entraîné à 30

      // On change le poids de départ à 20 SANS reset (simule l'ancien bug).
      final ex = (await exo.getById('ex-tri'))!
          .copyWith(startingWeightKg: 20, updatedAt: DateTime(2026, 2, 2));
      final t = await nextTarget(ex);
      expect(t.targetWeightKg, 30,
          reason: 'sans reset, l\'historique à 30 reste l\'ancre');
    });

    test('avec reset (poids de départ changé) → repart bien de 20', () async {
      await exo.upsert(makeExo(startWeight: 20));
      await logSession('ex-tri', uniform(3, 10, 30),
          endedAt: DateTime(2026, 2, 1));

      // Geste réel : changer le poids de départ pose progressionResetAt = now.
      final reset = DateTime(2026, 2, 2);
      final ex = (await exo.getById('ex-tri'))!.copyWith(
        startingWeightKg: 20,
        progressionResetAt: reset,
        updatedAt: reset,
      );
      await exo.upsert(ex);

      final t = await nextTarget(ex);
      expect(t.targetWeightKg, 20, reason: 'séance à 30 ignorée (avant reset)');
      expect(t.targetReps, ex.targetRepRangeMin);
      expect(t.reason, 'Première séance');
    });

    test('après reset, une nouvelle séance reprend la progression normale',
        () async {
      final reset = DateTime(2026, 2, 2);
      await exo.upsert(makeExo(startWeight: 20, resetAt: reset));
      // séance AVANT reset (doit être ignorée)
      await logSession('ex-tri', uniform(3, 10, 30),
          endedAt: DateTime(2026, 2, 1));
      // séance APRÈS reset à 20, top de fourchette
      await logSession('ex-tri', uniform(3, 12, 20),
          endedAt: DateTime(2026, 2, 10));

      final ex = (await exo.getById('ex-tri'))!;
      final t = await nextTarget(ex);
      expect(t.targetWeightKg, 22.5, reason: '20 + incrément 2.5');
      expect(t.targetReps, 8);
    });
  });

  // =========================================================================
  group('Changement de fourchette de reps', () {
    test('élargir le plafond (12→15) : on continue à monter les reps, pas de +kg',
        () async {
      await exo.upsert(makeExo(min: 8, max: 12));
      await logSession('ex-tri', uniform(3, 12, 20),
          endedAt: DateTime(2026, 2, 1));

      // Avec l'ancienne fourchette : 12 = max → +kg. On élargit AVANT recalcul.
      final ex = (await exo.getById('ex-tri'))!
          .copyWith(targetRepRangeMax: 15, updatedAt: DateTime(2026, 2, 2));
      final t = await nextTarget(ex);
      expect(t.targetWeightKg, 20, reason: '12 < nouveau max 15 → pas de +kg');
      expect(t.targetReps, 13);
    });

    test('relever le plancher au-dessus de la perf → recalibrage e1RM plus léger',
        () async {
      await exo.upsert(makeExo(min: 8, max: 12, startWeight: 30));
      await logSession('ex-tri', uniform(3, 8, 30),
          endedAt: DateTime(2026, 2, 1)); // 8 reps à 30

      // On relève le plancher à 12 : 8 < 12 → la charge est trop lourde pour
      // tenir la nouvelle fourchette → le moteur doit recaler plus léger.
      final ex = (await exo.getById('ex-tri'))!
          .copyWith(targetRepRangeMin: 12, updatedAt: DateTime(2026, 2, 2));
      final t = await nextTarget(ex);
      expect(t.targetWeightKg, lessThan(30),
          reason: 'recalibrage vers une charge tenable pour 12 reps');
      expect(t.targetReps, 12);
    });

    test(
        'clampPlannedRepsForExercise borne les reps planifiées du modèle après '
        'rétrécissement de la fourchette', () async {
      await exo.upsert(makeExo(min: 8, max: 12));
      await templates.upsertTemplate(WorkoutTemplate(
        id: 't1',
        name: 'Triceps',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await templates.setTemplateExercises('t1', [
        TemplateExerciseWithSets(
          exercise: const WorkoutTemplateExercise(
            id: 'te1',
            templateId: 't1',
            exerciseId: 'ex-tri',
            orderIndex: 0,
            targetSets: 3,
            restSeconds: 90,
          ),
          sets: [
            for (var i = 0; i < 3; i++)
              TemplateExerciseSet(
                id: 'te1-s$i',
                templateExerciseId: 'te1',
                setIndex: i,
                plannedReps: 12,
                plannedWeightKg: 20,
              ),
          ],
        ),
      ]);
      // Nouvelle fourchette 6-8 → 12 planifié doit être ramené à 8.
      await templates.clampPlannedRepsForExercise(
          exerciseId: 'ex-tri', min: 6, max: 8);
      final sets = await templates.getTemplateExerciseSets('te1');
      expect(sets.every((s) => s.plannedReps == 8), isTrue);
    });
  });

  // =========================================================================
  group('Bascule poids-du-corps', () {
    test('passer en poids-du-corps : la charge loggée est ignorée, reps-only',
        () async {
      await exo.upsert(makeExo(bodyweight: false, startWeight: 20));
      await logSession('ex-tri', uniform(3, 10, 20),
          endedAt: DateTime(2026, 2, 1));

      final ex = (await exo.getById('ex-tri'))!
          .copyWith(useBodyweight: true, updatedAt: DateTime(2026, 2, 2));
      final t = await nextTarget(ex);
      expect(t.targetWeightKg, 0, reason: 'jamais de charge au poids du corps');
      expect(t.targetReps, 11, reason: '+1 rep (validé)');
    });
  });

  // =========================================================================
  group('Remplacement d\'exo dans un modèle (nouvel exo, neuf)', () {
    test('un exo vraiment neuf démarre à son poids de départ, pas à l\'ancien',
        () async {
      // Ancien exo entraîné lourd.
      await exo.upsert(makeExo(id: 'ex-old', name: 'Dips', startWeight: 40));
      await logSession('ex-old', uniform(3, 10, 40),
          endedAt: DateTime(2026, 2, 1));
      // Nouvel exo distinct, jamais loggé, poids de départ 20.
      await exo.upsert(makeExo(id: 'ex-new', name: 'Pushdown', startWeight: 20));

      final ex = (await exo.getById('ex-new'))!;
      final t = await nextTarget(ex);
      expect(t.targetWeightKg, 20);
      expect(t.reason, 'Première séance');
    });
  });

  // =========================================================================
  group('Ratchet du plan via applyValidatedSet pendant une séance', () {
    test('valider 12@25 monte le plan du modèle de 20 à 25', () async {
      await exo.upsert(makeExo());
      await templates.upsertTemplate(WorkoutTemplate(
        id: 't1',
        name: 'Triceps',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await templates.setTemplateExercises('t1', [
        TemplateExerciseWithSets(
          exercise: const WorkoutTemplateExercise(
            id: 'te1',
            templateId: 't1',
            exerciseId: 'ex-tri',
            orderIndex: 0,
            targetSets: 3,
            restSeconds: 90,
          ),
          sets: [
            for (var i = 0; i < 3; i++)
              TemplateExerciseSet(
                id: 'te1-s$i',
                templateExerciseId: 'te1',
                setIndex: i,
                plannedReps: 10,
                plannedWeightKg: 20,
              ),
          ],
        ),
      ]);
      await templates.applyValidatedSet(
        templateId: 't1',
        exerciseId: 'ex-tri',
        reps: 12,
        weightKg: 25,
      );
      final sets = await templates.getTemplateExerciseSets('te1');
      expect(sets.first.plannedWeightKg, 25);
      expect(sets.first.plannedReps, 12);
    });
  });

  // =========================================================================
  group('Progression multi-séances (sanity end-to-end)', () {
    test('3x8@20 → 3x9 → 3x10 → 3x11 → 3x12 → 3x8@22.5', () async {
      await exo.upsert(makeExo(min: 8, max: 12, startWeight: 20));
      var day = DateTime(2026, 2, 1);
      // séance 1 : 3x8@20
      await logSession('ex-tri', uniform(3, 8, 20), endedAt: day);
      Future<ProgressionTarget> step() async =>
          nextTarget((await exo.getById('ex-tri'))!);

      var t = await step();
      expect((t.targetReps, t.targetWeightKg), (9, 20.0));

      // On loggue chaque cible et on avance.
      for (final reps in [9, 10, 11, 12]) {
        day = day.add(const Duration(days: 2));
        await logSession('ex-tri', uniform(3, reps, 20), endedAt: day);
        t = await step();
        if (reps < 12) {
          expect(t.targetWeightKg, 20);
          expect(t.targetReps, reps + 1);
        } else {
          expect(t.targetWeightKg, 22.5, reason: 'max atteint → +incrément');
          expect(t.targetReps, 8);
        }
      }
    });
  });
}
