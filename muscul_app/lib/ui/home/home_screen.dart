import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/supabase_config.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/auth/auth_service.dart';
import '../../data/sync/sync_service.dart';
import '../../domain/models/bodyweight_entry.dart';
import '../../domain/models/session.dart';
import '../../domain/models/workout_template.dart';
import '../session/start_session_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inProgress = ref.watch(inProgressSessionProvider);
    final templates = ref.watch(allTemplatesProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Header: title + auth button + settings.
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Accueil',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                const _AuthPill(),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Réglages',
                  icon: const Icon(Icons.tune_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppTokens.radiusM),
                    ),
                  ),
                  onPressed: () => _openSettings(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 18),
            inProgress.when(
              data: (s) => s == null
                  ? const SizedBox.shrink()
                  : _ResumeHero(s),
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Erreur: $e'),
            ),
            inProgress.maybeWhen(
              data: (s) => s != null
                  ? const SizedBox(height: 22)
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
            _SectionTitle(label: 'Démarrer une séance'),
            const SizedBox(height: 10),
            templates.when(
              data: (list) {
                if (list.isEmpty) {
                  return _EmptyTemplatesCard(onTap: () => context.go('/library'));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TemplateCard(t),
                      ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.flash_on_rounded),
                        label: const Text(
                            'Séance freestyle (sans template)'),
                        onPressed: () async {
                          final id = await ref
                              .read(startSessionControllerProvider)
                              .startSession();
                          if (context.mounted) context.push('/session/$id');
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
              error: (e, _) => Text('Erreur: $e'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SettingsSheet(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ResumeHero extends ConsumerWidget {
  final WorkoutSession session;
  const _ResumeHero(this.session);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final elapsed = DateTime.now().difference(session.startedAt);
    final hh = elapsed.inHours;
    final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final durationLabel =
        hh > 0 ? '${hh}h${mm}' : '${elapsed.inMinutes} min';

    return InkWell(
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      onTap: () => context.push('/session/${session.id}'),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary,
              cs.primary.withOpacity(0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: cs.onPrimary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.play_arrow_rounded,
                color: cs.onPrimary,
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SÉANCE EN COURS',
                    style: TextStyle(
                      color: cs.onPrimary.withOpacity(0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reprendre',
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'démarrée à ${fmtTime(session.startedAt)} · $durationLabel',
                    style: TextStyle(
                      color: cs.onPrimary.withOpacity(0.85),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded,
                color: cs.onPrimary.withOpacity(0.9)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _EmptyTemplatesCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyTemplatesCard({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusL),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border.all(
            color: cs.outlineVariant,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(AppTokens.radiusL),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.add_rounded, color: cs.primary, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aucun template',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Crée ta première séance dans Mes séances',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends ConsumerWidget {
  final WorkoutTemplate template;
  const _TemplateCard(this.template);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final lastByTemplate =
        ref.watch(lastSessionByTemplateProvider).valueOrNull ?? const {};
    final last = lastByTemplate[template.id];
    final lastStr = last != null && last.endedAt != null
        ? _relativeDay(last.endedAt!)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusL),
        onTap: () async {
          final id = await ref
              .read(startSessionControllerProvider)
              .startSession(templateId: template.id);
          if (context.mounted) context.push('/session/$id');
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.13),
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusM),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.fitness_center_rounded,
                    color: cs.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      template.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      template.notes != null && template.notes!.isNotEmpty
                          ? template.notes!
                          : (lastStr ?? 'Jamais effectué'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius:
                      BorderRadius.circular(AppTokens.radiusM),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: cs.onPrimary,
                  size: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeDay(DateTime d) =>
    fmtRelativeDay(d, prefix: 'Dernière séance');

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsStreamProvider);
    return asyncSettings.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Erreur: $e'),
      ),
      data: (s) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text('Réglages',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Incrément par défaut'),
              trailing: Text('${s.defaultIncrementKg} kg',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              title: const Text('Repos par défaut'),
              trailing: Text('${s.defaultRestSeconds} s',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            SwitchListTile(
              title: const Text('Utiliser RIR au lieu de RPE'),
              value: s.useRirInsteadOfRpe,
              onChanged: (v) async {
                await ref
                    .read(settingsRepositoryProvider)
                    .save(s.copyWith(useRirInsteadOfRpe: v));
                try {
                  await ref.read(syncServiceProvider).pushSettings();
                } catch (_) {/* later sync will retry */}
              },
            ),
            ListTile(
              title: const Text('Mon poids (kg)'),
              subtitle: const Text(
                  "Mis à jour à chaque saisie dans Progression > Poids"),
              trailing: SizedBox(
                width: 96,
                child: TextFormField(
                  // Key forces a rebuild of the field whenever the synced
                  // value changes — otherwise the local controller state
                  // sticks to its first initialValue.
                  key: ValueKey('bw_${s.userBodyweightKg ?? ""}'),
                  initialValue: s.userBodyweightKg?.toStringAsFixed(1) ?? '',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                      suffixText: 'kg', isDense: true),
                  onFieldSubmitted: (v) async {
                    final parsed = double.tryParse(v.replaceAll(',', '.'));
                    if (parsed != null && parsed > 0) {
                      // Logging here too keeps Progression > Poids and
                      // Settings in sync — the bodyweight entries stream
                      // is the single source of truth.
                      final today = DateTime.now();
                      final dateStr = BodyweightEntry.formatDate(today);
                      await ref.read(bodyweightRepositoryProvider).upsert(
                            BodyweightEntry(
                              date: dateStr,
                              weightKg: parsed,
                              updatedAt: today,
                            ),
                          );
                      try {
                        await ref
                            .read(syncServiceProvider)
                            .pushBodyweight(dateStr);
                      } catch (_) {/* later sync will retry */}
                    } else {
                      // User cleared the field → drop the cached weight
                      // (does not touch logged history).
                      await ref.read(settingsRepositoryProvider).save(
                            s.copyWith(
                              userBodyweightKg: null,
                              clearUserBodyweightKg: true,
                            ),
                          );
                      try {
                        await ref.read(syncServiceProvider).pushSettings();
                      } catch (_) {/* later sync will retry */}
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Auth pill in the Home header. Always visible: tapping it leads to the
/// login screen (which itself explains if Supabase isn't configured yet),
/// or to a logged-in info sheet when a session is active.
class _AuthPill extends ConsumerWidget {
  const _AuthPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final user = SupabaseConfig.isConfigured
        ? ref.watch(currentUserProvider)
        : null;
    final loggedIn = user != null;

    return Material(
      color: loggedIn
          ? AppTokens.successGreen.withOpacity(0.13)
          : cs.primary.withOpacity(0.12),
      borderRadius: BorderRadius.circular(AppTokens.radiusXL),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusXL),
        onTap: () {
          if (loggedIn) {
            _showLoggedInSheet(context, ref, user?.email);
          } else {
            context.push('/login');
          }
        },
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTokens.radiusXL),
            border: Border.all(
              color: loggedIn
                  ? AppTokens.successGreen.withOpacity(0.5)
                  : cs.primary.withOpacity(0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                loggedIn
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_outlined,
                size: 18,
                color: loggedIn ? AppTokens.successGreen : cs.primary,
              ),
              const SizedBox(width: 6),
              Text(
                loggedIn ? 'Connecté' : 'Se connecter',
                style: TextStyle(
                  color: loggedIn ? AppTokens.successGreen : cs.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showLoggedInSheet(
    BuildContext context, WidgetRef ref, String? email) {
  showModalBottomSheet(
    context: context,
    builder: (sctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_done_rounded,
                  color: AppTokens.successGreen),
              title: Text(email ?? 'Connecté'),
              subtitle: const Text(
                  'Tes données se synchronisent automatiquement.'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(sctx);
                await ref.read(authServiceProvider).signOut();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    ),
  );
}
