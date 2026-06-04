import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/sync/sync_service.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/exercise.dart';

const _uuid = Uuid();

/// Minimal "create an exercise on the fly" sheet (name + primary muscle +
/// equipment). Persists the new custom exercise, pushes it to the cloud, and
/// pops with the created [Exercise]. Shared between the in-session quick-swap
/// flow and the template builder's exercise picker so a missing exercise can
/// be created without leaving the screen.
class QuickCreateExerciseForm extends ConsumerStatefulWidget {
  /// Label for the confirm button — wording differs by caller
  /// ("Créer & substituer" in a session, "Créer & ajouter" in a template).
  final String ctaLabel;
  const QuickCreateExerciseForm({super.key, this.ctaLabel = 'Créer'});

  @override
  ConsumerState<QuickCreateExerciseForm> createState() =>
      _QuickCreateExerciseFormState();
}

class _QuickCreateExerciseFormState
    extends ConsumerState<QuickCreateExerciseForm> {
  final _nameCtrl = TextEditingController();
  MuscleGroup _muscle = MuscleGroup.chest;
  Equipment _equipment = Equipment.barbell;
  bool _showErrors = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

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
                ref.read(syncServiceProvider).pushExercise(ex.id).ignore();
                if (mounted) Navigator.pop(context, ex);
              },
              child: Text(widget.ctaLabel),
            ),
          ],
        ),
      ),
    );
  }
}
