import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:sqlite3/sqlite3.dart';

import 'tables/bodyweight_table.dart';
import 'tables/exercises_table.dart';
import 'tables/templates_table.dart';
import 'tables/sessions_table.dart';
import 'tables/settings_table.dart';
import 'seeds/default_exercises.dart';

part 'database.g.dart';

@DriftDatabase(tables: [
  Exercises,
  WorkoutTemplates,
  WorkoutTemplateExercises,
  TemplateExerciseSets,
  WorkoutSessions,
  SessionExercises,
  SetEntries,
  UserSettingsTable,
  BodyweightEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(exercises, exercises.defaultRestSeconds);
          }
          if (from < 3) {
            await m.addColumn(sessionExercises, sessionExercises.restSeconds);
          }
          if (from < 4) {
            // Add a synthetic `id` PK to workout_template_exercises so the same
            // exercise can appear several times in a template.
            await customStatement('''
              CREATE TABLE workout_template_exercises_new (
                id TEXT NOT NULL PRIMARY KEY,
                template_id TEXT NOT NULL,
                exercise_id TEXT NOT NULL,
                order_index INTEGER NOT NULL,
                target_sets INTEGER NOT NULL DEFAULT 3
              );
            ''');
            await customStatement('''
              INSERT INTO workout_template_exercises_new
                (id, template_id, exercise_id, order_index, target_sets)
              SELECT
                template_id || '|' || exercise_id,
                template_id, exercise_id, order_index, target_sets
              FROM workout_template_exercises;
            ''');
            await customStatement(
                'DROP TABLE workout_template_exercises;');
            await customStatement('''
              ALTER TABLE workout_template_exercises_new
                RENAME TO workout_template_exercises;
            ''');
          }
          if (from < 5) {
            await m.addColumn(exercises, exercises.useBodyweight);
            await m.addColumn(
                sessionExercises, sessionExercises.supersetGroupId);
            await m.addColumn(
                userSettingsTable, userSettingsTable.userBodyweightKg);
          }
          if (from < 6) {
            await m.createTable(bodyweightEntries);
          }
          if (from < 7) {
            await m.addColumn(workoutTemplateExercises,
                workoutTemplateExercises.restSeconds);
            await m.createTable(templateExerciseSets);
          }
          if (from < 9) {
            // Suppression de la planification de séances (jamais utilisée
            // côté UI). On drop la colonne plannedFor pour garder la DB
            // simple et alignée avec le modèle.
            try {
              await customStatement(
                  'ALTER TABLE workout_sessions DROP COLUMN planned_for;');
            } catch (_) {/* déjà absente */}
          }
          if (from < 8) {
            // Refactor surcharge progressive : on remplace le champ
            // `progression_strategy` par 3 paramètres explicites.
            await m.addColumn(
                exercises, exercises.progressiveOverloadEnabled);
            await m.addColumn(exercises, exercises.progressionPriority);
            await m.addColumn(exercises, exercises.minimumRpeThreshold);
            // SQLite >= 3.35 supporte DROP COLUMN. Le plugin sqlite3_flutter_libs
            // embarque une version récente, mais on protège par try/catch :
            // si la colonne n'existe plus pour une raison X, on ignore.
            try {
              await customStatement(
                  'ALTER TABLE exercises DROP COLUMN progression_strategy;');
            } catch (_) {/* ignore */}
          }
        },
        onCreate: (m) async {
          await m.createAll();
          // Seed default exercises and singleton settings.
          final now = DateTime.now();
          await batch((b) {
            b.insertAll(
              exercises,
              [
                for (final s in defaultExerciseSeeds)
                  ExercisesCompanion.insert(
                    id: s.id,
                    name: s.name,
                    category: s.category.name,
                    primaryMuscle: s.primary.name,
                    secondaryMuscles: Value(
                        jsonEncode(s.secondary.map((m) => m.name).toList())),
                    equipment: s.equipment.name,
                    isCustom: const Value(false),
                    targetRepRangeMin: Value(s.repMin),
                    targetRepRangeMax: Value(s.repMax),
                    startingWeightKg: Value(s.startingWeight),
                    updatedAt: now,
                    syncStatus: const Value('synced'),
                  ),
              ],
            );
            b.insert(
              userSettingsTable,
              UserSettingsTableCompanion.insert(id: const Value(1)),
              mode: InsertMode.insertOrIgnore,
            );
          });
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'muscul_app.db'));
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;
    return NativeDatabase.createInBackground(file);
  });
}
