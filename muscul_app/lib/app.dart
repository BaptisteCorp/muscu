import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/auth/auth_service.dart';
import 'data/sync/sync_service.dart';
import 'domain/models/enums.dart';

class MusculApp extends ConsumerStatefulWidget {
  const MusculApp({super.key});

  @override
  ConsumerState<MusculApp> createState() => _MusculAppState();
}

class _MusculAppState extends ConsumerState<MusculApp>
    with WidgetsBindingObserver {
  bool _syncInFlight = false;
  String? _lastUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Trigger an initial sync after first frame, in case we boot already
    // logged in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trySync(reason: 'app start');
    });
    // No periodic timer: every write action pushes synchronously to the
    // cloud (see SyncService.pushXxx methods). The full bidirectional
    // sync runs only on app start, on login, and on resume — which is
    // when the user could conceivably have edits from another device.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trySync(reason: 'resume');
    }
  }

  Future<void> _trySync({required String reason}) async {
    if (_syncInFlight) return;
    final svc = ref.read(syncServiceProvider);
    if (!svc.isAvailable) return;
    _syncInFlight = true;
    // Only the post-login sync gets the blocking overlay: that's the fresh
    // login / reinstall case where local is empty and content would
    // otherwise pop in table-by-table. Resume / app-start syncs stay silent.
    final blocking = reason == 'login';
    if (blocking) {
      ref.read(initialSyncInProgressProvider.notifier).state = true;
    }
    try {
      var report = await svc.sync();
      // App resumes often fire before the radio is fully back up, so the
      // first try may hit "Failed host lookup" or AuthRetryableFetchError.
      // Give the network a beat and retry once before bothering the user.
      if (!report.ok && _isTransientNetworkError(report.error)) {
        await Future.delayed(const Duration(seconds: 3));
        report = await svc.sync();
      }
      // Still transient after a retry → stay silent. The next resume / start
      // will retry naturally; flashing a red snackbar for normal mobile
      // network blips trains the user to ignore real failures.
      if (report.ok || !_isTransientNetworkError(report.error)) {
        ref.read(lastSyncReportProvider.notifier).state = report;
      }
      // Prune phantom in-progress sessions even if sync failed — they're a
      // purely local concern (more than one row with endedAt IS NULL).
      final stale = await ref
          .read(sessionRepositoryProvider)
          .pruneStaleInProgress();
      // Fire-and-forget each pruned deletion: local DB already marks the
      // session deleted, and the next full sync will retry on failure.
      for (final id in stale) {
        svc.pushSession(id).ignore();
      }
    } catch (e, st) {
      final errStr = '$e';
      if (_isTransientNetworkError(errStr)) {
        // See above — silent for transient network failures.
        return;
      }
      ref.read(lastSyncReportProvider.notifier).state = SyncReport(
        ok: false,
        error: errStr,
        stackTrace: st.toString(),
      );
    } finally {
      _syncInFlight = false;
      if (blocking) {
        ref.read(initialSyncInProgressProvider.notifier).state = false;
      }
    }
  }

  /// True if [err] looks like a "network momentarily unavailable" error —
  /// the kind that resolves itself on the next attempt. Worth distinguishing
  /// from real failures (auth expired, RLS, server 500) which the user
  /// should see immediately.
  static bool _isTransientNetworkError(String? err) {
    if (err == null || err.isEmpty) return false;
    final s = err.toLowerCase();
    return s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('no address associated') ||
        s.contains('handshakeexception') ||
        s.contains('timeoutexception') ||
        s.contains('connection closed') ||
        s.contains('connection reset') ||
        s.contains('clientexception') ||
        s.contains('authretryablefetch');
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settingsAsync = ref.watch(settingsStreamProvider);
    // Side-effect: keep settings.userBodyweightKg synced to the latest
    // bodyweight entry. Eagerly watched here so the invariant holds for
    // the entire app lifetime, regardless of which screen is on top.
    ref.watch(bodyweightSettingsSyncProvider);
    final mode = settingsAsync.maybeWhen(
      data: (s) => switch (s.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      orElse: () => ThemeMode.system,
    );
    final palette = settingsAsync.maybeWhen(
      data: (s) => s.palette,
      orElse: () => AppPalette.crimson,
    );

    // Trigger a sync as soon as we transition into a logged-in state. This
    // protects users who tap "Connexion" but forget to hit "Sync now".
    final user = ref.watch(currentUserProvider);
    if (user != null && user.id != _lastUserId) {
      _lastUserId = user.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _trySync(reason: 'login');
      });
    } else if (user == null) {
      _lastUserId = null;
    }

    final initialSyncing = ref.watch(initialSyncInProgressProvider);

    return MaterialApp.router(
      title: 'Reps',
      theme: AppTheme.light(palette),
      darkTheme: AppTheme.dark(palette),
      themeMode: mode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Overlay the whole app with a single loading screen while the
      // post-login sync runs, so a fresh login / reinstall doesn't show the
      // theme and data popping in table-by-table as each pull lands.
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (initialSyncing) const _InitialSyncOverlay(),
          ],
        );
      },
    );
  }
}

/// Full-screen, opaque loading overlay shown during the post-login sync.
/// Includes a "Continuer" escape hatch after a few seconds so a slow or
/// wedged network never traps the user behind the spinner.
class _InitialSyncOverlay extends ConsumerStatefulWidget {
  const _InitialSyncOverlay();

  @override
  ConsumerState<_InitialSyncOverlay> createState() =>
      _InitialSyncOverlayState();
}

class _InitialSyncOverlayState extends ConsumerState<_InitialSyncOverlay> {
  bool _showSkip = false;
  Timer? _skipTimer;

  @override
  void initState() {
    super.initState();
    _skipTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _showSkip = true);
    });
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('Synchronisation de tes données…', style: tt.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Récupération depuis le cloud',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            AnimatedOpacity(
              opacity: _showSkip ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: TextButton(
                onPressed: _showSkip
                    ? () => ref
                        .read(initialSyncInProgressProvider.notifier)
                        .state = false
                    : null,
                child: const Text('Continuer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
