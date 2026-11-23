import 'dart:async';

/// Bounded concurrency, the counterpart of errgroup.SetLimit. Tasks start in
/// submission order once a slot frees up.
final class Pool {
  Pool(this.limit) : assert(limit > 0);
  final int limit;
  int _active = 0;
  final _waiting = <Completer<void>>[];
  final _tasks = <Future<void>>[];
  Object? _error;
  StackTrace? _stack;

  void run(Future<void> Function() task) {
    _tasks.add(_run(task));
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_active >= limit) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _active++;
    try {
      await task();
    } on Object catch (error, stack) {
      // Kept for wait(); a failed task must not surface as an unhandled
      // asynchronous error before anyone waits.
      _error ??= error;
      _stack ??= stack;
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  /// Waits for every task, including ones submitted while waiting; rethrows
  /// the first failure after all finish, like errgroup.Group.Wait.
  Future<void> wait() async {
    for (var index = 0; index < _tasks.length; index++) {
      await _tasks[index];
    }
    _tasks.clear();
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stack!);
  }
}
