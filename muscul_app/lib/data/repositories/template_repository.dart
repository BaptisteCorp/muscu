import 'package:drift/drift.dart';

import '../../domain/models/workout_template.dart';
import '../db/database.dart';
import 'mappers.dart';

class TemplateWithExercises {
  final WorkoutTemplate template;
  /// Ordered list of (exercise + planned sets).
  final List<TemplateExerciseWithSets> exercises;
  const TemplateWithExercises({required this.template, required this.exercises});
}

abstract class TemplateRepository {
  Stream<List<WorkoutTemplate>> watchAll();
  Future<TemplateWithExercises?> getWithExercises(String id);
  Future<void> upsertTemplate(WorkoutTemplate t);

  /// Replaces every (template_exercise + sets) row for [templateId].
  Future<void> setTemplateExercises(
      String templateId, List<TemplateExerciseWithSets> exercises);

  /// Returns the planned sets for [templateExerciseId], in setIndex order.
  Future<List<TemplateExerciseSet>> getTemplateExerciseSets(
      String templateExerciseId);

  Future<void> softDelete(String id);

  /// Replace every planned rep/weight value across this template's
  /// exercise rows that match [exerciseId] with the given values.
  ///
  /// Called when the user validates a working set during a session that
  /// was started from this template — the freshly-done weight/reps
  /// becomes the template's new "default" so it shows up next time the
  /// user looks at the template or starts another session from it.
  ///
  /// Bumps the template's updated_at + sync_status so the sync picks up
  /// the change and propagates it to the cloud.
  Future<void> applyValidatedSet({
    required String templateId,
    required String exerciseId,
    required int reps,
    required double? weightKg,
  });
}

class LocalTemplateRepository implements TemplateRepository {
  final AppDatabase db;
  LocalTemplateRepository(this.db);

  @override
  Stream<List<WorkoutTemplate>> watchAll() {
    final q = db.select(db.workoutTemplates)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch().map((rows) => rows.map(templateFromRow).toList());
  }

  @override
  Future<TemplateWithExercises?> getWithExercises(String id) async {
    final tRow = await (db.select(db.workoutTemplates)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (tRow == null) return null;
    final teRows = await (db.select(db.workoutTemplateExercises)
          ..where((t) => t.templateId.equals(id))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();
    if (teRows.isEmpty) {
      return TemplateWithExercises(
        template: templateFromRow(tRow),
        exercises: const [],
      );
    }
    final ids = teRows.map((r) => r.id).toList();
    final setRows = await (db.select(db.templateExerciseSets)
          ..where((t) => t.templateExerciseId.isIn(ids))
          ..orderBy([
            (t) => OrderingTerm.asc(t.templateExerciseId),
            (t) => OrderingTerm.asc(t.setIndex),
          ]))
        .get();
    final setsByTe = <String, List<TemplateExerciseSet>>{};
    for (final r in setRows) {
      setsByTe
          .putIfAbsent(r.templateExerciseId, () => [])
          .add(templateExerciseSetFromRow(r));
    }
    return TemplateWithExercises(
      template: templateFromRow(tRow),
      exercises: teRows
          .map((r) => TemplateExerciseWithSets(
                exercise: templateExerciseFromRow(r),
                sets: setsByTe[r.id] ?? const [],
              ))
          .toList(),
    );
  }

  @override
  Future<List<TemplateExerciseSet>> getTemplateExerciseSets(
      String templateExerciseId) async {
    final rows = await (db.select(db.templateExerciseSets)
          ..where((t) => t.templateExerciseId.equals(templateExerciseId))
          ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
        .get();
    return rows.map(templateExerciseSetFromRow).toList();
  }

  @override
  Future<void> upsertTemplate(WorkoutTemplate t) async {
    await db
        .into(db.workoutTemplates)
        .insertOnConflictUpdate(templateToCompanion(t));
  }

  @override
  Future<void> setTemplateExercises(
      String templateId, List<TemplateExerciseWithSets> exercises) async {
    await db.transaction(() async {
      // Delete every set whose parent template_exercise belongs to this
      // template, then delete the parents themselves.
      final existingTeRows = await (db.select(db.workoutTemplateExercises)
            ..where((t) => t.templateId.equals(templateId)))
          .get();
      final teIds = existingTeRows.map((r) => r.id).toList();
      if (teIds.isNotEmpty) {
        await (db.delete(db.templateExerciseSets)
              ..where((t) => t.templateExerciseId.isIn(teIds)))
            .go();
      }
      await (db.delete(db.workoutTemplateExercises)
            ..where((t) => t.templateId.equals(templateId)))
          .go();
      for (final tew in exercises) {
        await db.into(db.workoutTemplateExercises).insert(
              templateExerciseToCompanion(tew.exercise),
              mode: InsertMode.insertOrReplace,
            );
        for (final s in tew.sets) {
          await db.into(db.templateExerciseSets).insert(
                templateExerciseSetToCompanion(s),
                mode: InsertMode.insertOrReplace,
              );
        }
      }
    });
  }

  @override
  Future<void> softDelete(String id) async {
    await (db.update(db.workoutTemplates)..where((t) => t.id.equals(id))).write(
      WorkoutTemplatesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  @override
  Future<void> applyValidatedSet({
    required String templateId,
    required String exerciseId,
    required int reps,
    required double? weightKg,
  }) async {
    await db.transaction(() async {
      final teRows = await (db.select(db.workoutTemplateExercises)
            ..where((t) =>
                t.templateId.equals(templateId) &
                t.exerciseId.equals(exerciseId)))
          .get();
      if (teRows.isEmpty) return;
      // Ratchet up only: never let a lighter / lower-rep validation drag
      // the template back down. The "current" baseline is read from the
      // first planned set of each matching template_exercise.
      for (final teRow in teRows) {
        final existing = await (db.select(db.templateExerciseSets)
              ..where((t) => t.templateExerciseId.equals(teRow.id))
              ..orderBy([(t) => OrderingTerm.asc(t.setIndex)])
              ..limit(1))
            .getSingleOrNull();
        if (existing != null) {
          final currentWeight = existing.plannedWeightKg ?? 0;
          final newWeight = weightKg ?? 0;
          final isUp = newWeight > currentWeight ||
              (newWeight == currentWeight &&
                  reps > existing.plannedReps);
          if (!isUp) continue;
        }
        await (db.update(db.templateExerciseSets)
              ..where((t) => t.templateExerciseId.equals(teRow.id)))
            .write(TemplateExerciseSetsCompanion(
          plannedReps: Value(reps),
          plannedWeightKg: Value(weightKg),
        ));
      }
      await (db.update(db.workoutTemplates)
            ..where((t) => t.id.equals(templateId)))
          .write(WorkoutTemplatesCompanion(
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ));
    });
  }
}
