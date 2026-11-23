import 'dart:async';

import 'context.dart';

/// A group of tasks with optionally bounded concurrency, the counterpart of
/// Go's `errgroup.Group`. Tasks start in submission order once a slot frees
/// up; [wait] rethrows the first failure after every task has finished.
final class Pool {
  /// A pool without a context, like a zero `errgroup.Group`. A null [limit]
  /// runs every task at once.
  Pool({this.limit}) : _context = null, assert(limit == null || limit > 0);

  Pool._(this._context, this.limit) : assert(limit == null || limit > 0);

  /// A pool and the child of [parent] its tasks should observe, like
  /// `errgroup.WithContext`.
  ///
  /// The child is cancelled with the first task failure as its cause, and
  /// with [Cancelled] once [wait] returns. Queued tasks never start after the
  /// child is cancelled; when no task failed, [wait] then throws the child's
  /// cancellation cause, so skipped work is never reported as success.
  static (Pool, Context) withContext(Context parent, {int? limit}) {
    final context = parent.child();
    return (Pool._(context, limit), context);
  }

  final int? limit;
  final Context? _context;
  int _active = 0;
  final _waiting = <Completer<void>>[];
  final _tasks = <Future<void>>[];
  Object? _error;
  StackTrace? _stack;

  void run(Future<void> Function() task) {
    _tasks.add(_run(task));
  }

  Future<void> _run(Future<void> Function() task) async {
    final limit = this.limit;
    if (limit != null && _active >= limit) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _active++;
    try {
      final context = _context;
      if (context != null && context.isCancelled) {
        _fail(context.cause!, StackTrace.current);
        return;
      }
      await task();
    } on Object catch (error, stack) {
      // Kept for wait(); a failed task must not surface as an unhandled
      // asynchronous error before anyone waits.
      _fail(error, stack);
      _context?.cancel(error);
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  void _fail(Object error, StackTrace stack) {
    if (_error != null) return;
    _error = error;
    _stack = stack;
  }

  /// Waits for every task, including ones submitted while waiting; rethrows
  /// the first failure after all finish, like `errgroup.Group.Wait`.
  Future<void> wait() async {
    for (var index = 0; index < _tasks.length; index++) {
      await _tasks[index];
    }
    _tasks.clear();
    _context?.cancel();
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stack!);
  }
}
