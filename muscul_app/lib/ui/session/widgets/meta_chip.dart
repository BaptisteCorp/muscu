import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Puce d'info compacte (icône + libellé) sous le header d'exo : repos
/// configuré, réglages machine, etc. Tapable si [onTap] fourni.
class MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  final double? maxWidth;
  final VoidCallback? onTap;
  const MetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.accent = false,
    this.maxWidth,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = accent ? cs.primary : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusS),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: accent
              ? cs.primary.withOpacity(0.10)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppTokens.radiusS),
          border: Border.all(
            color: accent ? cs.primary.withOpacity(0.4) : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
