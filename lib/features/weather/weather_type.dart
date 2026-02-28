enum WeatherType { sunny, cloudy, rainy, windy, snowy, stormy }

extension WeatherTypeExt on WeatherType {
  String get label {
    const labels = {
      WeatherType.sunny: '晴',
      WeatherType.cloudy: '阴',
      WeatherType.rainy: '雨',
      WeatherType.windy: '风',
      WeatherType.snowy: '雪',
      WeatherType.stormy: '暴风雨',
    };
    return labels[this]!;
  }

  String get icon {
    const icons = {
      WeatherType.sunny: '☀️',
      WeatherType.cloudy: '☁️',
      WeatherType.rainy: '🌧️',
      WeatherType.windy: '🌬️',
      WeatherType.snowy: '❄️',
      WeatherType.stormy: '⛈️',
    };
    return icons[this]!;
  }

  /// 树木额外摇摆倍率
  double get windFactor {
    const factors = {
      WeatherType.sunny: 0.0,
      WeatherType.cloudy: 0.2,
      WeatherType.rainy: 0.5,
      WeatherType.windy: 1.8,
      WeatherType.snowy: 0.2,
      WeatherType.stormy: 2.2,
    };
    return factors[this]!;
  }
}
