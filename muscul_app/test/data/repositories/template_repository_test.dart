import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/db/database.dart';
import 'package:reps/data/repositories/template_repository.dart';
import 'package:reps/domain/models/workout_template.dart';

void main() {
  late AppDatabase db;
  late LocalTemplateRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalTemplateRepository(db);
  });

  tearDown(() async => db.close());

  TemplateExerciseWithSets te(
    String id,
    String exerciseId,
    int order, {
    int sets = 3,
  }) {
    return TemplateExerciseWithSets(
      exercise: WorkoutTemplateExercise(
        id: id,
        templateId: 't1',
        exerciseId: exerciseId,
        orderIndex: order,
        targetSets: sets,
        restSeconds: 90,
      ),
      sets: [
        for (var i = 0; i < sets; i++)
          TemplateExerciseSet(
            id: '$id-s$i',
            templateExerciseId: id,
            setIndex: i,
            plannedReps: 10,
            plannedWeightKg: 40,
          ),
      ],
    );
  }

  Future<void> seedTemplate(List<TemplateExerciseWithSets> exercises) async {
    await repo.upsertTemplate(WorkoutTemplate(
      id: 't1',
      name: 'Push A',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ));
    await repo.setTemplateExercises('t1', exercises);
  }

  test('removing an exercise drops its rows and its planned sets', () async {
    await seedTemplate([te('te-a', 'ex-a', 0), te('te-b', 'ex-b', 1)]);

    var detail = await repo.getWithExercises('t1');
    expect(detail!.exercises.length, 2);

    // Save again without te-b — mirrors deleting an exercise in the editor.
    await repo.setTemplateExercises('t1', [te('te-a', 'ex-a', 0)]);

    detail = await repo.getWithExercises('t1');
    expect(detail!.exercises.length, 1);
    expect(detail.exercises.single.exercise.id, 'te-a');

    // The removed exercise's planned sets must be gone too (no orphans that a
    // pull could resurrect).
    final orphanSets = await repo.getTemplateExerciseSets('te-b');
    expect(orphanSets, isEmpty);
  });

  test('reducing the set count drops the removed planned sets', () async {
    await seedTemplate([te('te-a', 'ex-a', 0, sets: 4)]);
    expect((await repo.getTemplateExerciseSets('te-a')).length, 4);

    await repo.setTemplateExercises('t1', [te('te-a', 'ex-a', 0, sets: 2)]);
    expect((await repo.getTemplateExerciseSets('te-a')).length, 2);
  });

  test('clearing every exercise leaves no template_exercise rows', () async {
    await seedTemplate([te('te-a', 'ex-a', 0)]);
    await repo.setTemplateExercises('t1', const []);

    final detail = await repo.getWithExercises('t1');
    expect(detail!.exercises, isEmpty);
  });

  group('applyValidatedSet — ratchet', () {
    test('weighted : poids inférieur ne fait PAS reculer le plan', () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]); // plan 10 reps @ 40kg
      await repo.applyValidatedSet(
        templateId: 't1',
        exerciseId: 'ex-a',
        reps: 12,
        weightKg: 30, // plus léger → ne doit pas écraser
      );
      final sets = await repo.getTemplateExerciseSets('te-a');
      expect(sets.first.plannedReps, 10, reason: 'ratchet up only');
      expect(sets.first.plannedWeightKg, 40);
    });

    test(
        'poids du corps : plannedWeightKg résiduel (20) ne bloque PAS la montée '
        'des reps', () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]); // plan 10 reps @ 40kg (sale)
      // Séance au poids du corps : 12 reps, poids 0. Sans le fix, 0 > 40 = faux
      // → le plan resterait figé. Avec useBodyweight on compare les reps seules.
      await repo.applyValidatedSet(
        templateId: 't1',
        exerciseId: 'ex-a',
        reps: 12,
        weightKg: 0,
        useBodyweight: true,
      );
      final sets = await repo.getTemplateExerciseSets('te-a');
      expect(sets.first.plannedReps, 12, reason: 'le plan suit les reps');
      expect(sets.first.plannedWeightKg, isNull,
          reason: 'poids planifié nettoyé au poids du corps');
    });

    test('poids du corps : reps inférieures ne font PAS reculer le plan',
        () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]); // plan 10 reps
      await repo.applyValidatedSet(
        templateId: 't1',
        exerciseId: 'ex-a',
        reps: 8,
        weightKg: 0,
        useBodyweight: true,
      );
      final sets = await repo.getTemplateExerciseSets('te-a');
      expect(sets.first.plannedReps, 10, reason: 'ratchet up only sur les reps');
    });
  });

  group('countTemplatesUsingExercise', () {
    test('compte les modèles distincts non supprimés référençant l\'exo',
        () async {
      await seedTemplate([te('te-a', 'ex-a', 0), te('te-b', 'ex-b', 1)]);
      // Second modèle utilisant aussi ex-a.
      await repo.upsertTemplate(WorkoutTemplate(
        id: 't2',
        name: 'Push B',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repo.setTemplateExercises('t2', [
        TemplateExerciseWithSets(
          exercise: const WorkoutTemplateExercise(
            id: 'te-a2',
            templateId: 't2',
            exerciseId: 'ex-a',
            orderIndex: 0,
            targetSets: 3,
            restSeconds: 90,
          ),
          sets: const [
            TemplateExerciseSet(
              id: 'te-a2-s0',
              templateExerciseId: 'te-a2',
              setIndex: 0,
              plannedReps: 10,
              plannedWeightKg: 40,
            ),
          ],
        ),
      ]);

      expect(await repo.countTemplatesUsingExercise('ex-a'), 2);
      expect(await repo.countTemplatesUsingExercise('ex-b'), 1);
      expect(await repo.countTemplatesUsingExercise('ex-x'), 0);
    });

    test('ignore les modèles supprimés', () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]);
      expect(await repo.countTemplatesUsingExercise('ex-a'), 1);
      await repo.softDelete('t1');
      expect(await repo.countTemplatesUsingExercise('ex-a'), 0);
    });
  });

  group('clampPlannedRepsForExercise', () {
    Future<DateTime> templateUpdatedAt() async {
      final row = await (db.select(db.workoutTemplates)
            ..where((t) => t.id.equals('t1')))
          .getSingle();
      return row.updatedAt;
    }

    test('borne les reps planifiées au-dessus du plafond', () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]); // plannedReps 10
      await repo.clampPlannedRepsForExercise(exerciseId: 'ex-a', min: 6, max: 8);
      final sets = await repo.getTemplateExerciseSets('te-a');
      expect(sets.every((s) => s.plannedReps == 8), isTrue);
      expect((await templateUpdatedAt()).isAfter(DateTime(2026, 1, 1)), isTrue,
          reason: 'modèle bumpé pour la sync');
    });

    test('borne les reps planifiées sous le plancher', () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]); // plannedReps 10
      await repo.clampPlannedRepsForExercise(
          exerciseId: 'ex-a', min: 12, max: 15);
      final sets = await repo.getTemplateExerciseSets('te-a');
      expect(sets.every((s) => s.plannedReps == 12), isTrue);
    });

    test('reps déjà dans la plage → inchangé, pas de bump', () async {
      await seedTemplate([te('te-a', 'ex-a', 0)]); // plannedReps 10
      await repo.clampPlannedRepsForExercise(
          exerciseId: 'ex-a', min: 8, max: 12);
      final sets = await repo.getTemplateExerciseSets('te-a');
      expect(sets.every((s) => s.plannedReps == 10), isTrue);
      expect(await templateUpdatedAt(), DateTime(2026, 1, 1),
          reason: 'aucune série hors plage → pas de bump');
    });

    test('ne bumpe QUE les modèles dont une série a été clampée', () async {
      // t1 utilise ex-a avec plannedReps 10 (sera hors plage 6-8 → clampé).
      await seedTemplate([te('te-a', 'ex-a', 0)]);
      // t2 utilise aussi ex-a mais avec plannedReps 7 (déjà dans 6-8).
      await repo.upsertTemplate(WorkoutTemplate(
        id: 't2',
        name: 'B',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ));
      await repo.setTemplateExercises('t2', [
        TemplateExerciseWithSets(
          exercise: const WorkoutTemplateExercise(
            id: 'te-a2',
            templateId: 't2',
            exerciseId: 'ex-a',
            orderIndex: 0,
            targetSets: 1,
            restSeconds: 90,
          ),
          sets: const [
            TemplateExerciseSet(
              id: 'te-a2-s0',
              templateExerciseId: 'te-a2',
              setIndex: 0,
              plannedReps: 7,
              plannedWeightKg: 40,
            ),
          ],
        ),
      ]);

      await repo.clampPlannedRepsForExercise(exerciseId: 'ex-a', min: 6, max: 8);

      // t1 corrigé (10 → 8) donc bumpé ; t2 intact donc PAS bumpé.
      expect((await templateUpdatedAt()).isAfter(DateTime(2026, 1, 1)), isTrue);
      final t2 = await (db.select(db.workoutTemplates)
            ..where((t) => t.id.equals('t2')))
          .getSingle();
      expect(t2.updatedAt, DateTime(2026, 1, 1),
          reason: 't2 n\'avait aucune série hors plage → pas de resync inutile');
    });
  });
}
