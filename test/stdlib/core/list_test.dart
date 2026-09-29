import 'dart:collection';
import 'dart:convert';

import 'package:d4rt/d4rt.dart';

import 'package:test/test.dart';

import '../../interpreter_test.dart';

void main() {
  group('List stdlib tests', () {
    test('List literal and basic properties', () {
      final result = execute(r'''
        main() {
          List<int> l1 = [1, 2, 3];
          List<dynamic> l2 = [];
          return [
            l1.length, l1.isEmpty, l1.isNotEmpty,
            l2.length, l2.isEmpty, l2.isNotEmpty
          ];
        }
      ''');
      expect(result, equals([3, false, true, 0, true, false]));
    });

    test('List index access [] and assignment []=', () {
      final result = execute(r'''
        main() {
          List<String> l = ['a', 'b', 'c'];
          var first = l[0];
          l[1] = 'B';
          return [first, l[1], l];
        }
      ''');
      expect(
          result,
          equals([
            'a',
            'B',
            ['a', 'B', 'c']
          ]));
    });

    test('List add and addAll', () {
      final result = execute(r'''
        main() {
          List<int> l = [1];
          l.add(2);
          l.addAll([3, 4]);
          return l;
        }
      ''');
      expect(result, equals([1, 2, 3, 4]));
    });

    test('List remove, removeAt, clear', () {
      final result = execute(r'''
        main() {
          List<String> l = ['x', 'y', 'z', 'y'];
          bool removedY = l.remove('y'); // Removes first 'y'
          var removedAt1 = l.removeAt(1); // Removes 'z'
          l.clear();
          return [removedY, removedAt1, l.length, l];
        }
      ''');
      expect(result, equals([true, 'z', 0, []]));
    });

    test('List contains, indexOf, lastIndexOf', () {
      final result = execute(r'''
        main() {
          List<int> l = [10, 20, 30, 20, 40];
          return [
            l.contains(20),
            l.contains(50),
            l.indexOf(20),       // First occurrence
            l.lastIndexOf(20),   // Last occurrence
            l.indexOf(50)        // Not found
          ];
        }
      ''');
      expect(result, equals([true, false, 1, 3, -1]));
    });

    test('List join', () {
      final result = execute(r'''
        main() {
          List<String> l = ['h', 'e', 'l', 'l', 'o'];
          return l.join('-');
        }
      ''');
      expect(result, equals('h-e-l-l-o'));
    });

    test('List sublist', () {
      final result = execute(r'''
        main() {
          List<int> l = [0, 1, 2, 3, 4, 5];
          return [l.sublist(1, 4), l.sublist(3)];
        }
      ''');
      expect(
          result,
          equals([
            [1, 2, 3],
            [3, 4, 5]
          ]));
    });

    group('List methods', () {
      test('insert', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 4];
        numbers.insert(2, 3);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2, 3, 4]));
      });

      test('insertAll', () {
        const source = '''
       main() {
        List<int> numbers = [1, 4];
        numbers.insertAll(1, [2, 3]);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2, 3, 4]));
      });

      test('setAll', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.setAll(1, [5, 6]);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 5, 6, 4]));
      });

      test('fillRange', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.fillRange(1, 3, 0);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 0, 0, 4]));
      });

      test('replaceRange', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.replaceRange(1, 3, [5, 6]);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 5, 6, 4]));
      });

      test('removeRange', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.removeRange(1, 3);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 4]));
      });

      test('retainWhere', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.retainWhere((n) => n % 2 == 0);
        return numbers;
      }
      ''';
        expect(execute(source), equals([2, 4]));
      });

      test('removeWhere', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.removeWhere((n) => n % 2 == 0);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 3]));
      });

      test('sort', () {
        const source = '''
       main() {
        List<int> numbers = [4, 2, 3, 1];
        numbers.sort();
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2, 3, 4]));
      });

      test('shuffle', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.shuffle();
        return numbers; // Cannot check order, but check length and elements
      }
      ''';
        final result = execute(source) as List;
        expect(result, isA<List>());
        expect(result.length, equals(4));
        expect(result, containsAll([1, 2, 3, 4]));
      });

      test('reversed', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        return numbers.reversed.toList();
      }
      ''';
        expect(execute(source), equals([4, 3, 2, 1]));
      });

      test('asMap', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.asMap();
      }
      ''';
        expect(execute(source), equals({0: 1, 1: 2, 2: 3}));
      });
    });

    group('List methods - comprehensive', () {
      test('add', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2];
        numbers.add(3);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2, 3]));
      });

      test('addAll', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2];
        numbers.addAll([3, 4]);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2, 3, 4]));
      });

      test('remove', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        numbers.remove(2);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 3]));
      });

      test('removeAt', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        numbers.removeAt(1);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 3]));
      });

      test('removeLast', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        numbers.removeLast();
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2]));
      });

      test('removeRange', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.removeRange(1, 3);
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 4]));
      });

      test('retainWhere', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        numbers.retainWhere((n) => n % 2 == 0);
        return numbers;
      }
      ''';
        expect(execute(source), equals([2, 4]));
      });

      test('indexOf', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 2];
        return numbers.indexOf(2);
      }
      ''';
        expect(execute(source), equals(1));
      });

      test('lastIndexOf', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 2];
        return numbers.lastIndexOf(2);
      }
      ''';
        expect(execute(source), equals(3));
      });

      test('sublist', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        return numbers.sublist(1, 3);
      }
      ''';
        expect(execute(source), equals([2, 3]));
      });

      test('contains', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.contains(2);
      }
      ''';
        expect(execute(source), equals(true));
      });

      test('length', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.length;
      }
      ''';
        expect(execute(source), equals(3));
      });

      test('isEmpty and isNotEmpty', () {
        const source = '''
       main() {
        List<int> numbers = [];
        return [numbers.isEmpty, numbers.isNotEmpty];
      }
      ''';
        expect(execute(source), equals([true, false]));
      });

      test('reverse', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.reversed.toList();
      }
      ''';
        expect(execute(source), equals([3, 2, 1]));
      });

      test('sort', () {
        const source = '''
       main() {
        List<int> numbers = [3, 1, 2];
        numbers.sort();
        return numbers;
      }
      ''';
        expect(execute(source), equals([1, 2, 3]));
      });

      test('shuffle', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        numbers.shuffle();
        return numbers; // Cannot check order, but check length and elements
      }
      ''';
        final result = execute(source) as List;
        expect(result, isA<List>());
        expect(result.length, equals(3));
        expect(result, containsAll([1, 2, 3]));
      });

      test('expand', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.expand((n) => [n, n * 2]).toList();
      }
      ''';
        expect(execute(source), equals([1, 2, 2, 4, 3, 6]));
      });

      test('forEach', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        var sum = 0;
        numbers.forEach((n) => sum += n);
        return sum;
      }
      ''';
        expect(execute(source), equals(6));
      });

      test('map', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.map((n) => n * 2).toList();
      }
      ''';
        expect(execute(source), equals([2, 4, 6]));
      });

      test('where', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3, 4];
        return numbers.where((n) => n % 2 == 0).toList();
      }
      ''';
        expect(execute(source), equals([2, 4]));
      });

      test('reduce', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.reduce((a, b) => a + b);
      }
      ''';
        expect(execute(source), equals(6));
      });

      test('fold', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.fold(0, (a, b) => a + b);
      }
      ''';
        expect(execute(source), equals(6));
      });

      test('join', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        return numbers.join(", ");
      }
      ''';
        expect(execute(source), equals('1, 2, 3'));
      });

      test('toSet', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 2, 3];
        return numbers.toSet().toList();
      }
      ''';
        final result = execute(source) as List;
        result.sort();
        expect(result, equals([1, 2, 3]));
      });

      test('toList', () {
        const source = '''
       main() {
        List<int> numbers = [1, 2, 3];
        var l = numbers.toList();
        l.add(4); // Modify to ensure it's a new list
        return [numbers, l]; // Return both to check independence
      }
      ''';
        expect(
            execute(source),
            equals([
              [1, 2, 3],
              [1, 2, 3, 4]
            ]));
      });
    });

    group('Iterable methods', () {
      test('cast', () {
        const source = '''
       main() {
        Iterable<dynamic> numbers = [1, 2, 3];
        Iterable<int> casted = numbers.cast<int>();
        return casted.toList();
      }
      ''';
        expect(execute(source), equals([1, 2, 3]));
      });

      test('followedBy', () {
        const source = '''
       main() {
        Iterable<int> numbers = [1, 2];
        Iterable<int> moreNumbers = numbers.followedBy([3, 4]);
        return moreNumbers.toList();
      }
      ''';
        expect(execute(source), equals([1, 2, 3, 4]));
      });

      test('elementAt', () {
        const source = '''
       main() {
        Iterable<int> numbers = [1, 2, 3];
        return numbers.elementAt(1);
      }
      ''';
        expect(execute(source), equals(2));
      });
    });

    group('Set methods', () {
      test('retainWhere', () {
        const source = '''
       main() {
        Set<int> numbers = {1, 2, 3, 4};
        numbers.retainWhere((n) => n % 2 == 0);
        return numbers.toList(); // Convert to list for stable comparison
      }
      ''';
        final result = execute(source) as List;
        result.sort();
        expect(result, equals([2, 4]));
      });

      test('removeWhere', () {
        const source = '''
       main() {
        Set<int> numbers = {1, 2, 3, 4};
        numbers.removeWhere((n) => n % 2 == 0);
        return numbers.toList(); // Convert to list for stable comparison
      }
      ''';
        final result = execute(source) as List;
        result.sort();
        expect(result, equals([1, 3]));
      });
    });
    test('typed literals and unmodifiable factories retain distinct types', () {
      final interpreter = D4rt();
      var hostSawReifiedList = false;
      interpreter.registertopLevelFunction('inspect',
          (visitor, args, named, types) {
        final value = args.single;
        hostSawReifiedList = value is List<String> &&
            value.runtimeType.toString().contains('String');
        return null;
      });
      final result = interpreter.execute(source: '''
        Object main() {
          final literal = <String>['a'];
          final immutable = List<String>.unmodifiable(literal);
          inspect(immutable);
          bool caught = false;
          try {
            immutable.add('b');
          } on UnsupportedError {
            caught = true;
          }
          return [
            literal.runtimeType.toString(),
            immutable is List<String>,
            caught,
            immutable.single
          ];
        }
      ''');
      expect(result, ['List<String>', true, true, 'a']);
      expect(hostSawReifiedList, isTrue);
    });

    test('host lists retain reification and mutability through invocation', () {
      const definitions = '''
        Object inspectList(List<String> values) {
          bool caught = false;
          try {
            values.add('forbidden');
          } on UnsupportedError {
            caught = true;
          }
          return [
            values is List<String>,
            values.runtimeType.toString(),
            caught,
            values.single
          ];
        }
        List<String> append(List<String> values) {
          values.add('new');
          return values;
        }
        class Probe {
          Object inspect(List<String> values) => inspectList(values);
          List<String> appendValue(List<String> values) => append(values);
        }
      ''';
      for (final instanceMethod in [true, false]) {
        final interpreter = D4rt();
        final entry = interpreter.execute(
          source: '$definitions main() => '
              '${instanceMethod ? 'Probe()' : 'inspectList'};',
        );
        final immutable = List<String>.unmodifiable(['original']);
        final observed = instanceMethod
            ? interpreter.invoke('inspect', [immutable])
            : interpreter.invokeInterpretedFunction(
                entry as InterpretedFunction, [immutable]);
        expect(observed,
            [true, immutable.runtimeType.toString(), true, 'original'],
            reason:
                'host immutable list through ${instanceMethod ? 'invoke' : 'invokeInterpretedFunction'}');
        expect(immutable, ['original']);
        expect(() => immutable.add('forbidden'), throwsUnsupportedError);

        final writable = <String>['original'];
        final appended = instanceMethod
            ? interpreter.invoke('appendValue', [writable])
            : interpreter.invokeInterpretedFunction(
                interpreter.execute(
                  source: '$definitions main() => append;',
                ) as InterpretedFunction,
                [writable],
              );
        expect(writable, ['original', 'new']);
        expect(appended, same(writable));
      }
    });

    test('nested collection views reach native JSON as ordinary lists and maps',
        () {
      const expected = {
        'nested': [
          [
            [3, null, 5],
            {
              'tags': ['red', 'blue'],
              'flags': [true, null]
            }
          ]
        ],
        'mutable': {
          'count': 2,
          'inside': [false, null]
        }
      };
      final interpreter = D4rt();
      interpreter.registertopLevelFunction('inspect',
          (visitor, args, named, types) {
        final value = args.single as Map;
        final nested = (value['nested'] as List).single as List;
        expect(nested, isA<UnmodifiableListView>());
        expect(nested[1], isA<UnmodifiableMapView>());
        expect(value['mutable'], isA<MapView>());
        expect(jsonDecode(jsonEncode(value)), expected);
        return value;
      });
      const script = '''
        import 'dart:collection';
        Object main() => inspect({
          'nested': [
            UnmodifiableListView([
              [3, null, 5],
              UnmodifiableMapView({
                'tags': ['red', 'blue'],
                'flags': [true, null]
              })
            ])
          ],
          'mutable': MapView({
            'count': 2,
            'inside': [false, null]
          })
        });
      ''';
      for (var call = 0; call < 2; call++) {
        final result = interpreter.execute(source: script) as Map;
        final nested = (result['nested'] as List).single as List;
        final view = nested[1] as Map;
        final mutable = result['mutable'] as Map;
        expect(nested, isA<UnmodifiableListView>());
        expect(view, isA<UnmodifiableMapView>());
        expect(mutable, isA<MapView>());
        expect(() => nested.add(null), throwsUnsupportedError);
        expect(() => view['extra'] = null, throwsUnsupportedError);
        expect(jsonDecode(jsonEncode(result)), expected);
        mutable['extra'] = 6;
        expect(mutable['extra'], 6);
      }
    });

    test('interpreted JSON encoder rejects cycles and recovers', () {
      final self = <Object?>[];
      self.add(self);
      final first = <String, Object?>{};
      final second = <String, Object?>{'next': first};
      first['next'] = second;
      final sources = <Object?>[
        self,
        first,
        {
          'ok': [1]
        }
      ];
      final interpreter = D4rt();
      var index = 0;
      var provided = 0;
      interpreter.registertopLevelFunction('provide',
          (visitor, args, named, types) {
        provided++;
        return sources[index];
      });
      const script = '''
        import 'dart:convert';
        Object main() => jsonEncode(provide());
      ''';
      for (; index < 2; index++) {
        // The interpreter wraps native codec errors as RuntimeError; the
        // identical entrypoint succeeds for the next acyclic graph.
        expect(() => interpreter.execute(source: script),
            throwsA(isA<RuntimeError>()));
        expect(provided, index + 1);
      }
      expect(interpreter.execute(source: script), '{"ok":[1]}');
      expect(provided, 3);
      expect(self.single, same(self));
      expect(second['next'], same(first));
    });

    test('nullable host list types survive both invocation boundaries', () {
      const definitions = '''
        Object inspect(List<int?> numbers, List<bool?> flags,
            List<double?> writable) {
          bool immutable = false;
          try {
            numbers.add(null);
          } on UnsupportedError {
            immutable = true;
          }
          writable.add(2.5);
          return [
            numbers is List<int?>,
            flags is List<bool?>,
            numbers[1] == null,
            flags[1] == null,
            immutable,
            numbers[0] + 2,
            writable is List<double?>,
            writable[1] == null,
            writable[2],
          ];
        }
        class Probe {
          Object check(List<int?> numbers, List<bool?> flags,
              List<double?> writable) =>
              inspect(numbers, flags, writable);
        }
      ''';
      final numbers = List<int?>.unmodifiable([3, null]);
      final flags = UnmodifiableListView<bool?>([true, null]);
      final writable = <double?>[1.5, null];
      for (final instanceMethod in [false, true]) {
        final interpreter = D4rt();
        final entry = interpreter.execute(
          source: '$definitions main() => '
              '${instanceMethod ? 'Probe()' : 'inspect'};',
        );
        final result = instanceMethod
            ? interpreter.invoke('check', [numbers, flags, writable])
            : interpreter.invokeInterpretedFunction(
                entry as InterpretedFunction, [numbers, flags, writable]);
        expect(result, [true, true, true, true, true, 5, true, true, 2.5]);
        expect(() => numbers.add(7), throwsUnsupportedError);
        expect(() => flags.add(false), throwsUnsupportedError);
        expect(writable, [1.5, null, 2.5]);
        writable.removeLast();
      }
    });

    test('host lists with bridged object elements keep their native type', () {
      final dates = <DateTime?>[DateTime.utc(2024), null];
      final interpreter = D4rt();
      final entry = interpreter.execute(source: '''
        Object inspect(Object source) {
          final values = source as List;
          return [values[0].year, values[1] == null, values];
        }
        Object main() => inspect;
      ''') as InterpretedFunction;
      final result =
          interpreter.invokeInterpretedFunction(entry, [dates]) as List;
      expect(result[0], 2024);
      expect(result[1], isTrue);
      expect(result[2], same(dates));
      expect(result[2], isA<List<DateTime?>>());
      dates.add(DateTime.utc(2025));
      expect(dates.length, 3);
    });

    test('host immutable core lists retain their elements and native types',
        () {
      final examples = <(String, List<Object?>)>[
        ('String', List<String>.unmodifiable(['a'])),
        ('int', List<int>.unmodifiable([1])),
        ('double', List<double>.unmodifiable([1.5])),
        ('num', List<num>.unmodifiable([1, 2.5])),
        ('bool', List<bool>.unmodifiable([true])),
        ('Object', List<Object>.unmodifiable(['a'])),
        ('Object?', List<Object?>.unmodifiable([null])),
        ('dynamic', List<dynamic>.unmodifiable([null])),
        ('Null', List<Null>.unmodifiable([null])),
        ('String?', List<String?>.unmodifiable([null])),
        ('int?', List<int?>.unmodifiable([null])),
        ('double?', List<double?>.unmodifiable([null])),
        ('num?', List<num?>.unmodifiable([null])),
        ('bool?', List<bool?>.unmodifiable([null])),
      ];
      for (final (type, values) in examples) {
        final interpreter = D4rt();
        final function = interpreter.execute(source: '''
          Object inspect(List<$type> values) {
            bool immutable = false;
            try {
              values.clear();
            } on UnsupportedError {
              immutable = true;
            }
            return [values is List<$type>, values.first, immutable, values];
          }
          Object main() => inspect;
        ''') as InterpretedFunction;
        final result =
            interpreter.invokeInterpretedFunction(function, [values]) as List;
        expect(result[0], isTrue, reason: type);
        expect(result[1], values.first, reason: type);
        expect(result[2], isTrue, reason: type);
        expect(result[3], same(values), reason: type);
        expect(() => values.clear(), throwsUnsupportedError, reason: type);
      }
    });

    test('interpreted nullable core factory has a reified immutable list', () {
      final interpreter = D4rt();
      List<int?>? observed;
      interpreter.registertopLevelFunction('inspect',
          (visitor, args, named, types) {
        observed = args.single as List<int?>;
        return null;
      });
      final result = interpreter.execute(source: '''
        Object main() {
          final values = List<int?>.unmodifiable(<int?>[1, null]);
          inspect(values);
          bool immutable = false;
          try {
            values.add(null);
          } on UnsupportedError {
            immutable = true;
          }
          return [values is List<int?>, values[1] == null, immutable];
        }
      ''');
      expect(result, [true, true, true]);
      expect(observed, [1, null]);
      expect(observed, isA<List<int?>>());
      expect(() => observed!.add(2), throwsUnsupportedError);
    });

    test('core immutable factories retain native element reification', () {
      final examples = <(String, String, bool Function(Object?))>[
        ('String', "['a']", (value) => value is List<String>),
        ('int', '[1]', (value) => value is List<int>),
        ('double', '[1.5]', (value) => value is List<double>),
        ('num', '[1, 2.5]', (value) => value is List<num>),
        ('bool', '[true]', (value) => value is List<bool>),
        ('Object', "['a', 1]", (value) => value is List<Object>),
        ('Object?', "['a', null]", (value) => value is List<Object?>),
        ('dynamic', '[1, null]', (value) => value is List<dynamic>),
        ('Null', '[null]', (value) => value is List<Null>),
        ('String?', "['a', null]", (value) => value is List<String?>),
        ('int?', '[1, null]', (value) => value is List<int?>),
        ('double?', '[1.5, null]', (value) => value is List<double?>),
        ('num?', '[1, 2.5, null]', (value) => value is List<num?>),
        ('bool?', '[true, null]', (value) => value is List<bool?>),
      ];
      for (final (type, contents, matches) in examples) {
        final interpreter = D4rt();
        Object? observed;
        interpreter.registertopLevelFunction('inspect',
            (visitor, args, named, types) {
          observed = args.single;
          return null;
        });
        final result = interpreter.execute(source: '''
          Object main() {
            final values = List<$type>.unmodifiable(<$type>$contents);
            inspect(values);
            return values;
          }
        ''');
        expect(matches(result), isTrue, reason: type);
        expect(observed, same(result), reason: type);
        expect(() => (result as List).clear(), throwsUnsupportedError,
            reason: type);
      }
    });

    test('unreifiable interpreted element types retain the factory error', () {
      final interpreter = D4rt();
      expect(() => interpreter.execute(source: '''
        class Custom {}
        Object main() => List<Custom>.unmodifiable([Custom()]);
      '''), throwsA(isA<RuntimeError>()));
    });

    test('typed unmodifiable factory rejects incompatible values', () {
      final interpreter = D4rt();
      expect(() => interpreter.execute(source: '''
            Object main() =>
                List<String>.unmodifiable(<Object?>['ok', 7]);
          '''), throwsA(isA<RuntimeError>()));
    });
  });
}
