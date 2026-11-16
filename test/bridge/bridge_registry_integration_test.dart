import 'package:test/test.dart';
import 'package:d4rt/d4rt.dart';

// Test enum for use in tests
enum TestEnum { value1, value2 }

void main() {
  group('BridgeRegistryIntegration', () {
    late D4rt interpreter;

    setUp(() {
      interpreter = D4rt();
    });

    test('registerBridgedClass tracks in manager', () {
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      interpreter.registerBridgedClass(bridgedClass, 'package:test/test.dart');

      expect(interpreter.registryStats.totalRegistered, equals(1));
      expect(interpreter.trackedClasses, hasLength(1));
    });

    test('registerBridgedEnum tracks in manager', () {
      final enumDef = BridgedEnumDefinition<TestEnum>(
        name: 'TestEnum',
        values: TestEnum.values,
        getters: {},
        methods: {},
      );

      interpreter.registerBridgedEnum(enumDef, 'package:test/test.dart');

      expect(interpreter.registryStats.totalRegistered, equals(1));
      expect(interpreter.trackedEnums, hasLength(1));
    });

    test('registertopLevelFunction tracks in manager', () {
      interpreter.registertopLevelFunction(
        'testFunc',
        (visitor, args, namedArgs, typeArgs) => 'result',
      );

      expect(interpreter.registryStats.totalRegistered, equals(1));
      expect(interpreter.trackedFunctions, hasLength(1));
    });

    test('multiple registrations tracked separately', () {
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      final enumDef = BridgedEnumDefinition<TestEnum>(
        name: 'TestEnum',
        values: TestEnum.values,
        getters: {},
        methods: {},
      );

      interpreter.registerBridgedClass(bridgedClass, 'package:test/test.dart');
      interpreter.registerBridgedEnum(enumDef, 'package:test/test.dart');
      interpreter.registertopLevelFunction(
        'testFunc',
        (visitor, args, namedArgs, typeArgs) => 'result',
      );

      expect(interpreter.registryStats.totalRegistered, equals(3));
      expect(interpreter.trackedClasses, hasLength(1));
      expect(interpreter.trackedEnums, hasLength(1));
      expect(interpreter.trackedFunctions, hasLength(1));
    });

    test('registry stats include deduplication info', () {
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      interpreter.registerBridgedClass(
        bridgedClass,
        'package:test/test.dart',
        sourceUri: 'package:test/src/test.dart',
      );

      final stats = interpreter.registryStats;
      expect(stats.totalRegistered, isNotNull);
      expect(stats.totalRegistered, equals(1));
    });

    test('clearBridgeRegistry resets all registrations', () {
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      interpreter.registerBridgedClass(bridgedClass, 'package:test/test.dart');
      expect(interpreter.registryStats.totalRegistered, equals(1));

      interpreter.clearBridgeRegistry();

      expect(interpreter.registryStats.totalRegistered, equals(0));
      expect(interpreter.trackedClasses, isEmpty);
    });

    test('source URI tracking works with explicit URI', () {
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      interpreter.registerBridgedClass(
        bridgedClass,
        'package:test/main.dart',
        sourceUri: 'package:test/src/bridges.dart',
      );

      final tracked = interpreter.trackedClasses.first;
      expect(tracked.origin, isNotNull);
      expect(tracked.origin?.canonicalUri, contains('bridges.dart'));
    });

    test('source URI inferred from library path when not provided', () {
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      interpreter.registerBridgedClass(bridgedClass, 'package:test/test.dart');

      final tracked = interpreter.trackedClasses.first;
      expect(tracked.origin?.elementName, equals('TestClass'));
    });

    test('backward compatibility with old API signatures', () {
      // Ensure old code without sourceUri still works
      final bridgedClass = BridgedClass(
        name: 'TestClass',
        nativeType: String,
        constructors: {},
        methods: {},
        getters: {},
      );

      // Should not throw
      expect(
        () => interpreter.registerBridgedClass(
          bridgedClass,
          'package:test/test.dart',
        ),
        returnsNormally,
      );

      // Verify it was registered
      expect(interpreter.registryStats.totalRegistered, equals(1));
    });
  });
}
