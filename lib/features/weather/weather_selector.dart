import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'weather_provider.dart';
import 'weather_type.dart';

/// 天气选择器：显示当前天气 emoji，点击弹出菜单手动切换
class WeatherSelector extends ConsumerWidget {
  const WeatherSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weather = ref.watch(effectiveWeatherProvider);
    final isAuto = ref.watch(weatherOverrideProvider) == null;

    return PopupMenuButton<WeatherType?>(
      tooltip: '天气（选"自动"恢复定位）',
      onSelected: (w) =>
          ref.read(weatherOverrideProvider.notifier).state = w,
      itemBuilder: (_) => [
        const PopupMenuItem<WeatherType?>(
          value: null,
          child: Text('🌐  自动定位'),
        ),
        const PopupMenuDivider(),
        for (final w in WeatherType.values)
          PopupMenuItem<WeatherType?>(
            value: w,
            child: Text('${w.icon}  ${w.label}'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(weather.icon, style: const TextStyle(fontSize: 16)),
            if (isAuto) ...[
              const SizedBox(width: 2),
              Text(
                '自动',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
