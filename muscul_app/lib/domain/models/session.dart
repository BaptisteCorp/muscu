import 'enums.dart';

class WorkoutSession {
  final String id;
  final String? templateId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;
  final DateTime? plannedFor;
  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String? remoteId;
  final DateTime? deletedAt;

  const WorkoutSession({
    required this.id,
    required this.startedAt,
    required this.updatedAt,
    this.templateId,
    this.endedAt,
    this.notes,
    this.plannedFor,
    this.syncStatus = SyncStatus.pending,
    this.remoteId,
    this.deletedAt,
  });

  bool get isFinished => endedAt != null;
  bool get isPlanned => endedAt == null && plannedFor != null;
  bool get isInProgress => endedAt == null && plannedFor == null;

  WorkoutSession copyWith({
    String? templateId,
    bool clearTemplateId = false,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
    String? notes,
    bool clearNotes = false,
    DateTime? plannedFor,
    bool clearPlannedFor = false,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? remoteId,
    DateTime? deletedAt,
  }) {
    return WorkoutSession(
      id: id,
      templateId: clearTemplateId ? null : (templateId ?? this.templateId),
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      notes: clearNotes ? null : (notes ?? this.notes),
      plannedFor: clearPlannedFor ? null : (plannedFor ?? this.plannedFor),
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      remoteId: remoteId ?? this.remoteId,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

class SessionExercise {
  final String id;
  final String sessionId;
  final String exerciseId;
  final int orderIndex;
  final int? restSeconds;
  final String? supersetGroupId;
  final String? note;
  final String? replacedFromSessionExerciseId;

  const SessionExercise({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.orderIndex,
    this.restSeconds,
    this.supersetGroupId,
    this.note,
    this.replacedFromSessionExerciseId,
  });

  SessionExercise copyWith({
    int? orderIndex,
    int? restSeconds,
    bool clearRestSeconds = false,
    String? supersetGroupId,
    bool clearSupersetGroupId = false,
    String? note,
    bool clearNote = false,
    String? replacedFromSessionExerciseId,
    bool clearReplacedFrom = false,
  }) {
    return SessionExercise(
      id: id,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: orderIndex ?? this.orderIndex,
      restSeconds:
          clearRestSeconds ? null : (restSeconds ?? this.restSeconds),
      supersetGroupId: clearSupersetGroupId
          ? null
          : (supersetGroupId ?? this.supersetGroupId),
      note: clearNote ? null : (note ?? this.note),
      replacedFromSessionExerciseId: clearReplacedFrom
          ? null
          : (replacedFromSessionExerciseId ?? this.replacedFromSessionExerciseId),
    );
  }
}

class SessionExerciseWithSets {
  final SessionExercise sessionExercise;
  final List<SetEntry> sets;
  const SessionExerciseWithSets({required this.sessionExercise, required this.sets});
}

class SetEntry {
  final String id;
  final String sessionExerciseId;
  final int setIndex;
  final int reps;
  final double weightKg;
  final int? rpe;
  final int? rir;
  final int restSeconds;
  final bool isWarmup;
  final bool isFailure;
  final DateTime completedAt;

  const SetEntry({
    required this.id,
    required this.sessionExerciseId,
    required this.setIndex,
    required this.reps,
    required this.weightKg,
    required this.restSeconds,
    required this.completedAt,
    this.rpe,
    this.rir,
    this.isWarmup = false,
    this.isFailure = false,
  });

  SetEntry copyWith({
    int? setIndex,
    int? reps,
    double? weightKg,
    int? rpe,
    bool clearRpe = false,
    int? rir,
    bool clearRir = false,
    int? restSeconds,
    bool? isWarmup,
    bool? isFailure,
    DateTime? completedAt,
  }) {
    return SetEntry(
      id: id,
      sessionExerciseId: sessionExerciseId,
      setIndex: setIndex ?? this.setIndex,
      reps: reps ?? this.reps,
      weightKg: weightKg ?? this.weightKg,
      rpe: clearRpe ? null : (rpe ?? this.rpe),
      rir: clearRir ? null : (rir ?? this.rir),
      restSeconds: restSeconds ?? this.restSeconds,
      isWarmup: isWarmup ?? this.isWarmup,
      isFailure: isFailure ?? this.isFailure,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
