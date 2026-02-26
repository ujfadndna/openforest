import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openforest/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // SharedPreferences 使用内存 mock，避免真实平台依赖。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ensureLoaded loads defaults when prefs empty', () async {
    final controller = SettingsController();
    await controller.ensureLoaded();

    expect(controller.state.loaded, true);
    expect(controller.state.minFocusMinutes, 10);
    expect(controller.state.maxFocusMinutes, 120);
    expect(controller.state.pomodoroWorkMinutes, 25);
    expect(controller.state.pomodoroBreakMinutes, 5);
    expect(controller.state.pomodoroRounds, 4);
    expect(controller.state.pomodoroLongBreakMinutes, 15);
    expect(controller.state.themeMode, ThemeMode.system);
  });

  test('setMinFocusMinutes clamps to 10..30 and keeps min < max', () async {
    final controller = SettingsController();
    await controller.ensureLoaded();

    await controller.setMaxFocusMinutes(60);
    await controller.setMinFocusMinutes(100); // should clamp to 30
    expect(controller.state.minFocusMinutes, 30);
    expect(controller.state.maxFocusMinutes, 60);
  });

  test('setThemeMode persists and updates state', () async {
    final controller = SettingsController();
    await controller.ensureLoaded();

    await controller.setThemeMode(ThemeMode.dark);
    expect(controller.state.themeMode, ThemeMode.dark);

    // 新实例应从 prefs 读到 dark
    final controller2 = SettingsController();
    await controller2.ensureLoaded();
    expect(controller2.state.themeMode, ThemeMode.dark);
  });
}

