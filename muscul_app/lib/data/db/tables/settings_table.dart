import 'package:drift/drift.dart';

@DataClassName('UserSettingsRow')
class UserSettingsTable extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  RealColumn get defaultIncrementKg =>
      real().withDefault(const Constant(2.5))();
  TextColumn get weightUnit => text().withDefault(const Constant('kg'))();
  IntColumn get defaultRestSeconds =>
      integer().withDefault(const Constant(120))();
  BoolColumn get useRirInsteadOfRpe =>
      boolean().withDefault(const Constant(false))();
  RealColumn get userBodyweightKg => real().nullable()();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'user_settings';
}
