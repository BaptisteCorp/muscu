import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/auth/login_screen.dart';
import '../../ui/history/history_screen.dart';
import '../../ui/home/home_screen.dart';
import '../../ui/library/library_screen.dart';
import '../../ui/library/exercises/exercise_edit_screen.dart';
import '../../ui/library/templates/template_edit_screen.dart';
import '../../ui/progression/progression_screen.dart';
import '../../ui/session/active_session_screen.dart';
import '../widgets/main_scaffold.dart';

final _rootNav = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNav = GlobalKey<NavigatorState>(debugLabel: 'shell');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNav,
    initialLocation: '/home',
    routes: [
      ShellRoute(
        navigatorKey: _shellNav,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (c, s) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/history',
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: HistoryScreen()),
          ),
          GoRoute(
            path: '/library',
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: LibraryScreen()),
          ),
          GoRoute(
            path: '/progression',
            pageBuilder: (c, s) =>
                const NoTransitionPage(child: ProgressionScreen()),
          ),
        ],
      ),
      GoRoute(
        path: '/session/:id',
        parentNavigatorKey: _rootNav,
        builder: (c, s) =>
            ActiveSessionScreen(sessionId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/library/exercise/new',
        parentNavigatorKey: _rootNav,
        builder: (c, s) => const ExerciseEditScreen(),
      ),
      GoRoute(
        path: '/library/exercise/:id',
        parentNavigatorKey: _rootNav,
        builder: (c, s) =>
            ExerciseEditScreen(exerciseId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/library/template/new',
        parentNavigatorKey: _rootNav,
        builder: (c, s) => const TemplateEditScreen(),
      ),
      GoRoute(
        path: '/library/template/:id',
        parentNavigatorKey: _rootNav,
        builder: (c, s) =>
            TemplateEditScreen(templateId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNav,
        builder: (c, s) => const LoginScreen(),
      ),
    ],
  );
});
