import 'dart:convert';
import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('Introspection serialization tests', () {
    test('IntrospectionResult toMap and toJson', () {
      final d4rt = D4rt();
      final result = d4rt.analyze(source: '''
        int add(int a, int b) => a + b;

        class Person {
          String name;
          Person(this.name);
          void greet() {}
        }

        enum Status { active, pending }

        extension StringExt on String {
          int get len => length;
        }

        const appVersion = '1.0.0';
      ''');

      final map = result.toMap();
      final jsonStr = result.toJson();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(map['functions'], isNotEmpty);
      expect(map['classes'], isNotEmpty);
      expect(map['enums'], isNotEmpty);
      expect(map['extensions'], isNotEmpty);
      expect(map['variables'], isNotEmpty);

      final funcNames =
          (decoded['functions'] as List).map((f) => f['name']).toList();
      final classNames =
          (decoded['classes'] as List).map((c) => c['name']).toList();
      final enumNames =
          (decoded['enums'] as List).map((e) => e['name']).toList();
      final extNames =
          (decoded['extensions'] as List).map((e) => e['name']).toList();
      final varNames =
          (decoded['variables'] as List).map((v) => v['name']).toList();

      expect(funcNames, contains('add'));
      expect(classNames, contains('Person'));
      expect(enumNames, contains('Status'));
      expect(extNames, contains('StringExt'));
      expect(varNames, contains('appVersion'));
    });

    test('analysis distinguishes unavailable values from computed null', () {
      var effects = 0;
      final d4rt = D4rt();
      d4rt.registertopLevelFunction('touch', (visitor, args, named, types) {
        effects++;
        return null;
      });
      final result = d4rt.analyze(
        source: '''
          final Object? empty = null;
          const int count = 42;
          late String pending;
          final nativeValue = touch();
        ''',
        includeBuiltins: true,
      );
      for (final name in ['empty', 'count', 'pending', 'nativeValue']) {
        final variable = result.getByName(name) as VariableInfo;
        expect(variable.isValueAvailable, isFalse);
        expect(variable.value, isNull);
        expect(variable.valueType, 'unavailable');
        expect(variable.toMap()['isValueAvailable'], isFalse);
        expect(jsonDecode(variable.toJson())['value'], isNull);
        expect(variable.toString(), contains('<unavailable>'));
      }
      expect((result.getByName('empty') as VariableInfo).isFinal, isTrue);
      expect((result.getByName('count') as VariableInfo).isConst, isTrue);
      expect((result.getByName('pending') as VariableInfo).isLate, isTrue);
      result.toMap();
      result.toJson();
      result.toString();
      expect(effects, 0);

      final executed = IntrospectionBuilder.buildFromEnvironment(
        Environment()..define('empty', null),
      ).variables.single;
      expect(executed.isValueAvailable, isTrue);
      expect(executed.valueType, 'Null');
      expect(executed.toString(), 'var empty: Null = null');
      const manual = VariableInfo(name: 'empty', valueType: 'Null');
      expect(manual.isValueAvailable, isTrue);
      expect(manual.toMap()['isValueAvailable'], isTrue);
      expect(manual.toString(), 'var empty: Null = null');
    });
  });
}
