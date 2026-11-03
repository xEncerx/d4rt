import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

Object? _executeEntry(
  D4rt interpreter,
  String mode,
  String source, {
  Map<String, String> sources = const {},
  int? maxSteps,
  Duration? timeout,
}) {
  return switch (mode) {
    'library' => interpreter.execute(
      library: 'package:probe/entry.dart',
      sources: {'package:probe/entry.dart': source, ...sources},
      maxSteps: maxSteps,
      timeout: timeout,
    ),
    'compiled' => interpreter.executeCompiled(
      interpreter.compile(source: source),
      sources: sources,
      maxSteps: maxSteps,
      timeout: timeout,
    ),
    _ => interpreter.execute(
      source: source,
      sources: sources,
      maxSteps: maxSteps,
      timeout: timeout,
    ),
  };
}

void main() {
  group('Root extension interpreted constructor limits', () {
    for (final mode in ['source', 'compiled', 'library']) {
      for (final named in [false, true]) {
        final constructor = named ? 'Worker.named' : 'Worker';
        final root =
            '''
          import 'package:probe/worker.dart';
          extension Holder on int { static final value = $constructor(); }
          int main() => 7;
        ''';
        test('$mode $constructor preserves initialization step exhaustion', () {
          final effects = <int>[];
          final interpreter = D4rt()
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              effects.add(args.single as int);
              return null;
            });
          final sources = {
            'package:probe/worker.dart':
                '''
              class Worker {
                $constructor() {
                  var n = 0;
                  while (n < 1000) { n++; }
                  mark(n);
                }
              }
            ''',
          };
          expect(
            () => _executeEntry(
              interpreter,
              mode,
              root,
              sources: sources,
              maxSteps: 100,
            ),
            throwsA(
              isA<ExecutionLimitException>().having(
                (error) => error.maxSteps,
                'maxSteps',
                100,
              ),
            ),
          );
          expect(effects, isEmpty);
          expect(
            _executeEntry(
              interpreter,
              mode,
              root,
              sources: sources,
              maxSteps: 100000,
            ),
            7,
          );
          expect(effects, [
            1000,
          ], reason: 'the constructor must actually finish');
        });

        test(
          '$mode $constructor preserves terminal initialization timeout',
          () {
            final effects = <int>[];
            final interpreter = D4rt()
              ..registertopLevelFunction('slow', (visitor, args, named, types) {
                final clock = Stopwatch()..start();
                while (clock.elapsed < const Duration(milliseconds: 160)) {}
                return null;
              })
              ..registertopLevelFunction('mark', (visitor, args, named, types) {
                effects.add(args.single as int);
                return null;
              });
            final sources = {
              'package:probe/worker.dart':
                  '''
              class Worker { $constructor() { slow(); mark(1000); } }
            ''',
            };
            expect(
              () => _executeEntry(
                interpreter,
                mode,
                root,
                sources: sources,
                timeout: const Duration(milliseconds: 100),
              ),
              throwsA(isA<ExecutionTimeoutException>()),
            );
            expect(effects, isEmpty);
            expect(
              _executeEntry(
                interpreter,
                mode,
                root,
                sources: sources,
                timeout: const Duration(seconds: 2),
              ),
              7,
            );
            expect(effects, [1000]);
          },
        );

        test(
          '$mode $constructor retains ordinary diagnostics and error policy',
          () {
            const diagnostic = 'ordinary constructor failure';
            final interpreter = D4rt()
              ..registertopLevelFunction('fail', (visitor, args, named, types) {
                throw RuntimeError(diagnostic);
              });
            final sources = {
              'package:probe/worker.dart':
                  '''
              class Worker { $constructor() { fail(); } }
            ''',
            };
            final prefix = named
                ? "Error during named constructor 'named' for class 'Worker':"
                : "Error during constructor execution for class 'Worker':";
            expect(
              () => _executeEntry(
                interpreter,
                mode,
                "import 'package:probe/worker.dart'; main() => $constructor();",
                sources: sources,
              ),
              throwsA(
                isA<RuntimeError>()
                    .having(
                      (error) => error.message,
                      'message',
                      contains(prefix),
                    )
                    .having(
                      (error) => error.message,
                      'message',
                      contains(diagnostic),
                    ),
              ),
            );
            if (mode == 'library') {
              expect(
                () => _executeEntry(interpreter, mode, root, sources: sources),
                throwsA(
                  isA<RuntimeError>().having(
                    (error) => error.message,
                    'message',
                    contains(diagnostic),
                  ),
                ),
              );
            } else {
              // Preserve the existing non-limit extension warning policy.
              expect(
                _executeEntry(interpreter, mode, root, sources: sources),
                7,
              );
            }
          },
        );
      }
    }
  });

  group('Invocation-wide module budgets', () {
    const loop = '''
      int work(int count) {
        var value = 0;
        for (var i = 0; i < count; i++) { value++; }
        return value;
      }
    ''';
    for (final mode in ['source', 'compiled', 'library']) {
      for (final constructor in ['ListQueue.from']) {
        test('$mode preserves limits in imported $constructor callbacks', () {
          final sources = {
            'package:probe/constructor.dart':
                '''
              import 'dart:collection';
              $loop
              final initialized =
                  $constructor([1].map((entry) => work(1000) + entry));
            ''',
          };
          const root = '''
            import 'package:probe/constructor.dart';
            main() => initialized.toList();
          ''';
          expect(
            () => _executeEntry(
              D4rt(),
              mode,
              root,
              sources: sources,
              maxSteps: 100,
            ),
            throwsA(isA<ExecutionLimitException>()),
          );
          expect(
            _executeEntry(
              D4rt(),
              mode,
              root,
              sources: sources,
              maxSteps: 100000,
            ),
            [1001],
          );
        });
      }

      test(
        '$mode root extension initialization keeps invocation authority',
        () {
          const source = '''
          extension Holder on int {
            static final values = List.unmodifiable([1].map((entry) {
              var n = 0;
              while (n < 1000) { n++; }
              return n + entry;
            }));
          }
          main() => Holder.values;
        ''';
          expect(
            () => _executeEntry(D4rt(), mode, source, maxSteps: 100),
            throwsA(isA<ExecutionLimitException>()),
          );
          expect(_executeEntry(D4rt(), mode, source, maxSteps: 100000), [1001]);
        },
      );

      test('$mode retained callbacks charge the consuming invocation', () {
        var effects = 0;
        final interpreter = D4rt()
          ..registertopLevelFunction(
            'touch',
            (visitor, args, named, types) => ++effects,
          );
        final retained =
            _executeEntry(
                  interpreter,
                  mode,
                  '''
          import 'package:probe/retained.dart';
          main() => values;
        ''',
                  sources: {
                    'package:probe/retained.dart':
                        '''
            $loop
            final values = [1].map((entry) {
              final n = work(30);
              touch();
              return n + entry;
            });
          ''',
                  },
                  maxSteps: 1000,
                )
                as Iterable;
        expect(() => retained.single, throwsA(isA<RuntimeError>()));
        expect(effects, 0);
        interpreter.registertopLevelFunction(
          'retained',
          (visitor, args, named, types) => retained,
        );
        expect(
          _executeEntry(
            interpreter,
            mode,
            'main() => retained().toList();',
            maxSteps: 100,
          ),
          [31],
        );
        expect(effects, 1);
        effects = 0;
        expect(
          () => _executeEntry(interpreter, mode, '''
            $loop
            int main() { work(30); return retained().single; }
          ''', maxSteps: 100),
          throwsA(isA<ExecutionLimitException>()),
        );
        expect(effects, 0);
      });

      for (final declaration in [
        'final initialized = work(1000);',
        'class Holder { static final initialized = work(1000); }',
        'mixin Holder { static final initialized = work(1000); }',
        'enum Holder { only; static final initialized = work(1000); }',
        'extension Holder on int { static final initialized = work(1000); }',
      ]) {
        test('$mode bounds imported $declaration', () {
          const root = "import 'package:probe/work.dart'; int main() => 7;";
          final sources = {
            'package:probe/work.dart':
                '''
              $loop $declaration
              ${declaration.startsWith('enum') ? 'final observed = Holder.initialized;' : ''}
            ''',
          };
          expect(
            () => _executeEntry(
              D4rt(),
              mode,
              root,
              sources: sources,
              maxSteps: 100,
            ),
            throwsA(
              isA<ExecutionLimitException>().having(
                (error) => error.maxSteps,
                'maxSteps',
                100,
              ),
            ),
          );
          expect(
            _executeEntry(
              D4rt(),
              mode,
              root,
              sources: sources,
              maxSteps: 100000,
            ),
            7,
          );
        });
      }

      for (final declaration in [
        'class Holder',
        'mixin Holder',
        'enum Holder',
        'extension Holder on int',
      ]) {
        test('$mode charges native callbacks in imported $declaration', () {
          final source = '''
            import 'package:probe/callback.dart';
            main() => Holder.entries;
          ''';
          final sources = {
            'package:probe/callback.dart':
                '''
              $loop
              $declaration {
                ${declaration.startsWith('enum') ? 'only;' : ''}
                static final entries =
                    List.unmodifiable([1, 2].map((value) => work(1000) + value));
              }
              ${declaration.startsWith('enum') ? 'final observed = Holder.entries;' : ''}
            ''',
          };
          expect(
            () => _executeEntry(
              D4rt(),
              mode,
              source,
              sources: sources,
              maxSteps: 100,
            ),
            throwsA(isA<ExecutionLimitException>()),
          );
          expect(
            _executeEntry(
              D4rt(),
              mode,
              source,
              sources: sources,
              maxSteps: 100000,
            ),
            [1001, 1002],
          );
        });
      }

      test('$mode charges supported extension-type initializer callbacks', () {
        const source = '''
          import 'package:probe/extension_type.dart';
          main() => initialized;
        ''';
        final sources = {
          'package:probe/extension_type.dart':
              '''
            $loop
            extension type Holder(int value) {
              int calculate() =>
                  [1, 2].map((entry) => work(1000) + entry).toList()[0];
            }
            final initialized = Holder(0).calculate();
          ''',
        };
        expect(
          () => _executeEntry(
            D4rt(),
            mode,
            source,
            sources: sources,
            maxSteps: 100,
          ),
          throwsA(isA<ExecutionLimitException>()),
        );
        expect(
          _executeEntry(
            D4rt(),
            mode,
            source,
            sources: sources,
            maxSteps: 100000,
          ),
          1001,
        );
      });

      test('$mode aggregates individually bounded dependencies', () {
        final sources = {
          for (var i = 0; i < 12; i++)
            'package:probe/part$i.dart': '$loop final value$i = work(10);',
        };
        for (var i = 0; i < 12; i++) {
          expect(
            _executeEntry(
              D4rt(),
              mode,
              "import 'package:probe/part$i.dart'; int main() => value$i;",
              sources: sources,
              maxSteps: 100,
            ),
            10,
          );
        }
        final root =
            '''
          ${List.generate(12, (i) => "import 'package:probe/part$i.dart' as part$i;").join('\n')}
          int main() => 7;
        ''';
        expect(
          () => _executeEntry(
            D4rt(),
            mode,
            root,
            sources: sources,
            maxSteps: 100,
          ),
          throwsA(isA<ExecutionLimitException>()),
        );
        expect(
          _executeEntry(D4rt(), mode, root, sources: sources, maxSteps: 100000),
          7,
        );
      });

      test('$mode carries initialization charges into root execution', () {
        final sources = {
          'package:probe/work.dart': '$loop final seed = work(30);',
        };
        const root = '''
          import 'package:probe/work.dart';
          int main() => seed + work(30);
        ''';
        expect(
          _executeEntry(
            D4rt(),
            mode,
            "import 'package:probe/work.dart'; int main() => seed;",
            sources: sources,
            maxSteps: 100,
          ),
          30,
        );
        expect(
          _executeEntry(
            D4rt(),
            mode,
            '$loop int main() => work(30);',
            maxSteps: 100,
          ),
          30,
        );
        expect(
          () => _executeEntry(
            D4rt(),
            mode,
            root,
            sources: sources,
            maxSteps: 100,
          ),
          throwsA(isA<ExecutionLimitException>()),
        );
        expect(
          _executeEntry(D4rt(), mode, root, sources: sources, maxSteps: 1000),
          60,
        );
      });

      test('$mode retains charges after async suspension', () async {
        final pending = Completer<int>();
        final interpreter = D4rt()
          ..registertopLevelFunction(
            'pending',
            (visitor, args, named, types) => pending.future,
          );
        final result =
            _executeEntry(
                  interpreter,
                  mode,
                  '''
          import 'package:probe/work.dart';
          Future<int> main() async {
            await pending();
            return seed + work(30);
          }
        ''',
                  sources: {
                    'package:probe/work.dart': '$loop final seed = work(30);',
                  },
                  maxSteps: 100,
                )
                as Future;
        pending.complete(1);
        await expectLater(result, throwsA(isA<ExecutionLimitException>()));
      });

      test('$mode caches diamond initialization without renewing budget', () {
        final events = <String>[];
        final interpreter = D4rt()
          ..registertopLevelFunction('mark', (visitor, args, named, types) {
            events.add(args.single as String);
            return null;
          });
        final sources = {
          'package:probe/shared.dart':
              '''
            $loop
            final shared = initialize();
            int initialize() { mark('shared'); return work(10); }
          ''',
          'package:probe/left.dart': '''
            import 'package:probe/shared.dart';
            final left = initializeLeft();
            int initializeLeft() { mark('left'); return shared; }
          ''',
          'package:probe/right.dart': '''
            import 'package:probe/shared.dart';
            final right = initializeRight();
            int initializeRight() { mark('right'); return shared; }
          ''',
        };
        expect(
          _executeEntry(
            interpreter,
            mode,
            '''
          import 'package:probe/left.dart';
          import 'package:probe/right.dart';
          int main() => left + right;
        ''',
            sources: sources,
            maxSteps: 100,
          ),
          20,
        );
        expect(events, ['shared', 'left', 'right']);
      });

      test('$mode reentry has an independent step budget', () {
        final interpreter = D4rt();
        interpreter.registertopLevelFunction(
          'reenter',
          (visitor, args, named, types) => _executeEntry(
            interpreter,
            mode,
            '$loop int main() => work(30);',
            maxSteps: 100,
          ),
        );
        expect(
          _executeEntry(interpreter, mode, '''
          $loop
          final seed = work(30);
          int main() => seed + reenter();
        ''', maxSteps: 100),
          60,
        );
        expect(
          () => _executeEntry(interpreter, mode, '''
            $loop
            final seed = work(30);
            int main() { reenter(); return seed + work(30); }
          ''', maxSteps: 100),
          throwsA(isA<ExecutionLimitException>()),
        );
      });
    }
  });

  group('Execution Limits & Sandbox Timeout Tests', () {
    test(
      'maxSteps terminates infinite while loop with ExecutionLimitException',
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
      },
    );

    test(
      'maxSteps terminates infinite for loop with ExecutionLimitException',
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
      },
    );

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
          source: source,
          timeout: const Duration(milliseconds: 100),
        ),
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
        () => interpreter.execute(
          source: '''
          void main() {
            try {
              while (true) {}
            } catch (_) {
              mark('caught');
            } finally {
              mark('finally');
            }
          }
        ''',
          timeout: const Duration(milliseconds: 60),
        ),
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
            'pending',
            (visitor, args, named, types) => nativeFuture.future,
          )
          ..registertopLevelFunction('mark', (visitor, args, named, types) {
            events.add(args.single as String);
            return null;
          });
        final result = scenario == 'lateValue'
            ? interpreter.executeCompiled(
                interpreter.compile(source: source),
                timeout: const Duration(milliseconds: 60),
              )
            : interpreter.execute(
                source: source,
                timeout: const Duration(milliseconds: 60),
              );
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
        expect(
          events,
          isEmpty,
          reason: 'late native completion must not resume interpreted code',
        );
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
      for (final mode in ['source', 'compiled', 'library']) {
        for (final failLate in [false, true]) {
          final nativeFuture = Completer<int>();
          final events = <String>[];
          final interpreter = D4rt()
            ..registertopLevelFunction(
              'pending',
              (visitor, args, named, types) => nativeFuture.future,
            )
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          final result = _executeEntry(
            interpreter,
            mode,
            source,
            sources: sources,
            timeout: const Duration(milliseconds: 80),
          );
          await expectLater(
            (result as Future).timeout(const Duration(seconds: 2)),
            throwsA(isA<ExecutionTimeoutException>()),
          );
          expect(events, isEmpty);
          if (failLate) {
            nativeFuture.completeError(StateError('late'));
          } else {
            nativeFuture.complete(4);
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          expect(
            events,
            isEmpty,
            reason: 'neither imported nor root frames may resume',
          );
        }
      }
    });

    test(
      'predeadline native errors remain catchable by interpreted code',
      () async {
        final nativeFuture = Completer<int>();
        final events = <String>[];
        final interpreter = D4rt()
          ..registertopLevelFunction(
            'pending',
            (visitor, args, named, types) => nativeFuture.future,
          )
          ..registertopLevelFunction('mark', (visitor, args, named, types) {
            events.add(args.single as String);
            return null;
          });
        final result =
            interpreter.execute(
                  source: '''
            Future<int> main() async {
              try {
                await pending();
                return 1;
              } catch (_) {
                mark('caught');
                return 2;
              }
            }
          ''',
                  timeout: const Duration(seconds: 2),
                )
                as Future;
        nativeFuture.completeError(StateError('expected'));
        expect(await result.timeout(const Duration(seconds: 2)), 2);
        expect(events, ['caught']);
      },
    );

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
              'pending',
              (visitor, args, named, types) => nativeFuture.future,
            )
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          final result = compiled
              ? interpreter.executeCompiled(
                  interpreter.compile(source: source),
                  timeout: const Duration(milliseconds: 100),
                )
              : interpreter.execute(
                  source: source,
                  timeout: const Duration(milliseconds: 100),
                );
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
          await expectLater(
            pendingResult.timeout(const Duration(seconds: 2)),
            throwsA(isA<ExecutionTimeoutException>()),
          );
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            events,
            isEmpty,
            reason: 'native completion must not beat the overdue timer',
          );
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
            ..registertopLevelFunction('pending', (
              visitor,
              args,
              named,
              types,
            ) {
              return args.single == 'outer'
                  ? outerNative.future
                  : innerNative.future;
            })
            ..registertopLevelFunction('mark', (visitor, args, named, types) {
              events.add(args.single as String);
              return null;
            });
          interpreter.registertopLevelFunction('reenter', (
            visitor,
            args,
            named,
            types,
          ) {
            inner = outerCompiled
                ? interpreter.execute(
                        source: innerSource,
                        timeout: Duration(
                          milliseconds: outerShorter ? 1000 : 80,
                        ),
                      )
                      as Future
                : interpreter.executeCompiled(
                        interpreter.compile(source: innerSource),
                        timeout: Duration(
                          milliseconds: outerShorter ? 1000 : 80,
                        ),
                      )
                      as Future;
            return null;
          });
          final outer =
              (outerCompiled
                      ? interpreter.executeCompiled(
                          interpreter.compile(source: outerSource),
                          timeout: Duration(
                            milliseconds: outerShorter ? 80 : 1000,
                          ),
                        )
                      : interpreter.execute(
                          source: outerSource,
                          timeout: Duration(
                            milliseconds: outerShorter ? 80 : 1000,
                          ),
                        ))
                  as Future;
          expect(
            inner,
            isNotNull,
            reason: 'host callback must reenter before outer returns',
          );
          if (outerShorter) {
            await expectLater(
              outer.timeout(const Duration(seconds: 2)),
              throwsA(isA<ExecutionTimeoutException>()),
            );
            innerNative.complete(7);
            expect(await inner!.timeout(const Duration(seconds: 2)), 7);
            outerNative.complete(3);
            expect(events, ['inner']);
          } else {
            await expectLater(
              inner!.timeout(const Duration(seconds: 2)),
              throwsA(isA<ExecutionTimeoutException>()),
            );
            outerNative.complete(3);
            expect(await outer.timeout(const Duration(seconds: 2)), 3);
            innerNative.complete(7);
            expect(events, ['outer']);
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            events,
            outerShorter ? ['inner'] : ['outer'],
            reason: 'late native completion cannot resume plugin',
          );
        }
      }
    });

    test(
      'initializer reentry keeps outer visitor, module and deadlines',
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
          'package:probe/seed.dart': 'final int seed = reenter();',
        };
        const nested = '''
        Future<int> main() async {
          final value = await pending('inner');
          mark('inner');
          return value;
        }
      ''';
        for (final importedInitializer in [false, true]) {
          for (final mode in ['source', 'compiled', 'library']) {
            for (final outerShorter in [false, true]) {
              final outerNative = Completer<int>();
              final innerNative = Completer<int>();
              final events = <String>[];
              Future? inner;
              final interpreter = D4rt()
                ..registertopLevelFunction('pending', (
                  visitor,
                  args,
                  named,
                  types,
                ) {
                  return args.single == 'outer'
                      ? outerNative.future
                      : innerNative.future;
                })
                ..registertopLevelFunction('mark', (
                  visitor,
                  args,
                  named,
                  types,
                ) {
                  events.add(args.single as String);
                  return null;
                });
              interpreter.registertopLevelFunction('reenter', (
                visitor,
                args,
                named,
                types,
              ) {
                inner = mode == 'compiled'
                    ? interpreter.execute(
                            source: nested,
                            timeout: Duration(
                              milliseconds: outerShorter ? 1000 : 120,
                            ),
                          )
                          as Future
                    : interpreter.executeCompiled(
                            interpreter.compile(source: nested),
                            timeout: Duration(
                              milliseconds: outerShorter ? 1000 : 120,
                            ),
                          )
                          as Future;
                return 10;
              });
              final source = importedInitializer ? importing : root;
              final outer =
                  _executeEntry(
                        interpreter,
                        mode,
                        source,
                        sources: importedInitializer ? imported : const {},
                        timeout: Duration(
                          milliseconds: outerShorter ? 120 : 1000,
                        ),
                      )
                      as Future;
              expect(inner, isNotNull);
              if (outerShorter) {
                await expectLater(
                  outer.timeout(const Duration(seconds: 3)),
                  throwsA(isA<ExecutionTimeoutException>()),
                );
                innerNative.complete(7);
                expect(await inner!.timeout(const Duration(seconds: 3)), 7);
                outerNative.complete(3);
                expect(events, ['inner']);
              } else {
                await expectLater(
                  inner!.timeout(const Duration(seconds: 3)),
                  throwsA(isA<ExecutionTimeoutException>()),
                );
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
      },
    );

    test(
      'slow native callbacks stop same-expression and initializer calls',
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
          'package:probe/slow.dart': 'final int seed = slow() + next();',
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
            'cascade',
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
                        'loaded' => {
                          'package:probe/entry.dart': rootInitializer,
                        },
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
      },
    );

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
      final first =
          interpreter.execute(
                source: source,
                timeout: const Duration(milliseconds: 80),
              )
              as Future;
      final second =
          interpreter.executeCompiled(
                interpreter.compile(source: source),
                timeout: const Duration(seconds: 1),
              )
              as Future;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      // The first call remains pending while the second completes normally.
      secondNative.complete(8);
      expect(await second.timeout(const Duration(seconds: 2)), 8);
      await expectLater(
        first.timeout(const Duration(seconds: 2)),
        throwsA(isA<ExecutionTimeoutException>()),
      );
      expect(observed, [8]);
      firstNative.complete(3);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(observed, [8], reason: 'late first invocation must stay terminal');
      expect(interpreter.execute(source: 'int main() => 10;'), 10);
    });
  });
}
