import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Count-up rest stopwatch state — free-standing (not tied to a specific
/// exercise or set), just a timer the user starts between any two sets and
/// stops whenever they're done resting.
class RestTimerState {
  const RestTimerState({this.isRunning = false, this.elapsed = Duration.zero});

  final bool isRunning;
  final Duration elapsed;

  RestTimerState copyWith({bool? isRunning, Duration? elapsed}) =>
      RestTimerState(
        isRunning: isRunning ?? this.isRunning,
        elapsed: elapsed ?? this.elapsed,
      );
}

/// Screen-local rest timer — `autoDispose` so it resets whenever the user
/// leaves the log-workout screen, matching the ephemeral, not-persisted
/// nature of rest timing (nothing asks for rest times to be saved).
class RestTimerNotifier extends Notifier<RestTimerState> {
  Timer? _ticker;

  @override
  RestTimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const RestTimerState();
  }

  void start() {
    _ticker?.cancel();
    state = const RestTimerState(isRunning: true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    state = const RestTimerState();
  }
}

final restTimerProvider = NotifierProvider.autoDispose<
  RestTimerNotifier,
  RestTimerState
>(RestTimerNotifier.new);
