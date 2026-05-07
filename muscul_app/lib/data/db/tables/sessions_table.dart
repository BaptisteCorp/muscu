import 'package:drift/drift.dart';

@DataClassName('WorkoutSessionEntity')
class WorkoutSessions extends Table {
  TextColumn get id => text()();
  TextColumn get templateId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get plannedFor => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get remoteId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SessionExerciseEntity')
class SessionExercises extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get orderIndex => integer()();
  IntColumn get restSeconds => integer().nullable()();
  TextColumn get supersetGroupId => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get replacedFromSessionExerciseId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SetEntryEntity')
class SetEntries extends Table {
  TextColumn get id => text()();
  TextColumn get sessionExerciseId => text()();
  IntColumn get setIndex => integer()();
  IntColumn get reps => integer()();
  RealColumn get weightKg => real()();
  IntColumn get rpe => integer().nullable()();
  IntColumn get rir => integer().nullable()();
  IntColumn get restSeconds => integer().withDefault(const Constant(0))();
  BoolColumn get isWarmup => boolean().withDefault(const Constant(false))();
  BoolColumn get isFailure => boolean().withDefault(const Constant(false))();
  DateTimeColumn get completedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
