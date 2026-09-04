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

void main() {
  group('Implicit bridged superclass constructor', () {
    late D4rt interpreter;

    setUp(() {
      interpreter = D4rt();
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
