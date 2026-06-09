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
  // Accent colour palette. Device-local (not synced to the cloud).
  TextColumn get palette => text().withDefault(const Constant('crimson'))();
  // Last local edit time, for last-write-wins sync. Null = never edited
  // (the default singleton) → loses every LWW comparison, so a fresh-install
  // default never overwrites real cloud settings on a push-before-pull sync.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  String get tableName => 'user_settings';
}
