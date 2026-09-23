import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mindfull/presentation/ask/ask_screen.dart';
import 'package:mindfull/presentation/entry/entry_editor_screen.dart';
import 'package:mindfull/presentation/home_shell.dart';
import 'package:mindfull/presentation/models/model_manager_screen.dart';
import 'package:mindfull/presentation/onboarding/welcome_screen.dart';
import 'package:mindfull/presentation/settings/app_lock_setup_screen.dart';
import 'package:mindfull/presentation/settings/privacy_screen.dart';
import 'package:mindfull/presentation/settings/settings_screen.dart';
import 'package:mindfull/presentation/timeline/timeline_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

abstract final class Routes {
  static const welcome = '/welcome';
  static const timeline = '/';
  static const newEntry = '/entry/new';
  static String entry(String id) => '/entry/$id';
  static const ask = '/ask';
  static const settings = '/settings';
  static const privacy = '/settings/privacy';
  static const lockSetup = '/settings/lock';
  static const models = '/settings/models';
}

GoRouter buildRouter({required bool onboarded}) => GoRouter(
  navigatorKey: _rootKey,
  initialLocation: onboarded ? Routes.timeline : Routes.welcome,
  routes: [
    GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
    GoRoute(
      path: Routes.newEntry,
      parentNavigatorKey: _rootKey,
      builder: (_, _) => const EntryEditorScreen(),
    ),
    GoRoute(
      path: '/entry/:id',
      parentNavigatorKey: _rootKey,
      builder: (_, s) => EntryEditorScreen(entryId: s.pathParameters['id']),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.timeline,
              builder: (_, _) => const _Tab(TimelineScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.ask,
              builder: (_, _) => const _Tab(AskScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.settings,
              builder: (_, _) => const _Tab(SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'privacy',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const PrivacyScreen(),
                ),
                GoRoute(
                  path: 'models',
                  parentNavigatorKey: _rootKey,
                  builder: (_, _) => const ModelManagerScreen(),
                ),
                GoRoute(
                  path: 'lock',
                  parentNavigatorKey: _rootKey,
                  builder: (_, s) => AppLockSetupScreen(
                    initialAction: switch (s.uri.queryParameters['action']) {
                      'disable' => LockSetupAction.disable,
                      'change' => LockSetupAction.change,
                      _ => null,
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Tabs stay alive in an IndexedStack. A per-tab ScaffoldMessenger keeps a
/// SnackBar in the visible tab only (otherwise every tab's Scaffold shows it
/// and their Hero tags collide during page transitions).
class _Tab extends StatelessWidget {
  const _Tab(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(child: child);
}
