import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscul_app/data/db/database.dart';
import 'package:muscul_app/data/repositories/exercise_repository.dart';
import 'package:muscul_app/domain/models/enums.dart';
import 'package:muscul_app/domain/models/exercise.dart';

void main() {
  late AppDatabase db;
  late LocalExerciseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalExerciseRepository(db);
  });

  tearDown(() async => db.close());

  test('seed exercises are present after first open', () async {
    final all = await repo.getAll();
    expect(all.length, greaterThanOrEqualTo(28));
    expect(all.any((e) => e.name == 'Squat barre'), isTrue);
  });

  test('upsert + getById round-trip', () async {
    final ex = Exercise(
      id: 'custom-1',
      name: 'Mon exo',
      category: ExerciseCategory.push,
      primaryMuscle: MuscleGroup.chest,
      secondaryMuscles: const [MuscleGroup.triceps],
      equipment: Equipment.machine,
      isCustom: true,
      progressionPriority: ProgressionPriority.repsFirst,
      targetRepRangeMin: 6,
      targetRepRangeMax: 10,
      startingWeightKg: 30,
      updatedAt: DateTime(2026, 4, 30),
    );
    await repo.upsert(ex);
    final loaded = await repo.getById('custom-1');
    expect(loaded, isNotNull);
    expect(loaded!.name, 'Mon exo');
    expect(loaded.secondaryMuscles, [MuscleGroup.triceps]);
    expect(loaded.equipment, Equipment.machine);
  });

  test('softDelete hides from default getAll', () async {
    final ex = Exercise(
      id: 'custom-2',
      name: 'À supprimer',
      category: ExerciseCategory.push,
      primaryMuscle: MuscleGroup.chest,
      secondaryMuscles: const [],
      equipment: Equipment.barbell,
      isCustom: true,
      progressionPriority: ProgressionPriority.repsFirst,
      targetRepRangeMin: 8,
      targetRepRangeMax: 12,
      startingWeightKg: 20,
      updatedAt: DateTime(2026, 4, 30),
    );
    await repo.upsert(ex);
    await repo.softDelete('custom-2');
    final visible = await repo.getAll();
    expect(visible.any((e) => e.id == 'custom-2'), isFalse);
    final all = await repo.getAll(includeDeleted: true);
    expect(all.any((e) => e.id == 'custom-2'), isTrue);
  });
}
