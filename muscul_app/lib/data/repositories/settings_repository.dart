import 'package:drift/drift.dart';

import '../../domain/models/enums.dart';
import '../../domain/models/user_settings.dart';
import '../db/database.dart';
import 'mappers.dart';

abstract class SettingsRepository {
  Stream<UserSettings> watch();
  Future<UserSettings> get();
  Future<void> save(UserSettings settings);
}

class LocalSettingsRepository implements SettingsRepository {
  final AppDatabase db;
  LocalSettingsRepository(this.db);

  Future<void> _ensure() async {
    final existing = await (db.select(db.userSettingsTable)
          ..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.userSettingsTable).insert(
            UserSettingsTableCompanion.insert(id: const Value(1)),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  @override
  Stream<UserSettings> watch() {
    final q = db.select(db.userSettingsTable)..where((t) => t.id.equals(1));
    return q.watchSingleOrNull().map(
          (row) => row == null ? const UserSettings() : settingsFromRow(row),
        );
  }

  @override
  Future<UserSettings> get() async {
    await _ensure();
    final row = await (db.select(db.userSettingsTable)
          ..where((t) => t.id.equals(1)))
        .getSingle();
    return settingsFromRow(row);
  }

  @override
  Future<void> save(UserSettings s) async {
    await _ensure();
    await (db.update(db.userSettingsTable)..where((t) => t.id.equals(1))).write(
      UserSettingsTableCompanion(
        defaultIncrementKg: Value(s.defaultIncrementKg),
        weightUnit: Value(s.weightUnit.name),
        defaultRestSeconds: Value(s.defaultRestSeconds),
        useRirInsteadOfRpe: Value(s.useRirInsteadOfRpe),
        userBodyweightKg: Value(s.userBodyweightKg),
        themeMode: Value(s.themeMode.name),
      ),
    );
  }
}

extension WeightUnitX on WeightUnit {
  String label() => switch (this) {
        WeightUnit.kg => 'kg',
        WeightUnit.lb => 'lb',
      };
}
