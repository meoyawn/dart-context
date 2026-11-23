import 'package:context/context.dart';
import 'package:test/test.dart';

void main() {
  test('cancelling a parent cancels its children with the same cause', () async {
    final parent = Context.background.child();
    final child = parent.child();
    parent.cancel('stop');
    expect(child.isCancelled, isTrue);
    expect(await child.done, 'stop');
  });

  test('cancelling a child leaves the parent running', () {
    final parent = Context.background.child();
    parent.child().cancel();
    expect(parent.isCancelled, isFalse);
  });

  test('the first cause wins', () {
    final context = Context.background.child()
      ..cancel('first')
      ..cancel('second');
    expect(context.cause, 'first');
  });

  test('withoutCancel survives its parent', () {
    final parent = Context.background.child();
    final detached = parent.withoutCancel();
    parent.cancel();
    expect(detached.isCancelled, isFalse);
  });

  test('guard throws the cause before the future completes', () async {
    final context = Context.background.child();
    final pending = context.guard(Future<void>.delayed(const Duration(hours: 1)));
    context.cancel(const Cancelled('gone'));
    await expectLater(pending, throwsA(isA<Cancelled>()));
  });

  test('onCancel unregisters', () {
    final context = Context.background.child();
    var calls = 0;
    final unregister = context.onCancel((_) => calls++);
    expect(unregister(), isTrue);
    context.cancel();
    expect(calls, 0);
  });

  test('sleep follows a fake clock and stops on cancel', () async {
    final clock = FakeClock();
    final context = Context.background.child();
    final slept = context.sleep(const Duration(seconds: 5), clock: clock);
    await clock.blockUntilTimer();
    clock.advance(const Duration(seconds: 5));
    expect(await slept, isTrue);

    final interrupted = context.sleep(const Duration(seconds: 5), clock: clock);
    context.cancel();
    expect(await interrupted, isFalse);
  });

  test('pool bounds concurrency and rethrows the first failure after all tasks', () async {
    final pool = Pool(2);
    var active = 0, peak = 0, finished = 0;
    for (var i = 0; i < 6; i++) {
      pool.run(() async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration.zero);
        active--;
        finished++;
        if (i == 1) throw StateError('task $i');
      });
    }
    await expectLater(pool.wait(), throwsA(isA<StateError>()));
    expect(peak, 2);
    expect(finished, 6);
  });
}
