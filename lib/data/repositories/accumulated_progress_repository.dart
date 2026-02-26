import 'package:shared_preferences/shared_preferences.dart';

/// 累计专注进度持久化
///
/// 跨 session 保存当前累计秒数和对应树种，
/// 凑够树种要求时种树并清零。
class AccumulatedProgressRepository {
  static const _kSeconds = 'accumulated_seconds';
  static const _kSpecies = 'accumulated_species';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _get() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<int> getSeconds() async {
    final p = await _get();
    return p.getInt(_kSeconds) ?? 0;
  }

  Future<String> getSpecies() async {
    final p = await _get();
    return p.getString(_kSpecies) ?? 'oak';
  }

  Future<void> save(int seconds, String species) async {
    final p = await _get();
    await p.setInt(_kSeconds, seconds);
    await p.setString(_kSpecies, species);
  }

  Future<void> clear() async {
    final p = await _get();
    await p.remove(_kSeconds);
    await p.remove(_kSpecies);
  }
}
