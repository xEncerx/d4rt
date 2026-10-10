import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

class _NativeBase {
  _NativeBase(this.value);

  int value;

  int increment() => ++value;
}

class _BridgeHarness {
  _BridgeHarness({this.constructorOutcome});

  final Object? Function()? constructorOutcome;
  int constructorCalls = 0;
  int bodyCalls = 0;
  int providerCalls = 0;
  List<Object?>? positionalArguments;
  Map<String, Object?>? namedArguments;
  final List<_NativeBase> constructedObjects = [];

  void register(D4rt interpreter, {bool includeUnnamedConstructor = true}) {
    final constructors = <String, BridgedConstructorCallable>{};
    if (includeUnnamedConstructor) {
      constructors[''] = (visitor, positionalArgs, namedArgs) {
        constructorCalls++;
        positionalArguments = positionalArgs;
        namedArguments = namedArgs;

        if (constructorOutcome != null) {
          return constructorOutcome!();
        }

        final nativeObject = _NativeBase(constructorCalls * 10);
        constructedObjects.add(nativeObject);
        return nativeObject;
      };
    }

    interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: _NativeBase,
        name: 'BridgedBase',
        constructors: constructors,
        staticMethods: {
          'markBody': (visitor, positionalArgs, namedArgs) {
            bodyCalls++;
            return null;
          },
          'markProvider': (visitor, positionalArgs, namedArgs) {
            providerCalls++;
            return null;
          },
        },
        getters: {
          'value': (visitor, target) => (target as _NativeBase).value,
        },
        methods: {
          'increment': (visitor, target, positionalArgs, namedArgs) =>
              (target as _NativeBase).increment(),
        },
      ),
      'package:test/implicit_bridged_super.dart',
    );
  }
}

abstract interface class _Parameters {
  List<Object?> get values;
}

class _NativePositional implements _Parameters {
  _NativePositional(
      [this.first = 'parent-first', this.second = 'parent-second']);
  final Object? first;
  final Object? second;
  @override
  List<Object?> get values => [first, second];
}

class _NativePositionalChild extends _NativePositional {
  _NativePositionalChild(this.local, super.renamed, [super.other]);
  _NativePositionalChild.defaults(this.local,
      [super.renamed = 'child-first', super.other = 'child-second']);
  final String local;
}

class _NativeInteriorDefaultChild extends _NativePositional {
  _NativeInteriorDefaultChild([super.first, super.second = 3]);
}

class _NativeNamed implements _Parameters {
  _NativeNamed(this.first, {this.second = 'parent-second', required this.tag});
  _NativeNamed.selected(Object? first,
      {Object? second = 'parent-second', required Object? tag})
      : this(first, second: second, tag: tag);
  _NativeNamed.options(
      {this.first = 'parent-first', this.second = 'parent-second'})
      : tag = null;
  final Object? first;
  final Object? second;
  final Object? tag;
  @override
  List<Object?> get values => [first, second, tag];
}

class _NativeDuration implements _Parameters {
  _NativeDuration([this.value = const Duration(seconds: 1)]);
  final Duration? value;
  @override
  List<Object?> get values => [value];
}

class _NativeFailureMembers {
  _NativeFailureMembers(this.error, this.stack);
  Object error;
  final StackTrace stack;
  Never fail() => Error.throwWithStackTrace(error, stack);
  Object? get value => Error.throwWithStackTrace(error, stack);
  set value(Object? value) => Error.throwWithStackTrace(error, stack);
}

void _registerFailureMembers(D4rt interpreter, _NativeFailureMembers native) {
  interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: _NativeFailureMembers,
        name: 'FailureBase',
        constructors: {'': (visitor, args, named) => native},
        methods: {
          'fail': (visitor, target, args, named) =>
              (target as _NativeFailureMembers).fail(),
        },
        getters: {
          'value': (visitor, target) => (target as _NativeFailureMembers).value,
        },
        setters: {
          'value': (visitor, target, value) =>
              (target as _NativeFailureMembers).value = value,
        },
      ),
      'package:test/native_member_errors.dart');
}

class _ParameterHarness {
  final events = <String>[];

