import 'dart:async';

/// A one-shot timer whose firing is a future.
abstract interface class ClockTimer {
  Future<void> get fired;
  void cancel();
}

/// Injectable time, the counterpart of clockwork.Clock.
abstract class Clock {
  const Clock();
  DateTime now();
  ClockTimer timer(Duration duration);
}

final class SystemClock extends Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
  @override
  ClockTimer timer(Duration duration) => _SystemTimer(duration);
}

final class _SystemTimer implements ClockTimer {
  _SystemTimer(Duration duration) {
    _timer = Timer(duration < Duration.zero ? Duration.zero : duration, () {
      if (!_fired.isCompleted) _fired.complete();
    });
  }
  late final Timer _timer;
  final _fired = Completer<void>();
  @override
  Future<void> get fired => _fired.future;
  @override
  void cancel() => _timer.cancel();
}

/// Deterministic clock for tests: time moves only through [advance].
final class FakeClock extends Clock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026);
  DateTime _now;
  final _timers = <_FakeTimer>[];
  final _blockers = <Completer<void>>[];

  @override
  DateTime now() => _now;

  @override
  ClockTimer timer(Duration duration) {
    final timer = _FakeTimer(this, _now.add(duration));
    if (duration <= Duration.zero) {
      timer._fire();
    } else {
      _timers.add(timer);
      for (final blocker in _blockers) {
        if (!blocker.isCompleted) blocker.complete();
      }
      _blockers.clear();
    }
    return timer;
  }

  /// Completes once at least one timer is pending.
  Future<void> blockUntilTimer() {
    if (_timers.isNotEmpty) return Future.value();
    final blocker = Completer<void>();
    _blockers.add(blocker);
    return blocker.future;
  }

  void advance(Duration duration) {
    _now = _now.add(duration);
    final due = _timers.where((timer) => !timer.at.isAfter(_now)).toList();
    _timers.removeWhere(due.contains);
    for (final timer in due) {
      timer._fire();
    }
  }
}

final class _FakeTimer implements ClockTimer {
  _FakeTimer(this.clock, this.at);
  final FakeClock clock;
  final DateTime at;
  final _fired = Completer<void>();
  void _fire() {
    if (!_fired.isCompleted) _fired.complete();
  }

  @override
  Future<void> get fired => _fired.future;
  @override
  void cancel() => clock._timers.remove(this);
}

