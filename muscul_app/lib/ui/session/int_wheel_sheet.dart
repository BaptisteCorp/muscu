import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ouvre un bottom sheet à molette unique pour choisir un entier dans
/// [min]..[max]. Retourne la valeur choisie, ou null si annulé. Sert aux reps
/// et au RPE/RIR (le poids a son propre sheet à deux molettes).
Future<int?> showIntWheel(
  BuildContext context, {
  required String title,
  required int min,
  required int max,
  required int initial,
  String unit = '',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IntWheelSheet(
      title: title,
      min: min,
      max: max,
      initial: initial,
      unit: unit,
    ),
  );
}

class _IntWheelSheet extends StatefulWidget {
  final String title;
  final int min;
  final int max;
  final int initial;
  final String unit;
  const _IntWheelSheet({
    required this.title,
    required this.min,
    required this.max,
    required this.initial,
    required this.unit,
  });

  @override
  State<_IntWheelSheet> createState() => _IntWheelSheetState();
}

class _IntWheelSheetState extends State<_IntWheelSheet> {
  late int _idx;
  late FixedExtentScrollController _ctrl;

  int get _count => widget.max - widget.min + 1;
  int get _value => widget.min + _idx;

  @override
  void initState() {
    super.initState();
    final clamped = widget.initial.clamp(widget.min, widget.max);
    _idx = clamped - widget.min;
    _ctrl = FixedExtentScrollController(initialItem: _idx);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Center(
              child: Text(
                widget.unit.isEmpty ? '$_value' : '$_value ${widget.unit}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                  ListWheelScrollView.useDelegate(
                    controller: _ctrl,
                    itemExtent: 42,
                    perspective: 0.003,
                    diameterRatio: 1.8,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) {
                      HapticFeedback.selectionClick();
                      setState(() => _idx = i);
                    },
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (context, i) {
                        if (i < 0 || i >= _count) return null;
                        return Center(
                          child: Text(
                            '${widget.min + i}',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        );
                      },
                      childCount: _count,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _value),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
