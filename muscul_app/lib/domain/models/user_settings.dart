import 'enums.dart';

class UserSettings {
  final double defaultIncrementKg;
  final WeightUnit weightUnit;
  final int defaultRestSeconds;
  final bool useRirInsteadOfRpe;
  final double? userBodyweightKg;
  final AppThemeMode themeMode;

  const UserSettings({
    this.defaultIncrementKg = 2.5,
    this.weightUnit = WeightUnit.kg,
    this.defaultRestSeconds = 120,
    this.useRirInsteadOfRpe = false,
    this.userBodyweightKg,
    this.themeMode = AppThemeMode.system,
  });

  UserSettings copyWith({
    double? defaultIncrementKg,
    WeightUnit? weightUnit,
    int? defaultRestSeconds,
    bool? useRirInsteadOfRpe,
    double? userBodyweightKg,
    bool clearUserBodyweightKg = false,
    AppThemeMode? themeMode,
  }) {
    return UserSettings(
      defaultIncrementKg: defaultIncrementKg ?? this.defaultIncrementKg,
      weightUnit: weightUnit ?? this.weightUnit,
      defaultRestSeconds: defaultRestSeconds ?? this.defaultRestSeconds,
      useRirInsteadOfRpe: useRirInsteadOfRpe ?? this.useRirInsteadOfRpe,
      userBodyweightKg: clearUserBodyweightKg
          ? null
          : (userBodyweightKg ?? this.userBodyweightKg),
      themeMode: themeMode ?? this.themeMode,
    );
  }
}
