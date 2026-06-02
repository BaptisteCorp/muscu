import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom sheet pour régler le poids d'une série à la main, en complément des
/// boutons +/- (qui avancent par incrément). Deux molettes : kilos entiers
/// (qui défilent kilo par kilo) et fraction (.0 / .25 / .5 / .75) pour coller
/// au montage des disques. Retourne le poids choisi, ou null si annulé.
class WeightEditSheet extends StatefulWidget {
  final double initialKg;

  /// Autorise les poids négatifs (lest assisté en poids du corps).
  final bool allowNegative;

  /// Libellé affiché ("kg" ou "+kg" pour le poids du corps).
  final String unitLabel;

  const WeightEditSheet({
    super.key,
    required this.initialKg,
    this.allowNegative = false,
    this.unitLabel = 'kg',
  });

  @override
  State<WeightEditSheet> createState() => _WeightEditSheetState();
}

class _WeightEditSheetState extends State<WeightEditSheet> {
  static const _fractions = [0.0, 0.25, 0.5, 0.75];
  static const _maxKg = 500;

  late int _minKg;
  late int _wholeIdx; // index dans la plage [_minKg .. _maxKg]
  late int _fracIdx;
  late FixedExtentScrollController _wholeCtrl;
  late FixedExtentScrollController _fracCtrl;

  int get _wholeCount => _maxKg - _minKg + 1;
  double get _weight => (_minKg + _wholeIdx) + _fractions[_fracIdx];

  @override
  void initState() {
    super.initState();
    _minKg = widget.allowNegative ? -50 : 0;
    final clamped = widget.initialKg.clamp(_minKg.toDouble(), _maxKg.toDouble());
    // floor() gère bien le négatif : floor(-1.5) = -2, fraction = 0.5.
    final whole = clamped.floor();
    final rawFrac = clamped - whole;
    _wholeIdx = (whole - _minKg).clamp(0, _wholeCount - 1);
    _fracIdx = _nearestFractionIndex(rawFrac);
    _wholeCtrl = FixedExtentScrollController(initialItem: _wholeIdx);
    _fracCtrl = FixedExtentScrollController(initialItem: _fracIdx);
  }

  int _nearestFractionIndex(double frac) {
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < _fractions.length; i++) {
      final d = (_fractions[i] - frac).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void dispose() {
    _wholeCtrl.dispose();
    _fracCtrl.dispose();
    super.dispose();
  }

  String _format(double kg) {
    // Pas de .0 inutile ; .5 sur une décimale ; .25/.75 sur deux.
    final String r;
    if (kg == kg.roundToDouble()) {
      r = kg.toStringAsFixed(0);
    } else if ((kg * 2) == (kg * 2).roundToDouble()) {
      r = kg.toStringAsFixed(1);
    } else {
      r = kg.toStringAsFixed(2);
    }
    return '$r ${widget.unitLabel}';
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
              'Poids de la série',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            // Live total — also the picker title.
            Center(
              child: Text(
                _format(_weight),
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
                        flex: 2,
                        child: _Wheel(
                          controller: _wholeCtrl,
                          count: _wholeCount,
                          formatItem: (i) => (_minKg + i).toString(),
                          unit: 'kg',
                          onChanged: (i) {
                            HapticFeedback.selectionClick();
                            setState(() => _wholeIdx = i);
                          },
                        ),
                      ),
                      Expanded(
                        child: _Wheel(
                          controller: _fracCtrl,
                          count: _fractions.length,
                          formatItem: (i) =>
                              '.${(_fractions[i] * 100).toInt().toString().padLeft(2, '0')}',
                          unit: '',
                          onChanged: (i) {
                            HapticFeedback.selectionClick();
                            setState(() => _fracIdx = i);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(context, _weight),
              child: const Text('Enregistrer'),
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
        if (unit.isNotEmpty)
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
