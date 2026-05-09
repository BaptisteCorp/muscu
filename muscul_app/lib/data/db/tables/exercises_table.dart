import 'package:drift/drift.dart';

@DataClassName('ExerciseEntity')
class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get primaryMuscle => text()();
  TextColumn get secondaryMuscles => text().withDefault(const Constant('[]'))();
  TextColumn get equipment => text()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();
  RealColumn get defaultIncrementKg => real().nullable()();
  IntColumn get defaultRestSeconds => integer().nullable()();
  BoolColumn get progressiveOverloadEnabled =>
      boolean().withDefault(const Constant(true))();
  TextColumn get progressionPriority =>
      text().withDefault(const Constant('repsFirst'))();
  IntColumn get minimumRpeThreshold => integer().nullable()();
  IntColumn get targetRepRangeMin => integer().withDefault(const Constant(8))();
  IntColumn get targetRepRangeMax => integer().withDefault(const Constant(12))();
  RealColumn get startingWeightKg =>
      real().withDefault(const Constant(20.0))();
  BoolColumn get useBodyweight =>
      boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable()();
  TextColumn get machineBrandModel => text().nullable()();
  TextColumn get machineSettings => text().nullable()();
  TextColumn get photoPath => text().nullable()();

  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  TextColumn get remoteId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
