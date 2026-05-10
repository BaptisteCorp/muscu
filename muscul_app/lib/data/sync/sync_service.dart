import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_config.dart';
import '../../core/providers.dart';
import '../auth/auth_service.dart';
import '../db/database.dart';

/// Bidirectional, per-user sync between the local Drift DB and a Supabase
/// project. Last-write-wins on `updated_at`; soft-deletes propagate via
/// `deleted_at`. Default seeded exercises (`is_custom = false`) are not
/// synced because they're identical for every user.
class SyncService {
  SyncService(this._db);
  final AppDatabase _db;

  /// Serializes every full sync. Many UI paths call `unawaited(sync())`
  /// (history delete, session start/finish, periodic timer) — without this
  /// gate two syncs can interleave their push/pull on the same rows and
  /// the second pull can wipe edits the first push just landed.
  Future<void>? _syncInFlight;

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _userId => _sb.auth.currentUser?.id;

  bool get isAvailable =>
      SupabaseConfig.isConfigured && _userId != null;

  /// Run a full bidirectional sync. Pull first (so local has every remote
  /// row), then push everything that's newer locally.
  Future<SyncReport> sync() async {
    if (!isAvailable) {
      return SyncReport(
        ok: false,
        error: 'Pas connecté ou Supabase non configuré',
      );
    }
    // If another sync is already running, wait for it instead of starting
    // a parallel one. Caller still gets a report — by reusing the one
    // returned by the in-flight sync.
    if (_syncInFlight != null) {
      await _syncInFlight;
      // The piggy-back report is "ok-ish" — we didn't run our own pass,
      // but the in-flight one did. Returning a synthetic ok report keeps
      // callers' `report.ok` checks honest enough.
      return SyncReport.empty().copyWith(ok: true);
    }
    final completer = Completer<void>();
    _syncInFlight = completer.future;
    final report = SyncReport.empty();
    try {
      // Push first so freshly-edited local rows reach the cloud BEFORE the
      // pull sees an older copy and overwrites them.
      await _pushAll(report);
      await _pullAll(report);
      return report.copyWith(ok: true);
    } catch (e, st) {
      return report.copyWith(
        ok: false,
        error: '$e',
        stackTrace: st.toString(),
      );
    } finally {
      _syncInFlight = null;
      completer.complete();
    }
  }

  // ----------------------- PULL ---------------------------

  Future<void> _pullAll(SyncReport report) async {
    final uid = _userId!;
    // Order matters because some inserts reference others (template_id, etc.).
    // We rely on the local schema having no FKs declared so order doesn't
    // strictly matter, but we keep it logical.
    await _pullExercises(uid, report);
    await _pullTemplates(uid, report);
    await _pullTemplateExercises(uid, report);
    await _pullTemplateExerciseSets(uid, report);
    await _pullSessions(uid, report);
    await _pullSessionExercises(uid, report);
    await _pullSetEntries(uid, report);
    await _pullSettings(uid, report);
    await _pullBodyweight(uid, report);
  }

  Future<void> _pullExercises(String uid, SyncReport report) async {
    final rows = await _sb
        .from('exercises')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      final id = m['id'] as String;
      final cloudUpdatedAt = DateTime.parse(m['updated_at'] as String).toLocal();
      final local = await (_db.select(_db.exercises)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (local != null &&
          !local.updatedAt.isBefore(cloudUpdatedAt)) {
        continue;
      }
      await _db.into(_db.exercises).insertOnConflictUpdate(
            ExercisesCompanion.insert(
              id: id,
              name: m['name'] as String,
              category: m['category'] as String,
              primaryMuscle: m['primary_muscle'] as String,
              secondaryMuscles: Value(
                  (m['secondary_muscles'] as String?) ?? '[]'),
              equipment: m['equipment'] as String,
              isCustom: Value((m['is_custom'] as bool?) ?? true),
              defaultIncrementKg: Value((m['default_increment_kg'] as num?)
                  ?.toDouble()),
              defaultRestSeconds:
                  Value(m['default_rest_seconds'] as int?),
              progressiveOverloadEnabled: Value(
                  (m['progressive_overload_enabled'] as bool?) ?? true),
              progressionPriority: Value(
                  (m['progression_priority'] as String?) ?? 'repsFirst'),
              minimumRpeThreshold:
                  Value(m['minimum_rpe_threshold'] as int?),
              targetRepRangeMin: Value(m['target_rep_range_min'] as int? ?? 8),
              targetRepRangeMax:
                  Value(m['target_rep_range_max'] as int? ?? 12),
              startingWeightKg: Value(
                  (m['starting_weight_kg'] as num?)?.toDouble() ?? 20.0),
              useBodyweight:
                  Value((m['use_bodyweight'] as bool?) ?? false),
              notes: Value(m['notes'] as String?),
              machineBrandModel: Value(m['machine_brand_model'] as String?),
              machineSettings: Value(m['machine_settings'] as String?),
              photoPath: Value(m['photo_path'] as String?),
              updatedAt: DateTime.parse(m['updated_at'] as String).toLocal(),
              syncStatus: const Value('synced'),
              remoteId: Value(m['remote_id'] as String?),
              deletedAt: Value(_parseDt(m['deleted_at'])),
            ),
          );
      report.pulled('exercises');
    }
  }

