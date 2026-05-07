import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/session.dart';

enum SetRowState { completed, active, pending, skipped }

/// Inline row for a single set: shows steppers when active, recap when validated,
/// a placeholder when pending, or a strikethrough label when skipped.
///
/// Built for one-handed use mid-workout — every interactive element meets the
/// 56pt comfort target so a sweaty thumb won't miss.
class SetRow extends StatelessWidget {
  final int setIndex;
  final SetEntry? entry;
  final int reps;
  final double weightKg;
  final int? rpe;
  final double incrementKg;
  final SetRowState state;
  final bool useRir;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int?> onRpeChanged;
  final VoidCallback onValidate;
  final VoidCallback? onSkip;
  final VoidCallback? onUnskip;
  final VoidCallback? onTap;
  final String? bodyweightLabel;

  const SetRow({
    super.key,
    required this.setIndex,
    required this.entry,
    required this.reps,
    required this.weightKg,
    required this.rpe,
    required this.incrementKg,
    required this.state,
    required this.useRir,
    required this.onRepsChanged,
    required this.onWeightChanged,
    required this.onRpeChanged,
    required this.onValidate,
    this.onSkip,
    this.onUnskip,
    this.onTap,
    this.bodyweightLabel,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case SetRowState.completed:
        return _completed(context);
      case SetRowState.skipped:
        return _skipped(context);
      case SetRowState.pending:
        return _pending(context);
      case SetRowState.active:
        return _active(context);
    }
  }

