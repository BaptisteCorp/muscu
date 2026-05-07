import 'enums.dart';

class WorkoutTemplate {
  final String id;
  final String name;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String? remoteId;
  final DateTime? deletedAt;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.syncStatus = SyncStatus.pending,
    this.remoteId,
    this.deletedAt,
  });

  WorkoutTemplate copyWith({
    String? name,
    String? notes,
    bool clearNotes = false,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? remoteId,
    DateTime? deletedAt,
  }) {
    return WorkoutTemplate(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: clearNotes ? null : (notes ?? this.notes),
      syncStatus: syncStatus ?? this.syncStatus,
      remoteId: remoteId ?? this.remoteId,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

class WorkoutTemplateExercise {
  final String id;
  final String templateId;
  final String exerciseId;
  final int orderIndex;
  final int targetSets;
  final int? restSeconds;

  const WorkoutTemplateExercise({
    required this.id,
    required this.templateId,
    required this.exerciseId,
    required this.orderIndex,
    required this.targetSets,
    this.restSeconds,
  });

  WorkoutTemplateExercise copyWith({
    int? orderIndex,
    int? targetSets,
    int? restSeconds,
    bool clearRestSeconds = false,
  }) {
    return WorkoutTemplateExercise(
      id: id,
      templateId: templateId,
      exerciseId: exerciseId,
      orderIndex: orderIndex ?? this.orderIndex,
      targetSets: targetSets ?? this.targetSets,
      restSeconds:
          clearRestSeconds ? null : (restSeconds ?? this.restSeconds),
    );
  }
}

/// One planned set inside a template-exercise. The position in the
/// sequence is `setIndex` (0-based).
class TemplateExerciseSet {
  final String id;
  final String templateExerciseId;
  final int setIndex;
  final int plannedReps;

  /// `null` for pure bodyweight exercises (or "to-decide-live").
  final double? plannedWeightKg;

  const TemplateExerciseSet({
    required this.id,
    required this.templateExerciseId,
    required this.setIndex,
    required this.plannedReps,
    this.plannedWeightKg,
  });

  TemplateExerciseSet copyWith({
    int? setIndex,
    int? plannedReps,
    double? plannedWeightKg,
    bool clearPlannedWeightKg = false,
  }) {
    return TemplateExerciseSet(
      id: id,
      templateExerciseId: templateExerciseId,
      setIndex: setIndex ?? this.setIndex,
      plannedReps: plannedReps ?? this.plannedReps,
      plannedWeightKg: clearPlannedWeightKg
          ? null
          : (plannedWeightKg ?? this.plannedWeightKg),
    );
  }
}

/// Convenience composite returned by the repo.
class TemplateExerciseWithSets {
  final WorkoutTemplateExercise exercise;
  final List<TemplateExerciseSet> sets;
  const TemplateExerciseWithSets({
    required this.exercise,
    required this.sets,
  });
}
