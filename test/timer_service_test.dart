import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openforest/core/timer_service.dart';

void main() {
  test('calculateCoinsForDuration: under 10 minutes returns 0', () {
    final service = TimerService();
    expect(service.calculateCoinsForDuration(const Duration(minutes: 9)), 0);
    expect(service.calculateCoinsForDuration(const Duration(minutes: 0)), 0);
  });

  test('calculateCoinsForDuration: 10 minutes or more returns minutes', () {
    final service = TimerService();
    expect(service.calculateCoinsForDuration(const Duration(minutes: 10)), 10);
    expect(service.calculateCoinsForDuration(const Duration(minutes: 25)), 25);
  });

  test('countdown completes and triggers onComplete', () async {
    final service = TimerService();

    final completer = Completer<int>();
    service.onComplete = (coins) async {
      if (!completer.isCompleted) completer.complete(coins);
    };

    service.startTimer(const Duration(seconds: 1), TimerMode.countdown);

    final coins = await completer.future.timeout(const Duration(seconds: 3));
    expect(service.state, TimerState.completed);
    expect(coins, 0);
  });

  test('abandonTimer sets failed and triggers onFailed', () async {
    final service = TimerService();

    final completer = Completer<void>();
    service.onFailed = () async {
      if (!completer.isCompleted) completer.complete();
    };

    service.startTimer(const Duration(seconds: 10), TimerMode.countdown);
    service.abandonTimer();

    await completer.future.timeout(const Duration(seconds: 1));
    expect(service.state, TimerState.failed);
    expect(service.withering, true);
  });
}

