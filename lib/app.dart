import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mindfull/core/theme.dart';
import 'package:mindfull/presentation/lock/lock_gate.dart';
import 'package:mindfull/presentation/shared/appearance.dart';

class MindfullApp extends ConsumerWidget {
  const MindfullApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Mindfull',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) => LockGate(child: child!),
    );
  }
}
