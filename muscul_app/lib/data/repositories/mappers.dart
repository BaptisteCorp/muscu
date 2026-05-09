import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/models/enums.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/session.dart';
import '../../domain/models/user_settings.dart';
import '../../domain/models/workout_template.dart';
import '../db/database.dart';

// --- Exercise -----------------------------------------------------

Exercise exerciseFromRow(ExerciseEntity row) {
  final secondaryRaw = jsonDecode(row.secondaryMuscles) as List<dynamic>;
  return Exercise(
    id: row.id,
    name: row.name,
    category:
        enumByName(ExerciseCategory.values, row.category, fallback: ExerciseCategory.push),
    primaryMuscle:
        enumByName(MuscleGroup.values, row.primaryMuscle, fallback: MuscleGroup.chest),
    secondaryMuscles: [
      for (final s in secondaryRaw)
        enumByName(MuscleGroup.values, s as String, fallback: MuscleGroup.chest),
    ],
    equipment:
        enumByName(Equipment.values, row.equipment, fallback: Equipment.other),
    isCustom: row.isCustom,
    defaultIncrementKg: row.defaultIncrementKg,
    defaultRestSeconds: row.defaultRestSeconds,
    progressiveOverloadEnabled: row.progressiveOverloadEnabled,
    progressionPriority: enumByName(
      ProgressionPriority.values,
      row.progressionPriority,
      fallback: ProgressionPriority.repsFirst,
    ),
    minimumRpeThreshold: row.minimumRpeThreshold,
    targetRepRangeMin: row.targetRepRangeMin,
    targetRepRangeMax: row.targetRepRangeMax,
    startingWeightKg: row.startingWeightKg,
    useBodyweight: row.useBodyweight,
    notes: row.notes,
    machineBrandModel: row.machineBrandModel,
    machineSettings: row.machineSettings,
    photoPath: row.photoPath,
    updatedAt: row.updatedAt,
    syncStatus: enumByName(SyncStatus.values, row.syncStatus,
        fallback: SyncStatus.pending),
    remoteId: row.remoteId,
    deletedAt: row.deletedAt,
  );
}

ExercisesCompanion exerciseToCompanion(Exercise e) {
  return ExercisesCompanion.insert(
    id: e.id,
    name: e.name,
    category: e.category.name,
    primaryMuscle: e.primaryMuscle.name,
    secondaryMuscles: drift.Value(
      jsonEncode(e.secondaryMuscles.map((m) => m.name).toList()),
    ),
    equipment: e.equipment.name,
    isCustom: drift.Value(e.isCustom),
    defaultIncrementKg: drift.Value(e.defaultIncrementKg),
    defaultRestSeconds: drift.Value(e.defaultRestSeconds),
    progressiveOverloadEnabled: drift.Value(e.progressiveOverloadEnabled),
    progressionPriority: drift.Value(e.progressionPriority.name),
    minimumRpeThreshold: drift.Value(e.minimumRpeThreshold),
    targetRepRangeMin: drift.Value(e.targetRepRangeMin),
    targetRepRangeMax: drift.Value(e.targetRepRangeMax),
    startingWeightKg: drift.Value(e.startingWeightKg),
    useBodyweight: drift.Value(e.useBodyweight),
    notes: drift.Value(e.notes),
    machineBrandModel: drift.Value(e.machineBrandModel),
    machineSettings: drift.Value(e.machineSettings),
    photoPath: drift.Value(e.photoPath),
    updatedAt: e.updatedAt,
    syncStatus: drift.Value(e.syncStatus.name),
    remoteId: drift.Value(e.remoteId),
    deletedAt: drift.Value(e.deletedAt),
  );
}

// --- Templates ----------------------------------------------------

WorkoutTemplate templateFromRow(WorkoutTemplateEntity row) => WorkoutTemplate(
      id: row.id,
      name: row.name,
      notes: row.notes,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      syncStatus: enumByName(SyncStatus.values, row.syncStatus,
          fallback: SyncStatus.pending),
      remoteId: row.remoteId,
      deletedAt: row.deletedAt,
    );

WorkoutTemplatesCompanion templateToCompanion(WorkoutTemplate t) =>
    WorkoutTemplatesCompanion.insert(
      id: t.id,
      name: t.name,
      notes: drift.Value(t.notes),
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      syncStatus: drift.Value(t.syncStatus.name),
      remoteId: drift.Value(t.remoteId),
      deletedAt: drift.Value(t.deletedAt),
    );

WorkoutTemplateExercise templateExerciseFromRow(
        WorkoutTemplateExerciseEntity row) =>
    WorkoutTemplateExercise(
      id: row.id,
      templateId: row.templateId,
      exerciseId: row.exerciseId,
      orderIndex: row.orderIndex,
      targetSets: row.targetSets,
      restSeconds: row.restSeconds,
    );

