import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

class MainScaffold extends StatelessWidget {
  final Widget child;
  const MainScaffold({super.key, required this.child});

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
    final idx = _index(context);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: child,
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
    );
  }
}
