import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'exercises/exercises_tab.dart';
import 'templates/templates_tab.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mes séances'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Templates'),
            Tab(text: 'Exercices'),
          ]),
        ),
        body: const TabBarView(
          children: [TemplatesTab(), ExercisesTab()],
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton(
            onPressed: () {
              final idx = DefaultTabController.of(ctx).index;
              if (idx == 0) {
                ctx.push('/library/template/new');
              } else {
                ctx.push('/library/exercise/new');
              }
            },
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}
