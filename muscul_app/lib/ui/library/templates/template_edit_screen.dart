import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../data/repositories/template_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/workout_template.dart';

const _uuid = Uuid();

class TemplateEditScreen extends ConsumerStatefulWidget {
  final String? templateId;
  const TemplateEditScreen({super.key, this.templateId});
  @override
  ConsumerState<TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TemplateEditScreenState extends ConsumerState<TemplateEditScreen> {
  final _nameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  List<TemplateExerciseWithSets> _exercises = [];
  WorkoutTemplate? _initial;
  bool _loading = true;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.templateId;
    if (id != null) {
      final detail =
          await ref.read(templateRepositoryProvider).getWithExercises(id);
      if (detail != null) {
        _initial = detail.template;
        _nameCtrl.text = detail.template.name;
        _notesCtrl.text = detail.template.notes ?? '';
        _exercises = [...detail.exercises];
      }
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _exercises.isEmpty) {
      setState(() => _showErrors = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(name.isEmpty
              ? 'Donne un nom au template'
              : 'Ajoute au moins un exercice'),
        ),
      );
      return;
    }
    final repo = ref.read(templateRepositoryProvider);
    final id = _initial?.id ?? _uuid.v4();
    final now = DateTime.now();
    final t = WorkoutTemplate(
      id: id,
      name: name,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: _initial?.createdAt ?? now,
      updatedAt: now,
    );
    await repo.upsertTemplate(t);
    // Stamp the (possibly newly-generated) template id onto every row.
    final reordered = <TemplateExerciseWithSets>[
      for (var i = 0; i < _exercises.length; i++)
        TemplateExerciseWithSets(
          exercise: WorkoutTemplateExercise(
            id: _exercises[i].exercise.id,
            templateId: id,
            exerciseId: _exercises[i].exercise.exerciseId,
            orderIndex: i,
            targetSets: _exercises[i].sets.length.clamp(1, 99),
            restSeconds: _exercises[i].exercise.restSeconds,
          ),
          sets: [
            for (var j = 0; j < _exercises[i].sets.length; j++)
              _exercises[i].sets[j].copyWith(setIndex: j),
          ],
        ),
    ];
    await repo.setTemplateExercises(id, reordered);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    if (_initial == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ce template ?'),
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
      await ref.read(templateRepositoryProvider).softDelete(_initial!.id);
      if (mounted) context.pop();
    }
  }

  Future<void> _addExercise() async {
    final picked = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExercisePickerSheet(
        templateName: _nameCtrl.text,
      ),
    );
    if (picked == null || !mounted) return;
    final teId = _uuid.v4();
    // Sensible default plan: 3 sets × 8 reps, weight=0 if bodyweight or
    // unknown.
    final defaultPlan = TemplateExerciseWithSets(
      exercise: WorkoutTemplateExercise(
        id: teId,
        templateId: _initial?.id ?? '',
        exerciseId: picked.id,
        orderIndex: _exercises.length,
        targetSets: 3,
        restSeconds: 90,
      ),
      sets: [
        for (var i = 0; i < 3; i++)
          TemplateExerciseSet(
            id: _uuid.v4(),
            templateExerciseId: teId,
            setIndex: i,
            plannedReps: 8,
            plannedWeightKg: picked.useBodyweight ? null : 20,
          ),
      ],
    );
    final result = await showModalBottomSheet<TemplateExerciseWithSets>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlanEditorSheet(
        exercise: picked,
        initial: defaultPlan,
        prefillFromHistory: true,
      ),
    );
    if (result != null) {
      setState(() => _exercises.add(result));
    }
  }

  Future<void> _editExercisePlan(int index) async {
    final exAsync = await ref
        .read(exerciseRepositoryProvider)
        .getById(_exercises[index].exercise.exerciseId);
    if (exAsync == null || !mounted) return;
    final result = await showModalBottomSheet<TemplateExerciseWithSets>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PlanEditorSheet(
        exercise: exAsync,
        initial: _exercises[index],
      ),
    );
    if (result != null) {
      setState(() => _exercises[index] = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? 'Nouveau template' : 'Template'),
        actions: [
          if (_initial != null)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
          IconButton(icon: const Icon(Icons.check), onPressed: _save),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            onChanged: (_) {
              if (_showErrors) setState(() {});
            },
            decoration: InputDecoration(
              labelText: 'Nom (ex: Push A)',
              border: const OutlineInputBorder(),
              errorText:
                  _showErrors && _nameCtrl.text.trim().isEmpty
                      ? 'Le nom est requis'
                      : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Exercices',
                  style: Theme.of(context).textTheme.titleMedium),
              if (_showErrors && _exercises.isEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '— ajoute au moins un exo',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_exercises.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: _showErrors
                    ? Theme.of(context)
                        .colorScheme
                        .errorContainer
                        .withOpacity(0.4)
                    : null,
                border: Border.all(
                  color: _showErrors
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Aucun exercice',
                style: TextStyle(
                  color: _showErrors
                      ? Theme.of(context).colorScheme.error
                      : Colors.grey,
                ),
              ),
            ),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: true,
            onReorder: (o, n) {
              setState(() {
                if (n > o) n -= 1;
                final item = _exercises.removeAt(o);
                _exercises.insert(n, item);
              });
            },
            children: [
              for (var i = 0; i < _exercises.length; i++)
                _TemplateExerciseTile(
                  key: ValueKey(_exercises[i].exercise.id),
                  plan: _exercises[i],
                  onTap: () => _editExercisePlan(i),
                  onDelete: () => setState(() => _exercises.removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _addExercise,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un exercice'),
          ),
        ],
      ),
    );
  }
}