  void register(D4rt interpreter) {
    void registerClass(
        Type type, String name, Map<String, Function> factories) {
      interpreter.registerBridgedClass(
          BridgedClass(
            nativeType: type,
            name: name,
            constructors: factories.map((key, factory) => MapEntry(
                  key,
                  (visitor, positional, named) {
                    events.add('constructor:$name.$key');
                    return Function.apply(factory, positional, {
                      for (final entry in named.entries)
                        Symbol(entry.key): entry.value,
                    });
                  },
                )),
            getters: {
              'values': (visitor, target) => (target as _Parameters).values,
            },
          ),
          'package:test/super_parameters.dart');
    }

    registerClass(_NativePositional, 'PositionalBase', {
      '': _NativePositional.new,
    });
    registerClass(_NativeNamed, 'NamedBase', {
      '': _NativeNamed.new,
      'selected': _NativeNamed.selected,
      'options': _NativeNamed.options,
    });
    registerClass(_NativeDuration, 'DurationBase', {
      '': _NativeDuration.new,
    });
    interpreter.registertopLevelFunction('markBody',
        (visitor, args, named, types) {
      events.add('body:${args.single}');
      return null;
    });
  }
}

void main() {
  group('Implicit bridged superclass constructor', () {
    late D4rt interpreter;

    setUp(() {
      interpreter = D4rt();
    });

    test('inherited native member failures retain identity and stack', () {
      final error = UnsupportedError('native member rejected');
      final stack = StackTrace.fromString('native member stack');
      final native = _NativeFailureMembers(error, stack);
      _registerFailureMembers(interpreter, native);
      final errors = <Object?>[];
      final stacks = <Object?>[];
      interpreter.registertopLevelFunction('observe',
          (visitor, args, named, types) {
        errors.add(args[0]);
        stacks.add(args[1]);
        return null;
      });
      expect(interpreter.execute(source: '''
import 'package:test/native_member_errors.dart';
class Child extends FailureBase {}
main() {
  final value = Child();
  int postFailure = 0;
  try { value.fail(); postFailure++; }
  on UnsupportedError catch (error, stack) { observe(error, stack); }
  try { final result = value.value; postFailure++; }
  on UnsupportedError catch (error, stack) { observe(error, stack); }
  try { value.value = 1; postFailure++; }
  on UnsupportedError catch (error, stack) { observe(error, stack); }
  return postFailure;
}
'''), 0);
      expect(errors, hasLength(3));
      for (final observed in errors) {
        expect(observed, same(error));
      }
      expect(stacks, List.filled(3, stack.toString()));
    });

    test('unhandled inherited native failures keep the public error boundary',
        () {
      final native = _NativeFailureMembers(
          UnsupportedError('native failure'), StackTrace.current);
      _registerFailureMembers(interpreter, native);
      for (final error in <Object>[
        UnsupportedError('native failure'),
        ArgumentError('invalid argument'),
      ]) {
        native.error = error;
        for (final operation in [
          'value.fail();',
          'final result = value.value;',
          'value.value = 1;',
        ]) {
          expect(() => interpreter.execute(source: '''
import 'package:test/native_member_errors.dart';
class Child extends FailureBase {}
main() { final value = Child(); $operation }
'''), throwsA(isA<RuntimeError>()));
        }
      }
    });

    test('positional super formals preserve order, defaults and null', () {
      final harness = _ParameterHarness()..register(interpreter);
      final result = interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Child extends PositionalBase {
  Child(this.local, super.renamed, [super.other]) { markBody(local); }
  Child.defaults(this.local,
      [super.renamed = 'child-first', super.other = 'child-second']) {
    markBody(local);
  }
  final String local;
}
class Optional extends PositionalBase {
  Optional([super.renamed, super.other]);
}
main() => [
  Child('local', 1).values,
  Child('local', 1, null).values,
  Child.defaults('local').values,
  Child.defaults('local', null).values,
  Child.defaults('local', 4, 5).values,
  Optional().values,
  Optional(null).values,
  Optional(null, null).values,
];
''');
      expect(result, [
        _NativePositionalChild('local', 1).values,
        _NativePositionalChild('local', 1, null).values,
        _NativePositionalChild.defaults('local').values,
        _NativePositionalChild.defaults('local', null).values,
        _NativePositionalChild.defaults('local', 4, 5).values,
        _NativePositional().values,
        _NativePositional(null).values,
        _NativePositional(null, null).values,
      ]);
      expect(harness.events, [
        for (var i = 0; i < 5; i++) ...[
          'constructor:PositionalBase.',
          'body:local',
        ],
        for (var i = 0; i < 3; i++) 'constructor:PositionalBase.',
      ]);
    });

    test('interior native default omission fails before constructor effects',
        () {
      final harness = _ParameterHarness()..register(interpreter);
      const declarations = '''
import 'package:test/super_parameters.dart';
class Child extends PositionalBase {
  Child([super.first, super.second = 3]) { markBody('child'); }
}
''';
      expect(
          () =>
              interpreter.execute(source: '${declarations}main() => Child();'),
          throwsA(isA<RuntimeError>()));
      expect(harness.events, isEmpty);

      final result = interpreter.execute(source: '''
${declarations}main() =>
    [Child(null).values, Child(4).values, Child(null, 5).values];
''');
      expect(result, [
        _NativeInteriorDefaultChild(null).values,
        _NativeInteriorDefaultChild(4).values,
        _NativeInteriorDefaultChild(null, 5).values,
      ]);
      expect(harness.events, [
        'constructor:PositionalBase.',
        'body:child',
        'constructor:PositionalBase.',
        'body:child',
        'constructor:PositionalBase.',
        'body:child',
      ]);
    });

    test('named super formals combine with valid explicit super arguments', () {
      final harness = _ParameterHarness()..register(interpreter);
      final result = interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Child extends NamedBase {
  Child(super.renamed, this.local, {required super.tag, super.second}) {
    markBody(local);
  }
  Child.defaults(super.renamed, {required super.tag, super.second = 'child'})
      : local = 'local';
  Child.explicit({required super.tag, super.second}) : local = 'local',
      super('fixed');
  Child.selected(super.renamed, {super.second = 'child'}) : local = 'local',
      super.selected(tag: 'selected');
  Child.options({super.first = 'child-first', super.second}) : local = 'local',
      super.options();
  final String local;
}
main() => [
  Child(1, 'local', tag: 'tag').values,
  Child(1, 'local', tag: null, second: null).values,
  Child.defaults(1, tag: 'tag').values,
  Child.explicit(tag: 'tag').values,
  Child.explicit(tag: 'tag', second: null).values,
  Child.selected(2).values,
  Child.options().values,
  Child.options(first: null, second: null).values,
];
''');
      expect(result, [
        _NativeNamed(1, tag: 'tag').values,
        _NativeNamed(1, tag: null, second: null).values,
        _NativeNamed(1, tag: 'tag', second: 'child').values,
        _NativeNamed('fixed', tag: 'tag').values,
        _NativeNamed('fixed', tag: 'tag', second: null).values,
        _NativeNamed.selected(2, tag: 'selected', second: 'child').values,
        _NativeNamed.options(first: 'child-first').values,
        _NativeNamed.options(first: null, second: null).values,
      ]);
      expect(harness.events, [
        'constructor:NamedBase.',
        'body:local',
        'constructor:NamedBase.',
        'body:local',
        'constructor:NamedBase.',
        'constructor:NamedBase.',
        'constructor:NamedBase.',
        'constructor:NamedBase.selected',
        'constructor:NamedBase.options',
        'constructor:NamedBase.options',
      ]);
    });

    test('native values in super defaults agree with supplied native values',
        () {
      final harness = _ParameterHarness()..register(interpreter);
      expect(interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Child extends DurationBase {
  Child([super.value = const Duration(seconds: 2)]);
}
main() => [Child().values, Child(Duration(seconds: 3)).values,
    Child(null).values];
'''), [
        _NativeDuration(const Duration(seconds: 2)).values,
        _NativeDuration(const Duration(seconds: 3)).values,
        _NativeDuration(null).values,
      ]);
      expect(harness.events, List.filled(3, 'constructor:DurationBase.'));
    });

    test('forwarding retains child arity and name errors before native effects',
        () {
      for (final expression in [
        "Child()",
        "Child(1, 'local')",
        "Child(1, 'local', 2, tag: 'tag')",
        "Child(1, 'local', tag: 'tag', unknown: 2)",
        "Optional(renamed: 1)",
      ]) {
        final interpreter = D4rt();
        final harness = _ParameterHarness()..register(interpreter);
        expect(() => interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Child extends NamedBase {
  Child(super.renamed, this.local, {required super.tag, super.second}) {
    markBody(local);
  }
  final String local;
}
class Optional extends PositionalBase {
  Optional([super.renamed, super.other]);
}
main() => $expression;
'''), throwsA(isA<RuntimeError>()), reason: expression);
        expect(harness.events, isEmpty, reason: expression);
      }
    });

    test('native type errors do not run the constructor body', () {
      final harness = _ParameterHarness()..register(interpreter);
      expect(() => interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Child extends DurationBase {
  Child(super.value) { markBody('local'); }
}
main() => Child('wrong type');
'''), throwsA(isA<RuntimeError>()));
      expect(harness.events, ['constructor:DurationBase.']);
    });

    test('duplicate explicit and formal named super arguments fail', () {
      final harness = _ParameterHarness()..register(interpreter);
      expect(() => interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Child extends NamedBase {
  Child({super.first}) : super.options(first: 'explicit');
}
main() => Child(first: 'forwarded');
'''), throwsA(isA<RuntimeError>()));
      expect(harness.events, isEmpty);
    });

    test('explicit named super expressions run once with forwarded formals',
        () {
      final harness = _ParameterHarness()..register(interpreter);
      expect(interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
int effects = 0;
String nextTag() { effects++; return 'tag'; }
class Child extends NamedBase {
  Child(super.renamed, {super.second = 'child'})
      : super.selected(tag: nextTag());
}
main() { final child = Child(1); return [child.values, effects]; }
'''), [_NativeNamed.selected(1, tag: 'tag', second: 'child').values, 1]);
      expect(harness.events, ['constructor:NamedBase.selected']);
    });

    test('super formals through redirects and interpreted chains call once',
        () {
      final harness = _ParameterHarness()..register(interpreter);
      expect(interpreter.execute(source: '''
import 'package:test/super_parameters.dart';
class Parent extends PositionalBase {
  Parent(super.renamed, [super.other]);
}
class Child extends Parent {
  Child(super.value, [super.extra = 'child']) { markBody('local'); }
  Child.redirect() : this(1);
}
main() => Child.redirect().values;
'''), _NativePositional(1, 'child').values);
      expect(harness.events, ['constructor:PositionalBase.', 'body:local']);
    });

    test('synthetic defaults own distinct raw state per instance', () {
      final harness = _BridgeHarness()..register(interpreter);

      final result = interpreter.execute(source: '''
        import 'package:test/implicit_bridged_super.dart';

        class Child extends BridgedBase {}

        main() {
          final first = Child();
          final second = Child();
          first.increment();
          second.increment();
          second.increment();
          return [first.value, second.value, first, second];
        }
      ''') as List<Object?>;

      expect(result[0], 11);
      expect(result[1], 22);
      expect(harness.constructorCalls, 2);
      expect(harness.positionalArguments, isEmpty);
      expect(harness.namedArguments, isEmpty);
      expect(result[2], isA<InterpretedInstance>());
      expect(result[3], isA<InterpretedInstance>());
      final firstInstance = result[2] as InterpretedInstance;
      final secondInstance = result[3] as InterpretedInstance;
      expect(
        firstInstance.bridgedSuperObject,
        same(harness.constructedObjects[0]),
      );
      expect(
        secondInstance.bridgedSuperObject,
        same(harness.constructedObjects[1]),
      );
      expect(
        firstInstance.bridgedSuperObject,
        isNot(same(secondInstance.bridgedSuperObject)),
      );
      expect(firstInstance.bridgedSuperObject, isNot(isA<BridgedInstance>()));
      expect(secondInstance.bridgedSuperObject, isNot(isA<BridgedInstance>()));
    });

    test('declared unnamed constructor implicitly invokes unnamed adapter', () {
      final harness = _BridgeHarness()..register(interpreter);

      final result = interpreter.execute(source: '''
        import 'package:test/implicit_bridged_super.dart';

        class Child extends BridgedBase {
          Child() {
            BridgedBase.markBody();
          }
        }

        main() => Child().value;
      ''');

      expect(result, 10);
      expect(harness.constructorCalls, 1);
      expect(harness.bodyCalls, 1);
    });

    test('declared named constructor implicitly invokes unnamed adapter', () {
      final harness = _BridgeHarness()..register(interpreter);

      final result = interpreter.execute(source: '''
        import 'package:test/implicit_bridged_super.dart';

        class Child extends BridgedBase {
          Child.named() {
            BridgedBase.markBody();
          }
        }

        main() => Child.named().value;
      ''');

      expect(result, 10);
      expect(harness.constructorCalls, 1);
      expect(harness.bodyCalls, 1);
    });

    test('explicit super invocation remains exactly once', () {
      final harness = _BridgeHarness()..register(interpreter);

      final result = interpreter.execute(source: '''
        import 'package:test/implicit_bridged_super.dart';

        class Child extends BridgedBase {
          Child() : super() {
            BridgedBase.markBody();
          }
        }

        main() => Child().value;
      ''');

      expect(result, 10);
      expect(harness.constructorCalls, 1);
      expect(harness.bodyCalls, 1);
    });

    test('redirecting constructor invokes bridge through final target once',
        () {
      final harness = _BridgeHarness()..register(interpreter);

      final result = interpreter.execute(source: '''
        import 'package:test/implicit_bridged_super.dart';

        class Child extends BridgedBase {
          Child.redirecting() : this();

          Child() {
            BridgedBase.markBody();
          }
        }

        main() => Child.redirecting().value;
      ''');

      expect(result, 10);
      expect(harness.constructorCalls, 1);
      expect(harness.bodyCalls, 1);
    });

    test('interpreted chain above bridge constructs native state once', () {
      final harness = _BridgeHarness()..register(interpreter);

      final result = interpreter.execute(source: '''
        import 'package:test/implicit_bridged_super.dart';

        class Intermediate extends BridgedBase {}
        class Child extends Intermediate {}

        main() => Child().increment();
      ''');

      expect(result, 11);
      expect(harness.constructorCalls, 1);
    });

    void testImplicitFailure(
      String description, {
      bool includeUnnamedConstructor = true,
      Object? Function()? constructorOutcome,
      required String expectedMessage,
      required int expectedConstructorCalls,
    }) {
      test(description, () {
        final harness = _BridgeHarness(constructorOutcome: constructorOutcome)
          ..register(
            interpreter,
            includeUnnamedConstructor: includeUnnamedConstructor,
          );

        expect(
          () => interpreter.execute(source: '''
            import 'package:test/implicit_bridged_super.dart';

            class Child extends BridgedBase {
              Child() {
                BridgedBase.markBody();
              }

              void providerMethod() {
                BridgedBase.markProvider();
              }
            }

            main() => Child().providerMethod();
          '''),
          throwsA(
            isA<RuntimeError>().having(
              (error) => error.message,
              'message',
              contains(expectedMessage),
            ),
          ),
        );
        expect(harness.constructorCalls, expectedConstructorCalls);
        expect(harness.bodyCalls, 0);
        expect(harness.providerCalls, 0);
      });
    }

    testImplicitFailure(
      'missing unnamed adapter fails before constructor body',
      includeUnnamedConstructor: false,
      expectedMessage: 'does not have an unnamed constructor adapter',
      expectedConstructorCalls: 0,
    );

    testImplicitFailure(
      'null unnamed adapter result fails before constructor body',
      constructorOutcome: () => null,
      expectedMessage: 'returned null',
      expectedConstructorCalls: 1,
    );

    testImplicitFailure(
      'adapter RuntimeError remains a descriptive RuntimeError boundary',
      constructorOutcome: () => throw RuntimeError('adapter runtime failure'),
      expectedMessage:
          "Error during bridged super constructor '': adapter runtime failure",
      expectedConstructorCalls: 1,
    );

    testImplicitFailure(
      'native adapter exception becomes a descriptive RuntimeError boundary',
      constructorOutcome: () => throw StateError('adapter native failure'),
      expectedMessage:
          "Native error during bridged super constructor '': Bad state: adapter native failure",
      expectedConstructorCalls: 1,
    );

    test('explicit super rejects null adapter output before constructor body',
        () {
      final harness = _BridgeHarness(constructorOutcome: () => null)
        ..register(interpreter);

      expect(
        () => interpreter.execute(source: '''
          import 'package:test/implicit_bridged_super.dart';

          class Child extends BridgedBase {
            Child() : super() {
              BridgedBase.markBody();
            }
          }

          main() => Child();
        '''),
        throwsA(
          isA<RuntimeError>().having(
            (error) => error.message,
            'message',
            contains('returned null'),
          ),
        ),
      );
      expect(harness.constructorCalls, 1);
      expect(harness.bodyCalls, 0);
    });
  });
}
