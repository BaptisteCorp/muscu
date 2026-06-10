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

  /// Efface toutes les données PERSONNELLES locales (séances, modèles, exos
  /// custom, poids de corps) et réinitialise les réglages. Conserve les
  /// exercices seed (définitions, non personnelles). Appelé après une
  /// suppression de compte pour ne laisser aucune trace locale.
  Future<void> wipeUserData() async {
    await transaction(() async {
      await delete(setEntries).go();
      await delete(sessionExercises).go();
      await delete(workoutSessions).go();
      await delete(templateExerciseSets).go();
      await delete(workoutTemplateExercises).go();
      await delete(workoutTemplates).go();
      await delete(bodyweightEntries).go();
      // Exos créés par l'utilisateur ; les seed (is_custom=false) restent.
      await (delete(exercises)..where((t) => t.isCustom.equals(true))).go();
      // Réglages → valeurs d'usine (singleton id=1).
      await delete(userSettingsTable).go();
      await into(userSettingsTable).insert(
        UserSettingsTableCompanion.insert(id: const Value(1)),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  @override
  int get schemaVersion => 15;

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
            // progression_priority a existé entre les schémas 8 et 11 puis a
            // été supprimé (cf. migration from < 12). On l'ajoute ici en SQL
            // brut — le getter Drift n'existe plus — pour préserver le chemin
            // de migration historique ; il sera droppé juste après pour qui
            // passe directement de <8 à >=12.
            try {
              await customStatement(
                  "ALTER TABLE exercises ADD COLUMN progression_priority "
                  "TEXT NOT NULL DEFAULT 'repsFirst';");
            } catch (_) {/* déjà présente */}
            await m.addColumn(exercises, exercises.minimumRpeThreshold);
            // SQLite >= 3.35 supporte DROP COLUMN. Le plugin sqlite3_flutter_libs
            // embarque une version récente, mais on protège par try/catch :
            // si la colonne n'existe plus pour une raison X, on ignore.
            try {
              await customStatement(
                  'ALTER TABLE exercises DROP COLUMN progression_strategy;');
            } catch (_) {/* ignore */}
          }
          if (from < 10) {
            // Accent colour palette preference (device-local).
            await m.addColumn(userSettingsTable, userSettingsTable.palette);
          }
          if (from < 11) {
            // Last-write-wins timestamp for user_settings sync. Nullable, so
            // existing rows start null (= never edited) and don't clobber
            // real cloud settings on the next push-before-pull sync.
            await m.addColumn(userSettingsTable, userSettingsTable.updatedAt);
          }
          if (from < 12) {
            // Suppression de la notion de priorité de progression
            // (reps-first / weight-first) : on garde uniquement la double
            // progression (reps puis poids). On drop la colonne devenue morte.
            try {
              await customStatement(
                  'ALTER TABLE exercises DROP COLUMN progression_priority;');
            } catch (_) {/* déjà absente */}
          }
          if (from < 13) {
            // Point de redémarrage de la progression par exercice : le moteur
            // ignore l'historique antérieur et repart du poids de départ.
            await m.addColumn(exercises, exercises.progressionResetAt);
          }
          if (from < 14) {
            // updated_at pour la sync LWW des enfants de séance (le cloud a
            // déjà ces colonnes). Ajout en SQL brut + backfill par une date
            // plausible : completed_at pour les séries, started_at de la séance
            // parente pour les session_exercises (0/epoch pour les orphelins).
            for (final t in ['session_exercises', 'set_entries']) {
              try {
                await customStatement(
                    'ALTER TABLE $t ADD COLUMN updated_at INTEGER;');
              } catch (_) {/* déjà présente */}
            }
            await customStatement(
                'UPDATE set_entries SET updated_at = completed_at '
                'WHERE updated_at IS NULL;');
            await customStatement(
                'UPDATE session_exercises SET updated_at = COALESCE('
                '(SELECT ws.started_at FROM workout_sessions ws '
                'WHERE ws.id = session_exercises.session_id), 0) '
                'WHERE updated_at IS NULL;');
          }
          if (from < 15) {
            // Mode « système » retiré → les réglages encore dessus passent en
            // sombre. Et le défaut de palette passe de rouge (crimson) à bleu
            // (ocean) : on bascule celles restées sur l'ancien défaut.
            await customStatement(
                "UPDATE user_settings SET theme_mode = 'dark' "
                "WHERE theme_mode = 'system';");
            await customStatement(
                "UPDATE user_settings SET palette = 'ocean' "
                "WHERE palette = 'crimson';");
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
    final file = File(p.join(dir.path, 'reps.db'));
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;
    return NativeDatabase.createInBackground(file);
  });
}
