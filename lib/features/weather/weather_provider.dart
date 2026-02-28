import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'weather_type.dart';

/// 手动覆盖（null = 使用自动定位）
final weatherOverrideProvider = StateProvider<WeatherType?>((ref) => null);

/// 基于 IP 自动获取天气（一次性缓存）
final autoWeatherProvider = FutureProvider<WeatherType>((ref) async {
  try {
    // Step 1: 通过 IP 获取城市
    final ipResp = await http
        .get(Uri.parse('https://ipinfo.io/json'))
        .timeout(const Duration(seconds: 5));
    if (ipResp.statusCode != 200) return WeatherType.sunny;

    final ipData = jsonDecode(ipResp.body) as Map<String, dynamic>;
    final city = (ipData['city'] as String? ?? '').trim();
    if (city.isEmpty) return WeatherType.sunny;

    // Step 2: 获取该城市天气
    final wttrResp = await http
        .get(Uri.parse('https://wttr.in/$city?format=j1'))
        .timeout(const Duration(seconds: 5));
    if (wttrResp.statusCode != 200) return WeatherType.sunny;

    final wttrData = jsonDecode(wttrResp.body) as Map<String, dynamic>;
    final current =
        (wttrData['current_condition'] as List<dynamic>?)?.firstOrNull;
    if (current == null) return WeatherType.sunny;

    final code =
        int.tryParse(current['weatherCode']?.toString() ?? '') ?? 113;
    final wind =
        int.tryParse(current['windspeedKmph']?.toString() ?? '') ?? 0;

    return _mapWeatherCode(code, wind);
  } catch (_) {
    return WeatherType.sunny; // 网络失败默认晴天
  }
});

/// 最终生效天气（手动优先，其次自动，默认晴）
final effectiveWeatherProvider = Provider<WeatherType>((ref) {
  return ref.watch(weatherOverrideProvider) ??
      ref.watch(autoWeatherProvider).valueOrNull ??
      WeatherType.sunny;
});

WeatherType _mapWeatherCode(int code, int windKmph) {
  if (windKmph > 35) return WeatherType.windy;
  if (code == 113) return WeatherType.sunny;
  if (code <= 122 || code == 143 || code == 248 || code == 260) {
    return WeatherType.cloudy;
  }
  if (code >= 386 || (code >= 200 && code <= 230)) return WeatherType.stormy;
  if ((code >= 227 && code <= 338) || (code >= 350 && code <= 377)) {
    return WeatherType.snowy;
  }
  return WeatherType.rainy;
}
