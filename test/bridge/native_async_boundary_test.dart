import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  test(
    'imported helper observes failed native future after synchronous prefix',
    () async {
      final events = <String>[];
      final failure = StateError('native failure');
      final sourceStack = StackTrace.fromString('native-source-frame');
      final future = Future<Object?>.error(failure, sourceStack);
      Object? caught;
      StackTrace? stack;
      Object? supplied;
      final interpreter = D4rt()
        ..registertopLevelFunction(
          'source',
          (visitor, args, named, types) => future,
        )
        ..registertopLevelFunction('mark', (visitor, args, named, types) {
          events.add(args.single as String);
          return null;
        })
        ..registertopLevelFunction('inspect', (visitor, args, named, types) {
          supplied = args[0];
          caught = args[1];
          stack = args[2] as StackTrace;
          return null;
        });
      final result =
          interpreter.execute(
                library: 'package:sample/main.dart',
                sources: {
                  'package:sample/main.dart': '''
          import 'helper.dart';
          Future<void> main() => helper(source());
        ''',
                  'package:sample/helper.dart': '''
          Future<void> helper(Future<Object?> input) async {
            mark('prefix');
            try { await input; }
            catch (error, trace) { inspect(input, error, trace); }
          }
        ''',
                },
              )
              as Future;
      expect(events, ['prefix']);
      await result;
      expect(identical(supplied, future), isTrue);
      expect(identical(caught, failure), isTrue);
      expect(stack.toString(), contains('native-source-frame'));
    },
  );

  test('catch and finally run before the first real suspension', () async {
    final events = <String>[];
    final pending = Completer<void>();
    final interpreter = D4rt()
      ..registertopLevelFunction('mark', (visitor, args, named, types) {
        events.add(args.single as String);
        return null;
      })
      ..registertopLevelFunction(
        'pending',
        (visitor, args, named, types) => pending.future,
      );
    final result =
        interpreter.execute(
              source: '''
      Future<void> main() async {
        try { throw 'failure'; }
        catch (_) { mark('catch'); }
        finally { mark('finally'); }
        mark('before await');
        await pending();
        mark('after await');
      }
    ''',
            )
            as Future;
    expect(events, ['catch', 'finally', 'before await']);
    pending.complete();
    await result;
    expect(events, ['catch', 'finally', 'before await', 'after await']);
  });

  test(
    'handling one native branch does not consume an independent failure',
    () async {
      final failure = StateError('independent');
      final unhandled = Completer<Object>();
      late Future result;
      runZonedGuarded(() {
        final interpreter = D4rt()
          ..registertopLevelFunction('fork', (visitor, args, named, types) {
            final source = Future<int>.value(4);
            source.then<void>((_) => throw failure);
            return source.then((value) => value + 1);
          });
        result =
            interpreter.execute(
                  source: 'Future<int> main() async => await fork();',
                )
                as Future;
      }, (error, stack) => unhandled.complete(error));
      expect(await result, 5);
      expect(await unhandled.future, same(failure));
    },
  );

  test('sync throw in Future.sync reaches host as original object', () async {
    final failure = StateError('callback failure');
    final interpreter = D4rt()
      ..registertopLevelFunction(
        'failure',
        (visitor, args, named, types) => failure,
      );
    final result =
        interpreter.execute(
              source: '''
      Future<Object?> main() => Future.sync(() { throw failure(); });
    ''',
            )
            as Future;
    await expectLater(result, throwsA(same(failure)));
  });

  for (final expression in [
    'Future.value(1).then((value) { throw failure(); })',
    'Future.error(failure()).catchError((error) { throw failure(); })',
  ]) {
    test('native Future callback exposes raw failure: $expression', () async {
      final failure = StateError('callback failure');
      final interpreter = D4rt()
        ..registertopLevelFunction(
          'failure',
          (visitor, args, named, types) => failure,
        );
      final result =
          interpreter.execute(source: 'main() => $expression;') as Future;
      await expectLater(result, throwsA(same(failure)));
    });
  }
  test(
    'invoke terminates at the original deadline and ignores late completion',
    () async {
      final pending = Completer<void>();
      final effects = <String>[];
      final interpreter = D4rt()
        ..registertopLevelFunction(
          'pending',
          (visitor, args, named, types) => pending.future,
        )
        ..registertopLevelFunction('mark', (visitor, args, named, types) {
          effects.add(args.single as String);
          return null;
        });
      interpreter.execute(
        source: '''
        class Worker {
          Future<void> work() async { await pending(); mark('late'); }
        }
        main() => Worker();
      ''',
        timeout: const Duration(seconds: 1),
      );
      final result = interpreter.invoke('work', []) as Future;
      await expectLater(result, throwsA(isA<ExecutionTimeoutException>()));
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(effects, isEmpty);
      expect(interpreter.execute(source: 'main() => 42;'), 42);
    },
  );
  test(
    'direct function invocation times out a never-completing native future',
    () async {
      final pending = Completer<void>();
      final interpreter = D4rt()
        ..registertopLevelFunction(
          'pending',
          (visitor, args, named, types) => pending.future,
        );
      final function =
          interpreter.execute(
                source: '''
        Future<void> work() async { await pending(); }
        main() => work;
      ''',
                timeout: const Duration(seconds: 1),
              )
              as InterpretedFunction;
      final result =
          interpreter.invokeInterpretedFunction(function, []) as Future;
      await expectLater(result, throwsA(isA<ExecutionTimeoutException>()));
      pending.complete();
    },
  );
}
