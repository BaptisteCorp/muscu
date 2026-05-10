import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../data/photo_storage.dart';
import '../data/repositories/bodyweight_repository.dart';
import '../data/repositories/exercise_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/template_repository.dart';
import '../domain/models/bodyweight_entry.dart';
import '../domain/models/exercise.dart';
import '../domain/models/session.dart';
import '../domain/models/user_settings.dart';
import '../domain/models/workout_template.dart';

// --- Infra & repositories ----------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return LocalExerciseRepository(ref.watch(databaseProvider));
});

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return LocalTemplateRepository(ref.watch(databaseProvider));
});

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  return LocalSessionRepository(ref.watch(databaseProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return LocalSettingsRepository(ref.watch(databaseProvider));
});

final bodyweightRepositoryProvider = Provider<BodyweightRepository>((ref) {
  return LocalBodyweightRepository(ref.watch(databaseProvider));
});

final bodyweightEntriesProvider =
    StreamProvider<List<BodyweightEntry>>((ref) {
  return ref.watch(bodyweightRepositoryProvider).watchAll();
});

final photoStorageProvider = Provider<PhotoStorage>((ref) => PhotoStorage());

// --- Stream / Future providers (centralized to avoid leaks) ------

final settingsStreamProvider = StreamProvider<UserSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watch();
});

final allExercisesProvider = StreamProvider<List<Exercise>>((ref) {
  return ref.watch(exerciseRepositoryProvider).watchAll();
});

final allTemplatesProvider = StreamProvider<List<WorkoutTemplate>>((ref) {
  return ref.watch(templateRepositoryProvider).watchAll();
});

final inProgressSessionProvider = StreamProvider<WorkoutSession?>((ref) {
  return ref.watch(sessionRepositoryProvider).watchInProgress();
});

final sessionHistoryProvider = StreamProvider<List<WorkoutSession>>((ref) {
  return ref.watch(sessionRepositoryProvider).watchHistory();
});

final sessionDetailProvider =
    StreamProvider.family<SessionDetail?, String>((ref, sessionId) {
  return ref.watch(sessionRepositoryProvider).watchDetail(sessionId);
});

final exerciseByIdProvider =
    FutureProvider.family<Exercise?, String>((ref, id) {
  return ref.watch(exerciseRepositoryProvider).getById(id);
});

final exerciseHistoryProvider =
    StreamProvider.family<List<SessionExerciseWithSets>, String>(
        (ref, exerciseId) {
  return ref
      .watch(sessionRepositoryProvider)
      .watchHistoryForExercise(exerciseId, limit: 90);
});

final trainedExerciseIdsProvider = StreamProvider<List<String>>((ref) {
  return ref.watch(sessionRepositoryProvider).watchTrainedExerciseIds();
});

final lastSessionByTemplateProvider =
    StreamProvider<Map<String, WorkoutSession>>((ref) {
  return ref.watch(sessionRepositoryProvider).watchLastSessionByTemplate();
});

final exerciseUsageCountsProvider =
    StreamProvider<Map<String, int>>((ref) {
  return ref.watch(sessionRepositoryProvider).watchExerciseUsageCounts();
});

class VolumeRange {
  final DateTime from;
  final DateTime to;
  const VolumeRange({required this.from, required this.to});
  @override
  bool operator ==(Object other) =>
      other is VolumeRange && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

final volumeByMuscleProvider =
    StreamProvider.family<Map<String, double>, VolumeRange>((ref, range) {
  return ref
      .watch(sessionRepositoryProvider)
      .watchVolumeByMuscle(from: range.from, to: range.to);
});

final setsByMuscleProvider =
    StreamProvider.family<Map<String, int>, VolumeRange>((ref, range) {
  return ref
      .watch(sessionRepositoryProvider)
      .watchSetsByMuscle(from: range.from, to: range.to);
});

final muscleWeeklyTrendProvider =
    StreamProvider.family<Map<String, List<MuscleWeekStat>>, int>(
        (ref, weeks) {
  return ref
      .watch(sessionRepositoryProvider)
      .watchMuscleWeeklyTrend(weeks: weeks);
});

/// Side-effect provider that keeps `UserSettings.userBodyweightKg` in
/// lockstep with the latest entry in the bodyweight log. The Progression
/// tab is the source of truth: any add / edit / delete there updates the
/// settings cache so bodyweight exercises always read a fresh value.
///
/// When the entries list is empty (e.g. first launch, or all entries
/// deleted) we leave the existing settings value untouched — the user may
/// have set their weight manually in Settings without ever logging.
///
/// Eagerly watched once from `MusculApp.build` so the invariant holds for
/// the entire app lifetime, regardless of which screen is on top.
final bodyweightSettingsSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<List<BodyweightEntry>>>(
    bodyweightEntriesProvider,
    (previous, next) async {
      final entries = next.valueOrNull;
      if (entries == null || entries.isEmpty) return;
      final latestKg = entries.last.weightKg;
      final repo = ref.read(settingsRepositoryProvider);
      final settings = await repo.get();
      if (settings.userBodyweightKg == latestKg) return;
      await repo.save(settings.copyWith(userBodyweightKg: latestKg));
      // The settings push happens at the call sites that *trigger* a
      // bodyweight change (Home > poids field, Progression > Poids); we
      // can't push from here without circular import (sync_service.dart
      // depends on providers.dart for databaseProvider).
    },
  );
});
