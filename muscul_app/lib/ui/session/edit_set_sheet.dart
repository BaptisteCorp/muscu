import 'package:flutter/material.dart';

import '../../domain/models/session.dart';

/// Bottom sheet pour éditer une série déjà validée (reps, poids, RPE).
class EditSetSheet extends StatefulWidget {
  final SetEntry entry;
  const EditSetSheet({super.key, required this.entry});

  @override
  State<EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<EditSetSheet> {
  late TextEditingController repsCtrl;
  late TextEditingController weightCtrl;
  late TextEditingController rpeCtrl;

  @override
  void initState() {
    super.initState();
    repsCtrl = TextEditingController(text: widget.entry.reps.toString());
    weightCtrl =
        TextEditingController(text: widget.entry.weightKg.toString());
    rpeCtrl = TextEditingController(text: widget.entry.rpe?.toString() ?? '');
  }

  @override
  void dispose() {
    repsCtrl.dispose();
    weightCtrl.dispose();
    rpeCtrl.dispose();
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
            Text('Série ${widget.entry.setIndex + 1}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: repsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Reps', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Poids (kg)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: rpeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'RPE', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final reps = int.tryParse(repsCtrl.text) ?? widget.entry.reps;
                final w = double.tryParse(weightCtrl.text) ??
                    widget.entry.weightKg;
                final rpe =
                    rpeCtrl.text.isEmpty ? null : int.tryParse(rpeCtrl.text);
                Navigator.pop(
                  context,
                  widget.entry.copyWith(
                    reps: reps,
                    weightKg: w,
                    rpe: rpe,
                    clearRpe: rpe == null,
                  ),
                );
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
