import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'data/database.dart';
import 'data/repositories/review_repository.dart';
import 'core/crash_logger.dart';
import 'features/allowlist/allowlist_screen.dart';
import 'features/forest/forest_screen.dart';
import 'features/review/review_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shop/shop_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/timer/timer_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化崩溃日志器（最早）
  await CrashLogger.instance.init();

  if (CrashLogger.instance.lastSessionCrashed) {
    CrashLogger.instance.log('检测到上次会话异常退出', level: LogLevel.warning);
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    CrashLogger.instance.error(
      'FlutterError: ${details.exception}',
      details.exception,
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLogger.instance.fatal('Uncaught: $error', error, stack);
    return true;
  };

  if (_isDesktop()) {
    await windowManager.ensureInitialized();
    await localNotifier.setup(appName: 'OpenForest');
    _checkDueReviews();

    const windowOptions = WindowOptions(
      size: Size(1100, 700),
      minimumSize: Size(800, 600),
      center: true,
      title: 'OpenForest',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runZonedGuarded(
    () => runApp(const ProviderScope(child: OpenForestApp())),
    (error, stack) {
      CrashLogger.instance.fatal('Zone uncaught: $error', error, stack);
    },
  );
}

bool _isDesktop() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS =>
      true,
    _ => false,
  };
}

Future<void> _checkDueReviews() async {
  try {
    final db = AppDatabase.instance;
    await db.ensureInitialized();
    final repo = ReviewRepository(db);
    final dueItems = await repo.getDueItems();
    if (dueItems.isEmpty) return;
    final titles = dueItems.map((e) => e.title).take(5).join('、');
    final notification = LocalNotification(
      title: 'OpenForest · 回顾提醒',
      body: '${dueItems.length} 个章节到期：$titles',
    );
    await notification.show();
  } catch (_) {}
}

class OpenForestApp extends ConsumerWidget {
  const OpenForestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'OpenForest',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4CAF50),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4CAF50),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: settings.themeMode,
      builder: (context, child) => child!,
      home: const HomeShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final AppLifecycleListener _lifecycleListener;

  static const double _navRailWidth = 96;

  final _pages = const <Widget>[
    TimerScreen(),
    ForestScreen(),
    ReviewScreen(),
    StatsScreen(),
    AllowlistScreen(),
    ShopScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        CrashLogger.instance.markSessionEnd();
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: _navRailWidth,
              child: NavigationRail(
                minWidth: _navRailWidth,
                groupAlignment: -1.0,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.timer_outlined),
                    selectedIcon: Icon(Icons.timer),
                    label: Text('计时器'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.forest_outlined),
                    selectedIcon: Icon(Icons.forest),
                    label: Text('森林'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.event_repeat_outlined),
                    selectedIcon: Icon(Icons.event_repeat),
                    label: Text('回顾'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart),
                    label: Text('统计'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.rule_outlined),
                    selectedIcon: Icon(Icons.rule),
                    label: Text('名单'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.storefront_outlined),
                    selectedIcon: Icon(Icons.storefront),
                    label: Text('商店'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings),
                    label: Text('设置'),
                  ),
                ],
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
                child: ExcludeSemantics(
                    child: IndexedStack(index: _index, children: _pages))),
          ],
        ),
      ),
    );
  }
}
