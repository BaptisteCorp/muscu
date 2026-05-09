import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/progression_target.dart';
import '../../../domain/models/workout_template.dart';

/// Carte récapitulant le plan du template (si présent) ou la cible calculée
/// par le moteur de progression sinon. Affiche aussi la raison de la cible
/// quand on n'a pas de plan explicite.
class PlanCard extends StatelessWidget {
  final List<TemplateExerciseSet> plan;
  final ProgressionTarget target;
  final String Function(double) formatWeight;
  final String Function(List<TemplateExerciseSet>) formatPlanLine;
  const PlanCard({
    super.key,
    required this.plan,
    required this.target,
    required this.formatWeight,
    required this.formatPlanLine,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasPlan = plan.isNotEmpty;
    final title = hasPlan ? 'PLAN' : 'CIBLE';
    final body = hasPlan
        ? formatPlanLine(plan)
        : '${target.targetSets}×${target.targetReps} @ '
            '${formatWeight(target.targetWeightKg)} kg';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusM),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: hasPlan ? cs.secondary : cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (target.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              target.reason,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
