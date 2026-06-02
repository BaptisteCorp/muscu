import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Résultat retourné par [RestEditSheet] : durée choisie + flag "réinitialiser
/// pour utiliser le repos par défaut de l'exo".
class RestEditResult {
  final int seconds;
  final bool reset;
  const RestEditResult({required this.seconds, this.reset = false});
}

/// Bottom sheet pour ajuster la durée de repos d'un exo en cours de séance.
/// Deux molettes scrollables (style picker Android) — minutes et secondes
/// par pas de 5s — plutôt que des boutons +/-15s : on règle la durée d'un
/// seul flick, sans avoir à compter ses taps.
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
  static const _secStep = 5;
  static const _minCount = 16; // 0..15 min
  static const _secCount = 12; // 0, 5, 10 … 55

  late int _minIdx;
  late int _secIdx;
  late FixedExtentScrollController _minCtrl;
  late FixedExtentScrollController _secCtrl;

  int get _seconds => _minIdx * 60 + _secIdx * _secStep;

  @override
  void initState() {
    super.initState();
    final clamped =
        widget.initialSeconds.clamp(0, (_minCount - 1) * 60 + 55);
    _minIdx = clamped ~/ 60;
    // Snap the seconds part to the nearest 5s so we land on a wheel slot.
    final rawSec = clamped % 60;
    _secIdx = (rawSec / _secStep).round().clamp(0, _secCount - 1);
    _minCtrl = FixedExtentScrollController(initialItem: _minIdx);
    _secCtrl = FixedExtentScrollController(initialItem: _secIdx);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _secCtrl.dispose();
    super.dispose();
  }

  String _format(int s) {
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    final r = s % 60;
    return r == 0 ? '${m}min' : '${m}min ${r}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            // Live total — also the picker title.
            Center(
              child: Text(
                _format(_seconds),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Selection band behind both wheels.
                  IgnorePointer(
                    child: Container(
                      height: 42,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border(
                          top: BorderSide(color: cs.outlineVariant),
                          bottom: BorderSide(color: cs.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _Wheel(
                          controller: _minCtrl,
                          count: _minCount,
                          formatItem: (i) => i.toString().padLeft(2, '0'),
                          unit: 'min',
                          onChanged: (i) {
                            HapticFeedback.selectionClick();
                            setState(() => _minIdx = i);
                          },
                        ),
                      ),
                      Expanded(
                        child: _Wheel(
                          controller: _secCtrl,
                          count: _secCount,
                          formatItem: (i) =>
                              (i * _secStep).toString().padLeft(2, '0'),
                          unit: 'sec',
                          onChanged: (i) {
                            HapticFeedback.selectionClick();
                            setState(() => _secIdx = i);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

class _Wheel extends StatelessWidget {
  final FixedExtentScrollController controller;
  final int count;
  final String Function(int) formatItem;
  final String unit;
  final ValueChanged<int> onChanged;
  const _Wheel({
    required this.controller,
    required this.count,
    required this.formatItem,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        ListWheelScrollView.useDelegate(
          controller: controller,
          itemExtent: 42,
          // Subtle 3D feel without bending the digits too much.
          perspective: 0.003,
          diameterRatio: 1.8,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: onChanged,
          childDelegate: ListWheelChildBuilderDelegate(
            builder: (context, i) {
              if (i < 0 || i >= count) return null;
              return Center(
                child: Text(
                  formatItem(i),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              );
            },
            childCount: count,
          ),
        ),
        // Unit label sitting next to the center value. IgnorePointer so it
        // doesn't eat the wheel's drag gestures.
        Positioned(
          right: 8,
          child: IgnorePointer(
            child: Text(
              unit,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
