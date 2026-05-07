import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
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

  MuscleGroup _primary = MuscleGroup.chest;
  final Set<MuscleGroup> _secondary = {};
  Equipment _equipment = Equipment.barbell;
  ProgressionStrategyKind _strategy = ProgressionStrategyKind.doubleProgression;
  bool _useBodyweight = false;
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _machineModelCtrl.dispose();
    _machineSettingsCtrl.dispose();
    _repMinCtrl.dispose();
    _repMaxCtrl.dispose();
    _startingWeightCtrl.dispose();
    _incrementCtrl.dispose();
    _restCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.exerciseId;
    final settings =
        await ref.read(settingsRepositoryProvider).watch().first;
    final globalIncrement = settings.defaultIncrementKg;
    if (id == null) {
      _incrementCtrl.text = _fmtKg(globalIncrement);
      setState(() => _loading = false);
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
          _fmtKg(ex.defaultIncrementKg ?? globalIncrement);
      _restCtrl.text = ex.defaultRestSeconds?.toString() ?? '';
      _primary = ex.primaryMuscle;
      _secondary
        ..clear()
        ..addAll(ex.secondaryMuscles);
      _equipment = ex.equipment;
      _strategy = ex.progressionStrategy;
      _useBodyweight = ex.useBodyweight;
      _photoPath = ex.photoPath;
    }
    setState(() => _loading = false);
  }

  String _fmtKg(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  bool get _readOnly => _initial != null && !_initial!.isCustom;

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Donne un nom à l'exercice")),
      );
      return;
    }
    final id = _initial?.id ?? _uuid.v4();
    final repMin = int.tryParse(_repMinCtrl.text) ?? 8;
    final repMax = int.tryParse(_repMaxCtrl.text) ?? 12;
    final startWeight = double.tryParse(_startingWeightCtrl.text) ?? 20;
    final inc = double.tryParse(_incrementCtrl.text);
    final restRaw = _restCtrl.text.trim();
    final rest = restRaw.isEmpty ? null : int.tryParse(restRaw);
    final now = DateTime.now();
    final exercise = Exercise(
      id: id,
      name: name,
      // Category is derived from the primary muscle — push/pull/legs are
      // session-level concepts, not exercise-level.
      category: _categoryFromMuscle(_primary),
      primaryMuscle: _primary,
      secondaryMuscles: _secondary.toList(),
      equipment: _equipment,
      isCustom: true,
      progressionStrategy: _strategy,
      targetRepRangeMin: repMin,
      targetRepRangeMax: repMax > repMin ? repMax : repMin + 1,
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
    if (mounted) context.pop();
  }

  Future<void> _capturePhoto({required ImageSource source}) async {
    final id = _initial?.id ?? _uuid.v4();
    final path =
        await ref.read(photoStorageProvider).capture(id, source: source);
    if (path != null) setState(() => _photoPath = path);
  }

  Future<void> _delete() async {
    if (_initial == null || !_initial!.isCustom) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer cet exercice ?'),
        content: const Text(
            'L\'historique des séances reste accessible. L\'exercice ne sera plus proposé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(exerciseRepositoryProvider).softDelete(_initial!.id);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? 'Nouvel exercice' : 'Exercice'),
        actions: [
          if (_initial != null && _initial!.isCustom)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(
              icon: const Icon(Icons.check),
              onPressed: _readOnly ? null : _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_readOnly)
            const Card(
              color: Color(0xFFFFF8E1),
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Exercice par défaut'),
                subtitle: Text(
                    'Dupliquez-le depuis le menu pour pouvoir le modifier.'),
              ),
            ),
          _PhotoBox(
            path: _photoPath,
            onTakePhoto: () => _capturePhoto(source: ImageSource.camera),
            onPickGallery: () => _capturePhoto(source: ImageSource.gallery),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            enabled: !_readOnly,
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
                DropdownMenuItem(value: m, child: Text(_muscleLabel(m))),
            ],
            onChanged:
                _readOnly ? null : (v) => setState(() => _primary = v!),
          ),
          const SizedBox(height: 12),
          // Secondary muscles — collapsed multi-select to avoid covering
          // half the screen with chips. Tap to open a sheet with the
          // full list.
          _SecondaryMusclesField(
            primary: _primary,
            selected: _secondary,
            readOnly: _readOnly,
            onChanged: (next) => setState(() {
              _secondary
                ..clear()
                ..addAll(next);
            }),
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
                DropdownMenuItem(value: e, child: Text(e.name)),
            ],
            onChanged:
                _readOnly ? null : (v) => setState(() => _equipment = v!),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: SwitchListTile(
              value: _useBodyweight,
              onChanged: _readOnly
                  ? null
                  : (v) => setState(() => _useBodyweight = v),
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
              subtitle: const Text(
                  'Tractions, dips… le poids = lest (+/-)'),
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
                          "Cible reps + incrément utilisés pour calculer la "
                          "prochaine série (Double Progression : on monte les "
                          "reps jusqu'au max, puis +incrément kg, retour au "
                          "min). Le RPE auto-régulé pilote le poids via "
                          "l'e1RM courant à un RPE cible.",
                    ),
                  ]),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ProgressionStrategyKind>(
                    value: _strategy,
                    decoration: const InputDecoration(
                      labelText: 'Stratégie',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ProgressionStrategyKind.doubleProgression,
                        child: Text('Double progression'),
                      ),
                      DropdownMenuItem(
                        value: ProgressionStrategyKind.rpeAutoregulated,
                        child: Text('Auto-régulé RPE'),
                      ),
                    ],
                    onChanged: _readOnly
                        ? null
                        : (v) => setState(() => _strategy = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _repMinCtrl,
                        enabled: !_readOnly,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reps min',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: 'Plancher de la fourchette',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _repMaxCtrl,
                        enabled: !_readOnly,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reps max',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: 'Atteint → +incrément',
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _incrementCtrl,
                        enabled: !_readOnly,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Incrément (kg)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: 'Override du global',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _startingWeightCtrl,
                        enabled: !_readOnly && !_useBodyweight,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Poids départ (kg)',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: 'Si pas d\'historique',
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _restCtrl,
                    enabled: !_readOnly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Repos par défaut (s) — laisser vide pour le global',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _machineModelCtrl,
            enabled: !_readOnly,
            decoration: const InputDecoration(
              labelText: 'Marque/modèle machine',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _machineSettingsCtrl,
            enabled: !_readOnly,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Réglages machine',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            enabled: !_readOnly,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
        ],
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
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
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
    final names = selected.map(_muscleLabel).toList()..sort();
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
                      title: Text(_muscleLabel(m)),
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

/// Maps a muscle group to the legacy ExerciseCategory we still keep in DB
/// for back-compat with the seeded exercises. Used at save time.
ExerciseCategory _categoryFromMuscle(MuscleGroup m) {
  switch (m) {
    case MuscleGroup.chest:
    case MuscleGroup.shoulders:
    case MuscleGroup.triceps:
      return ExerciseCategory.push;
    case MuscleGroup.upperBack:
    case MuscleGroup.lats:
    case MuscleGroup.biceps:
    case MuscleGroup.forearms:
    case MuscleGroup.lowerBack:
    case MuscleGroup.rearDelts:
      return ExerciseCategory.pull;
    case MuscleGroup.quads:
    case MuscleGroup.hamstrings:
    case MuscleGroup.glutes:
    case MuscleGroup.calves:
      return ExerciseCategory.legs;
    case MuscleGroup.abs:
    case MuscleGroup.obliques:
      return ExerciseCategory.core;
    case MuscleGroup.cardio:
      return ExerciseCategory.cardio;
  }
}

String _muscleLabel(MuscleGroup m) {
  switch (m) {
    case MuscleGroup.chest:
      return 'Pectoraux';
    case MuscleGroup.upperBack:
      return 'Dos (haut)';
    case MuscleGroup.lats:
      return 'Grands dorsaux';
    case MuscleGroup.lowerBack:
      return 'Lombaires';
    case MuscleGroup.shoulders:
      return 'Épaules';
    case MuscleGroup.rearDelts:
      return 'Deltoïdes postérieurs';
    case MuscleGroup.biceps:
      return 'Biceps';
    case MuscleGroup.triceps:
      return 'Triceps';
    case MuscleGroup.forearms:
      return 'Avant-bras';
    case MuscleGroup.quads:
      return 'Quadriceps';
    case MuscleGroup.hamstrings:
      return 'Ischio-jambiers';
    case MuscleGroup.glutes:
      return 'Fessiers';
    case MuscleGroup.calves:
      return 'Mollets';
    case MuscleGroup.abs:
      return 'Abdos';
    case MuscleGroup.obliques:
      return 'Obliques';
    case MuscleGroup.cardio:
      return 'Cardio';
  }
}
