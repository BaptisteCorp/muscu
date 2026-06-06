import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reps/data/db/database.dart';
import 'package:reps/data/repositories/settings_repository.dart';
import 'package:reps/domain/models/enums.dart';
import 'package:reps/domain/models/user_settings.dart';

void main() {
  late AppDatabase db;
  late LocalSettingsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LocalSettingsRepository(db);
  });

  tearDown(() async => db.close());

  test('palette and theme mode round-trip through save/get', () async {
    await repo.save(const UserSettings(
      themeMode: AppThemeMode.dark,
      palette: AppPalette.ocean,
    ));

    final loaded = await repo.get();
    expect(loaded.themeMode, AppThemeMode.dark);
    expect(loaded.palette, AppPalette.ocean);
  });

  test('palette persists when other settings are saved afterwards', () async {
    await repo.save(const UserSettings(palette: AppPalette.violet));
    // A later save that only means to change the rest timer must not clobber
    // the chosen accent colour.
    final current = await repo.get();
    await repo.save(current.copyWith(defaultRestSeconds: 75));

    final loaded = await repo.get();
    expect(loaded.palette, AppPalette.violet);
    expect(loaded.defaultRestSeconds, 75);
  });
}
