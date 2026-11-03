import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

Object? _execute(String source, {List<Object?> args = const []}) =>
    D4rt().execute(source: source, positionalArgs: args);

void main() {
  group('Expression execution', () {
    test('compound locals retain the value read before RHS effects', () {
      expect(
        _execute('''
main() {
  var x = 1;
  var calls = 0;
  int change() { calls++; x = 10; return 2; }
  final result = x += change();
  int? present = 7;
  final retained = present ??= change();
  int? absent;
  final initialized = absent ??= change();
  return [result, x, retained, present, initialized, absent, calls];
}
'''),
        [3, 10, 7, 7, 2, 2, 2],
      );
      // Assert the compound result and final binding before any later mutation.
      expect(
        _execute('''
main() {
  var x = 1;
  int change() { x = 10; return 2; }
  final result = x += change();
  return [result, x];
}
'''),
        [3, 3],
      );
    });

    test('escaped block locals keep distinct iteration bindings', () {
      expect(
        _execute('''
main() {
  var callbacks = [];
  for (var i = 0; i < 3; i++) {
    final local = i;
    callbacks.add(() => local);
  }
  var result = '';
  for (final callback in callbacks) { result += callback().toString(); }
  return result;
}
'''),
        '012',
      );
    });

    test('patterns, local functions and shadowing keep lexical scopes', () {
      expect(
        _execute('''
main() {
  var value = 9;
  var callbacks = [];
  for (var i = 0; i < 3; i++) {
    var (value, other) = (i, 10);
    int read() => value + other;
    { final other = 100; callbacks.add(() => other); }
    callbacks.add(read);
    if ((i, 20) case (var matched, var offset) when matched >= 0) {
      callbacks.add(() => matched + offset);
    }
  }
  var result = [];
  for (final callback in callbacks) { result.add(callback()); }
  return [value, result];
}
'''),
        [
          9,
          [100, 10, 20, 100, 11, 21, 100, 12, 22],
        ],
      );
    });

    test(
      'binding-free branches preserve return, break, continue and finally',
      () {
        expect(
          _execute('''
int choose(bool flag) { if (flag) { return 7; } return 9; }
main() {
  var value = 1;
  var sum = 0;
  for (var i = 0; i < 6; i++) {
    if (i == 1) { continue; }
    if (i == 4) { break; }
    { ; assert(i >= 0); sum += i; }
  }
  var count = 0;
  while (count < 2) { count++; }
  do { count--; } while (count > 0);
  try { { final value = 10; throw value; } }
  catch (error) { sum += error as int; }
  finally { sum += value; }
  {}
  return [sum, count, value, choose(!false), choose(false)];
}
'''),
          [16, 0, 1, 7, 9],
        );
      },
    );

    test('numeric operations retain precision, overflow and mixed types', () {
      const large = 9007199254740993;
      const maximum = 9223372036854775807;
      expect(
        _execute(
          '''
main(num large, num maximum) => [
  large + 2, large - 2, large * 3,
  large > 9007199254740992, large >= 9007199254740993,
  large < 9007199254740994, large <= 9007199254740992,
  large == 9007199254740992, large != 9007199254740992,
  large == 9007199254740992.0, large != 9007199254740992.0,
  maximum + 1, -maximum - 1, -(-maximum - 1),
  5 + 0.5, 5 - 0.5, 5 * 0.5, 5 / 2, -5 % 3, -5 ~/ 2, ~5
];
''',
          args: [large, maximum],
        ),
        [
          large + 2,
          large - 2,
          large * 3,
          true,
          true,
          true,
          false,
          false,
          true,
          // Mixed numeric equality retains the existing runtime dispatch.
          true,
          false,
          maximum + 1,
          -maximum - 1,
          -(-maximum - 1),
          5.5,
          4.5,
          2.5,
          2.5,
          1,
          -2,
          -6,
        ],
      );
    });

    test('IEEE values retain NaN, infinity and signed zero behavior', () {
      final values =
          _execute(
                '''
main(num nan, num infinity, num zero) => [
  nan + 1, nan * 0, nan < 1, nan >= 1, nan == nan, nan != nan,
  infinity + 1, -infinity, 1 / zero, 0 / zero,
  -zero, zero * 2, zero / 2
];
''',
                args: [double.nan, double.infinity, -0.0],
              )
              as List;
      expect(values[0], isNaN);
      expect(values[1], isNaN);
      expect(values.sublist(2, 6), [false, false, false, true]);
      expect(values.sublist(6, 9), [
        double.infinity,
        double.negativeInfinity,
        double.negativeInfinity,
      ]);
      expect(values[9], isNaN);
      expect((values[10] as double).isNegative, isFalse);
      expect((values[11] as double).isNegative, isTrue);
      expect((values[12] as double).isNegative, isTrue);
    });

    for (final divisor in [0, 0.0, -0.0]) {
      for (final operator in ['%', '~/']) {
        test('$operator rejects zero divisor $divisor after operand effects', () {
          final events = <String>[];
          final runtime = D4rt()
            ..registertopLevelFunction('mark', (v, args, named, types) {
              events.add(args[0] as String);
              return args[1];
            });
          expect(
            () => runtime.execute(
              source:
                  "main(num divisor) => mark('left', 5) $operator mark('right', divisor);",
              positionalArgs: [divisor],
            ),
            throwsA(
              isA<RuntimeError>().having(
                (error) => error.message,
                'message',
                operator == '%'
                    ? 'Modulo par zéro.'
                    : 'Division entière par zéro.',
              ),
            ),
          );
          expect(events, ['left', 'right']);
        });
      }
    }

    test('non-finite truncating division and invalid shifts still fail', () {
      for (final source in [
        'main(num x) => x ~/ 1;',
        'main(num x) => 1 ~/ x;',
      ]) {
        expect(
          () => _execute(source, args: [double.nan]),
          throwsA(
            isA<RuntimeError>().having(
              (error) => error.message,
              'message',
              contains('Infinity or NaN'),
            ),
          ),
        );
      }
      for (final operator in ['<<', '>>', '>>>']) {
        expect(
          () => _execute('main(int shift) => 1 $operator shift;', args: [-1]),
          throwsA(anyOf(isA<RuntimeError>(), isA<ArgumentError>())),
        );
      }
    });

    test('native, class, extension and enum fallbacks remain usable', () {
      expect(
        _execute('''
class Value {
  final int value;
  Value(this.value);
  Value operator +(Value other) => Value(value + other.value);
  Value operator -() => Value(-value);
  Value operator ~() => Value(~value);
}
class Offset { final int value; Offset(this.value); }
extension OffsetOps on Offset {
  int operator +(int other) => value + other;
}
enum Flag { one, two }
main() {
  final big = BigInt.parse('9007199254740993');
  final a = Value(5);
  return [
    (big + BigInt.one).toString(), (-big).toString(),
    (Duration(seconds: 3) + Duration(seconds: 2)).inSeconds,
    (Duration(seconds: 3) * 2).inSeconds,
    (a + Value(2)).value, (-a).value, (~a).value,
    Offset(4) + 3, Flag.one == Flag.one, Flag.one != Flag.two,
    'a' + 'b', 5 | 2, 5 & 3, 5 ^ 3, 8 >> 1, 1 << 3, 8 >>> 1
  ];
}
'''),
        [
          '9007199254740994',
          '-9007199254740993',
          5,
          6,
          7,
          -5,
          -6,
          7,
          true,
          true,
          'ab',
          7,
          1,
          6,
          4,
          8,
          4,
        ],
      );
    });

    test('primitive equality retains early extension authority', () {
      expect(
        _execute('''
var events = [];
extension IntEquality on int {
  bool operator ==(Object other) { events.add('int'); return false; }
}
extension BoolEquality on bool {
  bool operator ==(Object other) { events.add('bool'); return false; }
}
extension StringEquality on String {
  bool operator ==(Object other) { events.add('string'); return false; }
}
main() {
  final result = [1 == 1, true == true, 'a' == 'a'];
  return [result, events];
}
'''),
        [
          [false, false, false],
          ['int', 'bool', 'string'],
        ],
      );
    });

    test('primitive concat, bitwise and shifts retain bridge authority', () {
      final calls = <String>[];
      final runtime = D4rt();
      runtime.registerBridgedClass(
        BridgedClass(
          nativeType: int,
          name: 'NumberOps',
          methods: {
            '|': (v, target, args, named) {
              calls.add('or');
              return 40;
            },
            '<<': (v, target, args, named) {
              calls.add('shift');
              return 50;
            },
            '+': (v, target, args, named) {
              calls.add('add');
              return 60;
            },
          },
        ),
        'package:synthetic/operators.dart',
      );
      runtime.registerBridgedClass(
        BridgedClass(
          nativeType: String,
          name: 'TextOps',
          methods: {
            '+': (v, target, args, named) {
              calls.add('concat');
              return 'adapted';
            },
          },
        ),
        'package:synthetic/operators.dart',
      );
      expect(
        runtime.execute(
          source: '''
import 'package:synthetic/operators.dart';
main() => [1 | 2, 1 << 2, 'a' + 'b', 1 + 2];
''',
        ),
        [40, 50, 'adapted', 3],
      );
      expect(calls, ['or', 'shift', 'concat']);
    });

    test('wrapped boolean conditions and unary operands still unwrap', () {
      final boolean = BridgedClass(nativeType: bool, name: 'WrappedBool');
      final number = BridgedClass(nativeType: int, name: 'WrappedNumber');
      expect(
        _execute(
          '''
main(dynamic condition, dynamic number) {
  var result = 0;
  if (condition) { result++; }
  while (condition) { result++; break; }
  do { result++; } while (!condition);
  for (; condition;) { result++; break; }
  assert(condition);
  return [result, condition ? 7 : 9, !condition, -number, ~number];
}
''',
          args: [BridgedInstance(boolean, true), BridgedInstance(number, 5)],
        ),
        [4, 7, false, -5, -6],
      );
    });

    for (final expression in ['!1', "-'text'", '~1.5', '1 ? 2 : 3']) {
      test('invalid primitive operand remains an error: $expression', () {
        expect(
          () => _execute('main() => $expression;'),
          throwsA(isA<RuntimeError>()),
        );
      });
    }
  });
}
