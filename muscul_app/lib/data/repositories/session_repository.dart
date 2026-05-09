import 'package:drift/drift.dart';

import '../../domain/models/session.dart';
import '../db/database.dart';
import 'mappers.dart';

class SessionDetail {
  final WorkoutSession session;
  final List<SessionExerciseWithSets> exercises;
  const SessionDetail({required this.session, required this.exercises});
}

abstract class SessionRepository {
  Stream<List<WorkoutSession>> watchHistory({int limit = 50});
  Stream<WorkoutSession?> watchInProgress();

  Future<SessionDetail?> getDetail(String sessionId);
  Stream<SessionDetail?> watchDetail(String sessionId);

  Future<void> upsertSession(WorkoutSession s);
  Future<void> softDeleteSession(String id);
  Future<void> upsertSessionExercise(SessionExercise se);
  Future<void> deleteSessionExercise(String id);
  Future<void> upsertSet(SetEntry s);
  Future<void> deleteSet(String id);

  /// Returns the full history for an exercise across all sessions, most-recent first.
  Future<List<SessionExerciseWithSets>> historyForExercise(String exerciseId,
      {int limit = 30});

  /// Returns the most recent ended working-sets for [exerciseId] across all
  /// templates / freestyle sessions. Tries to match [preferSetCount] exactly
  /// first; falls back to the latest occurrence of any set count if no
  /// exact match exists. Empty list = no past data.
  Future<List<SetEntry>> findBestMatchingSets({
    required String exerciseId,
    required int preferSetCount,
  });

  /// Same as [historyForExercise] but reactive — re-emits on writes.
  Stream<List<SessionExerciseWithSets>> watchHistoryForExercise(
      String exerciseId,
      {int limit = 30});

  /// Exercise IDs that have at least one validated set in an ended session,
  /// ordered by most recently trained.
  Stream<List<String>> watchTrainedExerciseIds();

  /// Reactive map: templateId → last finished session for that template.
  Stream<Map<String, WorkoutSession>> watchLastSessionByTemplate();

  /// Reactive map: exerciseId → number of times performed (in ended sessions).
  Stream<Map<String, int>> watchExerciseUsageCounts();

  /// Reactive map: primary muscle group name → total working volume (kg)
  /// across all ended sessions whose `endedAt` is within [from, to).
  Stream<Map<String, double>> watchVolumeByMuscle({
    required DateTime from,
    required DateTime to,
  });

  /// Reactive map: primary muscle group name → number of working sets in
  /// [from, to). Pairs with [watchVolumeByMuscle].
  Stream<Map<String, int>> watchSetsByMuscle({
    required DateTime from,
    required DateTime to,
  });

  /// Reactive map: primary muscle group → list of (week start, sets,
  /// volume) over the last [weeks] weeks. Used for sparkline trends.
  Stream<Map<String, List<MuscleWeekStat>>> watchMuscleWeeklyTrend({
    required int weeks,
  });
}

class MuscleWeekStat {
  /// Week-start (Monday) at 00:00.
  final DateTime weekStart;
  final int sets;
  final double volume;
  const MuscleWeekStat({
    required this.weekStart,
    required this.sets,
    required this.volume,
  });
}

class LocalSessionRepository implements SessionRepository {
  final AppDatabase db;
  LocalSessionRepository(this.db);

