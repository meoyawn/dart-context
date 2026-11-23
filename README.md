# context

Go-style cancellation for Dart: `context.Context`, an injectable clock, and an
`errgroup`-like bounded task pool. No dependencies.

```dart
import 'package:context/context.dart';

Future<void> main() async {
  final ctx = Context.background.child();

  // Cancelling a context cancels every child with the same cause.
  final request = ctx.child();
  request.onCancel((cause) => print('request stopped: $cause'));

  // guard() throws the cancellation cause as soon as the context is cancelled.
  final body = request.guard(fetchSomething());

  // sleep() waits on an injectable clock and returns false when cancelled.
  await ctx.sleep(const Duration(seconds: 1), clock: const SystemClock());

  ctx.cancel(const Cancelled('shutting down'));
  await body.catchError((Object _) => '');

  // Like errgroup.WithContext: at most 4 tasks run at once, the first failure
  // cancels `group` (with that failure as its cause), queued tasks never start
  // after it is cancelled, and wait() rethrows the first failure once every
  // started task has finished.
  final (pool, group) = Pool.withContext(Context.background, limit: 4);
  for (final url in ['a', 'b', 'c']) {
    pool.run(() => download(group, url));
  }
  await pool.wait();
}
```

| Go                          | Dart                         |
| --------------------------- | ---------------------------- |
| `context.Background()`      | `Context.background`         |
| `context.WithCancelCause`   | `ctx.child()` + `cancel(cause)` |
| `context.WithoutCancel`     | `ctx.withoutCancel()`        |
| `context.AfterFunc`         | `ctx.onCancel(callback)`     |
| `ctx.Done()` / `Cause(ctx)` | `ctx.done` / `ctx.cause`     |
| `clockwork.Clock`           | `Clock`, `SystemClock`, `FakeClock` |
| `errgroup.WithContext`      | `Pool.withContext(ctx)`      |
| `errgroup.Group.SetLimit`   | `Pool(limit: n)`             |

`FakeClock` moves only when you call `advance`, and `blockUntilTimer()` lets a
test wait until the code under test has started a timer.

## Install

```yaml
dependencies:
  context:
    git: https://github.com/meoyawn/dart-context
```
