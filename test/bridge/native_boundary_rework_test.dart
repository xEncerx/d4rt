import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

enum NativeSignal { failed }

class NativeBase {}

void main() {
  test('retained instance uses the active caller step budget', () {
    final retained = D4rt();
    retained.execute(
      source: '''
      class Worker {
        int work() { var n = 0; while (n < 1000) { n++; } return n; }
      }
      main() => Worker();
    ''',
    );
    final caller = D4rt()
      ..registertopLevelFunction(
        'callRetained',
        (visitor, args, named, types) => retained.invoke('work', []),
      );
    expect(
      () => caller.execute(source: 'main() => callRetained();', maxSteps: 60),
      throwsA(isA<ExecutionLimitException>()),
    );
    expect(retained.invoke('work', []), 1000);
  });

  for (final scoped in [false, true]) {
    for (final asynchronous in [false, true]) {
      test(
        'registered native failure scoped=$scoped async=$asynchronous',
        () async {
          final failure = StateError('registered failure');
          final stack = StackTrace.fromString('registered-source-frame');
          Object? fail(
            InterpreterVisitor visitor,
            List<Object?> positional,
            Map<String, Object?> named,
            List<RuntimeType>? types,
          ) {
            if (asynchronous) return Future<Object?>.error(failure, stack);
            Error.throwWithStackTrace(failure, stack);
          }

          final interpreter = D4rt();
          if (scoped) {
            interpreter.registerLibraryFunction(
              'package:sample/native.dart',
              'fail',
              fail,
            );
          } else {
            interpreter.registertopLevelFunction('fail', fail);
          }
          final source =
              "${scoped ? "import 'package:sample/native.dart';" : ''} main() => fail();";
          try {
            final result = interpreter.execute(source: source);
            if (result is Future) await result;
            failTest('Expected native failure');
          } catch (error, observedStack) {
            expect(error, same(failure));
            expect(
              observedStack.toString(),
              contains('registered-source-frame'),
            );
          }
        },
      );
    }
  }

  test('native inherited failure respects terminal deadline', () {
    final failure = StateError('native adapter');
    final trace = StackTrace.fromString('adapter-source-frame');
    var expire = false;
    final interpreter = D4rt()
      ..registerBridgedClass(
        BridgedClass(
          nativeType: NativeBase,
          name: 'NativeBase',
          constructors: {'': (visitor, positional, named) => NativeBase()},
          methods: {
            'work': (visitor, target, positional, named) {
              if (expire) visitor.deadline!.expire();
              Error.throwWithStackTrace(failure, trace);
            },
          },
        ),
        'package:sample/base.dart',
      );
    interpreter.execute(
      source: '''
      import 'package:sample/base.dart';
      class Child extends NativeBase {}
      main() => Child();
    ''',
      timeout: const Duration(seconds: 10),
    );
    try {
      interpreter.invoke('work', []);
      failTest('Expected native failure');
    } catch (error, stack) {
      expect(error, same(failure));
      expect(stack.toString(), contains('adapter-source-frame'));
    }
    expire = true;
    expect(
      () => interpreter.invoke('work', []),
      throwsA(isA<ExecutionTimeoutException>()),
    );
  });

  test(
    'native observers and guest async failures receive native enum',
    () async {
      final interpreter = D4rt()
        ..registerBridgedEnum(
          BridgedEnumDefinition<NativeSignal>(
            name: 'NativeSignal',
            values: NativeSignal.values,
          ),
          'package:sample/signal.dart',
        );
      Object? observed;
      interpreter.registertopLevelFunction('observe', (
        visitor,
        args,
        named,
        types,
      ) {
        try {
          InterpreterVisitor.invokeCallback(args.single as Callable, []);
        } catch (error) {
          observed = error;
        }
        return null;
      });
      await interpreter.execute(
        source: '''
      import 'package:sample/signal.dart';
      Future<void> main() async {
        observe(() { throw NativeSignal.failed; });
      }
    ''',
      );
      expect(observed, same(NativeSignal.failed));
      final failed =
          interpreter.execute(
                source: '''
      import 'package:sample/signal.dart';
      Future<void> main() async { throw NativeSignal.failed; }
    ''',
              )
              as Future;
      await expectLater(failed, throwsA(same(NativeSignal.failed)));
    },
  );
}

Never failTest(String message) => throw StateError(message);
