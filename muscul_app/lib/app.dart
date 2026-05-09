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
  Timer? _syncTimer;
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
    // Periodic safety net while the app stays open.
    _syncTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      _trySync(reason: 'periodic');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
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
    try {
      final report = await svc.sync();
      // Surface the result so MainScaffold can show errors. Without this
      // a failing sync silently swallows the error and the user thinks
      // their data is gone.
      ref.read(lastSyncReportProvider.notifier).state = report;
      // After the pull lands, prune phantom in-progress sessions: more than
      // one session with endedAt IS NULL is always wrong (you can only do
      // one workout at a time), and abandoning the visible one would
      // otherwise just surface the next-stalest. Run after sync so we
      // include any sessions just pulled from the cloud.
      final stale = await ref
          .read(sessionRepositoryProvider)
          .pruneStaleInProgress();
      // Push each pruned deletion synchronously so it can't be lost.
      for (final id in stale) {
        try {
          await svc.pushSession(id);
        } catch (_) {/* periodic sync will retry */}
      }
    } catch (e, st) {
      ref.read(lastSyncReportProvider.notifier).state = SyncReport(
        ok: false,
        error: '$e',
        stackTrace: st.toString(),
      );
    } finally {
      _syncInFlight = false;
    }
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

    return MaterialApp.router(
      title: 'Muscul',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
