import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'features/settings/settings_screen.dart';
import 'features/shop/shop_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/timer/timer_screen.dart';
import 'features/allowlist/allowlist_screen.dart';
import 'features/forest/forest_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (_isDesktop()) {
    await windowManager.ensureInitialized();
    await localNotifier.setup(appName: 'OpenForest');

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

  runApp(const ProviderScope(child: OpenForestApp()));
}

bool _isDesktop() {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS =>
      true,
    _ => false,
  };
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
      builder: (context, child) => _FpsOverlay(child: child!),
      home: const HomeShell(),
    );
  }
}

// ── FPS 计数器悬浮层 ──────────────────────────────────────────────────────────

class _FpsOverlay extends StatefulWidget {
  const _FpsOverlay({required this.child});
  final Widget child;

  @override
  State<_FpsOverlay> createState() => _FpsOverlayState();
}

class _FpsOverlayState extends State<_FpsOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<int> _times = [];
  double _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final now = DateTime.now().microsecondsSinceEpoch;
      _times.add(now);
      if (_times.length > 60) _times.removeAt(0);
      if (_times.length >= 2) {
        final span = (_times.last - _times.first) / 1e6;
        final fps = (_times.length - 1) / span;
        if ((fps - _fps).abs() >= 1) setState(() => _fps = fps);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _fps >= 55
        ? Colors.greenAccent
        : _fps >= 30
            ? Colors.orangeAccent
            : Colors.redAccent;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 8,
          right: 8,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${_fps.round()} fps',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Courier New',
                ),
              ),
            ),
          ),
        ),
      ],
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

  static const double _navRailWidth = 96;

  final _pages = const <Widget>[
    TimerScreen(),
    ForestScreen(),
    StatsScreen(),
    AllowlistScreen(),
    ShopScreen(),
    SettingsScreen(),
  ];

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
            Expanded(child: _pages[_index]),
          ],
        ),
      ),
    );
  }
}