  @override
  Stream<List<WorkoutSession>> watchHistory({int limit = 50}) {
    final q = db.select(db.workoutSessions)
      ..where((t) => t.endedAt.isNotNull() & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.endedAt)])
      ..limit(limit);
    return q.watch().map((rows) => rows.map(sessionFromRow).toList());
  }

  @override
  Stream<WorkoutSession?> watchInProgress() {
    final q = db.select(db.workoutSessions)
      ..where((t) => t.endedAt.isNull() & t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(1);
    return q
        .watch()
        .map((rows) => rows.isEmpty ? null : sessionFromRow(rows.first));
  }

  Future<List<SessionExerciseWithSets>> _exercisesWithSets(
      String sessionId) async {
    final exerciseRows = await (db.select(db.sessionExercises)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();
    if (exerciseRows.isEmpty) return [];
    final ids = exerciseRows.map((r) => r.id).toList();
    final setRows = await (db.select(db.setEntries)
          ..where((t) => t.sessionExerciseId.isIn(ids))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sessionExerciseId),
            (t) => OrderingTerm.asc(t.setIndex),
          ]))
        .get();
    final setsByExercise = <String, List<SetEntry>>{};
    for (final r in setRows) {
      setsByExercise.putIfAbsent(r.sessionExerciseId, () => []).add(setFromRow(r));
    }
    return exerciseRows.map((r) {
      return SessionExerciseWithSets(
        sessionExercise: sessionExerciseFromRow(r),
        sets: setsByExercise[r.id] ?? const [],
      );
    }).toList();
  }

  @override
  Future<SessionDetail?> getDetail(String sessionId) async {
    final row = await (db.select(db.workoutSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
    if (row == null) return null;
    return SessionDetail(
      session: sessionFromRow(row),
      exercises: await _exercisesWithSets(sessionId),
    );
  }

  @override
  Stream<SessionDetail?> watchDetail(String sessionId) async* {
    // Drift's typical watch() only fires on the queried table; here the detail
    // depends on three tables (session row + its exercises + their sets), so
    // we listen to all of them via tableUpdates and re-fetch.
    yield await getDetail(sessionId);
    yield* db
        .tableUpdates(TableUpdateQuery.onAllTables([
          db.workoutSessions,
          db.sessionExercises,
          db.setEntries,
        ]))
        .asyncMap((_) => getDetail(sessionId));
  }

  @override
  Future<void> upsertSession(WorkoutSession s) async {
    await db
        .into(db.workoutSessions)
        .insertOnConflictUpdate(sessionToCompanion(s));
  }

  @override
  Future<void> softDeleteSession(String id) async {
    final now = DateTime.now();
    await (db.update(db.workoutSessions)..where((t) => t.id.equals(id)))
        .write(WorkoutSessionsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      syncStatus: const Value('pending'),
    ));
  }

  @override
  Future<void> upsertSessionExercise(SessionExercise se) async {
    await db
        .into(db.sessionExercises)
        .insertOnConflictUpdate(sessionExerciseToCompanion(se));
  }

  @override
  Future<void> deleteSessionExercise(String id) async {
    await db.transaction(() async {
      await (db.delete(db.setEntries)
            ..where((t) => t.sessionExerciseId.equals(id)))
          .go();
      await (db.delete(db.sessionExercises)..where((t) => t.id.equals(id))).go();
    });
  }

  @override
  Future<void> upsertSet(SetEntry s) async {
    await db.into(db.setEntries).insertOnConflictUpdate(setToCompanion(s));
  }

  @override
  Future<void> deleteSet(String id) async {
    await (db.delete(db.setEntries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Stream<List<SessionExerciseWithSets>> watchHistoryForExercise(
      String exerciseId,
      {int limit = 30}) async* {
    yield await historyForExercise(exerciseId, limit: limit);
    yield* db
        .tableUpdates(TableUpdateQuery.onAllTables([
          db.workoutSessions,
          db.sessionExercises,
          db.setEntries,
        ]))
        .asyncMap((_) => historyForExercise(exerciseId, limit: limit));
  }

  @override
  Stream<Map<String, WorkoutSession>> watchLastSessionByTemplate() {
    final q = db.select(db.workoutSessions)
      ..where((t) =>
          t.endedAt.isNotNull() &
          t.deletedAt.isNull() &
          t.templateId.isNotNull())
      ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]);
    return q.watch().map((rows) {
      final map = <String, WorkoutSession>{};
      for (final r in rows) {
        final tid = r.templateId;
        if (tid == null) continue;
        if (!map.containsKey(tid)) {
          map[tid] = sessionFromRow(r);
        }
      }
      return map;
    });
  }

  @override
  Stream<Map<String, int>> watchExerciseUsageCounts() {
    return db.customSelect(
      '''
      SELECT se.exercise_id AS exercise_id, COUNT(*) AS cnt
      FROM session_exercises se
      JOIN workout_sessions s ON s.id = se.session_id
      JOIN exercises e ON e.id = se.exercise_id
      WHERE s.ended_at IS NOT NULL
        AND s.deleted_at IS NULL
        AND e.deleted_at IS NULL
      GROUP BY se.exercise_id
      ''',
      readsFrom: {db.sessionExercises, db.workoutSessions, db.exercises},
    ).watch().map((rows) {
      final map = <String, int>{};
      for (final r in rows) {
        map[r.read<String>('exercise_id')] = r.read<int>('cnt');
      }
      return map;
    });
  }

  @override
  Stream<Map<String, double>> watchVolumeByMuscle({
    required DateTime from,
    required DateTime to,
  }) {
    return db.customSelect(
      '''
      SELECT e.primary_muscle AS muscle,
             SUM(set_entries.reps * set_entries.weight_kg) AS volume
      FROM set_entries
      JOIN session_exercises se ON se.id = set_entries.session_exercise_id
      JOIN workout_sessions s ON s.id = se.session_id
      JOIN exercises e ON e.id = se.exercise_id
      WHERE s.ended_at IS NOT NULL
        AND s.deleted_at IS NULL
        AND set_entries.is_warmup = 0
        AND s.ended_at >= ?
        AND s.ended_at < ?
      GROUP BY e.primary_muscle
      ''',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
      ],
      readsFrom: {
        db.setEntries,
        db.sessionExercises,
        db.workoutSessions,
        db.exercises,
      },
    ).watch().map((rows) {
      final map = <String, double>{};
      for (final r in rows) {
        final muscle = r.read<String>('muscle');
        final v = r.read<double>('volume');
        map[muscle] = v;
      }
      return map;
    });
  }

  @override
  Stream<Map<String, int>> watchSetsByMuscle({
    required DateTime from,
    required DateTime to,
  }) {
    return db.customSelect(
      '''
      SELECT e.primary_muscle AS muscle, COUNT(*) AS cnt
      FROM set_entries
      JOIN session_exercises se ON se.id = set_entries.session_exercise_id
      JOIN workout_sessions s ON s.id = se.session_id
      JOIN exercises e ON e.id = se.exercise_id
      WHERE s.ended_at IS NOT NULL
        AND s.deleted_at IS NULL
        AND set_entries.is_warmup = 0
        AND s.ended_at >= ?
        AND s.ended_at < ?
      GROUP BY e.primary_muscle
      ''',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
      ],
      readsFrom: {
        db.setEntries,
        db.sessionExercises,
        db.workoutSessions,
        db.exercises,
      },
    ).watch().map((rows) {
      final map = <String, int>{};
      for (final r in rows) {
        map[r.read<String>('muscle')] = r.read<int>('cnt');
      }
      return map;
    });
  }

  @override
  Stream<Map<String, List<MuscleWeekStat>>> watchMuscleWeeklyTrend({
    required int weeks,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Anchor on the most-recent Monday so each "week_start" lands on a
    // weekday.monday (1) — ISO-style.
    final daysSinceMonday = today.weekday - 1;
    final thisMonday = today.subtract(Duration(days: daysSinceMonday));
    final from = thisMonday.subtract(Duration(days: 7 * (weeks - 1)));
    final to = thisMonday.add(const Duration(days: 7));
    // Pull every set in the window with its primary muscle and date,
    // bucket by ISO week in Dart.
    return db.customSelect(
      '''
      SELECT e.primary_muscle AS muscle,
             set_entries.completed_at AS completed_at,
             set_entries.reps * set_entries.weight_kg AS volume
      FROM set_entries
      JOIN session_exercises se ON se.id = set_entries.session_exercise_id
      JOIN workout_sessions s ON s.id = se.session_id
      JOIN exercises e ON e.id = se.exercise_id
      WHERE s.ended_at IS NOT NULL
        AND s.deleted_at IS NULL
        AND set_entries.is_warmup = 0
        AND set_entries.completed_at >= ?
        AND set_entries.completed_at < ?
      ''',
      variables: [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
      ],
      readsFrom: {
        db.setEntries,
        db.sessionExercises,
        db.workoutSessions,
        db.exercises,
      },
    ).watch().map((rows) {
      final byMuscle = <String, Map<DateTime, MuscleWeekStat>>{};
      for (final r in rows) {
        final muscle = r.read<String>('muscle');
        final completedAt = r.read<DateTime>('completed_at').toLocal();
        final volume = r.read<double>('volume');
        final dayOfWeek = completedAt.weekday - 1;
        final weekStart = DateTime(completedAt.year, completedAt.month,
            completedAt.day - dayOfWeek);
        final perMuscle =
            byMuscle.putIfAbsent(muscle, () => {});
        final existing = perMuscle[weekStart];
        if (existing == null) {
          perMuscle[weekStart] = MuscleWeekStat(
              weekStart: weekStart, sets: 1, volume: volume);
        } else {
          perMuscle[weekStart] = MuscleWeekStat(
            weekStart: weekStart,
            sets: existing.sets + 1,
            volume: existing.volume + volume,
          );
        }
      }
      // Fill gaps with zero so sparklines have a continuous x-axis.
      final result = <String, List<MuscleWeekStat>>{};
      for (final entry in byMuscle.entries) {
        final list = <MuscleWeekStat>[];
        for (var w = 0; w < weeks; w++) {
          final weekStart = from.add(Duration(days: 7 * w));
          list.add(entry.value[weekStart] ??
              MuscleWeekStat(
                  weekStart: weekStart, sets: 0, volume: 0));
        }
        result[entry.key] = list;
      }
      return result;
    });
  }

  @override
  Stream<List<String>> watchTrainedExerciseIds() {
    return db.customSelect(
      '''
      SELECT se.exercise_id AS exercise_id, MAX(s.ended_at) AS latest
      FROM session_exercises se
      JOIN workout_sessions s ON s.id = se.session_id
      JOIN set_entries entry ON entry.session_exercise_id = se.id
      JOIN exercises e ON e.id = se.exercise_id
      WHERE s.ended_at IS NOT NULL
        AND s.deleted_at IS NULL
        AND e.deleted_at IS NULL
        AND entry.is_warmup = 0
      GROUP BY se.exercise_id
      ORDER BY latest DESC
      ''',
      readsFrom: {
        db.sessionExercises,
        db.workoutSessions,
        db.setEntries,
        db.exercises,
      },
    ).watch().map((rows) =>
        [for (final r in rows) r.read<String>('exercise_id')]);
  }

  @override
  Future<List<SetEntry>> findBestMatchingSets({
    required String exerciseId,
    required int preferSetCount,
  }) async {
    // Pull the 30 most recent ended session_exercises of this exo, then
    // filter their working sets in memory.
    final query = db.select(db.sessionExercises).join([
      innerJoin(
        db.workoutSessions,
        db.workoutSessions.id.equalsExp(db.sessionExercises.sessionId),
      ),
    ])
      ..where(db.sessionExercises.exerciseId.equals(exerciseId))
      ..where(db.workoutSessions.endedAt.isNotNull())
      ..where(db.workoutSessions.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(db.workoutSessions.endedAt)])
      ..limit(30);
    final rows = await query.get();
    if (rows.isEmpty) return const [];

    Future<List<SetEntry>> workingSets(String seId) async {
      final setRows = await (db.select(db.setEntries)
            ..where((t) =>
                t.sessionExerciseId.equals(seId) &
                t.isWarmup.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
          .get();
      return setRows.map(setFromRow).toList();
    }

    // Pass 1: exact set count.
    for (final row in rows) {
      final se = row.readTable(db.sessionExercises);
      final sets = await workingSets(se.id);
      if (sets.length == preferSetCount) return sets;
    }
    // Pass 2: most recent occurrence regardless of count.
    final firstSe = rows.first.readTable(db.sessionExercises);
    return workingSets(firstSe.id);
  }

  @override
  Future<List<SessionExerciseWithSets>> historyForExercise(String exerciseId,
      {int limit = 30}) async {
    final query = db.select(db.sessionExercises).join([
      innerJoin(
        db.workoutSessions,
        db.workoutSessions.id.equalsExp(db.sessionExercises.sessionId),
      ),
    ])
      ..where(db.sessionExercises.exerciseId.equals(exerciseId))
      ..where(db.workoutSessions.endedAt.isNotNull())
      ..where(db.workoutSessions.deletedAt.isNull())
      ..orderBy([OrderingTerm.desc(db.workoutSessions.endedAt)])
      ..limit(limit);
    final rows = await query.get();
    final result = <SessionExerciseWithSets>[];
    for (final row in rows) {
      final se = row.readTable(db.sessionExercises);
      final setRows = await (db.select(db.setEntries)
            ..where((t) => t.sessionExerciseId.equals(se.id))
            ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
          .get();
      result.add(SessionExerciseWithSets(
        sessionExercise: sessionExerciseFromRow(se),
        sets: setRows.map(setFromRow).toList(),
      ));
    }
    return result;
  }
}
