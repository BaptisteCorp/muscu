import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../core/utils/formatters.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/exercise.dart';

const _uuid = Uuid();

/// Substitution rapide en cours de séance.
///
/// 1. Suggestions intelligentes (même primaryMuscle + même category)
/// 2. Recherche
/// 3. Création à la volée (3 champs)
class QuickSwapSheet extends ConsumerStatefulWidget {
  /// If null, this sheet is used to add a brand-new exercise to the session
  /// (no "current" reference for suggestions).
  final String? currentExerciseId;
  const QuickSwapSheet({super.key, this.currentExerciseId});

  @override
  ConsumerState<QuickSwapSheet> createState() => _QuickSwapSheetState();
}

class _QuickSwapSheetState extends ConsumerState<QuickSwapSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(allExercisesProvider);
    final currentAsync = widget.currentExerciseId == null
        ? const AsyncValue<Exercise?>.data(null)
        : ref.watch(exerciseByIdProvider(widget.currentExerciseId!));

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, MediaQuery.of(context).viewInsets.bottom + 8),
        child: Column(
          children: [
            Text(
              widget.currentExerciseId == null
                  ? 'Ajouter un exercice'
                  : 'Substituer cet exercice',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: asyncList.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Erreur: $e')),
                data: (all) {
                  final current = currentAsync.valueOrNull;
                  final suggestions = _suggestions(all, current);
                  return Column(
                    children: [
                      if (suggestions.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Suggestions',
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemCount: suggestions.length,
                            itemBuilder: (_, i) => _SuggestionCard(
                              exercise: suggestions[i],
                              onTap: () =>
                                  Navigator.pop(context, suggestions[i]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Rechercher dans tout le catalogue...',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => _search = v.toLowerCase()),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Builder(builder: (_) {
                          final filtered = (_search.isEmpty
                                  ? [...all]
                                  : all
                                      .where((e) => e.name
                                          .toLowerCase()
                                          .contains(_search))
                                      .toList())
                            ..sort((a, b) {
                              // Custom-first only when not actively searching.
                              if (_search.isEmpty &&
                                  a.isCustom != b.isCustom) {
                                return a.isCustom ? -1 : 1;
                              }
                              return a.name
                                  .toLowerCase()
                                  .compareTo(b.name.toLowerCase());
                            });
                          return ListView.builder(
                            controller: controller,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => ListTile(
                              title: Text(filtered[i].name),
                              subtitle: Text(filtered[i].primaryMuscle.name),
                              onTap: () =>
                                  Navigator.pop(context, filtered[i]),
                            ),
                          );
                        }),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('+ Nouvel exo rapide'),
                          onPressed: () => _quickCreate(context),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Exercise> _suggestions(List<Exercise> all, Exercise? current) {
    if (current == null) return [];
    final suggestions = all.where((e) {
      if (e.id == current.id) return false;
      return e.primaryMuscle == current.primaryMuscle &&
          e.category == current.category;
    }).toList();
    return suggestions.take(8).toList();
  }

  Future<void> _quickCreate(BuildContext context) async {
    final ex = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _QuickCreateForm(),
    );
    if (ex != null && context.mounted) Navigator.pop(context, ex);
  }
}

class _SuggestionCard extends StatelessWidget {
  final Exercise exercise;
  final VoidCallback onTap;
  const _SuggestionCard({required this.exercise, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exercise.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(exercise.equipment.name,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCreateForm extends ConsumerStatefulWidget {
  const _QuickCreateForm();
  @override
  ConsumerState<_QuickCreateForm> createState() => _QuickCreateFormState();
}

class _QuickCreateFormState extends ConsumerState<_QuickCreateForm> {
  final _nameCtrl = TextEditingController();
  MuscleGroup _muscle = MuscleGroup.chest;
  Equipment _equipment = Equipment.barbell;
  bool _showErrors = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Création rapide',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
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
              value: _muscle,
              decoration: const InputDecoration(
                labelText: 'Muscle principal',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in MuscleGroup.values)
                  DropdownMenuItem(value: m, child: Text(muscleLabel(m))),
              ],
              onChanged: (v) => setState(() => _muscle = v!),
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
              onChanged: (v) => setState(() => _equipment = v!),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final name = _nameCtrl.text.trim();
                if (name.isEmpty) {
                  setState(() => _showErrors = true);
                  return;
                }
                final ex = Exercise(
                  id: _uuid.v4(),
                  name: name,
                  category: categoryFromMuscle(_muscle),
                  primaryMuscle: _muscle,
                  secondaryMuscles: const [],
                  equipment: _equipment,
                  isCustom: true,
                  targetRepRangeMin: 8,
                  targetRepRangeMax: 12,
                  startingWeightKg:
                      _equipment == Equipment.bodyweight ? 0.0 : 20.0,
                  updatedAt: DateTime.now(),
                );
                await ref.read(exerciseRepositoryProvider).upsert(ex);
                if (mounted) Navigator.pop(context, ex);
              },
              child: const Text('Créer & substituer'),
            ),
          ],
        ),
      ),
    );
  }

}
