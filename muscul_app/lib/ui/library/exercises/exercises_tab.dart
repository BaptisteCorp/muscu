import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/exercise.dart';

class ExercisesTab extends ConsumerStatefulWidget {
  const ExercisesTab({super.key});
  @override
  ConsumerState<ExercisesTab> createState() => _ExercisesTabState();
}

class _ExercisesTabState extends ConsumerState<ExercisesTab> {
  String _search = '';
  MuscleGroup? _muscle;

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(allExercisesProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Rechercher...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v.toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<MuscleGroup?>(
                value: _muscle,
                hint: const Text('Tous muscles'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous')),
                  for (final m in MuscleGroup.values)
                    DropdownMenuItem(value: m, child: Text(muscleLabel(m))),
                ],
                onChanged: (v) => setState(() => _muscle = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: asyncList.when(
            data: (list) {
              final filtered = list.where((e) {
                final matchesSearch =
                    _search.isEmpty || e.name.toLowerCase().contains(_search);
                // Filter on primary muscle only — the muscle a user thinks
                // of when picking "exos pour les pecs" is the primary one.
                final matchesMuscle =
                    _muscle == null || e.primaryMuscle == _muscle;
                return matchesSearch && matchesMuscle;
              }).toList()
                ..sort((a, b) {
                  // Custom-first ONLY when not actively searching, then alpha.
                  if (_search.isEmpty && a.isCustom != b.isCustom) {
                    return a.isCustom ? -1 : 1;
                  }
                  return a.name
                      .toLowerCase()
                      .compareTo(b.name.toLowerCase());
                });
              if (filtered.isEmpty) {
                return const Center(child: Text('Aucun exercice'));
              }
              return ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => _ExerciseTile(filtered[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Erreur: $e')),
          ),
        ),
      ],
    );
  }
}

class _ExerciseTile extends ConsumerWidget {
  final Exercise exercise;
  const _ExerciseTile(this.exercise);

  Future<bool> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Supprimer cet exercice ?'),
        content: const Text(
            "L'historique des séances passées reste intact, mais l'exo "
            "ne sera plus proposé."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = ListTile(
      leading: _Thumbnail(path: exercise.photoPath),
      title: Row(children: [
        Expanded(child: Text(exercise.name)),
        if (exercise.isCustom)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.person, size: 14, color: Colors.amber),
          ),
      ]),
      subtitle: Text(
        '${muscleLabel(exercise.primaryMuscle)} • ${exercise.equipment.label}',
      ),
      trailing: exercise.isCustom
          ? const Icon(Icons.edit_outlined, size: 18)
          : const Icon(Icons.lock_outline, size: 18),
      onTap: () => context.push('/library/exercise/${exercise.id}'),
    );
    // Default-seeded exercises are read-only.
    if (!exercise.isCustom) return tile;
    return Dismissible(
      key: ValueKey('exo_${exercise.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) async {
        await ref.read(exerciseRepositoryProvider).softDelete(exercise.id);
        try {
          await ref.read(syncServiceProvider).pushExercise(exercise.id);
        } catch (_) {/* periodic sync will retry */}
      },
      child: tile,
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  final String? path;
  const _Thumbnail({this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (path == null) {
      return const CircleAvatar(child: Icon(Icons.fitness_center));
    }
    return FutureBuilder<File?>(
      future: ref.read(photoStorageProvider).resolve(path),
      builder: (_, snap) {
        if (snap.data == null) {
          return const CircleAvatar(child: Icon(Icons.fitness_center));
        }
        return CircleAvatar(backgroundImage: FileImage(snap.data!));
      },
    );
  }
}

