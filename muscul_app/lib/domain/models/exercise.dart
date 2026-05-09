import 'enums.dart';

class Exercise {
  final String id;
  final String name;
  final ExerciseCategory category;
  final MuscleGroup primaryMuscle;
  final List<MuscleGroup> secondaryMuscles;
  final Equipment equipment;
  final bool isCustom;
  final double? defaultIncrementKg;
  final int? defaultRestSeconds;

  // --- Surcharge progressive --------------------------------------------
  /// Master switch. Si false, la séance suivante reproduit exactement les
  /// dernières valeurs (poids + reps).
  final bool progressiveOverloadEnabled;

  /// Ordre d'application : monter les reps d'abord, ou la charge d'abord.
  final ProgressionPriority progressionPriority;

  /// RPE maximum autorisé pour valider une progression (incl.). Si la séance
  /// précédente a dépassé ce seuil, on ne progresse pas. `null` = pas de
  /// contrainte RPE. Les sets sans RPE renseigné sont considérés validés.
  final int? minimumRpeThreshold;

  final int targetRepRangeMin;
  final int targetRepRangeMax;
  final double startingWeightKg;
  final bool useBodyweight;
  final String? notes;
  final String? machineBrandModel;
  final String? machineSettings;
  final String? photoPath;

  final DateTime updatedAt;
  final SyncStatus syncStatus;
  final String? remoteId;
  final DateTime? deletedAt;

  const Exercise({
    required this.id,
    required this.name,
    required this.category,
    required this.primaryMuscle,
    required this.secondaryMuscles,
    required this.equipment,
    required this.isCustom,
    required this.targetRepRangeMin,
    required this.targetRepRangeMax,
    required this.startingWeightKg,
    required this.updatedAt,
    this.progressiveOverloadEnabled = true,
    this.progressionPriority = ProgressionPriority.repsFirst,
    this.minimumRpeThreshold,
    this.useBodyweight = false,
    this.defaultIncrementKg,
    this.defaultRestSeconds,
    this.notes,
    this.machineBrandModel,
    this.machineSettings,
    this.photoPath,
    this.syncStatus = SyncStatus.pending,
    this.remoteId,
    this.deletedAt,
  });

  Exercise copyWith({
    String? name,
    ExerciseCategory? category,
    MuscleGroup? primaryMuscle,
    List<MuscleGroup>? secondaryMuscles,
    Equipment? equipment,
    double? defaultIncrementKg,
    bool clearDefaultIncrementKg = false,
    int? defaultRestSeconds,
    bool clearDefaultRestSeconds = false,
    bool? progressiveOverloadEnabled,
    ProgressionPriority? progressionPriority,
    int? minimumRpeThreshold,
    bool clearMinimumRpeThreshold = false,
    int? targetRepRangeMin,
    int? targetRepRangeMax,
    double? startingWeightKg,
    bool? useBodyweight,
    String? notes,
    bool clearNotes = false,
    String? machineBrandModel,
    bool clearMachineBrandModel = false,
    String? machineSettings,
    bool clearMachineSettings = false,
    String? photoPath,
    bool clearPhotoPath = false,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    String? remoteId,
    DateTime? deletedAt,
  }) {
    return Exercise(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      primaryMuscle: primaryMuscle ?? this.primaryMuscle,
      secondaryMuscles: secondaryMuscles ?? this.secondaryMuscles,
      equipment: equipment ?? this.equipment,
      isCustom: isCustom,
      defaultIncrementKg: clearDefaultIncrementKg
          ? null
          : (defaultIncrementKg ?? this.defaultIncrementKg),
      defaultRestSeconds: clearDefaultRestSeconds
          ? null
          : (defaultRestSeconds ?? this.defaultRestSeconds),
      progressiveOverloadEnabled:
          progressiveOverloadEnabled ?? this.progressiveOverloadEnabled,
      progressionPriority: progressionPriority ?? this.progressionPriority,
      minimumRpeThreshold: clearMinimumRpeThreshold
          ? null
          : (minimumRpeThreshold ?? this.minimumRpeThreshold),
      targetRepRangeMin: targetRepRangeMin ?? this.targetRepRangeMin,
      targetRepRangeMax: targetRepRangeMax ?? this.targetRepRangeMax,
      startingWeightKg: startingWeightKg ?? this.startingWeightKg,
      useBodyweight: useBodyweight ?? this.useBodyweight,
      notes: clearNotes ? null : (notes ?? this.notes),
      machineBrandModel: clearMachineBrandModel
          ? null
          : (machineBrandModel ?? this.machineBrandModel),
      machineSettings: clearMachineSettings
          ? null
          : (machineSettings ?? this.machineSettings),
      photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      remoteId: remoteId ?? this.remoteId,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  double effectiveIncrementKg(double globalDefault) =>
      defaultIncrementKg ?? globalDefault;

  int effectiveRestSeconds(int globalDefault) =>
      defaultRestSeconds ?? globalDefault;

  bool get isDeleted => deletedAt != null;
}
