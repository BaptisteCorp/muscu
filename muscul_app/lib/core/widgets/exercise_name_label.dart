import 'package:flutter/material.dart';

import '../../domain/models/enums.dart';

/// An exercise's name followed by its equipment as a discreet, smaller and
/// muted suffix — e.g. "Extension poulie haute  Corde".
///
/// Used wherever a list of exercises is shown so that two visually-similar
/// names that only differ by equipment (poulie corde vs barre) can be told
/// apart at a glance without making the equipment compete with the title.
class ExerciseNameLabel extends StatelessWidget {
  final String name;
  final Equipment equipment;

  /// Optional base style for the name. The equipment suffix is always
  /// rendered smaller/muted relative to this (or the ambient text style).
  final TextStyle? style;

  /// How many lines the name+equipment may span before ellipsizing.
  ///
  /// Defaults to 2 so long names ("Développé couché machine convergente")
  /// show in full and wrap gracefully instead of being cut mid-word. Pass 1
  /// in height-constrained spots like a [DropdownMenuItem].
  final int maxLines;

  const ExerciseNameLabel({
    super.key,
    required this.name,
    required this.equipment,
    this.style,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: name),
          // Non-breaking space keeps "  Corde" glued together so the
          // equipment never wraps a single letter onto its own line.
          TextSpan(
            text: '  ${equipment.label}',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