class _TemplateExerciseTile extends ConsumerWidget {
  final TemplateExerciseWithSets plan;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _TemplateExerciseTile({
    required super.key,
    required this.plan,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exAsync =
        ref.watch(exerciseByIdProvider(plan.exercise.exerciseId));
    return Card(
      child: ListTile(
        onTap: onTap,
        title: exAsync.when(
          data: (ex) => Text(ex?.name ?? '?'),
          loading: () => const Text('...'),
          error: (e, _) => Text('Erreur: $e'),
        ),
        subtitle: Text(_planSummary(plan)),
        isThreeLine: false,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Modifier le plan',
              onPressed: onTap,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// "4×10 @ 60kg • repos 90s" if every set has the same reps+weight,
/// else "10×60, 8×70, 6×80 • repos 90s".
String _planSummary(TemplateExerciseWithSets plan) {
  final sets = plan.sets;
  if (sets.isEmpty) return 'Aucune série planifiée';
  final allSame = sets.every((s) =>
      s.plannedReps == sets.first.plannedReps &&
      s.plannedWeightKg == sets.first.plannedWeightKg);
  String body;
  if (allSame) {
    final w = sets.first.plannedWeightKg;
    body = '${sets.length}×${sets.first.plannedReps}'
        '${w == null ? '' : ' @ ${_fmtKg(w)}kg'}';
  } else {
    body = sets
        .map((s) => '${s.plannedReps}'
            '${s.plannedWeightKg == null ? '' : '×${_fmtKg(s.plannedWeightKg!)}'}')
        .join(', ');
  }
  final rest = plan.exercise.restSeconds;
  if (rest != null) body += ' • repos ${_fmtRest(rest)}';
  return body;
}

String _fmtKg(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toStringAsFixed(1);
}

String _fmtRest(int s) {
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final r = s % 60;
  return r == 0 ? '${m}min' : '${m}min${r}s';
}

class _ExercisePickerSheet extends ConsumerStatefulWidget {
  final String templateName;
  const _ExercisePickerSheet({this.templateName = ''});
  @override
  ConsumerState<_ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<_ExercisePickerSheet> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(allExercisesProvider);
    final usageCounts =
        ref.watch(exerciseUsageCountsProvider).valueOrNull ?? const {};
    // When the user is typing a search, that's their priority signal.
    // Otherwise we lean on the template name to drive relevance.
    final relevance = _muscleRelevanceFromName(
        _search.isNotEmpty ? _search : widget.templateName);
    final hasRelevance = relevance.isNotEmpty;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
            if (hasRelevance && _search.isEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 14,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Tri intelligent : pertinence + fréquence',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: asyncList.when(
                data: (list) {
                  final filtered = list
                      .where((e) =>
                          _search.isEmpty ||
                          e.name.toLowerCase().contains(_search))
                      .toList();
                  // Sort priorities:
                  //   1. Relevance score (per-token-position, higher = better)
                  //   2. Custom-first ONLY when not actively searching
                  //   3. Frequency
                  //   4. Alphabetical
                  final scored = filtered
                      .map((e) => (
                            e,
                            _relevanceScore(e, relevance),
                            usageCounts[e.id] ?? 0,
                          ))
                      .toList();
                  final pinCustom = _search.isEmpty;
                  scored.sort((a, b) {
                    if (b.$2 != a.$2) return b.$2.compareTo(a.$2);
                    if (pinCustom && a.$1.isCustom != b.$1.isCustom) {
                      return a.$1.isCustom ? -1 : 1;
                    }
                    if (b.$3 != a.$3) return b.$3.compareTo(a.$3);
                    return a.$1.name
                        .toLowerCase()
                        .compareTo(b.$1.name.toLowerCase());
                  });
                  return ListView.builder(
                    controller: controller,
                    itemCount: scored.length,
                    itemBuilder: (_, i) {
                      final ex = scored[i].$1;
                      final isRelevant = scored[i].$2 > 0;
                      final count = scored[i].$3;
                      return ListTile(
                        title: Row(
                          children: [
                            Expanded(child: Text(ex.name)),
                            if (isRelevant)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.auto_awesome,
                                    size: 14, color: Colors.amber),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          count > 0
                              ? '${_muscleLabel(ex.primaryMuscle)} • fait $count fois'
                              : _muscleLabel(ex.primaryMuscle),
                        ),
                        onTap: () => Navigator.pop(context, ex),
                      );
                    },
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Relevance signal computed from the user's free-text input. Returns the
/// list of muscle groups in the order they appear in [title] — earlier
/// tokens get more weight downstream.
List<MuscleGroup> _muscleRelevanceFromName(String title) {
  final t = title.toLowerCase();
  // List of (alias-list, target muscle groups). Push/Pull/Legs etc. expand
  // to the muscles they imply, in a sensible order.
  const rules = <(List<String>, List<MuscleGroup>)>[
    // Categories implying multiple muscles.
    (
      ['push', 'poussée', 'poussee', 'pousser'],
      [
        MuscleGroup.chest,
        MuscleGroup.shoulders,
        MuscleGroup.triceps,
      ]
    ),
    (
      ['pull', 'tirage', 'tirer'],
      [
        MuscleGroup.upperBack,
        MuscleGroup.lats,
        MuscleGroup.biceps,
        MuscleGroup.rearDelts,
      ]
    ),
    (
      ['legs', 'jambe', 'leg ', 'jamb'],
      [
        MuscleGroup.quads,
        MuscleGroup.hamstrings,
        MuscleGroup.glutes,
        MuscleGroup.calves,
      ]
    ),
    (['core', 'gainage'], [MuscleGroup.abs, MuscleGroup.obliques]),
    (['cardio'], [MuscleGroup.cardio]),
    // Single-muscle aliases.
    (
      ['pec', 'pecto', 'chest', 'poitrine'],
      [MuscleGroup.chest]
    ),
    (
      ['epaule', 'épaule', 'shoulder', 'delto'],
      [MuscleGroup.shoulders]
    ),
    (['biceps', 'bicep'], [MuscleGroup.biceps]),
    (['triceps', 'tricep'], [MuscleGroup.triceps]),
    (['avant-bras', 'forearm'], [MuscleGroup.forearms]),
    (['dos', 'back'], [MuscleGroup.upperBack, MuscleGroup.lats]),
    (['lat', 'grand dorsal'], [MuscleGroup.lats]),
    (['lombaire', 'lower back'], [MuscleGroup.lowerBack]),
    (['quad', 'cuisse'], [MuscleGroup.quads]),
    (['ischio', 'hamstring'], [MuscleGroup.hamstrings]),
    (['fessier', 'glute'], [MuscleGroup.glutes]),
    (['mollet', 'calve'], [MuscleGroup.calves]),
    (['abdo', 'abs '], [MuscleGroup.abs]),
    (['oblique'], [MuscleGroup.obliques]),
  ];
  // Find the earliest alias position for each muscle group across all rules.
  final firstHit = <MuscleGroup, int>{};
  for (final rule in rules) {
    final aliases = rule.$1;
    final muscles = rule.$2;
    var earliest = -1;
    for (final a in aliases) {
      final idx = t.indexOf(a);
      if (idx < 0) continue;
      if (earliest < 0 || idx < earliest) earliest = idx;
    }
    if (earliest < 0) continue;
    for (final m in muscles) {
      final prev = firstHit[m];
      if (prev == null || earliest < prev) firstHit[m] = earliest;
    }
  }
  final ordered = firstHit.keys.toList()
    ..sort((a, b) => firstHit[a]!.compareTo(firstHit[b]!));
  return ordered;
}

/// Higher = more relevant. The earlier a muscle appeared in the user's
/// input, the more its hit is worth — so "biceps pec" puts biceps exos
/// before chest exos. Only the primary muscle counts: secondary muscles
/// are noise for relevance ("dev couché" travaillerait aussi triceps mais
/// on veut surtout des exos pec en tête).
int _relevanceScore(Exercise ex, List<MuscleGroup> ordered) {
  if (ordered.isEmpty) return 0;
  final n = ordered.length;
  final pIdx = ordered.indexOf(ex.primaryMuscle);
  if (pIdx < 0) return 0;
  return (n - pIdx) * 3;
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

/// Bottom sheet to plan an exercise inside a template:
///   - sets count
///   - rest between sets
///   - per-set reps + weight (with "same for all" toggle)
class _PlanEditorSheet extends ConsumerStatefulWidget {
  final Exercise exercise;
  final TemplateExerciseWithSets initial;
  /// When true, the editor tries to seed reps/weights from the user's most
  /// recent matching session — typically when adding a brand new exo.
  final bool prefillFromHistory;
  const _PlanEditorSheet({
    required this.exercise,
    required this.initial,
    this.prefillFromHistory = false,
  });
  @override
  ConsumerState<_PlanEditorSheet> createState() => _PlanEditorSheetState();
}

class _PlanEditorSheetState extends ConsumerState<_PlanEditorSheet> {
  late List<TemplateExerciseSet> _sets;
  late int _restSeconds;
  late bool _sameForAll;
  bool _userTouched = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _sets = widget.initial.sets.map((s) => s.copyWith()).toList();
    if (_sets.isEmpty) {
      _sets = [_makeSet(0, 8, widget.exercise.useBodyweight ? null : 20)];
    }
    _restSeconds = widget.initial.exercise.restSeconds ?? 90;
    _sameForAll = _sets.every((s) =>
        s.plannedReps == _sets.first.plannedReps &&
        s.plannedWeightKg == _sets.first.plannedWeightKg);
    if (widget.prefillFromHistory) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runPrefill());
    }
  }

  /// Looks up the user's most recent matching session for this exercise and
  /// seeds the plan with those reps/weights. Tries to match the current
  /// sets count exactly; falls back to the latest occurrence.
  Future<void> _runPrefill({bool force = false}) async {
    if (!widget.prefillFromHistory) return;
    if (_userTouched && !force) return;
    final sets = await ref
        .read(sessionRepositoryProvider)
        .findBestMatchingSets(
          exerciseId: widget.exercise.id,
          preferSetCount: _sets.length,
        );
    if (!mounted || sets.isEmpty) return;
    if (_userTouched && !force) return;
    setState(() {
      _sets = [
        for (var i = 0; i < _sets.length; i++)
          _sets[i].copyWith(
            plannedReps:
                i < sets.length ? sets[i].reps : sets.last.reps,
            plannedWeightKg: i < sets.length
                ? sets[i].weightKg
                : sets.last.weightKg,
          ),
      ];
      // Re-evaluate "same for all" after the prefill.
      _sameForAll = _sets.every((s) =>
          s.plannedReps == _sets.first.plannedReps &&
          s.plannedWeightKg == _sets.first.plannedWeightKg);
      _prefilled = true;
    });
  }

  TemplateExerciseSet _makeSet(int idx, int reps, double? weight) {
    return TemplateExerciseSet(
      id: const Uuid().v4(),
      templateExerciseId: widget.initial.exercise.id,
      setIndex: idx,
      plannedReps: reps,
      plannedWeightKg: weight,
    );
  }

  void _setSetsCount(int count) {
    final clamped = count.clamp(1, 20);
    if (clamped == _sets.length) return;
    setState(() {
      if (clamped > _sets.length) {
        final ref = _sets.last;
        for (var i = _sets.length; i < clamped; i++) {
          _sets.add(_makeSet(i, ref.plannedReps, ref.plannedWeightKg));
        }
      } else {
        _sets = _sets.sublist(0, clamped);
      }
    });
    // If the user hasn't manually edited yet, re-search for a session
    // that matches the new sets count exactly.
    if (!_userTouched) {
      _runPrefill();
    }
  }

  void _updateSet(int i,
      {int? reps, double? weight, bool clearWeight = false}) {
    _userTouched = true;
    setState(() {
      final updated = _sets[i].copyWith(
        plannedReps: reps,
        plannedWeightKg: weight,
        clearPlannedWeightKg: clearWeight,
      );
      if (_sameForAll) {
        // Apply to every set so they stay in sync.
        for (var j = 0; j < _sets.length; j++) {
          _sets[j] = _sets[j].copyWith(
            plannedReps: updated.plannedReps,
            plannedWeightKg: updated.plannedWeightKg,
            clearPlannedWeightKg: updated.plannedWeightKg == null,
          );
        }
      } else {
        _sets[i] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isBw = widget.exercise.useBodyweight;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.exercise.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Planifie cet exo : nombre de séries, repos, et reps/poids '
              'pour chaque série.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (_prefilled && !_userTouched) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Icon(Icons.history,
                      size: 16,
                      color:
                          Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Pré-rempli depuis ta dernière séance avec cet exo.',
                      style:
                          Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _LabelStepper(
                    label: 'Séries',
                    value: _sets.length.toString(),
                    onMinus: () => _setSetsCount(_sets.length - 1),
                    onPlus: () => _setSetsCount(_sets.length + 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _RestField(
                  seconds: _restSeconds,
                  onChanged: (v) => setState(() => _restSeconds = v),
                )),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Même reps/poids pour toutes les séries'),
              subtitle: const Text(
                  'Pratique pour un classique 4×10. Désactive pour des '
                  'séries dégressives ou variables.'),
              value: _sameForAll,
              onChanged: (v) => setState(() {
                _sameForAll = v;
                if (v && _sets.isNotEmpty) {
                  // Force-sync everyone to set #1.
                  final ref = _sets.first;
                  for (var i = 0; i < _sets.length; i++) {
                    _sets[i] = _sets[i].copyWith(
                      plannedReps: ref.plannedReps,
                      plannedWeightKg: ref.plannedWeightKg,
                      clearPlannedWeightKg: ref.plannedWeightKg == null,
                    );
                  }
                }
              }),
            ),
            const Divider(),
            for (var i = 0; i < _sets.length; i++)
              _PlanSetRow(
                index: i,
                set: _sets[i],
                isBodyweight: isBw,
                editable: !_sameForAll || i == 0,
                onChange: (reps, weight) => _updateSet(
                  i,
                  reps: reps,
                  weight: weight,
                  clearWeight: weight == null && isBw,
                ),
              ),
            const SizedBox(height: 16),
            Row(
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
                    onPressed: () {
                      Navigator.pop(
                        context,
                        TemplateExerciseWithSets(
                          exercise: widget.initial.exercise.copyWith(
                            targetSets: _sets.length,
                            restSeconds: _restSeconds,
                          ),
                          sets: [
                            for (var i = 0; i < _sets.length; i++)
                              _sets[i].copyWith(setIndex: i),
                          ],
                        ),
                      );
                    },
                    child: const Text('Enregistrer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelStepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _LabelStepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: onMinus,
                visualDensity: VisualDensity.compact,
              ),
              Text(value,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: onPlus,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RestField extends StatefulWidget {
  final int seconds;
  final ValueChanged<int> onChanged;
  const _RestField({required this.seconds, required this.onChanged});
  @override
  State<_RestField> createState() => _RestFieldState();
}

class _RestFieldState extends State<_RestField> {
  late TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.seconds.toString());
  }

  @override
  void didUpdateWidget(_RestField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync if the prop actually changed; otherwise an empty in-flight
    // edit gets reset to the previous value before the user can finish.
    if (oldWidget.seconds != widget.seconds) {
      _ctrl.text = widget.seconds.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Repos (s)',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        final parsed = int.tryParse(v);
        if (parsed != null && parsed >= 0) widget.onChanged(parsed);
      },
    );
  }
}

class _PlanSetRow extends StatefulWidget {
  final int index;
  final TemplateExerciseSet set;
  final bool isBodyweight;
  final bool editable;
  final void Function(int reps, double? weight) onChange;
  const _PlanSetRow({
    required this.index,
    required this.set,
    required this.isBodyweight,
    required this.editable,
    required this.onChange,
  });
  @override
  State<_PlanSetRow> createState() => _PlanSetRowState();
}

class _PlanSetRowState extends State<_PlanSetRow> {
  late TextEditingController _repsCtrl;
  late TextEditingController _weightCtrl;

  @override
  void initState() {
    super.initState();
    _repsCtrl =
        TextEditingController(text: widget.set.plannedReps.toString());
    _weightCtrl = TextEditingController(
      text: widget.set.plannedWeightKg == null
          ? ''
          : _fmtKg(widget.set.plannedWeightKg!),
    );
  }

  @override
  void didUpdateWidget(covariant _PlanSetRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only sync from props when the prop *actually changed* (e.g. when
    // "same for all" propagates a new value to other rows, or when the
    // sets count grows). Otherwise we'd overwrite the user's empty field
    // mid-edit, which made deleting a single-digit value impossible.
    if (oldWidget.set.plannedReps != widget.set.plannedReps) {
      _repsCtrl.text = widget.set.plannedReps.toString();
    }
    if (oldWidget.set.plannedWeightKg != widget.set.plannedWeightKg) {
      _weightCtrl.text = widget.set.plannedWeightKg == null
          ? ''
          : _fmtKg(widget.set.plannedWeightKg!);
    }
  }

  @override
  void dispose() {
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    // Empty reps box → user is mid-edit. Don't call back so the parent
    // doesn't overwrite the field on the next rebuild.
    if (_repsCtrl.text.trim().isEmpty) return;
    final reps = int.tryParse(_repsCtrl.text) ?? widget.set.plannedReps;
    final w = _weightCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    widget.onChange(reps, w);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              'Série ${widget.index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _repsCtrl,
              keyboardType: TextInputType.number,
              enabled: widget.editable,
              decoration: const InputDecoration(
                labelText: 'reps',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _emit(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _weightCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: widget.editable,
              decoration: InputDecoration(
                labelText:
                    widget.isBodyweight ? '+kg (optionnel)' : 'kg',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => _emit(),
            ),
          ),
        ],
      ),
    );
  }
}
