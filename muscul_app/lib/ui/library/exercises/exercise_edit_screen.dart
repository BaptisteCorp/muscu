import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/exercise.dart';

const _uuid = Uuid();

class ExerciseEditScreen extends ConsumerStatefulWidget {
  final String? exerciseId;
  const ExerciseEditScreen({super.key, this.exerciseId});
  @override
  ConsumerState<ExerciseEditScreen> createState() => _ExerciseEditScreenState();
}

class _ExerciseEditScreenState extends ConsumerState<ExerciseEditScreen> {
  Exercise? _initial;
  bool _loading = true;
  bool _showErrors = false;
  bool _dirty = false;

  // form fields
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _machineModelCtrl = TextEditingController();
  final _machineSettingsCtrl = TextEditingController();
  final _repMinCtrl = TextEditingController(text: '8');
  final _repMaxCtrl = TextEditingController(text: '12');
  final _startingWeightCtrl = TextEditingController(text: '20');
  final _incrementCtrl = TextEditingController();
  final _restCtrl = TextEditingController();
  final _rpeThresholdCtrl = TextEditingController();

  late final List<TextEditingController> _allCtrls = [
    _nameCtrl,
    _notesCtrl,
    _machineModelCtrl,
    _machineSettingsCtrl,
    _repMinCtrl,
    _repMaxCtrl,
    _startingWeightCtrl,
    _incrementCtrl,
    _restCtrl,
    _rpeThresholdCtrl,
  ];

  MuscleGroup _primary = MuscleGroup.chest;
  final Set<MuscleGroup> _secondary = {};
  Equipment _equipment = Equipment.barbell;
  bool _progressiveOverloadEnabled = true;
  bool _useBodyweight = false;
  String? _photoPath;

  void _markDirty() {
    if (!_dirty) _dirty = true;
  }

