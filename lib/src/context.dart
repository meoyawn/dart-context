import 'dart:async';

import 'clock.dart';

/// Thrown when work stops because its [Context] was cancelled.
class Cancelled implements Exception {
  const Cancelled([this.reason = 'operation cancelled']);
  final String reason;
  @override
  String toString() => reason;
}

/// Cancellation scope for asynchronous work, the counterpart of Go's
/// `context.Context`. Children are cancelled with their parent; cancelling a
/// child never affects the parent. The first cause wins.
final class Context {
  Context._(this._parent, {this._detached = false}) {
    final parent = _parent;
    if (parent != null && !_detached) {
      if (parent.isCancelled) {
        _cause = parent._cause;
        _done.complete(_cause!);
      } else {
        parent._children.add(this);
      }
    }
  }

  /// A root that is never cancelled.
  static final Context background = Context._(null);

  final Context? _parent;
  final bool _detached;
  final _children = <Context>{};
  final _done = Completer<Object>();
  final _callbacks = <void Function(Object)>[];
  Object? _cause;

  /// A cancellable child of this context.
  Context child() => Context._(this);

  /// A child that keeps running when this context is cancelled, like Go's
  /// `context.WithoutCancel`, for cleanup or writes that must finish.
  Context withoutCancel() => Context._(this, detached: true);

  bool get isCancelled => _cause != null;

  /// The cancellation cause, or null while the context is live.
  Object? get cause => _cause;

  /// Completes with the cause when this context is cancelled.
  Future<Object> get done => _done.future;

  void cancel([Object cause = const Cancelled()]) {
    if (_cause != null) return;
    _cause = cause;
    _parent?._children.remove(this);
    _done.complete(cause);
    for (final callback in List.of(_callbacks)) {
      callback(cause);
    }
    _callbacks.clear();
    for (final child in List.of(_children)) {
      child.cancel(cause);
    }
    _children.clear();
  }

  /// Runs [callback] once on cancellation; returns a function that unregisters
  /// it and reports whether it had not run yet (Go's `context.AfterFunc`).
  bool Function() onCancel(void Function(Object cause) callback) {
    if (_cause != null) {
      callback(_cause!);
      return () => false;
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  void throwIfCancelled() {
    final cause = _cause;
    if (cause != null) throw cause;
  }

  /// Completes like [future], or throws the cancellation cause first.
  Future<T> guard<T>(Future<T> future) {
    if (_cause != null) {
      future.ignore();
      return Future.error(_cause!);
    }
    final result = Completer<T>();
    final unregister = onCancel((cause) {
      if (!result.isCompleted) result.completeError(cause);
    });
    future.then((value) {
      unregister();
      if (!result.isCompleted) result.complete(value);
    }, onError: (Object error, StackTrace stack) {
      unregister();
      if (!result.isCompleted) result.completeError(error, stack);
    });
    return result.future;
  }

  /// Waits [duration] on [clock] unless cancelled first; returns false when
  /// cancelled.
  Future<bool> sleep(Duration duration, {required Clock clock}) async {
    if (isCancelled) return false;
    final timer = clock.timer(duration);
    try {
      await guard(timer.fired);
      return true;
    } on Object {
      if (isCancelled) return false;
      rethrow;
    } finally {
      timer.cancel();
    }
  }
}

