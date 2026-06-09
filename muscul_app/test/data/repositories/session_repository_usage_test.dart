import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/db/database.dart';
import 'package:reps/data/repositories/exercise_repository.dart';
import 'package:reps/data/repositories/session_repository.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/session.dart';

void main() {
  late AppDatabase db;
  late LocalSessionRepository repo;
  late LocalExerciseRepository exo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalSessionRepository(db);
    exo = LocalExerciseRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> addExercise(String id) => exo.upsert(Exercise(
        id: id,
        name: id,
        category: ExerciseCategory.pull,
        primaryMuscle: MuscleGroup.biceps,
        secondaryMuscles: const [],
        equipment: Equipment.cable,
        isCustom: true,
        targetRepRangeMin: 8,
        targetRepRangeMax: 12,
        startingWeightKg: 20,
        updatedAt: DateTime(2026, 6, 1),
      ));

  /// Records an ended session containing [exId]. Optionally adds a validated
  /// working set and/or a warm-up-only set.
  Future<void> endedSession(
    String sid,
    String exId,
    String seId, {
    bool workingSet = false,
    bool warmupSet = false,
  }) async {
    await repo.upsertSession(WorkoutSession(
      id: sid,
      startedAt: DateTime(2026, 6, 1, 10),
      endedAt: DateTime(2026, 6, 1, 11),
      updatedAt: DateTime(2026, 6, 1, 11),
    ));
    await repo.upsertSessionExercise(SessionExercise(
      id: seId,
      sessionId: sid,
      exerciseId: exId,
      orderIndex: 0,
    ));
    if (workingSet) {
      await repo.upsertSet(SetEntry(
        id: '$seId-w',
        sessionExerciseId: seId,
        setIndex: 0,
        reps: 10,
        weightKg: 30,
        restSeconds: 0,
        completedAt: DateTime(2026, 6, 1, 10, 30),
      ));
    }
    if (warmupSet) {
      await repo.upsertSet(SetEntry(
        id: '$seId-wu',
        sessionExerciseId: seId,
        setIndex: 1,
        reps: 10,
        weightKg: 10,
        restSeconds: 0,
        isWarmup: true,
        completedAt: DateTime(2026, 6, 1, 10, 20),
      ));
    }
  }

  test('usage count ignores sessions where only a warm-up was logged',
      () async {
    await addExercise('curl');
    await endedSession('s1', 'curl', 'se1', workingSet: true);
    // Curl present but only warmed up — no working set validated.
    await endedSession('s2', 'curl', 'se2', warmupSet: true);

    final counts = await repo.watchExerciseUsageCounts().first;
    expect(counts['curl'], 1);
  });

  test('usage count ignores sessions with no validated set at all', () async {
    await addExercise('curl');
    await endedSession('s1', 'curl', 'se1', workingSet: true);
    await endedSession('s2', 'curl', 'se2'); // exo present, nothing logged

    final counts = await repo.watchExerciseUsageCounts().first;
    expect(counts['curl'], 1);
  });

  test('two genuinely-trained sessions count twice', () async {
    await addExercise('curl');
    await endedSession('s1', 'curl', 'se1', workingSet: true);
    await endedSession('s2', 'curl', 'se2', workingSet: true);

    final counts = await repo.watchExerciseUsageCounts().first;
    expect(counts['curl'], 2);
  });
}