  Future<void> _pullTemplates(String uid, SyncReport report) async {
    final rows = await _sb
        .from('workout_templates')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      final id = m['id'] as String;
      final cloudUpdatedAt = DateTime.parse(m['updated_at'] as String).toLocal();
      final local = await (_db.select(_db.workoutTemplates)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (local != null &&
          !local.updatedAt.isBefore(cloudUpdatedAt)) {
        continue;
      }
      await _db.into(_db.workoutTemplates).insertOnConflictUpdate(
            WorkoutTemplatesCompanion.insert(
              id: id,
              name: m['name'] as String,
              notes: Value(m['notes'] as String?),
              createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
              updatedAt: cloudUpdatedAt,
              syncStatus: const Value('synced'),
              remoteId: Value(m['remote_id'] as String?),
              deletedAt: Value(_parseDt(m['deleted_at'])),
            ),
          );
      report.pulled('workout_templates');
    }
  }

  Future<void> _pullTemplateExercises(
      String uid, SyncReport report) async {
    final rows = await _sb
        .from('workout_template_exercises')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      await _db
          .into(_db.workoutTemplateExercises)
          .insertOnConflictUpdate(
            WorkoutTemplateExercisesCompanion.insert(
              id: m['id'] as String,
              templateId: m['template_id'] as String,
              exerciseId: m['exercise_id'] as String,
              orderIndex: m['order_index'] as int,
              targetSets: Value(m['target_sets'] as int? ?? 3),
              restSeconds: Value(m['rest_seconds'] as int?),
            ),
          );
      report.pulled('workout_template_exercises');
    }
  }

  Future<void> _pullTemplateExerciseSets(
      String uid, SyncReport report) async {
    final rows = await _sb
        .from('template_exercise_sets')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      await _db.into(_db.templateExerciseSets).insertOnConflictUpdate(
            TemplateExerciseSetsCompanion.insert(
              id: m['id'] as String,
              templateExerciseId:
                  m['template_exercise_id'] as String,
              setIndex: m['set_index'] as int,
              plannedReps: m['planned_reps'] as int,
              plannedWeightKg:
                  Value((m['planned_weight_kg'] as num?)?.toDouble()),
            ),
          );
      report.pulled('template_exercise_sets');
    }
  }

  Future<void> _pullSessions(String uid, SyncReport report) async {
    final rows = await _sb
        .from('workout_sessions')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      final id = m['id'] as String;
      final cloudUpdatedAt = DateTime.parse(m['updated_at'] as String).toLocal();
      // Skip if local row exists with a newer or equal updated_at: don't
      // overwrite a fresh local edit with stale cloud data.
      final local = await (_db.select(_db.workoutSessions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (local != null &&
          !local.updatedAt.isBefore(cloudUpdatedAt)) {
        continue;
      }
      await _db.into(_db.workoutSessions).insertOnConflictUpdate(
            WorkoutSessionsCompanion.insert(
              id: id,
              templateId: Value(m['template_id'] as String?),
              startedAt: DateTime.parse(m['started_at'] as String).toLocal(),
              endedAt: Value(_parseDt(m['ended_at'])),
              notes: Value(m['notes'] as String?),
              updatedAt: cloudUpdatedAt,
              syncStatus: const Value('synced'),
              remoteId: Value(m['remote_id'] as String?),
              deletedAt: Value(_parseDt(m['deleted_at'])),
            ),
          );
      report.pulled('workout_sessions');
    }
  }

  Future<void> _pullSessionExercises(
      String uid, SyncReport report) async {
    final rows = await _sb
        .from('session_exercises')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      await _db.into(_db.sessionExercises).insertOnConflictUpdate(
            SessionExercisesCompanion.insert(
              id: m['id'] as String,
              sessionId: m['session_id'] as String,
              exerciseId: m['exercise_id'] as String,
              orderIndex: m['order_index'] as int,
              restSeconds: Value(m['rest_seconds'] as int?),
              supersetGroupId:
                  Value(m['superset_group_id'] as String?),
              note: Value(m['note'] as String?),
              replacedFromSessionExerciseId: Value(
                  m['replaced_from_session_exercise_id'] as String?),
            ),
          );
      report.pulled('session_exercises');
    }
  }

  Future<void> _pullSetEntries(String uid, SyncReport report) async {
    final rows = await _sb
        .from('set_entries')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      await _db.into(_db.setEntries).insertOnConflictUpdate(
            SetEntriesCompanion.insert(
              id: m['id'] as String,
              sessionExerciseId: m['session_exercise_id'] as String,
              setIndex: m['set_index'] as int,
              reps: m['reps'] as int,
              weightKg: (m['weight_kg'] as num).toDouble(),
              rpe: Value(m['rpe'] as int?),
              rir: Value(m['rir'] as int?),
              restSeconds: Value(m['rest_seconds'] as int? ?? 0),
              isWarmup: Value((m['is_warmup'] as bool?) ?? false),
              isFailure: Value((m['is_failure'] as bool?) ?? false),
              completedAt:
                  DateTime.parse(m['completed_at'] as String).toLocal(),
            ),
          );
      report.pulled('set_entries');
    }
  }

  Future<void> _pullSettings(String uid, SyncReport report) async {
    final rows = await _sb
        .from('user_settings')
        .select()
        .eq('user_id', uid)
        .limit(1);
    if ((rows as List).isEmpty) return;
    final m = rows.first as Map<String, dynamic>;
    await (_db.update(_db.userSettingsTable)
          ..where((t) => t.id.equals(1)))
        .write(
      UserSettingsTableCompanion(
        defaultIncrementKg:
            Value((m['default_increment_kg'] as num?)?.toDouble() ?? 2.5),
        weightUnit: Value((m['weight_unit'] as String?) ?? 'kg'),
        defaultRestSeconds:
            Value((m['default_rest_seconds'] as int?) ?? 120),
        useRirInsteadOfRpe:
            Value((m['use_rir_instead_of_rpe'] as bool?) ?? false),
        userBodyweightKg:
            Value((m['user_bodyweight_kg'] as num?)?.toDouble()),
        themeMode: Value((m['theme_mode'] as String?) ?? 'system'),
      ),
    );
    report.pulled('user_settings');
  }

  Future<void> _pullBodyweight(String uid, SyncReport report) async {
    final rows = await _sb
        .from('bodyweight_entries')
        .select()
        .eq('user_id', uid);
    for (final r in rows as List) {
      final m = r as Map<String, dynamic>;
      final date = m['date'] as String;
      final cloudUpdatedAt =
          DateTime.parse(m['updated_at'] as String).toLocal();
      final local = await (_db.select(_db.bodyweightEntries)
            ..where((t) => t.date.equals(date)))
          .getSingleOrNull();
      if (local != null &&
          !local.updatedAt.isBefore(cloudUpdatedAt)) {
        continue;
      }
      await _db.into(_db.bodyweightEntries).insertOnConflictUpdate(
            BodyweightEntriesCompanion.insert(
              date: date,
              weightKg: (m['weight_kg'] as num).toDouble(),
              note: Value(m['note'] as String?),
              updatedAt: cloudUpdatedAt,
            ),
          );
      report.pulled('bodyweight_entries');
    }
  }

  // ----------------------- PUSH ---------------------------

  Future<void> _pushAll(SyncReport report) async {
    final uid = _userId!;
    await _pushExercises(uid, report);
    await _pushTemplates(uid, report);
    await _pushTemplateExercises(uid, report);
    await _pushTemplateExerciseSets(uid, report);
    await _pushSessions(uid, report);
    await _pushSessionExercises(uid, report);
    await _pushSetEntries(uid, report);
    await _pushSettings(uid, report);
    await _pushBodyweight(uid, report);
  }

  Future<void> _pushExercises(String uid, SyncReport report) async {
    // Skip seeded (is_custom = false) — same for everyone.
    final rows = await (_db.select(_db.exercises)
          ..where((t) => t.isCustom.equals(true)))
        .get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'name': r.name,
              'category': r.category,
              'primary_muscle': r.primaryMuscle,
              'secondary_muscles': r.secondaryMuscles,
              'equipment': r.equipment,
              'is_custom': r.isCustom,
              'default_increment_kg': r.defaultIncrementKg,
              'default_rest_seconds': r.defaultRestSeconds,
              'progressive_overload_enabled': r.progressiveOverloadEnabled,
              'progression_priority': r.progressionPriority,
              'minimum_rpe_threshold': r.minimumRpeThreshold,
              'target_rep_range_min': r.targetRepRangeMin,
              'target_rep_range_max': r.targetRepRangeMax,
              'starting_weight_kg': r.startingWeightKg,
              'use_bodyweight': r.useBodyweight,
              'notes': r.notes,
              'machine_brand_model': r.machineBrandModel,
              'machine_settings': r.machineSettings,
              'photo_path': r.photoPath,
              'updated_at': _isoUtc(r.updatedAt),
              'remote_id': r.remoteId,
              'deleted_at': _isoUtcN(r.deletedAt),
            })
        .toList();
    await _sb.from('exercises').upsert(payload, onConflict: 'user_id,id');
    report.pushed('exercises', rows.length);
  }

  Future<void> _pushTemplates(String uid, SyncReport report) async {
    final rows = await _db.select(_db.workoutTemplates).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'name': r.name,
              'notes': r.notes,
              'created_at': _isoUtc(r.createdAt),
              'updated_at': _isoUtc(r.updatedAt),
              'remote_id': r.remoteId,
              'deleted_at': _isoUtcN(r.deletedAt),
            })
        .toList();
    await _sb
        .from('workout_templates')
        .upsert(payload, onConflict: 'user_id,id');
    report.pushed('workout_templates', rows.length);
  }

  Future<void> _pushTemplateExercises(
      String uid, SyncReport report) async {
    final rows = await _db.select(_db.workoutTemplateExercises).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'template_id': r.templateId,
              'exercise_id': r.exerciseId,
              'order_index': r.orderIndex,
              'target_sets': r.targetSets,
              'rest_seconds': r.restSeconds,
            })
        .toList();
    await _sb
        .from('workout_template_exercises')
        .upsert(payload, onConflict: 'user_id,id');
    report.pushed('workout_template_exercises', rows.length);
  }

  Future<void> _pushTemplateExerciseSets(
      String uid, SyncReport report) async {
    final rows = await _db.select(_db.templateExerciseSets).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'template_exercise_id': r.templateExerciseId,
              'set_index': r.setIndex,
              'planned_reps': r.plannedReps,
              'planned_weight_kg': r.plannedWeightKg,
            })
        .toList();
    await _sb
        .from('template_exercise_sets')
        .upsert(payload, onConflict: 'user_id,id');
    report.pushed('template_exercise_sets', rows.length);
  }

  /// Push a single workout_session row to the cloud, blocking until done.
  ///
  /// Called from critical UX paths (e.g. soft-delete) where we can't risk
  /// the change being lost if the next batched sync fails on another
  /// table or the app is killed before it runs.
  Future<void> pushSession(String sessionId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    final row = await (_db.select(_db.workoutSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
    if (row == null) return;
    await _sb.from('workout_sessions').upsert({
      'id': row.id,
      'user_id': uid,
      'template_id': row.templateId,
      'started_at': _isoUtc(row.startedAt),
      'ended_at': _isoUtcN(row.endedAt),
      'notes': row.notes,
      'updated_at': _isoUtc(row.updatedAt),
      'remote_id': row.remoteId,
      'deleted_at': _isoUtcN(row.deletedAt),
    }, onConflict: 'user_id,id');
  }

  /// Push a session row + every session_exercise and set_entry that hangs
  /// off it. Used at session finish so the freshly-completed workout is
  /// safe on the cloud before the user can do anything destructive (close
  /// the app, reinstall, lose the device).
  Future<void> pushSessionWithChildren(String sessionId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    await pushSession(sessionId);
    final exRows = await (_db.select(_db.sessionExercises)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();
    if (exRows.isEmpty) return;
    final now = _isoUtc(DateTime.now());
    await _sb.from('session_exercises').upsert(
      [
        for (final r in exRows)
          {
            'id': r.id,
            'user_id': uid,
            'session_id': r.sessionId,
            'exercise_id': r.exerciseId,
            'order_index': r.orderIndex,
            'rest_seconds': r.restSeconds,
            'superset_group_id': r.supersetGroupId,
            'note': r.note,
            'replaced_from_session_exercise_id':
                r.replacedFromSessionExerciseId,
            'updated_at': now,
          }
      ],
      onConflict: 'user_id,id',
    );
    final exIds = exRows.map((r) => r.id).toList();
    final setRows = await (_db.select(_db.setEntries)
          ..where((t) => t.sessionExerciseId.isIn(exIds)))
        .get();
    if (setRows.isEmpty) return;
    await _sb.from('set_entries').upsert(
      [
        for (final r in setRows)
          {
            'id': r.id,
            'user_id': uid,
            'session_exercise_id': r.sessionExerciseId,
            'set_index': r.setIndex,
            'reps': r.reps,
            'weight_kg': r.weightKg,
            'rpe': r.rpe,
            'rir': r.rir,
            'rest_seconds': r.restSeconds,
            'is_warmup': r.isWarmup,
            'is_failure': r.isFailure,
            'completed_at': _isoUtc(r.completedAt),
            'updated_at': _isoUtc(r.completedAt),
          }
      ],
      onConflict: 'user_id,id',
    );
  }

  /// Push a single template row + every WorkoutTemplateExercise and
  /// TemplateExerciseSet that hangs off it. Called from edit screens so
  /// new/edited/deleted templates land on the cloud immediately and can't
  /// be lost between local save and the next batched sync.
  Future<void> pushTemplate(String templateId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    final tRow = await (_db.select(_db.workoutTemplates)
          ..where((t) => t.id.equals(templateId)))
        .getSingleOrNull();
    if (tRow == null) return;
    await _sb.from('workout_templates').upsert({
      'id': tRow.id,
      'user_id': uid,
      'name': tRow.name,
      'notes': tRow.notes,
      'created_at': _isoUtc(tRow.createdAt),
      'updated_at': _isoUtc(tRow.updatedAt),
      'remote_id': tRow.remoteId,
      'deleted_at': _isoUtcN(tRow.deletedAt),
    }, onConflict: 'user_id,id');
    final teRows = await (_db.select(_db.workoutTemplateExercises)
          ..where((t) => t.templateId.equals(templateId)))
        .get();
    if (teRows.isNotEmpty) {
      await _sb.from('workout_template_exercises').upsert(
        [
          for (final r in teRows)
            {
              'id': r.id,
              'user_id': uid,
              'template_id': r.templateId,
              'exercise_id': r.exerciseId,
              'order_index': r.orderIndex,
              'target_sets': r.targetSets,
              'rest_seconds': r.restSeconds,
            }
        ],
        onConflict: 'user_id,id',
      );
      final teIds = teRows.map((r) => r.id).toList();
      final setRows = await (_db.select(_db.templateExerciseSets)
            ..where((t) => t.templateExerciseId.isIn(teIds)))
          .get();
      if (setRows.isNotEmpty) {
        await _sb.from('template_exercise_sets').upsert(
          [
            for (final r in setRows)
              {
                'id': r.id,
                'user_id': uid,
                'template_exercise_id': r.templateExerciseId,
                'set_index': r.setIndex,
                'planned_reps': r.plannedReps,
                'planned_weight_kg': r.plannedWeightKg,
              }
          ],
          onConflict: 'user_id,id',
        );
      }
    }
  }

  /// Push a single exercise row to the cloud immediately. Same rationale
  /// as pushTemplate: don't wait for the periodic batched sync — a fresh
  /// custom exercise can be lost if the user reinstalls or the app dies
  /// before the next sync window. Default seeded exercises (is_custom=false)
  /// are skipped because they're identical for every user and never go
  /// to the cloud.
  Future<void> pushExercise(String exerciseId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    final row = await (_db.select(_db.exercises)
          ..where((t) => t.id.equals(exerciseId)))
        .getSingleOrNull();
    if (row == null || !row.isCustom) return;
    await _sb.from('exercises').upsert({
      'id': row.id,
      'user_id': uid,
      'name': row.name,
      'category': row.category,
      'primary_muscle': row.primaryMuscle,
      'secondary_muscles': row.secondaryMuscles,
      'equipment': row.equipment,
      'is_custom': row.isCustom,
      'default_increment_kg': row.defaultIncrementKg,
      'default_rest_seconds': row.defaultRestSeconds,
      'progressive_overload_enabled': row.progressiveOverloadEnabled,
      'progression_priority': row.progressionPriority,
      'minimum_rpe_threshold': row.minimumRpeThreshold,
      'target_rep_range_min': row.targetRepRangeMin,
      'target_rep_range_max': row.targetRepRangeMax,
      'starting_weight_kg': row.startingWeightKg,
      'use_bodyweight': row.useBodyweight,
      'notes': row.notes,
      'machine_brand_model': row.machineBrandModel,
      'machine_settings': row.machineSettings,
      'photo_path': row.photoPath,
      'updated_at': _isoUtc(row.updatedAt),
      'remote_id': row.remoteId,
      'deleted_at': _isoUtcN(row.deletedAt),
    }, onConflict: 'user_id,id');
  }

  /// Push a single session_exercise row. Used when the user adds or
  /// reorders an exercise mid-session, swaps one out, or edits its rest
  /// seconds — anything that mutates a single row in `session_exercises`.
  Future<void> pushSessionExercise(String sessionExerciseId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    final row = await (_db.select(_db.sessionExercises)
          ..where((t) => t.id.equals(sessionExerciseId)))
        .getSingleOrNull();
    if (row == null) return;
    await _sb.from('session_exercises').upsert({
      'id': row.id,
      'user_id': uid,
      'session_id': row.sessionId,
      'exercise_id': row.exerciseId,
      'order_index': row.orderIndex,
      'rest_seconds': row.restSeconds,
      'superset_group_id': row.supersetGroupId,
      'note': row.note,
      'replaced_from_session_exercise_id':
          row.replacedFromSessionExerciseId,
      'updated_at': _isoUtc(DateTime.now()),
    }, onConflict: 'user_id,id');
  }

  /// Push a single set_entry row. Used after every validate / edit so the
  /// freshly-logged set survives an immediate app death.
  Future<void> pushSet(String setId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    final row = await (_db.select(_db.setEntries)
          ..where((t) => t.id.equals(setId)))
        .getSingleOrNull();
    if (row == null) return;
    await _sb.from('set_entries').upsert({
      'id': row.id,
      'user_id': uid,
      'session_exercise_id': row.sessionExerciseId,
      'set_index': row.setIndex,
      'reps': row.reps,
      'weight_kg': row.weightKg,
      'rpe': row.rpe,
      'rir': row.rir,
      'rest_seconds': row.restSeconds,
      'is_warmup': row.isWarmup,
      'is_failure': row.isFailure,
      'completed_at': _isoUtc(row.completedAt),
      'updated_at': _isoUtc(DateTime.now()),
    }, onConflict: 'user_id,id');
  }

  /// Hard-delete a set on the cloud. Local DB hard-deletes too (no
  /// tombstone column on `set_entries` either side).
  Future<void> deleteSetOnCloud(String setId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    await _sb
        .from('set_entries')
        .delete()
        .eq('user_id', uid)
        .eq('id', setId);
  }

  /// Hard-delete a session_exercise + every set_entry that hangs off it
  /// on the cloud. Mirrors the local cascade in
  /// `SessionRepository.deleteSessionExercise`.
  Future<void> deleteSessionExerciseOnCloud(String sessionExerciseId) async {
    if (!isAvailable) return;
    final uid = _userId!;
    // Sets first to mirror the local order — and so an interrupted call
    // doesn't leave orphan sets on the cloud after the parent vanishes.
    await _sb
        .from('set_entries')
        .delete()
        .eq('user_id', uid)
        .eq('session_exercise_id', sessionExerciseId);
    await _sb
        .from('session_exercises')
        .delete()
        .eq('user_id', uid)
        .eq('id', sessionExerciseId);
  }

  /// Push the current settings singleton.
  Future<void> pushSettings() async {
    if (!isAvailable) return;
    final uid = _userId!;
    final row = await (_db.select(_db.userSettingsTable)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    if (row == null) return;
    await _sb.from('user_settings').upsert({
      'user_id': uid,
      'default_increment_kg': row.defaultIncrementKg,
      'weight_unit': row.weightUnit,
      'default_rest_seconds': row.defaultRestSeconds,
      'use_rir_instead_of_rpe': row.useRirInsteadOfRpe,
      'user_bodyweight_kg': row.userBodyweightKg,
      'theme_mode': row.themeMode,
      'updated_at': _isoUtc(DateTime.now()),
    }, onConflict: 'user_id');
  }

  /// Push (or hard-delete, when [delete] is true) a single bodyweight
  /// entry by date.
  Future<void> pushBodyweight(String date, {bool delete = false}) async {
    if (!isAvailable) return;
    final uid = _userId!;
    if (delete) {
      await _sb
          .from('bodyweight_entries')
          .delete()
          .eq('user_id', uid)
          .eq('date', date);
      return;
    }
    final row = await (_db.select(_db.bodyweightEntries)
          ..where((t) => t.date.equals(date)))
        .getSingleOrNull();
    if (row == null) return;
    await _sb.from('bodyweight_entries').upsert({
      'user_id': uid,
      'date': row.date,
      'weight_kg': row.weightKg,
      'note': row.note,
      'updated_at': _isoUtc(row.updatedAt),
    }, onConflict: 'user_id,date');
  }

  Future<void> _pushSessions(String uid, SyncReport report) async {
    final rows = await _db.select(_db.workoutSessions).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'template_id': r.templateId,
              'started_at': _isoUtc(r.startedAt),
              'ended_at': _isoUtcN(r.endedAt),
              'notes': r.notes,
              'updated_at': _isoUtc(r.updatedAt),
              'remote_id': r.remoteId,
              'deleted_at': _isoUtcN(r.deletedAt),
            })
        .toList();
    await _sb
        .from('workout_sessions')
        .upsert(payload, onConflict: 'user_id,id');
    report.pushed('workout_sessions', rows.length);
  }

  Future<void> _pushSessionExercises(
      String uid, SyncReport report) async {
    final rows = await _db.select(_db.sessionExercises).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'session_id': r.sessionId,
              'exercise_id': r.exerciseId,
              'order_index': r.orderIndex,
              'rest_seconds': r.restSeconds,
              'superset_group_id': r.supersetGroupId,
              'note': r.note,
              'replaced_from_session_exercise_id':
                  r.replacedFromSessionExerciseId,
              'updated_at': _isoUtc(DateTime.now()),
            })
        .toList();
    await _sb
        .from('session_exercises')
        .upsert(payload, onConflict: 'user_id,id');
    report.pushed('session_exercises', rows.length);
  }

  Future<void> _pushSetEntries(String uid, SyncReport report) async {
    final rows = await _db.select(_db.setEntries).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'id': r.id,
              'user_id': uid,
              'session_exercise_id': r.sessionExerciseId,
              'set_index': r.setIndex,
              'reps': r.reps,
              'weight_kg': r.weightKg,
              'rpe': r.rpe,
              'rir': r.rir,
              'rest_seconds': r.restSeconds,
              'is_warmup': r.isWarmup,
              'is_failure': r.isFailure,
              'completed_at': _isoUtc(r.completedAt),
              'updated_at': _isoUtc(r.completedAt),
            })
        .toList();
    await _sb
        .from('set_entries')
        .upsert(payload, onConflict: 'user_id,id');
    report.pushed('set_entries', rows.length);
  }

  Future<void> _pushSettings(String uid, SyncReport report) async {
    final row = await (_db.select(_db.userSettingsTable)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    if (row == null) return;
    await _sb.from('user_settings').upsert({
      'user_id': uid,
      'default_increment_kg': row.defaultIncrementKg,
      'weight_unit': row.weightUnit,
      'default_rest_seconds': row.defaultRestSeconds,
      'use_rir_instead_of_rpe': row.useRirInsteadOfRpe,
      'user_bodyweight_kg': row.userBodyweightKg,
      'theme_mode': row.themeMode,
      'updated_at': _isoUtc(DateTime.now()),
    }, onConflict: 'user_id');
    report.pushed('user_settings', 1);
  }

  Future<void> _pushBodyweight(String uid, SyncReport report) async {
    final rows = await _db.select(_db.bodyweightEntries).get();
    if (rows.isEmpty) return;
    final payload = rows
        .map((r) => {
              'user_id': uid,
              'date': r.date,
              'weight_kg': r.weightKg,
              'note': r.note,
              'updated_at': _isoUtc(r.updatedAt),
            })
        .toList();
    await _sb
        .from('bodyweight_entries')
        .upsert(payload, onConflict: 'user_id,date');
    report.pushed('bodyweight_entries', rows.length);
  }

  // ----------------------- HELPERS ------------------------

  /// Parse an ISO timestamp from Postgres (always with TZ marker) and
  /// convert to local time so it lines up with `DateTime.now()` used
  /// throughout the app.
  static DateTime? _parseDt(Object? v) =>
      v == null ? null : DateTime.parse(v as String).toLocal();
}

