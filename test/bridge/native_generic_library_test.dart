import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

class _Native {
  String kind<T>() => T == String
      ? 'string'
      : T == bool
      ? 'bool'
      : 'other';
}

enum _Shade { light, dark }

void main() {
  late D4rt d;
  late List<List<RuntimeType>?> seen;
  setUp(() {
    d = D4rt();
    seen = [];
    d.registerBridgedClass(
      BridgedClass(
        nativeType: _Native,
        name: 'Native',
        constructors: {'': (_, _, _) => _Native()},
        genericMethods: {
          'kind': (_, target, positional, named, types) {
            seen.add(types);
            if (types == null) return 'omitted';
            final type = types.single;
            if (type is BridgedClass && type.nativeType == String) {
              return (target as _Native).kind<String>();
            }
            if (type is BridgedClass && type.nativeType == bool) {
              return (target as _Native).kind<bool>();
            }
            return 'other';
          },
          'args': (_, target, positional, named, types) => [
            positional.length,
            ...positional,
            named.containsKey('x'),
            named['x'],
            types?.single.name,
          ],
          'call': (_, _, _, _, types) {
            seen.add(types);
            return types?.single.name;
          },
        },
      ),
      'package:test/native.dart',
    );
  });

  Object? run(String body) => d.execute(
    source:
        '''
    import 'package:test/native.dart';
    main() { $body }
  ''',
  );

  test('direct and reusable bound methods retain type arguments', () {
    expect(
      run('''
      var n = Native();
      var f = n.kind;
      var g = n.kind<String>;
      return [n.kind<String>(), n.kind<bool>(), f<bool>(), g(), g(), n.kind()];
    '''),
      ['string', 'bool', 'bool', 'string', 'string', 'omitted'],
    );
    expect(seen.last, isNull);
  });

  test('generic callable instance preserves nullable metadata', () {
    expect(run('var n = Native(); return n<String?>();'), 'String?');
    expect(seen.single!.single, isA<NullableEnumArgument>());
  });

  test('tearoff call forms preserve nullable outer types', () {
    expect(
      run('var f = Native().kind; return [f<String?>(), f.call<String?>()];'),
      ['other', 'other'],
    );
    expect(seen, hasLength(2));
    expect(seen[0]!.single, isA<NullableEnumArgument>());
    expect(seen[1]!.single, isA<NullableEnumArgument>());
  });

  test('instantiated tearoff metadata cannot mutate across calls', () {
    var rejected = false;
    d.registerBridgedClass(
      BridgedClass(
        nativeType: Object,
        name: 'Guard',
        constructors: {'': (_, _, _) => Object()},
        genericMethods: {
          'probe': (_, _, _, _, types) {
            try {
              types!.clear();
            } on UnsupportedError {
              rejected = true;
            }
            return types!.single.name;
          },
        },
      ),
      'package:test/guard.dart',
    );
    expect(
      d.execute(
        source: '''
      import 'package:test/guard.dart';
      main() { var f = Guard().probe<String>; return [f(), f()]; }
    ''',
      ),
      ['String', 'String'],
    );
    expect(rejected, isTrue);
  });

  test('nested nullable arguments are structured', () {
    expect(run('return Native().kind<List<String?>?>();'), 'other');
    final outer = seen.single!.single as NullableEnumArgument;
    final applied = outer.type as AppliedRuntimeType;
    expect(applied.typeArguments.single, isA<NullableEnumArgument>());
  });

  test('unresolved type arguments do not reach native adapters', () {
    expect(() => run('return Native().kind<Missing>();'), throwsA(anything));
    expect(seen, isEmpty);
    expect(run('return Native().kind<bool>();'), 'bool');
  });
  test('inherited and super dispatch retain the native receiver', () {
    expect(
      d.execute(
        source: '''
      import 'package:test/native.dart';
      class Child extends Native {
        direct() => super.kind<String>();
        bound() { var f = super.kind; return f<bool>(); }
      }
      main() {
        var c = Child();
        return [c.kind<String>(), c.direct(), c.bound()];
      }
    ''',
      ),
      ['string', 'string', 'bool'],
    );
  });

  test('type metadata retains prefixed registered identity', () {
    final custom = BridgedClass(nativeType: _Native, name: 'Custom');
    d.registerBridgedClass(custom, 'package:test/types.dart');
    expect(
      d.execute(
        source: '''
      import 'package:test/native.dart';
      import 'package:test/types.dart' as t;
      main() => Native().kind<List<t.Custom?>>();
    ''',
      ),
      'other',
    );
    final applied = seen.single!.single as AppliedRuntimeType;
    final inner = applied.typeArguments.single as NullableEnumArgument;
    expect(identical(inner.type, custom), isTrue);
  });

  test('native generic failures retain error and stack identity', () {
    final error = StateError('native');
    final stack = StackTrace.fromString('native stack');
    d.registerBridgedClass(
      BridgedClass(
        nativeType: Object,
        name: 'Failer',
        constructors: {'': (_, _, _) => Object()},
        genericMethods: {
          'fail': (_, _, _, _, _) => Error.throwWithStackTrace(error, stack),
        },
      ),
      'package:test/fail.dart',
    );
    final result =
        d.execute(
              source: '''
      import 'package:test/fail.dart';
      main() {
        try { Failer().fail<String>(); } catch (e, s) { return [e, s]; }
      }
    ''',
            )
            as List;
    expect(identical(result[0], error), isTrue);
    expect(identical(result[1], stack), isTrue);
  });

  test('arguments preserve omission and supplied null', () {
    expect(run('return Native().args<String>();'), [0, false, null, 'String']);
    expect(run('return Native().args<bool>(null, x: null);'), [
      1,
      null,
      true,
      null,
      'bool',
    ]);
  });

  test('suspended arguments evaluate once in order', () async {
    final gate = Completer<Object?>();
    final entered = Completer<void>();
    final events = <String>[];
    d.registertopLevelFunction('mark', (_, args, _, _) {
      events.add(args.single as String);
      return args.single;
    });
    d.registertopLevelFunction('waitValue', (_, _, _, _) {
      events.add('wait');
      entered.complete();
      return gate.future;
    });
    final result =
        d.execute(
              source: '''
      import 'package:test/native.dart';
      main() async {
        var n = Native();
        return n.args<String>(mark('before'), await waitValue(), x: mark('after'));
      }
    ''',
            )
            as Future;
    await entered.future;
    expect(events, ['before', 'wait']);
    gate.complete('middle');
    expect(await result, [2, 'before', 'middle', true, 'after', 'String']);
    expect(events, ['before', 'wait', 'after']);
  });

  test(
    'implicit generic call suspends positional and named arguments',
    () async {
      for (final named in [false, true]) {
        final interpreter = D4rt();
        final gate = Completer<Object?>();
        final entered = Completer<void>();
        final events = <String>[];
        interpreter.registerBridgedClass(
          BridgedClass(
            nativeType: _Native,
            name: 'Native',
            constructors: {
              '': (_, _, _) {
                events.add('receiver');
                return _Native();
              },
            },
            genericMethods: {
              'call': (_, _, positional, names, types) => [
                positional,
                names,
                types!.single.name,
              ],
            },
          ),
          'package:test/native.dart',
        );
        interpreter.registertopLevelFunction('mark', (_, args, _, _) {
          events.add(args.single as String);
          return args.single;
        });
        interpreter.registertopLevelFunction('waitValue', (_, _, _, _) {
          events.add('wait');
          entered.complete();
          return gate.future;
        });
        final argument = named
            ? "mark('before'), x: await waitValue(), y: mark('after')"
            : "mark('before'), await waitValue(), x: mark('after')";
        final result =
            interpreter.execute(
                  source:
                      '''
        import 'package:test/native.dart';
        main() async => Native()<String>($argument);
      ''',
                )
                as Future;
        await entered.future;
        expect(events, ['receiver', 'before', 'wait']);
        gate.complete('middle');
        final value = await result as List;
        expect(value[0], named ? ['before'] : ['before', 'middle']);
        expect(
          value[1],
          named ? {'x': 'middle', 'y': 'after'} : {'x': 'after'},
        );
        expect(value[2], 'String');
        expect(events, ['receiver', 'before', 'wait', 'after']);
      }
    },
  );

  test('duplicate ordinary and generic adapters are rejected', () {
    expect(
      () => BridgedClass(
        nativeType: Object,
        name: 'Duplicate',
        methods: {'m': (_, _, _, _) => null},
        genericMethods: {'m': (_, _, _, _, _) => null},
      ),
      throwsArgumentError,
    );
  });

  test('scoped functions respect imports and distinct URIs', () {
    var calls = 0;
    d.registerLibraryFunction('package:test/a.dart', 'convert', (_, _, _, _) {
      calls++;
      return 'a';
    });
    d.registerLibraryFunction('package:test/b.dart', 'convert', (_, _, _, _) {
      calls++;
      return 'b';
    });
    expect(
      d.execute(
        source: '''
      import 'package:test/a.dart' as a;
      import 'package:test/b.dart' as b;
      main() { var f = a.convert; return [f(), b.convert()]; }
    ''',
      ),
      ['a', 'b'],
    );
    expect(calls, 2);
    expect(
      () => d.execute(
        source:
            "import 'package:test/a.dart' as a hide convert; main() => a.convert();",
      ),
      throwsA(anything),
    );
    expect(calls, 2);
  });

  test('scoped imports do not leak through helpers or filters', () {
    var calls = 0;
    d.registerLibraryFunction('package:test/a.dart', 'convert', (_, _, _, _) {
      calls++;
      return 7;
    });
    const helper = 'package:test/helper.dart';
    const sources = {
      helper: "import 'package:test/a.dart' as a; int use() => a.convert();",
      'package:test/export.dart': "export 'package:test/a.dart' show convert;",
    };
    expect(
      d.execute(source: "import '$helper'; main() => use();", sources: sources),
      7,
    );
    expect(
      d.execute(
        source: "import 'package:test/export.dart'; main() => convert();",
        sources: sources,
      ),
      7,
    );
    for (final source in [
      'main() => convert();',
      "import '$helper'; main() => convert();",
      "import 'package:test/a.dart' show missing; main() => convert();",
      "import 'package:test/a.dart' as a; main() => convert();",
    ]) {
      expect(
        () => d.execute(source: source, sources: sources),
        throwsA(anything),
      );
    }
    expect(calls, 2);
  });

  test('global provenance does not override an imported function', () {
    d.registertopLevelFunction(
      'convert',
      (_, _, _, _) => 'global',
      sourceUri: 'package:test/b.dart',
    );
    d.registerLibraryFunction(
      'package:test/b.dart',
      'convert',
      (_, _, _, _) => 'library',
    );
    expect(d.execute(source: 'main() => convert();'), 'global');
    expect(
      d.execute(source: "import 'package:test/b.dart'; main() => convert();"),
      'library',
    );
    expect(
      d.trackedFunctions.where((entry) => entry.name == 'convert'),
      hasLength(2),
    );
  });

  test('duplicate scoped names are rejected and reset', () {
    d.registerLibraryFunction(
      'package:test/a.dart',
      'convert',
      (_, _, _, _) => 1,
    );
    expect(
      () => d.registerLibraryFunction(
        'package:test/a.dart',
        'convert',
        (_, _, _, _) => 2,
      ),
      throwsArgumentError,
    );
    d.clearBridgeRegistry();
    expect(
      () => d.execute(
        source: "import 'package:test/a.dart'; main() => convert();",
      ),
      throwsA(anything),
    );
  });
  test('successive import and export combinators intersect and hide', () {
    var effects = 0;
    for (final name in ['convert', 'other']) {
      d.registerLibraryFunction('package:test/filter.dart', name, (_, _, _, _) {
        effects++;
        return name;
      });
    }
    const sources = {
      'package:test/reexport.dart':
          "export 'package:test/filter.dart' show convert, other hide other show convert;",
      'package:test/repeated.dart':
          "export 'package:test/filter.dart' show convert, other show convert;",
    };
    for (final prefix in [
      "import 'package:test/filter.dart' show convert, other hide other show convert;",
      "import 'package:test/filter.dart' hide other show convert, other;",
      "import 'package:test/filter.dart' show convert, other show convert;",
      "import 'package:test/repeated.dart';",
      "import 'package:test/reexport.dart';",
    ]) {
      expect(
        d.execute(source: '$prefix main() => convert();', sources: sources),
        'convert',
      );
      expect(
        () => d.execute(source: '$prefix main() => other();', sources: sources),
        throwsA(anything),
      );
    }
    expect(effects, 5);
  });

  test(
    'scoped callback carries arguments, types and async native errors',
    () async {
      final error = StateError('async native');
      final stack = StackTrace.fromString('async native stack');
      d.registerLibraryFunction(
        'package:test/fns.dart',
        'inspectArgs',
        (_, positional, named, types) => [
          positional.length,
          ...positional,
          named.containsKey('x'),
          named['x'],
          types?.single.name,
        ],
      );
      d.registerLibraryFunction(
        'package:test/fns.dart',
        'failAsync',
        (_, _, _, _) => Future.error(error, stack),
      );
      final result =
          await (d.execute(
                    source: '''
      import 'package:test/fns.dart';
      main() async {
        var a = inspectArgs<String>();
        var b = inspectArgs<bool>(null, x: null);
        try { await failAsync(); } catch (e, s) { return [a, b, e, s]; }
      }
    ''',
                  )
                  as Future)
              as List;
      expect(result[0], [0, false, null, 'String']);
      expect(result[1], [1, null, true, null, 'bool']);
      expect(identical(result[2], error), isTrue);
      expect(identical(result[3], stack), isTrue);
    },
  );

  test('one URI composes types and functions and rejects collisions', () {
    const uri = 'package:test/composed.dart';
    final runtime = D4rt();
    runtime.registerBridgedClass(
      BridgedClass(
        name: 'Thing',
        nativeType: _Native,
        constructors: {'': (_, _, _) => _Native()},
      ),
      uri,
    );
    runtime.registerBridgedEnum(
      BridgedEnumDefinition<_Shade>(name: 'Shade', values: _Shade.values),
      uri,
    );
    runtime.registerLibraryFunction(uri, 'answer', (_, _, _, _) => 42);
    expect(
      runtime.execute(
        source: '''
      import 'package:test/composed.dart';
      main() => [Thing() is Thing, Shade.light.name, answer()];
    ''',
      ),
      [true, 'light', 42],
    );
    expect(
      () => runtime.registerLibraryFunction(uri, 'Thing', (_, _, _, _) => 0),
      throwsArgumentError,
    );
    expect(
      () => runtime.registerLibraryFunction(uri, 'Shade', (_, _, _, _) => 0),
      throwsArgumentError,
    );
    final reverse = D4rt();
    reverse.registerLibraryFunction(uri, 'Thing', (_, _, _, _) => 0);
    reverse.registerLibraryFunction(uri, 'Shade', (_, _, _, _) => 0);
    expect(
      () => reverse.registerBridgedClass(
        BridgedClass(name: 'Thing', nativeType: _Native),
        uri,
      ),
      throwsArgumentError,
    );
    expect(
      () => reverse.registerBridgedEnum(
        BridgedEnumDefinition<_Shade>(name: 'Shade', values: _Shade.values),
        uri,
      ),
      throwsArgumentError,
    );
  });

  test('nested generic calls and errors do not leak type state', () {
    d.registerBridgedClass(
      BridgedClass(
        name: 'Relay',
        nativeType: Object,
        constructors: {'': (_, _, _) => Object()},
        genericMethods: {
          'run': (_, _, positional, _, types) {
            final outer = types!.single.name;
            final inner = InterpreterVisitor.invokeCallback(
              positional.single as Callable,
              [],
            );
            return [outer, inner, types.single.name];
          },
          'fail': (_, _, _, _, _) => throw StateError('synthetic'),
        },
      ),
      'package:test/relay.dart',
    );
    expect(
      d.execute(
        source: '''
      import 'package:test/relay.dart';
      main() {
        var r = Relay(); var f = r.run;
        try { r.fail<String>(); } catch (_) {}
        return f<String>(() => f<bool>(() => 7));
      }
    ''',
      ),
      [
        'String',
        ['bool', 7, 'bool'],
        'String',
      ],
    );
  });

  test('new entrypoints preserve callback budget and revoked authority', () {
    for (final generic in [false, true]) {
      final runtime = D4rt()..grant(DangerousPermission.developerTools);
      var expire = false;
      Object? invoke(InterpreterVisitor visitor, List<Object?> positional) {
        if (expire) visitor.deadline!.expire();
        return InterpreterVisitor.invokeCallback(
          positional.single as Callable,
          [],
        );
      }

      runtime.registerLibraryFunction(
        'package:test/callback.dart',
        'run',
        (v, p, _, _) => invoke(v, p),
      );
      runtime.registerBridgedClass(
        BridgedClass(
          name: 'Runner',
          nativeType: Object,
          constructors: {'': (_, _, _) => Object()},
          genericMethods: {'run': (v, _, p, _, _) => invoke(v, p)},
        ),
        'package:test/callback.dart',
      );
      runtime.registertopLevelFunction('revoke', (_, _, _, _) {
        runtime.revoke(DangerousPermission.developerTools);
        return null;
      });
      final call = generic ? 'Runner().run<String>' : 'run';
      expect(
        () => runtime.execute(
          source:
              '''
        import 'dart:developer';
        import 'package:test/callback.dart';
        main() { revoke(); try { $call(() => inspect(1)); } catch (_) { return 'bypass'; } }
      ''',
        ),
        throwsA(isA<RuntimeError>()),
      );
      expect(
        () => runtime.execute(
          source:
              '''
        import 'package:test/callback.dart';
        main() { try { $call(() { while (true) {} }); } catch (_) { return 'bypass'; } }
      ''',
          maxSteps: 200,
        ),
        throwsA(isA<ExecutionLimitException>()),
      );
      expire = true;
      expect(
        () => runtime.execute(
          source:
              '''
          import 'package:test/callback.dart';
          main() { try { $call(() => 1); } catch (_) { return 'bypass'; } }
        ''',
          timeout: const Duration(seconds: 30),
        ),
        throwsA(isA<ExecutionTimeoutException>()),
      );
    }
  });
}
