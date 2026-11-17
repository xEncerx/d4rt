import 'dart:async';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/stdlib/io/http.dart' show HttpClientRequestIo;
import 'package:test/test.dart';

class _Native {
  _Native();
}

class _NativeMixin {}

enum _NativeEnum { value }

class _PredicateType {}

class _Unregistered {}

class _Request implements HttpClientRequest {
  @override
  bool followRedirects = false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected request operation: $invocation');
}

void main() {
  late D4rt interpreter;
  late Object error;
  late StackTrace trace;
  late Completer<Object?> completer;
  final replacement = FormatException('replacement');
  final replacementTrace = StackTrace.fromString('replacement stack');

  Never fail() => Error.throwWithStackTrace(error, trace);

  setUp(() {
    interpreter = D4rt();
    error = ArgumentError('synthetic');
    trace = StackTrace.fromString('synthetic native stack');
    completer = Completer<Object?>();
    interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: _Native,
        name: 'Native',
        constructors: {
          '': (visitor, positional, named) => _Native(),
          'named': (visitor, positional, named) => fail(),
        },
        methods: {
          'fail': (visitor, target, positional, named) => fail(),
          'toString': (visitor, target, positional, named) => fail(),
          'call': (visitor, target, positional, named) => fail(),
          'future': (visitor, target, positional, named) => completer.future,
          '[]': (visitor, target, positional, named) => fail(),
          '[]=': (visitor, target, positional, named) => fail(),
          '+': (visitor, target, positional, named) => fail(),
        },
        getters: {'failure': (visitor, target) => fail()},
        setters: {'failure': (visitor, target, value) => fail()},
        staticMethods: {
          'fail': (visitor, positional, named) => fail(),
          'replace': (visitor, positional, named) =>
              Error.throwWithStackTrace(replacement, replacementTrace),
        },
      ),
      'package:test/native.dart',
    );
    interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: _NativeMixin,
        name: 'NativeMixin',
        canBeUsedAsMixin: true,
        getters: {'failure': (visitor, target) => fail()},
        methods: {'fail': (visitor, target, positional, named) => fail()},
      ),
      'package:test/native.dart',
    );
    interpreter.registerBridgedEnum(
      BridgedEnumDefinition<_NativeEnum>(
        name: 'NativeEnum',
        values: _NativeEnum.values,
        getters: {'failure': (visitor, target) => fail()},
        methods: {'fail': (visitor, target, positional, named) => fail()},
      ),
      'package:test/native.dart',
    );
  });

  Object? run(String body) => interpreter.execute(
    source:
        '''
    import 'package:test/native.dart';
    main() { $body }
  ''',
  );

  test('native entry points retain typed error and stack', () {
    for (final call in [
      'Native.named()',
      'Native.fail()',
      'Native().fail()',
      'Native().failure',
      'Native().failure = 1',
      'Native()[0]',
      'Native()[0] = 1',
      'Native()(1)',
      'Native() + 1',
      'NativeEnum.value.fail()',
      'var f = NativeEnum.value.fail; f()',
      'var f = Native().fail; f()',
      'Native().toString()',
      'var f = Native().toString; f()',
      'var f = Native.fail; f()',
    ]) {
      final result =
          run('''
        try { $call; } on FormatException { return 'wrong'; }
        on Error catch (e, s) { return [e, s]; }
      ''')
              as List;
      expect(identical(result[0], error), isTrue, reason: call);
      expect(identical(result[1], trace), isTrue, reason: call);
    }
  });

  test('interpreted invocation frames preserve native error and stack', () {
    for (final expression in [
      'Relay() + 1',
      '-Relay()',
      'top = 1',
      'top',
      'Wrapped(1) + 1',
      'Relay().extensionFailure',
      '(1).relayFailure()',
    ]) {
      final result = interpreter.execute(
        source:
            '''
        import 'package:test/native.dart';
        class Relay {
          int operator +(int value) { Native().fail(); return 0; }
          int operator -() { Native().fail(); return 0; }
        }
        extension type Wrapped(int value) {
          int operator +(int other) { Native().fail(); return 0; }
        }
        set top(value) { Native().fail(); }
        get top { Native().fail(); }
        extension RelayExtension on Relay {
          set extensionFailure(value) { Native().fail(); }
          int get extensionFailure { Native().fail(); return 0; }
        }
        extension IntExtension on int {
          int relayFailure() { Native().fail(); return 0; }
        }
        main() {
          try { $expression; } on ArgumentError catch (e, s) { return [e, s]; }
        }
      ''',
      );
      expect(result, isA<List>(), reason: expression);
      final values = result as List;
      expect(values[0], same(error), reason: expression);
      expect(values[1], same(trace), reason: expression);
    }
  });

  test('universal getter and native enum pattern preserve failure', () {
    for (final statement in [
      'Relay().hashCode;',
      'var NativeEnum(failure: result) = NativeEnum.value;',
      'print(Relay());',
      'LateFields.failure;',
    ]) {
      final result =
          interpreter.execute(
                source:
                    '''
        import 'package:test/native.dart';
        class Relay {
          int get hashCode { Native().fail(); return 0; }
          String toString() { Native().fail(); return ''; }
        }
        class LateFields {
          static late final failure = Native().fail();
        }
        main() {
          try { $statement } on ArgumentError catch (e, s) { return [e, s]; }
        }
      ''',
              )
              as List;
      expect(result[0], same(error), reason: statement);
      expect(result[1], same(trace), reason: statement);
    }
  });

  test(
    'semantic runtime failures remain catchable synchronously and asynchronously',
    () async {
      expect(
        run("try { 'text' as int; } catch (_) { return 'handled'; }"),
        'handled',
      );
      final future =
          interpreter.execute(
                source: '''
      Future main() async {
        await Future.value(1);
        try { 'text' as int; } catch (_) { return 'handled'; }
      }
    ''',
              )
              as Future;
      expect(await future, 'handled');
    },
  );

  test('terminal failure in native catch predicate cannot be handled', () {
    final terminal = ExecutionLimitException('predicate');
    interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: _PredicateType,
        name: 'PredicateType',
        isSubtypeOfFunc: (_) => throw terminal,
      ),
      'package:test/native.dart',
    );
    expect(
      () => run('''
        try { try { Native().fail(); } on PredicateType {} }
        on Object { return 'bypassed'; }
      '''),
      throwsA(same(terminal)),
    );
  });

  test('terminal native predicate failure survives object lookup fallback', () {
    final terminal = ExecutionLimitException('lookup predicate');
    interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: _PredicateType,
        name: 'PredicateType',
        isSubtypeOfFunc: (_) => throw terminal,
      ),
      'package:test/native.dart',
    );
    interpreter.registertopLevelFunction(
      'unknownValue',
      (v, a, n, t) => _Unregistered(),
    );
    expect(
      () => run(
        "try { unknownValue().hashCode; } catch (_) { return 'bypassed'; }",
      ),
      throwsA(same(terminal)),
    );
  });

  test(
    'revoked native permission bypasses guest catches sync and async',
    () async {
      for (final asynchronous in [false, true]) {
        final runtime = D4rt()..grant(DangerousPermission.developerTools);
        runtime.registertopLevelFunction('revokeAccess', (v, args, n, t) {
          runtime.revoke(DangerousPermission.developerTools);
          return null;
        });
        final source =
            '''
        import 'dart:developer';
        ${asynchronous ? 'Future main() async' : 'main()'} {
          ${asynchronous ? 'await Future.value(0);' : ''}
          revokeAccess();
          try { inspect(1); } on Object { return 'bypassed'; }
        }
      ''';
        if (asynchronous) {
          await expectLater(
            runtime.execute(source: source),
            throwsA(isA<RuntimeError>()),
          );
        } else {
          expect(
            () => runtime.execute(source: source),
            throwsA(isA<RuntimeError>()),
          );
        }
      }
    },
  );

  test('protected async failures cannot be replaced by finally', () async {
    for (final cleanup in ["return 'bypassed';", "throw 'replacement';"]) {
      final runtime = D4rt()..grant(DangerousPermission.developerTools);
      var cleanupRan = false;
      runtime.registertopLevelFunction('revokeAccess', (v, args, n, t) {
        runtime.revoke(DangerousPermission.developerTools);
        return null;
      });
      runtime.registertopLevelFunction('cleanup', (v, args, n, t) {
        cleanupRan = true;
        return null;
      });
      final result = runtime.execute(
        source:
            '''
        import 'dart:developer';
        Future main() async {
          await Future.value(0);
          revokeAccess();
          try { inspect(1); } finally { cleanup(); $cleanup }
        }
      ''',
      );
      await expectLater(result, throwsA(isA<RuntimeError>()));
      expect(cleanupRan, isFalse);
    }
  });

  test('generator cleanup cannot replace a protected failure', () async {
    for (final cleanup in ['return;', "throw 'replacement';"]) {
      final runtime = D4rt()..grant(DangerousPermission.developerTools);
      var cleanupRan = false;
      runtime.registertopLevelFunction('revokeAccess', (v, args, n, t) {
        runtime.revoke(DangerousPermission.developerTools);
        return null;
      });
      runtime.registertopLevelFunction('cleanup', (v, args, n, t) {
        cleanupRan = true;
        return null;
      });
      final stream =
          runtime.execute(
                source:
                    '''
        import 'dart:developer';
        Stream main() async* {
          await Future.value(0);
          revokeAccess();
          try { inspect(1); } finally {
            try { await Future.error('inner'); } catch (_) {}
            cleanup(); $cleanup
          }
        }
      ''',
              )
              as Stream;
      await expectLater(stream.first, throwsA(isA<RuntimeError>()));
      expect(cleanupRan, isTrue);
    }
  });

  for (final transfer in [
    'return;',
    "throw 'replacement';",
    'break;',
    'continue;',
  ]) {
    test(
      'protected generator failure unwinds outer finalizers after $transfer',
      () async {
        final events = <int>[];
        error = ExecutionLimitException('protected failure');
        interpreter.registertopLevelFunction('mark', (v, args, n, t) {
          events.add(args.single as int);
          return null;
        });
        final stream =
            interpreter.execute(
                  source:
                      '''
        import 'package:test/native.dart';
        Stream main() async* {
          await Future.value(0);
          for (var i = 0; i < 1; i++) {
            try {
              try {
                try { Native().fail(); }
                finally { mark(1); $transfer }
              } finally { mark(2); }
            } finally { mark(3); }
          }
        }
      ''',
                  maxSteps: 10000,
                )
                as Stream;
        try {
          await stream.first;
          throw StateError('protected failure was lost');
        } catch (caught, caughtStack) {
          expect(caught, same(error));
          expect(caughtStack, same(trace));
        }
        expect(events, [1, 2, 3]);
      },
    );
  }

  for (final transfer in [
    'return;',
    "throw 'replacement';",
    'break;',
    'continue;',
  ]) {
    test(
      'protected cleanup retains shadowed loop scope after $transfer',
      () async {
        final seen = <int>[];
        error = ExecutionLimitException('protected failure');
        interpreter.registertopLevelFunction('mark', (v, args, n, t) {
          seen.add(args.single as int);
          return null;
        });
        final stream =
            interpreter.execute(
                  source:
                      '''
        import 'package:test/native.dart';
        Stream main() async* {
          await Future.value(0);
          var i = 99;
          try {
            for (var i = 0; i < 1; i++) {
              try {
                try { Native().fail(); }
                finally { $transfer }
              } finally { mark(i); }
            }
          } finally { mark(i); }
        }
      ''',
                  maxSteps: 10000,
                )
                as Stream;
        try {
          await stream.first;
          throw StateError('protected failure was lost');
        } catch (caught, caughtStack) {
          expect(caught, same(error));
          expect(caughtStack, same(trace));
        }
        expect(seen, [0, 99]);
      },
    );
  }

  test('denied generator operation completes all nested cleanup', () async {
    final runtime = D4rt()..grant(DangerousPermission.developerTools);
    final events = <int>[];
    runtime.registertopLevelFunction('revokeAccess', (v, args, n, t) {
      runtime.revoke(DangerousPermission.developerTools);
      return null;
    });
    runtime.registertopLevelFunction('mark', (v, args, n, t) {
      events.add(args.single as int);
      return null;
    });
    final stream =
        runtime.execute(
              source: '''
      import 'dart:developer';
      Stream main() async* {
        await Future.value(0);
        revokeAccess();
        try {
          try { inspect(1); } finally { mark(1); return; }
        } finally { mark(2); }
      }
    ''',
            )
            as Stream;
    await expectLater(stream.first, throwsA(isA<RuntimeError>()));
    expect(events, [1, 2]);
  });

  test('extension initialization propagates denied permission', () {
    final runtime = D4rt()..grant(DangerousPermission.developerTools);
    runtime.registertopLevelFunction('revokeAccess', (v, args, n, t) {
      runtime.revoke(DangerousPermission.developerTools);
      return 1;
    });
    expect(
      () => runtime.execute(
        source: '''
        import 'dart:developer';
        extension Holder on int { static final value = inspect(revokeAccess()); }
        main() => 7;
      ''',
      ),
      throwsA(isA<RuntimeError>()),
    );
    expect(
      D4rt().execute(
        source: '''
      extension Holder on int { static final value = 1 as String; }
      main() => 7;
    ''',
      ),
      7,
    );
  });

  test('automatic redirect denial cannot be caught or mutate the request', () {
    final request = _Request();
    interpreter.registertopLevelFunction(
      'request',
      (v, args, n, t) =>
          BridgedInstance(HttpClientRequestIo.definition, request),
    );
    expect(
      () => run(
        "try { request().followRedirects = true; } catch (_) { return 'bypassed'; }",
      ),
      throwsA(isA<RuntimeError>()),
    );
    expect(request.followRedirects, isFalse);
  });

  test('generator cancellation keeps the active catch for rethrow', () async {
    final started = Completer<void>();
    final entered = Completer<void>();
    final gate = Completer<void>();
    interpreter.registertopLevelFunction('started', (v, args, n, t) {
      started.complete();
      return null;
    });
    interpreter.registertopLevelFunction('waitGate', (v, args, n, t) {
      entered.complete();
      return gate.future;
    });
    final stream =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Stream main() async* {
        try { started(); await Native().future(); } catch (e, s) {
          try { await waitGate(); } finally { rethrow; }
        }
      }
    ''',
            )
            as Stream;
    final subscription = stream.listen((_) {});
    await started.future;
    completer.completeError(error, trace);
    await entered.future;
    try {
      await subscription.cancel();
      throw StateError('Expected cancellation to propagate the original error');
    } catch (caught, stack) {
      expect(caught, same(error));
      expect(stack, same(trace));
    } finally {
      gate.complete();
    }
  });

  test('native access to collection override retains originating stack', () {
    interpreter.registertopLevelFunction('readLength', (v, args, n, t) {
      return (args.single as List).length;
    });
    final result =
        interpreter.execute(
              source: '''
      import 'dart:collection';
      import 'package:test/native.dart';
      class Sample extends UnmodifiableListView<Object?> {
        Sample() : super([]);
        int get length { Native().fail(); return 0; }
      }
      main() {
        try { readLength(Sample()); }
        on ArgumentError catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as List;
    expect(result[0], same(error));
    expect(result[1], same(trace));
  });

  for (final outer in ['catch', 'finally']) {
    test('nested finally failure does not reenter outer $outer', () async {
      final events = <int>[];
      interpreter.registertopLevelFunction('mark', (v, args, n, t) {
        events.add(args.single as int);
        return null;
      });
      final handler = outer == 'catch' ? 'catch (_)' : 'finally';
      final future =
          interpreter.execute(
                source:
                    '''
        import 'package:test/native.dart';
        Future main() async {
          try {
            try { await Native().future(); }
            $handler {
              mark(1);
              try { mark(2); }
              finally { await Future.value(null); Native.replace(); }
            }
          } on FormatException catch (e, s) { return [e, s]; }
        }
      ''',
                maxSteps: 10000,
              )
              as Future;
      completer.completeError(error, trace);
      final result = await future as List;
      expect(result[0], same(replacement));
      expect(result[1], same(replacementTrace));
      expect(events, [1, 2]);
    });
  }

  test('nested handled catch restores outer rethrow provenance', () {
    final result =
        run('''
      try {
        try { Native().fail(); } catch (e, s) {
          try { throw 'inner'; } catch (_) {}
          rethrow;
        }
      } on ArgumentError catch (e, s) { return [e, s]; }
    ''')
            as List;
    expect(identical(result[0], error), isTrue);
    expect(identical(result[1], trace), isTrue);
  });

  test('native Exception and Error select distinct clauses', () {
    error = FormatException('synthetic');
    expect(
      run('''
      try { Native().fail(); }
      on Error { return 'wrong'; }
      on Exception { return 'exception'; }
    '''),
      'exception',
    );
  });

  test('unmatched catches and rethrow preserve identity and trace', () {
    final result =
        run('''
      try {
        try { Native().fail(); } on FormatException { return 'wrong'; }
      } on Object catch (e, s) { return [e, s]; }
    ''')
            as List;
    expect(identical(result[0], error), isTrue);
    expect(identical(result[1], trace), isTrue);
  });

  test('genuine native UnsupportedError remains catchable', () {
    error = UnsupportedError('synthetic');
    expect(
      run('''
      try { Native().fail(); } on UnsupportedError { return true; }
      return false;
    '''),
      isTrue,
    );
  });

  test('unhandled native failures retain host RuntimeError boundary', () {
    expect(() => run('Native().fail();'), throwsA(isA<RuntimeError>()));
    expect(
      () => run('try { Native().fail(); } on FormatException {}'),
      throwsA(isA<RuntimeError>()),
    );
  });

  test('execution limits cannot be caught by script', () {
    for (final clause in [
      'on Object catch (_) { return 1; }',
      'catch (_) { return 1; }',
      'on Exception catch (_) { return 1; }',
    ]) {
      expect(
        () => D4rt().execute(
          source: 'main() { try { while (true) {} } $clause }',
          maxSteps: 100,
        ),
        throwsA(isA<ExecutionLimitException>()),
        reason: clause,
      );
    }
  });

  test('replacement errors have their own provenance', () {
    for (final body in [
      'try { Native().fail(); } catch (_) { Native.replace(); }',
      'try { Native().fail(); } finally { Native.replace(); }',
      'try { return 1; } finally { Native.replace(); }',
      'try { Native().fail(); } catch (_) { return 1; } finally { Native.replace(); }',
    ]) {
      final result =
          run('''
        try { $body } on FormatException catch (e, s) { return [e, s]; }
      ''')
              as List;
      expect(identical(result[0], replacement), isTrue);
      expect(identical(result[1], replacementTrace), isTrue);
    }
  });

  test('prefixed registered native catches match', () {
    final result =
        interpreter.execute(
              source: '''
      import 'dart:core' as core;
      import 'package:test/native.dart';
      main() {
        try { Native().fail(); }
        on core.ArgumentError catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as List;
    expect(identical(result[0], error), isTrue);
    expect(identical(result[1], trace), isTrue);
  });

  test('eval preserves native host failure boundary', () {
    interpreter.grant(DangerousPermission.codeEvaluation);
    interpreter.registertopLevelFunction(
      'rawFail',
      (visitor, args, named, types) => fail(),
    );
    interpreter.execute(source: "import 'package:test/native.dart'; main() {}");
    expect(
      () => interpreter.eval('Native().fail()'),
      throwsA(isA<RuntimeError>()),
    );
    expect(
      () => interpreter.eval('try { Native().fail(); } on FormatException {}'),
      throwsA(isA<RuntimeError>()),
    );
    for (final expression in [
      'Native.fail()',
      'Native.named()',
      'NativeEnum.value.fail()',
      'Native()[0]',
      'Native()[0] = 1',
      'Native()(1)',
      '(Native() + 1)',
    ]) {
      expect(
        () => interpreter.eval(expression),
        throwsA(isA<RuntimeError>()),
        reason: expression,
      );
    }
    expect(() => interpreter.eval('rawFail()'), throwsA(same(error)));
    expect(
      () => interpreter.eval('try { rawFail(); } on FormatException {}'),
      throwsA(same(error)),
    );
    expect(() => interpreter.eval("throw 'script'"), throwsA('script'));
    expect(() => interpreter.eval('Native().fail;'), returnsNormally);
  });

  test(
    'super and mixin owners preserve catch provenance and eval boundary',
    () {
      interpreter.grant(DangerousPermission.codeEvaluation);
      for (final expression in [
        'Child().methodFailure()',
        'Child().getterFailure()',
        'Child().setterFailure()',
        'Mixed().fail()',
        'Mixed().failure',
      ]) {
        final result =
            interpreter.execute(
                  source:
                      '''
        import 'package:test/native.dart';
        class Child extends Native {
          methodFailure() => super.fail();
          getterFailure() => super.failure;
          setterFailure() => super.failure = 1;
        }
        class Mixed with NativeMixin {}
        main() {
          try { $expression; }
          on ArgumentError catch (e, s) { return [e, s]; }
        }
      ''',
                )
                as List;
        expect(result[0], same(error), reason: expression);
        expect(result[1], same(trace), reason: expression);
        expect(
          () => interpreter.eval(expression),
          throwsA(isA<RuntimeError>()),
          reason: expression,
        );
      }
    },
  );

  for (final inner in [
    'try { return 42; } catch (_) {}',
    'try { return 42; } finally {}',
  ]) {
    test('return skips already executing finally: $inner', () async {
      final events = <int>[];
      interpreter.registertopLevelFunction('mark', (v, args, n, t) {
        events.add(args.single as int);
        return null;
      });
      final future =
          interpreter.execute(
                source:
                    '''
        import 'package:test/native.dart';
        Future main() async {
          try { await Native().future(); }
          finally { mark(1); $inner }
        }
      ''',
                maxSteps: 10000,
              )
              as Future;
      completer.completeError(error, trace);
      expect(await future, 42);
      expect(events, [1]);
    });
  }

  test('return within finally still runs outer cleanup', () async {
    final events = <int>[];
    interpreter.registertopLevelFunction('mark', (v, args, n, t) {
      events.add(args.single as int);
      return null;
    });
    final future =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Future main() async {
        try {
          try { await Native().future(); }
          finally { mark(1); try { return 42; } catch (_) {} }
        } finally { mark(2); }
      }
    ''',
              maxSteps: 10000,
            )
            as Future;
    completer.completeError(error, trace);
    expect(await future, 42);
    expect(events, [1, 2]);
  });

  for (final body in [
    "try { throw 'inner'; } catch (_) {} return [outer, stack];",
    'try { rethrow; } on ArgumentError catch (e, s) { return [e, s]; }',
  ]) {
    test('async nested catch preserves lexical state: $body', () async {
      final future =
          interpreter.execute(
                source:
                    '''
        import 'package:test/native.dart';
        Future main() async {
          try { await Native().future(); }
          catch (outer, stack) { $body }
        }
      ''',
              )
              as Future;
      completer.completeError(error, trace);
      final result = await future as List;
      expect(result[0], same(error));
      expect(result[1], same(trace));
    });
  }

  test(
    'handled failure in async finally preserves pending native error',
    () async {
      final future =
          interpreter.execute(
                source: '''
      import 'package:test/native.dart';
      Future main() async {
        try {
          try { await Native().future(); }
          finally { try { throw 'cleanup'; } catch (_) {} }
        } on ArgumentError catch (e, s) { return [e, s]; }
        return 'lost';
      }
    ''',
              )
              as Future;
      completer.completeError(error, trace);
      final result = await future as List;
      expect(result[0], same(error));
      expect(result[1], same(trace));
    },
  );

  test(
    'handled awaited failure in async finally preserves pending return',
    () async {
      final future =
          interpreter.execute(
                source: '''
      import 'package:test/native.dart';
      Future main() async {
        try { return 42; }
        finally { try { await Native().future(); } on ArgumentError {} }
      }
    ''',
              )
              as Future;
      completer.completeError(error, trace);
      expect(await future, 42);
    },
  );

  test(
    'continue from finally abandons pending failure before next iteration',
    () async {
      final future =
          interpreter.execute(
                source: '''
      import 'package:test/native.dart';
      Future main() async {
        for (var i = 0; i < 2; i++) {
          try { if (i == 0) await Native().future(); }
          finally { if (i == 0) continue; }
        }
        return 42;
      }
    ''',
                maxSteps: 10000,
              )
              as Future;
      completer.completeError(error, trace);
      expect(await future, 42);
    },
  );

  test('nested return does not reenter an executing finally', () async {
    final events = <int>[];
    interpreter.registertopLevelFunction('mark', (v, args, n, t) {
      events.add(args.single as int);
      return null;
    });
    final future =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Future main() async {
        try { await Native().future(); }
        finally {
          mark(1);
          try { return 42; }
          finally { mark(2); try { Native().fail(); } on ArgumentError {} }
        }
      }
    ''',
              maxSteps: 10000,
            )
            as Future;
    completer.completeError(error, trace);
    expect(await future, 42);
    expect(events, [1, 2]);
  });

  test('escaping finally error replaces pending native failure', () async {
    final future =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Future main() async {
        try {
          try { await Native().future(); }
          finally { Native.replace(); }
        } on FormatException catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as Future;
    completer.completeError(error, trace);
    final result = await future as List;
    expect(result[0], same(replacement));
    expect(result[1], same(replacementTrace));
  });

  test('empty async finally preserves pending native failure', () async {
    final future =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Future main() async {
        try { try { await Native().future(); } finally {} }
        on ArgumentError catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as Future;
    completer.completeError(error, trace);
    final result = await future as List;
    expect(result[0], same(error));
    expect(result[1], same(trace));
  });

  test('async nested handling restores outer rethrow', () async {
    final future =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Future main() async {
        try {
          try { await Native().future(); } catch (e, s) {
            try { throw 'inner'; } catch (_) {}
            rethrow;
          }
        } on ArgumentError catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as Future;
    completer.completeError(error, trace);
    final result = await future as List;
    expect(identical(result[0], error), isTrue);
    expect(identical(result[1], trace), isTrue);
  });

  test('awaited native failure retains object and stack', () async {
    final future =
        interpreter.execute(
              source: '''
      import 'package:test/native.dart';
      Future main() async {
        try { await Native().future(); }
        on ArgumentError catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as Future;
    completer.completeError(error, trace);
    final result = await future as List;
    expect(identical(result[0], error), isTrue);
    expect(identical(result[1], trace), isTrue);
  });
}
