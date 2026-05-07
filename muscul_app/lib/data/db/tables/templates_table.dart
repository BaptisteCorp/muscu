import 'package:drift/drift.dart';

@DataClassName('WorkoutTemplateEntity')
class WorkoutTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get remoteId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('WorkoutTemplateExerciseEntity')
class WorkoutTemplateExercises extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get orderIndex => integer()();
  /// Legacy. With the per-set plan, the count is derived from
  /// `template_exercise_sets`. Kept for migration of older templates.
  IntColumn get targetSets => integer().withDefault(const Constant(3))();
  /// Rest between sets, override of the global default and of any
  /// (now-legacy) per-exercise rest.
  IntColumn get restSeconds => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per planned set of a template-exercise.
/// Allows mixed rep/weight schemes like a 7+6 drop set.
@DataClassName('TemplateExerciseSetEntity')
class TemplateExerciseSets extends Table {
  TextColumn get id => text()();
  TextColumn get templateExerciseId => text()();
  IntColumn get setIndex => integer()();
  IntColumn get plannedReps => integer()();
  /// `null` for bodyweight-only exercises (no added load).
  RealColumn get plannedWeightKg => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