  Widget _completed(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final weightStr = bodyweightLabel != null
        ? bodyweightLabel!
        : '${_fmt(entry!.weightKg)} kg';
    final rpeText = entry!.rpe != null
        ? '${useRir ? "RIR" : "RPE"} ${useRir ? (10 - entry!.rpe!) : entry!.rpe}'
        : null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            _SetIndexBadge(index: setIndex, completed: true),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontSize: 16,
                ),
                child: Row(
                  children: [
                    Text(
                      '${entry!.reps}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    Text(' × ', style: TextStyle(color: cs.onSurfaceVariant)),
                    Text(
                      weightStr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    if (rpeText != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius:
                              BorderRadius.circular(AppTokens.radiusS),
                        ),
                        child: Text(
                          rpeText,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Icon(Icons.edit_outlined, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _skipped(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _SetIndexBadge(index: setIndex, skipped: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Passée',
              style: TextStyle(
                color: muted,
                fontStyle: FontStyle.italic,
                fontSize: 14,
                decoration: TextDecoration.lineThrough,
                decorationColor: muted,
              ),
            ),
          ),
          if (onUnskip != null)
            TextButton(
              onPressed: onUnskip,
              child: const Text('Annuler'),
            ),
        ],
      ),
    );
  }

  Widget _pending(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _SetIndexBadge(index: setIndex),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$reps × ${_fmt(weightKg)} kg',
                    style: TextStyle(
                      color: muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '   à venir',
                    style: TextStyle(
                      color: muted.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onSkip != null)
            IconButton(
              icon: const Icon(Icons.skip_next_outlined),
              tooltip: 'Passer cette série',
              onPressed: onSkip,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _active(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUpdate = entry != null;
    return Container(
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.07),
        border: Border(
          left: BorderSide(color: cs.primary, width: 3),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SetIndexBadge(index: setIndex, active: true),
              const SizedBox(width: 10),
              Text(
                'EN COURS',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BigStepper(
                  label: 'reps',
                  value: reps.toString(),
                  onMinus: () => onRepsChanged((reps - 1).clamp(1, 999)),
                  onPlus: () => onRepsChanged(reps + 1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStepper(
                  label: bodyweightLabel != null ? '+kg' : 'kg',
                  value: _fmt(weightKg),
                  onMinus: () => onWeightChanged(
                    bodyweightLabel != null
                        ? (weightKg - incrementKg)
                        : (weightKg - incrementKg)
                            .clamp(0, 9999)
                            .toDouble(),
                  ),
                  onPlus: () => onWeightChanged(weightKg + incrementKg),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BigStepper(
                  label: useRir ? 'RIR' : 'RPE',
                  value: rpe == null
                      ? '—'
                      : (useRir ? (10 - rpe!).toString() : rpe!.toString()),
                  onMinus: () {
                    final cur = rpe ?? 8;
                    onRpeChanged((cur - 1).clamp(1, 10));
                  },
                  onPlus: () {
                    final cur = rpe ?? 8;
                    onRpeChanged((cur + 1).clamp(1, 10));
                  },
                  onInfo: () => _showRpeInfo(context, useRir),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: AppTokens.tapTargetXL,
                  child: FilledButton(
                    onPressed: onValidate,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusM),
                      ),
                    ),
                    child: Text(isUpdate ? 'METTRE À JOUR' : 'VALIDER'),
                  ),
                ),
              ),
              if (onSkip != null) ...[
                const SizedBox(width: 8),
                SizedBox(
                  height: AppTokens.tapTargetXL,
                  width: AppTokens.tapTargetXL,
                  child: OutlinedButton(
                    onPressed: onSkip,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: cs.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTokens.radiusM),
                      ),
                    ),
                    child: Icon(
                      Icons.skip_next_outlined,
                      size: 26,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

class _SetIndexBadge extends StatelessWidget {
  final int index;
  final bool completed;
  final bool active;
  final bool skipped;
  const _SetIndexBadge({
    required this.index,
    this.completed = false,
    this.active = false,
    this.skipped = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final Widget child;
    if (completed) {
      bg = AppTokens.successGreen.withOpacity(0.18);
      fg = AppTokens.successGreen;
      child = Icon(Icons.check_rounded, size: 18, color: fg);
    } else if (active) {
      bg = cs.primary;
      fg = cs.onPrimary;
      child = Text(
        '${index + 1}',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      );
    } else if (skipped) {
      bg = cs.surfaceContainerHigh;
      fg = cs.onSurfaceVariant;
      child = Icon(Icons.remove, size: 16, color: fg);
    } else {
      bg = cs.surfaceContainerHigh;
      fg = cs.onSurfaceVariant;
      child = Text(
        '${index + 1}',
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

class _BigStepper extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onInfo;
  const _BigStepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.onInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                if (onInfo != null) ...[
                  const SizedBox(width: 3),
                  GestureDetector(
                    onTap: onInfo,
                    child: Icon(
                      Icons.info_outline,
                      size: 13,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Row(
            children: [
              _StepperButton(icon: Icons.remove_rounded, onPressed: onMinus),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              _StepperButton(icon: Icons.add_rounded, onPressed: onPlus),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _StepperButton({required this.icon, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppTokens.radiusS),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
        ),
        child: Icon(icon, size: 22, color: cs.onSurface),
      ),
    );
  }
}

void _showRpeInfo(BuildContext context, bool useRir) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(useRir
          ? 'RIR — Reps In Reserve'
          : 'RPE — Rate of Perceived Exertion'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(useRir
                ? "Combien de reps il te restait dans le réservoir à la fin de la série."
                : "À quel point la série était dure, sur une échelle de 1 à 10."),
            const SizedBox(height: 12),
            const Text('Repères :',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (useRir) ...const [
              Text("• RIR 0 → max, impossible d'en faire une de plus"),
              Text('• RIR 1 → 1 rep encore en réserve'),
              Text('• RIR 2 → 2 reps en réserve (cible classique)'),
              Text('• RIR 3 → 3 reps en réserve, série modérée'),
              Text('• RIR 4+ → trop léger pour de la prise de muscle'),
            ] else ...const [
              Text('• RPE 10 → max, 0 rep en réserve (échec)'),
              Text('• RPE 9  → très dur, 1 rep en réserve'),
              Text('• RPE 8  → dur, 2 reps en réserve (cible classique)'),
              Text('• RPE 7  → modéré, 3 reps en réserve'),
              Text('• RPE 6 et moins → échauffement / trop léger'),
            ],
            const SizedBox(height: 12),
            Text(
              "L'app utilise cette valeur pour calibrer la progression : "
              "${useRir ? 'RIR ≤ 1' : 'RPE ≥ 9'} signale qu'on est proche de l'échec, "
              "et la cible n'augmentera pas tant que tu n'as pas un peu de marge.",
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
