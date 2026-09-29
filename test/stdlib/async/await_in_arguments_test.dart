import 'dart:async';

import 'package:test/test.dart';
import '../../interpreter_test.dart';

void main() {
  group('Await in Function Arguments Tests', () {
    test('await in positional arguments', () async {
      const source = '''
        Future<int> getValue() async {
          await Future.delayed(Duration(milliseconds: 5));
          return 42;
        }
        
        int processValue(int value) {
          return value * 2;
        }

        Future<int> main() async {
          int result = processValue(await getValue());
          return result;
        }
      ''';
      expect(await execute(source), equals(84));
    });

    test('await in named arguments', () async {
      const source = '''
        Future<String> getName() async {
          await Future.delayed(Duration(milliseconds: 5));
          return "World";
        }
        
        String greet({required String name, String prefix = "Hello"}) {
          return prefix + ", " + name + "!";
        }

        Future<String> main() async {
          String result = greet(name: await getName());
          return result;
        }
      ''';
      expect(await execute(source), equals("Hello, World!"));
    });

    test('constructor with await in arguments', () async {
      const source = '''
        class Point {
          int x;
          int y;
          
          Point(this.x, this.y);
          
          int sum() {
            return x + y;
          }
        }
        
        Future<int> getCoordinate() async {
          await Future.delayed(Duration(milliseconds: 5));
          return 15;
        }

        Future<int> main() async {
          Point point = Point(await getCoordinate(), 25);
          return point.sum();
        }
      ''';
      expect(await execute(source), equals(40));
    });

    test('nested await in map argument resumes each await once', () async {
      final nativeEvents = <String>[];
      Future<String> readName() async {
        nativeEvents.add('read:start');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        nativeEvents.add('read:end');
        return 'Ada';
      }

      Future<String> writeValue(Map<String, String> value) async {
        nativeEvents.add('write:${value['name']}');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        nativeEvents.add('write:end');
        return value['name']!;
      }

      final nativeResult = await writeValue({'name': await readName()});
      nativeEvents.add('after:$nativeResult');

      const source = '''
        List<String> events = [];

        Future<String> readName() async {
          events.add('read:start');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('read:end');
          return 'Ada';
        }

        Future<String> writeValue(Map<String, String> value) async {
          events.add('write:\${value['name']}');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('write:end');
          return value['name']!;
        }

        Future<Map<String, Object?>> main() async {
          final result = await writeValue({'name': await readName()});
          events.add('after:\$result');
          return {'result': result, 'events': events};
        }
      ''';
      expect(
          await execute(source),
          equals({
            'result': nativeResult,
            'events': nativeEvents,
          }));
    });

    test('nested map key and named argument preserve sibling order and null',
        () async {
      final nativeEvents = <String>[];
      Future<String> read(String label, String value) async {
        nativeEvents.add('$label:start');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        nativeEvents.add('$label:end');
        return value;
      }

      Future<String?> writeValue(Map<String, String> data,
          {required String suffix}) async {
        nativeEvents.add('write:${data['key']}:$suffix');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        nativeEvents.add('write:end');
        return null;
      }

      final nativeResult = await writeValue(
        {await read('key', 'key'): await read('value', 'Ada')},
        suffix: await read('suffix', '!'),
      );
      nativeEvents.add('after:${nativeResult == null}');

      const source = '''
        List<String> events = [];

        Future<String> read(String label, String value) async {
          events.add('\$label:start');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('\$label:end');
          return value;
        }

        Future<String?> writeValue(Map<String, String> data,
            {required String suffix}) async {
          events.add('write:\${data['key']}:\$suffix');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('write:end');
          return null;
        }

        Future<Map<String, Object?>> main() async {
          final result = await writeValue(
            {await read('key', 'key'): await read('value', 'Ada')},
            suffix: await read('suffix', '!'),
          );
          events.add('after:\${result == null}');
          return {'result': result, 'events': events};
        }
      ''';
      expect(
          await execute(source),
          equals({
            'result': nativeResult,
            'events': nativeEvents,
          }));
    });

    test('an inner null reaches the outer call without skipping its await',
        () async {
      final nativeEvents = <String>[];
      Future<String?> readName() async {
        nativeEvents.add('read:start');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        nativeEvents.add('read:end');
        return null;
      }

      Future<String> writeValue(Map<String, String?> data) async {
        nativeEvents.add('write:${data.length}:${data['name'] == null}');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        nativeEvents.add('write:end');
        return data['name'] ?? 'fallback';
      }

      final nativeResult = await writeValue({'name': await readName()});
      nativeEvents.add('after:$nativeResult');

      const source = '''
        List<String> events = [];

        Future<String?> readName() async {
          events.add('read:start');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('read:end');
          return null;
        }

        Future<String> writeValue(Map<String, String?> data) async {
          events.add('write:\${data.length}:\${data['name'] == null}');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('write:end');
          return data['name'] ?? 'fallback';
        }

        Future<Map<String, Object?>> main() async {
          final result = await writeValue({'name': await readName()});
          events.add('after:\$result');
          return {'result': result, 'events': events};
        }
      ''';
      expect(
          await execute(source),
          equals({
            'result': nativeResult,
            'events': nativeEvents,
          }));
    });

    test('nested inner and outer failures reach catch and finally once',
        () async {
      const source = '''
        List<String> events = [];

        Future<String> readName(bool failInner) async {
          events.add('inner:start');
          await Future.delayed(Duration(milliseconds: 1));
          if (failInner) {
            events.add('inner:fail');
            throw 'inner';
          }
          events.add('inner:end');
          return 'Ada';
        }

        Future<String> writeValue(Map<String, String> data) async {
          events.add('outer:start:\${data['name']}');
          await Future.delayed(Duration(milliseconds: 1));
          events.add('outer:fail');
          throw 'outer';
        }

        Future<Map<String, Object?>> main(bool failInner) async {
          String result;
          try {
            result = await writeValue({'name': await readName(failInner)});
          } catch (error) {
            events.add('catch:\$error');
            result = 'recovered';
          } finally {
            events.add('finally');
          }
          events.add('after:\$result');
          return {'result': result, 'events': events};
        }
      ''';

      for (final failInner in [true, false]) {
        final nativeEvents = <String>[];
        Future<String> readName() async {
          nativeEvents.add('inner:start');
          await Future<void>.delayed(const Duration(milliseconds: 1));
          if (failInner) {
            nativeEvents.add('inner:fail');
            throw 'inner';
          }
          nativeEvents.add('inner:end');
          return 'Ada';
        }

        Future<String> writeValue(Map<String, String> data) async {
          nativeEvents.add('outer:start:${data['name']}');
          await Future<void>.delayed(const Duration(milliseconds: 1));
          nativeEvents.add('outer:fail');
          throw 'outer';
        }

        String nativeResult;
        try {
          nativeResult = await writeValue({'name': await readName()});
        } catch (error) {
          nativeEvents.add('catch:$error');
          nativeResult = 'recovered';
        } finally {
          nativeEvents.add('finally');
        }
        nativeEvents.add('after:$nativeResult');
        expect(
            await execute(source, args: [failInner]),
            equals({
              'result': nativeResult,
              'events': nativeEvents,
            }));
      }
    });

    test('overlapping nested awaits keep their owning async frames', () async {
      final nativeEvents = <String>[];
      Future<String> readName(String label, Completer<String> gate) async {
        nativeEvents.add('$label:read:start');
        final value = await gate.future;
        nativeEvents.add('$label:read:end:$value');
        return value;
      }

      Future<String> writeValue(String label, Map<String, String> data,
          Completer<String> gate) async {
        nativeEvents.add('$label:write:${data['name']}');
        final release = await gate.future;
        nativeEvents.add('$label:write:end:$release');
        return '${data['name']}:$release';
      }

      Future<String> work(String label, Completer<String> inner,
          Completer<String> outer) async {
        final result = await writeValue(
            label, {'name': await readName(label, inner)}, outer);
        nativeEvents.add('$label:after:$result');
        return result;
      }

      final slowInner = Completer<String>();
      final slowOuter = Completer<String>();
      final fastInner = Completer<String>();
      final fastOuter = Completer<String>();
      final slow = work('slow', slowInner, slowOuter);
      final fast = work('fast', fastInner, fastOuter);
      fastInner.complete('fast');
      fastOuter.complete('fast-ok');
      final nativeFast = await fast;
      slowInner.complete('slow');
      slowOuter.complete('slow-ok');
      final nativeSlow = await slow;

      const source = '''
        import 'dart:async';

        List<String> events = [];

        Future<String> readName(String label, Completer<String> gate) async {
          events.add('\$label:read:start');
          final value = await gate.future;
          events.add('\$label:read:end:\$value');
          return value;
        }

        Future<String> writeValue(
            String label, Map<String, String> data, Completer<String> gate) async {
          events.add('\$label:write:\${data['name']}');
          final release = await gate.future;
          events.add('\$label:write:end:\$release');
          return '\${data['name']}:\$release';
        }

        Future<String> work(String label, Completer<String> inner,
            Completer<String> outer) async {
          final result = await writeValue(
              label, {'name': await readName(label, inner)}, outer);
          events.add('\$label:after:\$result');
          return result;
        }

        Future<Map<String, Object?>> main() async {
          final slowInner = Completer<String>();
          final slowOuter = Completer<String>();
          final fastInner = Completer<String>();
          final fastOuter = Completer<String>();
          final slow = work('slow', slowInner, slowOuter);
          final fast = work('fast', fastInner, fastOuter);
          fastInner.complete('fast');
          fastOuter.complete('fast-ok');
          final fastResult = await fast;
          slowInner.complete('slow');
          slowOuter.complete('slow-ok');
          final slowResult = await slow;
          return {'results': [fastResult, slowResult], 'events': events};
        }
      ''';
      expect(
          await execute(source),
          equals({
            'results': [nativeFast, nativeSlow],
            'events': nativeEvents,
          }));
    });

    test('await with exception handling in arguments', () async {
      const source = '''
        Future<int> riskyFunction() async {
          await Future.delayed(Duration(milliseconds: 5));
          throw Exception("Something went wrong");
        }
        
        Future<int> safeFunction() async {
          await Future.delayed(Duration(milliseconds: 5));
          return 100;
        }
        
        int processValue(int value) {
          return value + 1;
        }

        Future<int> main() async {
          try {
            int result = processValue(await riskyFunction());
            return result;
          } catch (e) {
            return processValue(await safeFunction());
          }
        }
      ''';

      expect(await execute(source), equals(101));
    });
  });
}
