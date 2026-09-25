import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('Execution Limits & Sandbox Timeout Tests', () {
    test('maxSteps terminates infinite while loop with ExecutionLimitException',
        () {
      final d4rt = D4rt();
      const source = '''
        void main() {
          while (true) {
            // Infinite loop
          }
        }
      ''';

      expect(
        () => d4rt.execute(source: source, maxSteps: 50),
        throwsA(isA<ExecutionLimitException>()),
      );
    });

    test('maxSteps terminates infinite for loop with ExecutionLimitException',
        () {
      final d4rt = D4rt();
      const source = '''
        void main() {
          for (var i = 0; i >= 0; i++) {
            // Infinite loop
          }
        }
      ''';

      expect(
        () => d4rt.execute(source: source, maxSteps: 100),
        throwsA(isA<ExecutionLimitException>()),
      );
    });

    test('timeout terminates infinite loop with ExecutionTimeoutException', () {
      final d4rt = D4rt();
      const source = '''
        void main() {
          var count = 0;
          while (true) {
            count++;
          }
        }
      ''';

      expect(
        () => d4rt.execute(
            source: source, timeout: const Duration(milliseconds: 100)),
        throwsA(isA<ExecutionTimeoutException>()),
      );
    });

    test('synchronous deadline does not run plugin catch or finally', () {
      final events = <String>[];
      final interpreter = D4rt()
        ..registertopLevelFunction('mark', (visitor, args, named, types) {
          events.add(args.single as String);
          return null;
        });
      expect(
        () => interpreter.execute(source: '''
          void main() {
            try {
              while (true) {}
            } catch (_) {
              mark('caught');
            } finally {
              mark('finally');
            }
          }
        ''', timeout: const Duration(milliseconds: 60)),
        throwsA(isA<ExecutionTimeoutException>()),
      );
      expect(events, isEmpty);
    });

    test('normal execution within limits succeeds', () {
      final d4rt = D4rt();
      const source = '''
        int main() {
          var sum = 0;
          for (var i = 0; i < 10; i++) {
            sum += i;
          }
          return sum;
        }
      ''';

      final result = d4rt.execute(
        source: source,
        maxSteps: 1000,
        timeout: const Duration(seconds: 2),
      );

      expect(result, equals(45));
    });

    test('eval respects timeout and maxSteps limits', () {
      final d4rt = D4rt();
      d4rt.execute(source: 'void main() {}');

      expect(
        () => d4rt.eval('while (true) {}', maxSteps: 20),
        throwsA(isA<ExecutionLimitException>()),
      );
    });
    test('native futures time out terminally for both entrypoints', () async {
      const source = '''
        Future<int> main() async {
          try {
            final value = await pending();
            mark('resumed');
            return value;
          } catch (_) {
            mark('caught');
            return -1;
          }
        }
      ''';
      for (final scenario in ['never', 'lateValue', 'lateError']) {
        final nativeFuture = Completer<int>();
        final events = <String>[];
        final interpreter = D4rt()
          ..registertopLevelFunction(
              'pending', (visitor, args, named, types) => nativeFuture.future)
          ..registertopLevelFunction('mark', (visitor, args, named, types) {
            events.add(args.single as String);
            return null;
          });
        final result = scenario == 'lateValue'
            ? interpreter.executeCompiled(interpreter.compile(source: source),
                timeout: const Duration(milliseconds: 60))
            : interpreter.execute(
                source: source, timeout: const Duration(milliseconds: 60));
        await expectLater(
          (result as Future).timeout(const Duration(seconds: 2)),
          throwsA(isA<ExecutionTimeoutException>()),
        );
        expect(events, isEmpty);
        if (scenario == 'lateValue') {
          nativeFuture.complete(4);
        } else if (scenario == 'lateError') {
          nativeFuture.completeError(StateError('late native failure'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(events, isEmpty,
            reason: 'late native completion must not resume interpreted code');
      }
    });

    test('imported initializer frames stop after invocation timeout', () async {
      const source = '''
        import 'package:probe/worker.dart';
        Future<int> main() async {
          try {
            final value = await work;
            mark('root');
            return value;
          } catch (_) {
            mark('root catch');
            return -1;
          }
        }
      ''';
      const sources = {
        'package:probe/worker.dart': '''
          final Future<int> work = process();
          Future<int> process() async {
            try {
              final value = await pending();
              mark('imported');
              return value;
            } catch (_) {
              mark('imported catch');
              return -1;
            } finally {
              mark('imported finally');
            }
          }
        ''',
      };
      for (final compiled in [false, true]) {
        for (final failLate in [false, true]) {
          final nativeFuture = Completer<int>();
          final events = <String>[];
          final interpreter = D4rt()
            ..registertopLevelFunction(
                'pending', (visitor, args, named, types) => nativeFuture.future)
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          final result = compiled
              ? interpreter.executeCompiled(interpreter.compile(source: source),
                  sources: sources, timeout: const Duration(milliseconds: 80))
              : interpreter.execute(
                  source: source,
                  sources: sources,
                  timeout: const Duration(milliseconds: 80));
          await expectLater(
              (result as Future).timeout(const Duration(seconds: 2)),
              throwsA(isA<ExecutionTimeoutException>()));
          expect(events, isEmpty);
          if (failLate) {
            nativeFuture.completeError(StateError('late'));
          } else {
            nativeFuture.complete(4);
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(events, isEmpty,
              reason: 'neither imported nor root frames may resume');
        }
      }
    });

    test('predeadline native errors remain catchable by interpreted code',
        () async {
      final nativeFuture = Completer<int>();
      final events = <String>[];
      final interpreter = D4rt()
        ..registertopLevelFunction(
            'pending', (visitor, args, named, types) => nativeFuture.future)
        ..registertopLevelFunction('mark', (visitor, args, named, types) {
          events.add(args.single as String);
          return null;
        });
      final result = interpreter.execute(source: '''
            Future<int> main() async {
              try {
                await pending();
                return 1;
              } catch (_) {
                mark('caught');
                return 2;
              }
            }
          ''', timeout: const Duration(seconds: 2)) as Future;
      nativeFuture.completeError(StateError('expected'));
      expect(await result.timeout(const Duration(seconds: 2)), 2);
      expect(events, ['caught']);
    });

    test('elapsed deadline beats an overdue timeout timer', () async {
      const source = '''
        Future<int> main() async {
          try {
            final value = await pending();
            mark('resumed');
            return value;
          } catch (_) {
            mark('caught');
            return -1;
          } finally {
            mark('finally');
          }
        }
      ''';
      for (final compiled in [false, true]) {
        for (final failNative in [false, true]) {
          final nativeFuture = Completer<int>();
          final events = <String>[];
          final interpreter = D4rt()
            ..registertopLevelFunction(
                'pending', (visitor, args, named, types) => nativeFuture.future)
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          final result = compiled
              ? interpreter.executeCompiled(interpreter.compile(source: source),
                  timeout: const Duration(milliseconds: 100))
              : interpreter.execute(
                  source: source, timeout: const Duration(milliseconds: 100));
          final pendingResult = result as Future;
          final blocked = Completer<void>();
          Timer(const Duration(milliseconds: 1), () {
            final clock = Stopwatch()..start();
            while (clock.elapsed < const Duration(milliseconds: 130)) {}
            if (failNative) {
              nativeFuture.completeError(StateError('overdue native failure'));
            } else {
              nativeFuture.complete(5);
            }
            blocked.complete();
          });
          await blocked.future;
          await expectLater(pendingResult.timeout(const Duration(seconds: 2)),
              throwsA(isA<ExecutionTimeoutException>()));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(events, isEmpty,
              reason: 'native completion must not beat the overdue timer');
        }
      }
    });

    test('reentrant same-instance calls keep their own deadlines', () async {
      const outerSource = '''
        dynamic main() {
          reenter();
          return work();
        }
        Future<int> work() async {
          final value = await pending('outer');
          mark('outer');
          return value;
        }
      ''';
      const innerSource = '''
        Future<int> main() async {
          final value = await pending('inner');
          mark('inner');
          return value;
        }
      ''';
      for (final outerCompiled in [false, true]) {
        for (final outerShorter in [false, true]) {
          final outerNative = Completer<int>();
          final innerNative = Completer<int>();
          final events = <String>[];
          Future? inner;
          final interpreter = D4rt()
            ..registertopLevelFunction('pending',
                (visitor, args, named, types) {
              return args.single == 'outer'
                  ? outerNative.future
                  : innerNative.future;
            })
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          interpreter.registertopLevelFunction('reenter',
              (visitor, args, named, types) {
            inner = outerCompiled
                ? interpreter.execute(
                    source: innerSource,
                    timeout: Duration(milliseconds: outerShorter ? 1000 : 80),
                  ) as Future
                : interpreter.executeCompiled(
                    interpreter.compile(source: innerSource),
                    timeout: Duration(milliseconds: outerShorter ? 1000 : 80),
                  ) as Future;
            return null;
          });
          final outer = (outerCompiled
              ? interpreter.executeCompiled(
                  interpreter.compile(source: outerSource),
                  timeout: Duration(milliseconds: outerShorter ? 80 : 1000),
                )
              : interpreter.execute(
                  source: outerSource,
                  timeout: Duration(milliseconds: outerShorter ? 80 : 1000),
                )) as Future;
          expect(inner, isNotNull,
              reason: 'host callback must reenter before outer returns');
          if (outerShorter) {
            await expectLater(outer.timeout(const Duration(seconds: 2)),
                throwsA(isA<ExecutionTimeoutException>()));
            innerNative.complete(7);
            expect(await inner!.timeout(const Duration(seconds: 2)), 7);
            outerNative.complete(3);
            expect(events, ['inner']);
          } else {
            await expectLater(inner!.timeout(const Duration(seconds: 2)),
                throwsA(isA<ExecutionTimeoutException>()));
            outerNative.complete(3);
            expect(await outer.timeout(const Duration(seconds: 2)), 3);
            innerNative.complete(7);
            expect(events, ['outer']);
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(events, outerShorter ? ['inner'] : ['outer'],
              reason: 'late native completion cannot resume plugin');
        }
      }
    });

    test('initializer reentry keeps outer visitor, module and deadlines',
        () async {
      const root = '''
        final int seed = reenter();
        Future<int> main() async {
          final value = await pending('outer');
          mark('outer');
          return seed + value;
        }
      ''';
      const importing = '''
        import 'package:probe/seed.dart';
        Future<int> main() async {
          final value = await pending('outer');
          mark('outer');
          return seed + value;
        }
      ''';
      const imported = {
        'package:probe/seed.dart': 'final int seed = reenter();'
      };
      const nested = '''
        Future<int> main() async {
          final value = await pending('inner');
          mark('inner');
          return value;
        }
      ''';
      for (final importedInitializer in [false, true]) {
        for (final compiled in [false, true]) {
          for (final outerShorter in [false, true]) {
            final outerNative = Completer<int>();
            final innerNative = Completer<int>();
            final events = <String>[];
            Future? inner;
            final interpreter = D4rt()
              ..registertopLevelFunction('pending',
                  (visitor, args, named, types) {
                return args.single == 'outer'
                    ? outerNative.future
                    : innerNative.future;
              })
              ..registertopLevelFunction('mark', (visitor, args, named, types) {
                events.add(args.single as String);
                return null;
              });
            interpreter.registertopLevelFunction('reenter',
                (visitor, args, named, types) {
              inner = compiled
                  ? interpreter.execute(
                      source: nested,
                      timeout:
                          Duration(milliseconds: outerShorter ? 1000 : 120),
                    ) as Future
                  : interpreter.executeCompiled(
                      interpreter.compile(source: nested),
                      timeout:
                          Duration(milliseconds: outerShorter ? 1000 : 120),
                    ) as Future;
              return 10;
            });
            final source = importedInitializer ? importing : root;
            final outer = (compiled
                ? interpreter.executeCompiled(
                    interpreter.compile(source: source),
                    sources: importedInitializer ? imported : null,
                    timeout: Duration(milliseconds: outerShorter ? 120 : 1000),
                  )
                : interpreter.execute(
                    source: source,
                    sources: importedInitializer ? imported : null,
                    timeout: Duration(milliseconds: outerShorter ? 120 : 1000),
                  )) as Future;
            expect(inner, isNotNull);
            if (outerShorter) {
              await expectLater(outer.timeout(const Duration(seconds: 3)),
                  throwsA(isA<ExecutionTimeoutException>()));
              innerNative.complete(7);
              expect(await inner!.timeout(const Duration(seconds: 3)), 7);
              outerNative.complete(3);
              expect(events, ['inner']);
            } else {
              await expectLater(inner!.timeout(const Duration(seconds: 3)),
                  throwsA(isA<ExecutionTimeoutException>()));
              outerNative.complete(3);
              expect(await outer.timeout(const Duration(seconds: 3)), 13);
              innerNative.complete(7);
              expect(events, ['outer']);
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
            expect(events, outerShorter ? ['inner'] : ['outer']);
          }
        }
      }
    });

    test('slow native callbacks stop same-expression and initializer calls',
        () {
      const mainExpression = '''
        int main() {
          try {
            return slow() + next();
          } catch (_) {
            mark('caught');
            return -1;
          } finally {
            mark('finally');
          }
        }
      ''';
      const rootInitializer = '''
        final int seed = slow() + next();
        int main() => seed;
      ''';
      const importing = '''
        import 'package:probe/slow.dart';
        int main() => seed;
      ''';
      const imported = {
        'package:probe/slow.dart': 'final int seed = slow() + next();'
      };
      const cascade = '''
        class Probe {
          void first() { slow(); }
          void second() { next(); }
        }
        int main() {
          try {
            Probe()..first()..second();
          } catch (_) {
            mark('caught');
          } finally {
            mark('finally');
          }
          return 1;
        }
      ''';
      for (final compiled in [false, true]) {
        for (final scenario in [
          'main',
          'root',
          'import',
          'loaded',
          'cascade'
        ]) {
          if (compiled && scenario == 'loaded') continue;
          var slowCalls = 0;
          var laterCalls = 0;
          final events = <String>[];
          final interpreter = D4rt()
            ..registertopLevelFunction('slow', (visitor, args, named, types) {
              slowCalls++;
              final clock = Stopwatch()..start();
              while (clock.elapsed < const Duration(milliseconds: 150)) {}
              return 1;
            })
            ..registertopLevelFunction('next', (visitor, args, named, types) {
              laterCalls++;
              return 2;
            })
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          final source = switch (scenario) {
            'root' || 'loaded' => rootInitializer,
            'import' => importing,
            'cascade' => cascade,
            _ => mainExpression,
          };
          expect(
            () => compiled
                ? interpreter.executeCompiled(
                    interpreter.compile(source: source),
                    sources: scenario == 'import' ? imported : null,
                    timeout: const Duration(milliseconds: 100),
                  )
                : interpreter.execute(
                    source: scenario == 'loaded' ? null : source,
                    library: scenario == 'loaded'
                        ? 'package:probe/entry.dart'
                        : null,
                    sources: switch (scenario) {
                      'import' => imported,
                      'loaded' => {'package:probe/entry.dart': rootInitializer},
                      _ => null,
                    },
                    timeout: const Duration(milliseconds: 100),
                  ),
            throwsA(isA<ExecutionTimeoutException>()),
            reason: '$scenario compiled=$compiled',
          );
          expect(slowCalls, 1, reason: '$scenario compiled=$compiled');
          expect(laterCalls, 0, reason: '$scenario compiled=$compiled');
          expect(events, isEmpty, reason: '$scenario compiled=$compiled');
        }
      }
    });

    test('overlapping native futures retain independent deadlines', () async {
      const source = '''
        Future<int> main() async {
          final value = await pending();
          mark(value);
          return value;
        }
      ''';
      final firstNative = Completer<int>();
      final secondNative = Completer<int>();
      var calls = 0;
      final observed = <int>[];
      final interpreter = D4rt()
        ..registertopLevelFunction('pending', (visitor, args, named, types) {
          return calls++ == 0 ? firstNative.future : secondNative.future;
        })
        ..registertopLevelFunction('mark', (visitor, args, named, types) {
          observed.add(args.single as int);
          return null;
        });
      final first = interpreter.execute(
          source: source, timeout: const Duration(milliseconds: 80)) as Future;
      final second = interpreter.executeCompiled(
          interpreter.compile(source: source),
          timeout: const Duration(seconds: 1)) as Future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      // The first call remains pending while the second completes normally.
      secondNative.complete(8);
      expect(await second.timeout(const Duration(seconds: 2)), 8);
      await expectLater(first.timeout(const Duration(seconds: 2)),
          throwsA(isA<ExecutionTimeoutException>()));
      expect(observed, [8]);
      firstNative.complete(3);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(observed, [8], reason: 'late first invocation must stay terminal');
      expect(interpreter.execute(source: 'int main() => 10;'), 10);
    });
  });
}