/// Encode a DateTime for Postgres `timestamptz`: emit UTC with `Z` suffix so
/// Postgres stores the actual moment, not a TZ-naive interpretation.
String _isoUtc(DateTime d) => d.toUtc().toIso8601String();
String? _isoUtcN(DateTime? d) => d == null ? null : _isoUtc(d);

class SyncReport {
  final bool ok;
  final String? error;
  final String? stackTrace;
  final Map<String, int> pulledByTable;
  final Map<String, int> pushedByTable;

  SyncReport({
    required this.ok,
    this.error,
    this.stackTrace,
    Map<String, int>? pulledByTable,
    Map<String, int>? pushedByTable,
  })  : pulledByTable = pulledByTable ?? {},
        pushedByTable = pushedByTable ?? {};

  factory SyncReport.empty() => SyncReport(ok: false);

  void pulled(String table) {
    pulledByTable[table] = (pulledByTable[table] ?? 0) + 1;
  }

  void pushed(String table, int count) {
    pushedByTable[table] = (pushedByTable[table] ?? 0) + count;
  }

  int get totalPulled =>
      pulledByTable.values.fold(0, (a, b) => a + b);
  int get totalPushed =>
      pushedByTable.values.fold(0, (a, b) => a + b);

  SyncReport copyWith({
    bool? ok,
    String? error,
    String? stackTrace,
  }) {
    return SyncReport(
      ok: ok ?? this.ok,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      pulledByTable: pulledByTable,
      pushedByTable: pushedByTable,
    );
  }

  @override
  String toString() {
    if (!ok) return 'Erreur: ${error ?? 'inconnue'}';
    final pull = pulledByTable.entries
        .map((e) => '${e.value} ${e.key}')
        .join(', ');
    final push = pushedByTable.entries
        .map((e) => '${e.value} ${e.key}')
        .join(', ');
    return jsonEncode({'pulled': pull, 'pushed': push});
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(ref.watch(databaseProvider));
});

/// True if connected and Supabase configured.
final canSyncProvider = Provider<bool>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(syncServiceProvider).isAvailable;
});

/// Last completed sync report. Null until the first sync runs. The auto-sync
/// in [MusculApp] updates this after every attempt so the UI can surface
/// failures (otherwise auto-sync errors are completely invisible to the
/// user and silent data loss is impossible to diagnose).
final lastSyncReportProvider = StateProvider<SyncReport?>((ref) => null);