  @override
  void initState() {
    super.initState();
    for (final c in _allCtrls) {
      c.addListener(_markDirty);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _allCtrls) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final id = widget.exerciseId;
      // .get() returns the singleton settings row directly; using .watch().first
      // would couple loading to a stream emission, which makes widget tests
      // flake when the fake clock doesn't drive real I/O timers.
      final settings = await ref.read(settingsRepositoryProvider).get();
      final globalIncrement = settings.defaultIncrementKg;
      if (id == null) {
        _incrementCtrl.text = fmtKg(globalIncrement);
        return;
      }
      final ex = await ref.read(exerciseRepositoryProvider).getById(id);
      if (ex != null) {
        _initial = ex;
        _nameCtrl.text = ex.name;
        _notesCtrl.text = ex.notes ?? '';
        _machineModelCtrl.text = ex.machineBrandModel ?? '';
        _machineSettingsCtrl.text = ex.machineSettings ?? '';
        _repMinCtrl.text = ex.targetRepRangeMin.toString();
        _repMaxCtrl.text = ex.targetRepRangeMax.toString();
        _startingWeightCtrl.text = ex.startingWeightKg.toString();
        _incrementCtrl.text =
            fmtKg(ex.defaultIncrementKg ?? globalIncrement);
        _restCtrl.text = ex.defaultRestSeconds?.toString() ?? '';
        _primary = ex.primaryMuscle;
        _secondary
          ..clear()
          ..addAll(ex.secondaryMuscles);
        _equipment = ex.equipment;
        _progressiveOverloadEnabled = ex.progressiveOverloadEnabled;
        _rpeThresholdCtrl.text = ex.minimumRpeThreshold?.toString() ?? '';
        _useBodyweight = ex.useBodyweight;
        _photoPath = ex.photoPath;
      }
    } finally {
      // Always exit loading even if anything above threw — leaving the
      // screen stuck on a CircularProgressIndicator is the worst outcome.
      // Listeners flipped _dirty during the controller text assignments;
      // reset so a clean load doesn't trigger the discard dialog.
      _dirty = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  // --- Validators (live, returnent null si OK, sinon le message d'erreur) ---
  String? _validatePositiveInt(String text, {int min = 1}) {
    if (text.isEmpty) return null;
    final v = int.tryParse(text);
    if (v == null) return 'Nombre attendu';
    if (v < min) return '≥ $min attendu';
    return null;
  }

  String? _validatePositiveDouble(String text) {
    if (text.isEmpty) return null;
    final v = double.tryParse(text);
    if (v == null) return 'Nombre attendu';
    if (v < 0) return 'Doit être ≥ 0';
    return null;
  }

  String? _validateRepMax() {
    final err = _validatePositiveInt(_repMaxCtrl.text);
    if (err != null) return err;
    final mn = int.tryParse(_repMinCtrl.text);
    final mx = int.tryParse(_repMaxCtrl.text);
    if (mn != null && mx != null && mx <= mn) return '> Reps min';
    return null;
  }

  String? _validateRpe() {
    if (_rpeThresholdCtrl.text.isEmpty) return null;
    final v = int.tryParse(_rpeThresholdCtrl.text);
    if (v == null) return 'Nombre attendu';
    if (v < 1 || v > 10) return 'Entre 1 et 10';
    return null;
  }

  bool get _hasFormErrors {
    return _validatePositiveInt(_repMinCtrl.text) != null ||
        _validateRepMax() != null ||
        _validatePositiveDouble(_incrementCtrl.text) != null ||
        _validatePositiveDouble(_startingWeightCtrl.text) != null ||
        _validatePositiveInt(_restCtrl.text) != null ||
        _validateRpe() != null;
  }

  Future<bool> _persist() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _hasFormErrors) return false;
    if (!await _confirmIfInUse()) return false;
    await _writeExercise();
    _dirty = false;
    return true;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _hasFormErrors) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Corrige les champs en rouge avant d\'enregistrer')),
      );
      return;
    }
    if (!await _confirmIfInUse()) return;
    await _writeExercise();
    _dirty = false;
    if (mounted) context.pop();
  }

  /// Vrai si l'édition touche quelque chose qui se répercute sur l'historique /
  /// les modèles : nom, fourchette de reps, muscles, équipement, bodyweight.
  /// Les changements purement "réglages" (repos, incrément, RPE, notes, photo,
  /// machine) ne réécrivent pas le passé → pas d'avertissement.
  bool _hasMaterialChange(Exercise initial) {
    final repMin = int.tryParse(_repMinCtrl.text) ?? initial.targetRepRangeMin;
    final repMaxRaw =
        int.tryParse(_repMaxCtrl.text) ?? initial.targetRepRangeMax;
    final effMax = repMaxRaw > repMin ? repMaxRaw : repMin + 1;
    return _nameCtrl.text.trim() != initial.name ||
        repMin != initial.targetRepRangeMin ||
        effMax != initial.targetRepRangeMax ||
        _primary != initial.primaryMuscle ||
        _equipment != initial.equipment ||
        _useBodyweight != initial.useBodyweight ||
        !setEquals(_secondary, initial.secondaryMuscles.toSet());
  }

  /// Avertit avant d'enregistrer une modification matérielle d'un exercice déjà
  /// utilisé (historique loggé ou présent dans un modèle). Renvoie `true` si on
  /// peut continuer (pas d'avertissement nécessaire, ou confirmé), `false` si
  /// l'utilisateur annule.
  Future<bool> _confirmIfInUse() async {
    final initial = _initial;
    if (initial == null || !_hasMaterialChange(initial)) return true;

    final id = initial.id;
    // One-shot query (PAS le StreamProvider trainedExerciseIdsProvider) : lire
    // un .watch() ici ouvrirait un stream Drift jamais fermé → timer pendant et
    // pumpAndSettle qui ne se stabilise plus en test. cf. note ".get() vs
    // .watch()". L'exo est « entraîné » s'il a au moins une série de travail
    // dans une séance terminée.
    final history =
        await ref.read(sessionRepositoryProvider).historyForExercise(id);
    final loggedUse = history.any((h) => h.sets.any((s) => !s.isWarmup));
    final templateCount =
        await ref.read(templateRepositoryProvider).countTemplatesUsingExercise(id);
    if (!loggedUse && templateCount == 0) return true;
    if (!mounted) return true;

    final parts = <String>[
      if (loggedUse) 'ton historique de séances',
      if (templateCount > 0)
        '$templateCount modèle${templateCount > 1 ? 's' : ''}',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Modifier un exercice utilisé ?'),
        content: Text(
            'Cet exercice apparaît dans ${parts.join(' et ')}. Tes '
            'modifications (nom, fourchette de reps…) se répercuteront sur ces '
            'éléments.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _writeExercise() async {
    final name = _nameCtrl.text.trim();
    final id = _initial?.id ?? _uuid.v4();
    final repMin = int.tryParse(_repMinCtrl.text) ?? 8;
    final repMaxRaw = int.tryParse(_repMaxCtrl.text) ?? 12;
    final repMax = repMaxRaw > repMin ? repMaxRaw : repMin + 1;
    // Au poids du corps : aucune charge prescrite, on force 0 (le champ est
    // grisé et pourrait encore contenir une vieille valeur, ex. 20).
    final startWeight =
        _useBodyweight ? 0.0 : (double.tryParse(_startingWeightCtrl.text) ?? 20);
    final inc = double.tryParse(_incrementCtrl.text);
    final restRaw = _restCtrl.text.trim();
    final rest = restRaw.isEmpty ? null : int.tryParse(restRaw);
    final rpeRaw = _rpeThresholdCtrl.text.trim();
    final rpeThreshold = rpeRaw.isEmpty ? null : int.tryParse(rpeRaw);
    final now = DateTime.now();
    // Changer le poids de départ = « je redémarre la progression ici » : on pose
    // un point de reset pour que le moteur ignore l'historique antérieur et
    // reparte de cette valeur (sinon le ratchet up-only rappellerait l'ancien
    // poids). Sur un exo neuf il n'y a pas d'historique → inutile.
    final initial = _initial;
    // On ne redémarre la progression que pour un exo CHARGÉ dont le poids de
    // départ change vraiment. Au poids du corps le poids est forcé à 0 et n'a
    // aucun sens : sans ce garde, un exo bodyweight avec un startingWeightKg
    // résiduel (ex. 20 d'avant le fix) se reset à CHAQUE save et jette tout
    // l'historique de reps. cf. _bodyweightTarget (progression sur les reps).
    final startWeightChanged = initial != null &&
        !_useBodyweight &&
        initial.startingWeightKg != startWeight;
    final progressionResetAt =
        startWeightChanged ? now : initial?.progressionResetAt;
    final exercise = Exercise(
      id: id,
      name: name,
      // Category is derived from the primary muscle — push/pull/legs are
      // session-level concepts, not exercise-level.
      category: categoryFromMuscle(_primary),
      primaryMuscle: _primary,
      secondaryMuscles: _secondary.toList(),
      equipment: _equipment,
      isCustom: _initial?.isCustom ?? true,
      progressiveOverloadEnabled: _progressiveOverloadEnabled,
      minimumRpeThreshold: rpeThreshold,
      progressionResetAt: progressionResetAt,
      targetRepRangeMin: repMin,
      targetRepRangeMax: repMax,
      startingWeightKg: startWeight,
      useBodyweight: _useBodyweight,
      defaultIncrementKg: inc,
      defaultRestSeconds: rest,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      machineBrandModel: _machineModelCtrl.text.trim().isEmpty
          ? null
          : _machineModelCtrl.text.trim(),
      machineSettings: _machineSettingsCtrl.text.trim().isEmpty
          ? null
          : _machineSettingsCtrl.text.trim(),
      photoPath: _photoPath,
      updatedAt: now,
      syncStatus: SyncStatus.pending,
    );
    await ref.read(exerciseRepositoryProvider).upsert(exercise);
    // Fire-and-forget: local DB is the source of truth, and awaiting the
    // network round-trip would freeze the Save button for 5-15s when the
    // Supabase auth token is in the middle of an AuthRetryableFetchError
    // backoff. Next full sync retries on failure.
    ref.read(syncServiceProvider).pushExercise(id).ignore();

    // Si la fourchette de reps a changé, les reps planifiées (snapshot) des
    // modèles qui utilisent cet exo peuvent être hors plage → on les borne.
    if (initial != null &&
        (repMin != initial.targetRepRangeMin ||
            repMax != initial.targetRepRangeMax)) {
      await ref.read(templateRepositoryProvider).clampPlannedRepsForExercise(
            exerciseId: id,
            min: repMin,
            max: repMax,
          );
    }
  }

  /// Called when the user navigates back. Auto-save if valid; otherwise ask
  /// whether to discard.
  Future<bool> _handlePop() async {
    if (!_dirty) return true;
    final canSave = _nameCtrl.text.trim().isNotEmpty && !_hasFormErrors;
    if (canSave) {
      // _persist renvoie false si l'utilisateur annule l'avertissement
      // "exercice utilisé" → on reste sur l'écran (on ne pop pas).
      return await _persist();
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Annuler les modifications ?'),
        content: const Text(
            'L\'exercice ne peut pas être enregistré (champs invalides ou nom manquant). '
            'Voulez-vous abandonner les modifications ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Continuer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _capturePhoto({required ImageSource source}) async {
    final id = _initial?.id ?? _uuid.v4();
    final result =
        await ref.read(photoStorageProvider).capture(id, source: source);
    if (!mounted) return;
    if (result.path != null) {
      _markDirty();
      setState(() => _photoPath = result.path);
    } else if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error!)),
      );
    }
  }

  Future<void> _delete() async {
    if (_initial == null || !_initial!.isCustom) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Supprimer cet exercice ?'),
        content: const Text(
            'L\'historique des séances reste accessible. L\'exercice ne sera plus proposé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      final id = _initial!.id;
      await ref.read(exerciseRepositoryProvider).softDelete(id);
      ref.read(syncServiceProvider).pushExercise(id).ignore();
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final allow = await _handlePop();
        if (allow && mounted) context.pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? 'Nouvel exercice' : 'Exercice'),
        actions: [
          if (_initial != null && _initial!.isCustom)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(
              icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PhotoBox(
            path: _photoPath,
            onTakePhoto: () => _capturePhoto(source: ImageSource.camera),
            onPickGallery: () => _capturePhoto(source: ImageSource.gallery),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            onChanged: (_) {
              if (_showErrors) setState(() {});
            },
            decoration: InputDecoration(
              labelText: 'Nom',
              border: const OutlineInputBorder(),
              errorText: _showErrors && _nameCtrl.text.trim().isEmpty
                  ? 'Le nom est requis'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MuscleGroup>(
            value: _primary,
            decoration: InputDecoration(
              labelText: 'Muscle principal',
              border: const OutlineInputBorder(),
              suffixIcon: _InfoIconBtn(
                title: 'Muscle principal',
                body:
                    "Le groupe musculaire qui fait le plus gros du travail. "
                    "C'est lui qui sert pour le tri intelligent quand tu "
                    "crées une séance (\"séance pec\" → exos chest en haut).",
              ),
            ),
            items: [
              for (final m in MuscleGroup.values)
                DropdownMenuItem(value: m, child: Text(muscleLabel(m))),
            ],
            onChanged: (v) {
              _markDirty();
              setState(() => _primary = v!);
            },
          ),
          const SizedBox(height: 12),
          // Secondary muscles — collapsed multi-select to avoid covering
          // half the screen with chips. Tap to open a sheet with the
          // full list.
          _SecondaryMusclesField(
            primary: _primary,
            selected: _secondary,
            readOnly: false,
            onChanged: (next) {
              _markDirty();
              setState(() {
                _secondary
                  ..clear()
                  ..addAll(next);
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Equipment>(
            value: _equipment,
            decoration: const InputDecoration(
              labelText: 'Équipement',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final e in Equipment.values)
                DropdownMenuItem(value: e, child: Text(e.label)),
            ],
            onChanged: (v) {
              _markDirty();
              setState(() => _equipment = v!);
            },
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SwitchListTile(
              value: _useBodyweight,
              onChanged: (v) {
                _markDirty();
                setState(() {
                  _useBodyweight = v;
                  // Au poids du corps : pas de charge prescrite, on remet
                  // le champ (grisé) à 0 pour refléter la donnée réelle.
                  if (v) _startingWeightCtrl.text = '0';
                });
              },
              title: Row(children: [
                const Text('Au poids du corps'),
                const SizedBox(width: 4),
                _InfoIconBtn(
                  title: 'Au poids du corps',
                  body:
                      "Pour les tractions, dips, pompes, etc. Le poids logé est "
                      "le lest ajouté (positif) ou retiré (assistance, négatif).\n\n"
                      "Si tu renseignes ton poids dans les Réglages, l'app affichera "
                      "aussi le poids total (corps + lest) à côté.",
                ),
              ]),
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(height: 12),
          // Progression — reps target range, increment, starting weight and
          // strategy. These drive the next-target computation and the
          // default values offered when the exo is added to a template.
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Progression',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 4),
                    _InfoIconBtn(
                      title: 'Surcharge progressive',
                      body:
                          "Double progression : on monte les reps jusqu'au "
                          "haut de la fourchette, puis +incrément kg et retour "
                          "au plancher de reps.\n\n"
                          "La progression n'a lieu que si toutes les séries "
                          "prévues sont terminées avec au moins le min de "
                          "reps, et que le RPE de la séance ne dépasse pas "
                          "le seuil (si défini).",
                    ),
                  ]),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Row(children: [
                      const Flexible(
                        child: Text('Surcharge progressive activée'),
                      ),
                      const SizedBox(width: 4),
                      _InfoIconBtn(
                        title: 'Surcharge progressive',
                        body:
                            'Active la progression automatique des reps ou du poids '
                            'à chaque séance réussie.\n\n'
                            'Si désactivée, la séance suivante reproduit '
                            'exactement les valeurs de la dernière fois.',
                      ),
                    ]),
                    value: _progressiveOverloadEnabled,
                    onChanged: (v) {
                      _markDirty();
                      setState(() => _progressiveOverloadEnabled = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rpeThresholdCtrl,
                    enabled: _progressiveOverloadEnabled,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'RPE max pour valider (optionnel)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _validateRpe(),
                      suffixIcon: _InfoIconBtn(
                        title: 'RPE max pour valider',
                        body:
                            "RPE max autorisé en fin de séance pour valider "
                            "la progression. Au-delà, on garde les mêmes "
                            "valeurs la fois suivante.\n\n"
                            "Ex. 9 → si tu finis à RPE 10, pas de progression.\n\n"
                            "Vide = pas de contrainte.\n"
                            "Aucun RPE renseigné = considéré validé.",
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _repMinCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Reps min',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText: _validatePositiveInt(_repMinCtrl.text),
                          suffixIcon: _InfoIconBtn(
                            title: 'Reps min',
                            body:
                                'Plancher de la fourchette de répétitions. '
                                'On retombe à cette valeur après une '
                                'augmentation de poids.',
                          ),
                        ),
                      ),
                    ),
                    if (!_useBodyweight) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _repMaxCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Reps max',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText: _validateRepMax(),
                          suffixIcon: _InfoIconBtn(
                            title: 'Reps max',
                            body:
                                'Plafond de la fourchette. Quand on l\'atteint '
                                'sur toutes les séries, la séance suivante '
                                'ajoute l\'incrément kg et repart du min.',
                          ),
                        ),
                      ),
                    ),
                    ],
                  ]),
                  if (!_useBodyweight) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _incrementCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Incrément (kg)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText:
                              _validatePositiveDouble(_incrementCtrl.text),
                          suffixIcon: _InfoIconBtn(
                            title: 'Incrément',
                            body:
                                'Combien de kg on ajoute à chaque progression '
                                'de poids pour cet exercice. Override la '
                                'valeur globale des Réglages.',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _startingWeightCtrl,
                        enabled: !_useBodyweight,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Poids départ (kg)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText: _validatePositiveDouble(
                              _startingWeightCtrl.text),
                          suffixIcon: _InfoIconBtn(
                            title: 'Poids de départ',
                            body:
                                "Charge proposée pour la toute première "
                                "séance, quand il n'y a pas encore d'historique.",
                          ),
                        ),
                      ),
                    ),
                  ]),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _restCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Repos par défaut (s)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      errorText: _validatePositiveInt(_restCtrl.text),
                      suffixIcon: _InfoIconBtn(
                        title: 'Repos par défaut',
                        body:
                            'Durée de repos préremplie entre les séries pour '
                            'cet exercice. Laisser vide pour utiliser le repos '
                            'global défini dans les Réglages.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _machineModelCtrl,
            decoration: const InputDecoration(
              labelText: 'Marque/modèle machine',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _machineSettingsCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Réglages machine',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      ),
    );
  }
}

