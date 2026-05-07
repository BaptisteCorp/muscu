import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../data/repositories/template_repository.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/session.dart';

const _uuid = Uuid();

/// Starts (or resumes) a workout session and returns its id.
class StartSessionController {
  StartSessionController(this.ref);
  final Ref ref;

  /// If [templateId] is provided, the session is materialized from the template.
  /// If null, an empty freestyle session is created.
  Future<String> startSession({String? templateId}) async {
    final sessions = ref.read(sessionRepositoryProvider);
    final id = _uuid.v4();
    final now = DateTime.now();
    final session = WorkoutSession(
      id: id,
      templateId: templateId,
      startedAt: now,
      updatedAt: now,
    );
    await sessions.upsertSession(session);
    if (templateId != null) {
      final tpl = await ref
          .read(templateRepositoryProvider)
          .getWithExercises(templateId);
      if (tpl != null) {
        for (var i = 0; i < tpl.exercises.length; i++) {
          final tew = tpl.exercises[i];
          await sessions.upsertSessionExercise(SessionExercise(
            id: _uuid.v4(),
            sessionId: id,
            exerciseId: tew.exercise.exerciseId,
            orderIndex: i,
            restSeconds: tew.exercise.restSeconds,
          ));
        }
      }
    }
    // Best-effort cloud backup of the freshly-created session shell.
    unawaited(ref.read(syncServiceProvider).sync());
    return id;
  }

  /// Promotes a previously planned session into in-progress (clears plannedFor,
  /// sets startedAt to now if not started yet).
  Future<void> activatePlanned(String sessionId) async {
    final sessions = ref.read(sessionRepositoryProvider);
    final detail = await sessions.getDetail(sessionId);
    if (detail == null) return;
    final updated = detail.session.copyWith(
      clearPlannedFor: true,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await sessions.upsertSession(updated);
  }
}

final startSessionControllerProvider = Provider<StartSessionController>((ref) {
  return StartSessionController(ref);
});

/// Materializes one session-exercise on the fly (used by quick-swap & freestyle add).
/// Pass either a Riverpod [Ref] or a [WidgetRef] — both have a [read] method.
Future<String> addExerciseToSession({
  required dynamic ref,
  required String sessionId,
  required String exerciseId,
  required int orderIndex,
  String? replacedFromSessionExerciseId,
}) async {
  final id = _uuid.v4();
  await ref.read(sessionRepositoryProvider).upsertSessionExercise(
        SessionExercise(
          id: id,
          sessionId: sessionId,
          exerciseId: exerciseId,
          orderIndex: orderIndex,
          replacedFromSessionExerciseId: replacedFromSessionExerciseId,
        ),
      );
  return id;
}
