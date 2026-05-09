import 'package:flutter/material.dart';

/// Résultat retourné par [RestEditSheet] : durée choisie + flag "réinitialiser
/// pour utiliser le repos par défaut de l'exo".
class RestEditResult {
  final int seconds;
  final bool reset;
  const RestEditResult({required this.seconds, this.reset = false});
}

/// Bottom sheet pour ajuster la durée de repos d'un exo en cours de séance.
/// Affiche la valeur par défaut, permet +/- 15s ou 30s, presets, et un
/// bouton "Réinitialiser" si l'utilisateur avait déjà override.
class RestEditSheet extends StatefulWidget {
  final int initialSeconds;
  final bool isOverridden;
  final int defaultSeconds;
  const RestEditSheet({
    super.key,
    required this.initialSeconds,
    required this.isOverridden,
    required this.defaultSeconds,
  });

  @override
  State<RestEditSheet> createState() => _RestEditSheetState();
}

class _RestEditSheetState extends State<RestEditSheet> {
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
  }

  String _format(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '${m}min' : '${m}min ${r}s';
  }

  void _adjust(int delta) {
    setState(() {
      _seconds = (_seconds + delta).clamp(0, 60 * 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Repos pour cet exercice',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Par défaut : ${_format(widget.defaultSeconds)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                FilledButton.tonal(
                  onPressed: () => _adjust(-30),
                  child: const Text('-30s'),
                ),
                FilledButton.tonal(
                  onPressed: () => _adjust(-15),
                  child: const Text('-15s'),
                ),
                Text(
                  _format(_seconds),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                FilledButton.tonal(
                  onPressed: () => _adjust(15),
                  child: const Text('+15s'),
                ),
                FilledButton.tonal(
                  onPressed: () => _adjust(30),
                  child: const Text('+30s'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final preset in const [60, 90, 120, 150, 180, 240, 300])
                  ChoiceChip(
                    label: Text(_format(preset)),
                    selected: _seconds == preset,
                    onSelected: (_) => setState(() => _seconds = preset),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.isOverridden)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const RestEditResult(seconds: 0, reset: true),
                      ),
                      child: const Text('Réinitialiser'),
                    ),
                  ),
                if (widget.isOverridden) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      RestEditResult(seconds: _seconds),
                    ),
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
