import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/core/providers.dart';
import 'package:reps/data/db/database.dart';
import 'package:reps/data/repositories/session_repository.dart';
import 'package:reps/domain/models/session.dart';
import 'package:reps/ui/session/start_session_controller.dart';

/// Régressions sur les flux de séance corrigés :
///  - double-tap de démarrage qui créait une séance orpheline,
///  - collision d'orderIndex lors d'un swap d'exo.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('StartSessionController — anti double-démarrage', () {
    test('appels concurrents → une seule séance, même id', () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final ctrl = container.read(startSessionControllerProvider);

      // Trois "taps" quasi simultanés (le Future en vol est partagé).
      final ids = await Future.wait([
        ctrl.startSession(),
        ctrl.startSession(),
        ctrl.startSession(),
      ]);

      expect(ids.toSet().length, 1, reason: 'même séance renvoyée à tous');
      final sessions = await db.select(db.workoutSessions).get();
      expect(sessions.length, 1, reason: 'pas de séance orpheline');
    });

    test('après complétion, un nouveau démarrage crée bien une autre séance',
        () async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      final ctrl = container.read(startSessionControllerProvider);

      final id1 = await ctrl.startSession();
      final id2 = await ctrl.startSession();
      expect(id1, isNot(id2));
      final sessions = await db.select(db.workoutSessions).get();
      expect(sessions.length, 2);
    });
  });

  group('Swap d\'exo — orderIndex sans collision', () {
    test('shiftSessionExerciseOrder libère la place, ordre déterministe',
        () async {
      final repo = LocalSessionRepository(db);
      await repo.upsertSession(WorkoutSession(
        id: 's1',
        startedAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 1),
      ));
      // 3 exos : A(0) B(1) C(2)
      for (final (i, ex) in [(0, 'A'), (1, 'B'), (2, 'C')]) {
        await repo.upsertSessionExercise(SessionExercise(
          id: 'se-$ex',
          sessionId: 's1',
          exerciseId: 'ex-$ex',
          orderIndex: i,
        ));
      }
      // On "swappe" A : insertion juste après orderIndex 0 → cible 1.
      await repo.shiftSessionExerciseOrder(sessionId: 's1', fromOrderIndex: 1);
      await repo.upsertSessionExercise(const SessionExercise(
        id: 'se-X',
        sessionId: 's1',
        exerciseId: 'ex-X',
        orderIndex: 1,
        replacedFromSessionExerciseId: 'se-A',
      ));

      final detail = await repo.getDetail('s1');
      final order =
          detail!.exercises.map((e) => e.sessionExercise.orderIndex).toList();
      // 4 exos, indices distincts et triés : 0,1,2,3
      expect(order, [0, 1, 2, 3]);
      // L'exo inséré (X) est bien en position 1, l'ancien suivant (B) en 2.
      final ids =
          detail.exercises.map((e) => e.sessionExercise.exerciseId).toList();
      expect(ids, ['ex-A', 'ex-X', 'ex-B', 'ex-C']);
    });
  });
}
