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
}
