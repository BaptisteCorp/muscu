import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/db/database.dart';
import 'package:reps/data/repositories/exercise_repository.dart';
import 'package:reps/data/repositories/session_repository.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/exercise.dart';
import 'package:reps/domain/models/session.dart';

/// `wipeUserData()` (suppression de compte) doit effacer toutes les données
/// personnelles locales mais préserver les exercices seed et laisser des
/// réglages par défaut exploitables.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('efface le perso, garde les seeds, réinitialise les réglages', () async {
    final exo = LocalExerciseRepository(db);
    final sessions = LocalSessionRepository(db);

    // onCreate a déjà inséré les exos seed.
    final seedCountBefore = (await (db.select(db.exercises)
              ..where((t) => t.isCustom.equals(false)))
            .get())
        .length;
    expect(seedCountBefore, greaterThan(0));

    // Données personnelles : un exo custom + une séance loggée.
    await exo.upsert(Exercise(
      id: 'custom-1',
      name: 'Mon exo',
      category: ExerciseCategory.push,
      primaryMuscle: MuscleGroup.chest,
      secondaryMuscles: const [],
      equipment: Equipment.barbell,
      isCustom: true,
      targetRepRangeMin: 8,
      targetRepRangeMax: 12,
      startingWeightKg: 40,
      updatedAt: DateTime(2026, 1, 1),
    ));
    await sessions.upsertSession(WorkoutSession(
      id: 's1',
      startedAt: DateTime(2026, 1, 2),
      endedAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    ));
    await sessions.upsertSessionExercise(const SessionExercise(
      id: 'se1',
      sessionId: 's1',
      exerciseId: 'custom-1',
      orderIndex: 0,
    ));
    await sessions.upsertSet(SetEntry(
      id: 'set1',
      sessionExerciseId: 'se1',
      setIndex: 0,
      reps: 10,
      weightKg: 40,
      restSeconds: 0,
      completedAt: DateTime(2026, 1, 2),
    ));

    await db.wipeUserData();

    // Perso effacé.
    expect(await db.select(db.workoutSessions).get(), isEmpty);
    expect(await db.select(db.sessionExercises).get(), isEmpty);
    expect(await db.select(db.setEntries).get(), isEmpty);
    final customAfter = await (db.select(db.exercises)
          ..where((t) => t.isCustom.equals(true)))
        .get();
    expect(customAfter, isEmpty, reason: 'exos custom supprimés');

    // Seeds conservés.
    final seedCountAfter = (await (db.select(db.exercises)
              ..where((t) => t.isCustom.equals(false)))
            .get())
        .length;
    expect(seedCountAfter, seedCountBefore, reason: 'seeds préservés');

    // Réglages : singleton par défaut présent.
    final settings = await db.select(db.userSettingsTable).get();
    expect(settings.length, 1);
    expect(settings.single.id, 1);
  });
}
