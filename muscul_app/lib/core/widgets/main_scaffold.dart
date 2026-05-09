import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/sync/sync_service.dart';
import '../theme/app_theme.dart';

class MainScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  static const _tabs = [
    ('/home', Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    ('/history', Icons.calendar_month_outlined, Icons.calendar_month_rounded,
        'Historique'),
    ('/library', Icons.menu_book_outlined, Icons.menu_book_rounded,
        'Mes séances'),
    ('/progression', Icons.show_chart_outlined, Icons.show_chart_rounded,
        'Progression'),
  ];

  int _index(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    for (var i = 0; i < _tabs.length; i++) {
      if (loc.startsWith(_tabs[i].$1)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Surface auto-sync ERRORS so the user knows when their data didn't
    // round-trip from the cloud. Successes stay silent — a working sync
    // shouldn't bug the user.
    ref.listen<SyncReport?>(lastSyncReportProvider, (prev, next) {
      if (next == null || next.ok) return;
      final messenger = _messengerKey.currentState;
      if (messenger == null) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 10),
        content: Text(
          'Sync échouée: ${next.error}',
          style: TextStyle(color: Theme.of(context).colorScheme.onError),
        ),
        action: SnackBarAction(
          textColor: Theme.of(context).colorScheme.onError,
          label: 'Détails',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Erreur de synchronisation'),
              content: SingleChildScrollView(
                child: SelectableText(
                  '${next.error}\n\n${next.stackTrace ?? ''}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ),
      ));
    });

    final idx = _index(context);
    final cs = Theme.of(context).colorScheme;
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: idx,
              backgroundColor: Colors.transparent,
              elevation: 0,
              height: 68,
              onDestinationSelected: (i) => context.go(_tabs[i].$1),
              indicatorShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusXL),
              ),
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(
                    icon: Icon(t.$2),
                    selectedIcon: Icon(t.$3),
                    label: t.$4,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