WorkoutTemplateExercisesCompanion templateExerciseToCompanion(
        WorkoutTemplateExercise te) =>
    WorkoutTemplateExercisesCompanion.insert(
      id: te.id,
      templateId: te.templateId,
      exerciseId: te.exerciseId,
      orderIndex: te.orderIndex,
      targetSets: drift.Value(te.targetSets),
      restSeconds: drift.Value(te.restSeconds),
    );

TemplateExerciseSet templateExerciseSetFromRow(
        TemplateExerciseSetEntity row) =>
    TemplateExerciseSet(
      id: row.id,
      templateExerciseId: row.templateExerciseId,
      setIndex: row.setIndex,
      plannedReps: row.plannedReps,
      plannedWeightKg: row.plannedWeightKg,
    );

TemplateExerciseSetsCompanion templateExerciseSetToCompanion(
        TemplateExerciseSet s) =>
    TemplateExerciseSetsCompanion.insert(
      id: s.id,
      templateExerciseId: s.templateExerciseId,
      setIndex: s.setIndex,
      plannedReps: s.plannedReps,
      plannedWeightKg: drift.Value(s.plannedWeightKg),
    );

// --- Sessions -----------------------------------------------------

WorkoutSession sessionFromRow(WorkoutSessionEntity row) => WorkoutSession(
      id: row.id,
      templateId: row.templateId,
      startedAt: row.startedAt,
      endedAt: row.endedAt,
      notes: row.notes,
      updatedAt: row.updatedAt,
      syncStatus: enumByName(SyncStatus.values, row.syncStatus,
          fallback: SyncStatus.pending),
      remoteId: row.remoteId,
      deletedAt: row.deletedAt,
    );

WorkoutSessionsCompanion sessionToCompanion(WorkoutSession s) =>
    WorkoutSessionsCompanion.insert(
      id: s.id,
      templateId: drift.Value(s.templateId),
      startedAt: s.startedAt,
      endedAt: drift.Value(s.endedAt),
      notes: drift.Value(s.notes),
      updatedAt: s.updatedAt,
      syncStatus: drift.Value(s.syncStatus.name),
      remoteId: drift.Value(s.remoteId),
      deletedAt: drift.Value(s.deletedAt),
    );

SessionExercise sessionExerciseFromRow(SessionExerciseEntity row) =>
    SessionExercise(
      id: row.id,
      sessionId: row.sessionId,
      exerciseId: row.exerciseId,
      orderIndex: row.orderIndex,
      restSeconds: row.restSeconds,
      supersetGroupId: row.supersetGroupId,
      note: row.note,
      replacedFromSessionExerciseId: row.replacedFromSessionExerciseId,
    );

SessionExercisesCompanion sessionExerciseToCompanion(SessionExercise se) =>
    SessionExercisesCompanion.insert(
      id: se.id,
      sessionId: se.sessionId,
      exerciseId: se.exerciseId,
      orderIndex: se.orderIndex,
      restSeconds: drift.Value(se.restSeconds),
      supersetGroupId: drift.Value(se.supersetGroupId),
      note: drift.Value(se.note),
      replacedFromSessionExerciseId:
          drift.Value(se.replacedFromSessionExerciseId),
    );

SetEntry setFromRow(SetEntryEntity row) => SetEntry(
      id: row.id,
      sessionExerciseId: row.sessionExerciseId,
      setIndex: row.setIndex,
      reps: row.reps,
      weightKg: row.weightKg,
      rpe: row.rpe,
      rir: row.rir,
      restSeconds: row.restSeconds,
      isWarmup: row.isWarmup,
      isFailure: row.isFailure,
      completedAt: row.completedAt,
    );

SetEntriesCompanion setToCompanion(SetEntry s) => SetEntriesCompanion.insert(
      id: s.id,
      sessionExerciseId: s.sessionExerciseId,
      setIndex: s.setIndex,
      reps: s.reps,
      weightKg: s.weightKg,
      rpe: drift.Value(s.rpe),
      rir: drift.Value(s.rir),
      restSeconds: drift.Value(s.restSeconds),
      isWarmup: drift.Value(s.isWarmup),
      isFailure: drift.Value(s.isFailure),
      completedAt: s.completedAt,
    );

// --- UserSettings -------------------------------------------------

UserSettings settingsFromRow(UserSettingsRow row) => UserSettings(
      defaultIncrementKg: row.defaultIncrementKg,
      weightUnit: enumByName(WeightUnit.values, row.weightUnit,
          fallback: WeightUnit.kg),
      defaultRestSeconds: row.defaultRestSeconds,
      useRirInsteadOfRpe: row.useRirInsteadOfRpe,
      userBodyweightKg: row.userBodyweightKg,
      themeMode: enumByName(AppThemeMode.values, row.themeMode,
          fallback: AppThemeMode.system),
    );