class _InfoIconBtn extends StatelessWidget {
  final String title;
  final String body;
  const _InfoIconBtn({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 20),
      tooltip: title,
      onPressed: () => showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact summary tile for secondary muscles. Tapping opens a sheet with
/// a multi-select list. Keeps the form short while still showing what's
/// picked at a glance.
class _SecondaryMusclesField extends StatelessWidget {
  final MuscleGroup primary;
  final Set<MuscleGroup> selected;
  final bool readOnly;
  final ValueChanged<Set<MuscleGroup>> onChanged;
  const _SecondaryMusclesField({
    required this.primary,
    required this.selected,
    required this.readOnly,
    required this.onChanged,
  });

  String _summary() {
    if (selected.isEmpty) return 'Aucun';
    final names = selected.map(muscleLabel).toList()..sort();
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<Set<MuscleGroup>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetCtx) => _SecondaryMusclesSheet(
        primary: primary,
        initial: selected,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: InkWell(
        onTap: readOnly ? null : () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Muscles secondaires',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      _InfoIconBtn(
                        title: 'Muscles secondaires',
                        body:
                            "Tous les autres groupes qui travaillent en plus "
                            "du principal. Sert au calcul du volume par muscle "
                            "(un développé couché compte aussi un peu pour "
                            "épaules et triceps).",
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      _summary(),
                      style: TextStyle(
                        color: selected.isEmpty
                            ? cs.onSurfaceVariant
                            : cs.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.expand_more_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryMusclesSheet extends StatefulWidget {
  final MuscleGroup primary;
  final Set<MuscleGroup> initial;
  const _SecondaryMusclesSheet({
    required this.primary,
    required this.initial,
  });
  @override
  State<_SecondaryMusclesSheet> createState() =>
      _SecondaryMusclesSheetState();
}

class _SecondaryMusclesSheetState extends State<_SecondaryMusclesSheet> {
  late Set<MuscleGroup> _picked;

  @override
  void initState() {
    super.initState();
    _picked = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final options = MuscleGroup.values
        .where((m) => m != widget.primary)
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Muscles secondaires',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (_picked.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_picked.clear),
                    child: const Text('Tout désélectionner'),
                  ),
              ],
            ),
            Text(
              'Coche tous les groupes qui travaillent en plus du principal.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                children: [
                  for (final m in options)
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(muscleLabel(m)),
                      value: _picked.contains(m),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _picked.add(m);
                        } else {
                          _picked.remove(m);
                        }
                      }),
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _picked),
                        child: Text(
                          _picked.isEmpty
                              ? 'Valider (aucun)'
                              : 'Valider (${_picked.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBox extends ConsumerWidget {
  final String? path;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickGallery;
  const _PhotoBox(
      {required this.path,
      required this.onTakePhoto,
      required this.onPickGallery});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget content;
    if (path != null) {
      content = FutureBuilder<File?>(
        future: ref.read(photoStorageProvider).resolve(path),
        builder: (_, snap) {
          if (snap.data == null) return const Center(child: Icon(Icons.photo));
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(snap.data!, fit: BoxFit.cover),
          );
        },
      );
    } else {
      content = const Center(
          child: Icon(Icons.add_a_photo_outlined, size: 48));
    }
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: content,
          ),
          Positioned(
            bottom: 8,
            right: 8,
            child: Wrap(spacing: 4, children: [
              FilledButton.tonalIcon(
                onPressed: onTakePhoto,
                icon: const Icon(Icons.photo_camera),
                label: const Text('Photo'),
              ),
              FilledButton.tonalIcon(
                onPressed: onPickGallery,
                icon: const Icon(Icons.image),
                label: const Text('Galerie'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

