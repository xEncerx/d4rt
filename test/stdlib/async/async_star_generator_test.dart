import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';
import '../../interpreter_test.dart';

void main() {
  group('Async* Generator Tests', () {
    test('Basic async* generator with yield', () async {
      const code = '''
        Stream<int> countAsync() async* {
          yield 1;
          yield 2;
          yield 3;
        }
        
        Future<List<int>> main() async {
          List<int> results = [];
          await for (var value in countAsync()) {
            results.add(value);
          }
          return results;
        }
      ''';

      final result = await execute(code);
      expect(result, equals([1, 2, 3]));
    });

    test('Async* generator with async operations between yields', () async {
      const code = '''
        Stream<int> delayedCount() async* {
          for (int i = 1; i <= 3; i++) {
            await Future.delayed(Duration(milliseconds: 1));
            yield i;
          }
        }
        
        Future<List<int>> main() async {
          List<int> results = [];
          await for (var value in delayedCount()) {
            results.add(value);
          }
          return results;
        }
      ''';

      final result = await execute(code);
      expect(result, equals([1, 2, 3]));
    });

    test('Async* generator with yield*', () async {
      const code = '''
        Stream<int> baseStream() async* {
          yield 1;
          yield 2;
        }
        
        Stream<int> extendedStream() async* {
          yield 0;
          yield* baseStream();
          yield 3;
        }
        
        Future<List<int>> main() async {
          List<int> results = [];
          await for (var value in extendedStream()) {
            results.add(value);
          }
          return results;
        }
      ''';

      final result = await execute(code);
      expect(result, equals([0, 1, 2, 3]));
    });

    test('Async* generator with early return', () async {
      const code = '''
        Stream<int> conditionalGenerator(bool shouldContinue) async* {
          yield 1;
          if (!shouldContinue) return;
          yield 2;
          yield 3;
        }
        
        Future<List<int>> main() async {
          List<int> results1 = [];
          await for (var value in conditionalGenerator(false)) {
            results1.add(value);
          }
          
          List<int> results2 = [];
          await for (var value in conditionalGenerator(true)) {
            results2.add(value);
          }
          
          return [results1, results2];
        }
      ''';

      final result = await execute(code);
      expect(
        result,
        equals([
          [1],
          [1, 2, 3],
        ]),
      );
    });

    test('Async* generator with exception handling', () async {
      const code = '''
        Stream<int> errorGenerator() async* {
          yield 1;
          throw Exception('Test error');
          yield 2; // Should not be reached
        }
        
        Future<String> main() async {
          try {
            await for (var value in errorGenerator()) {
              // First value should be received
              if (value == 1) continue;
            }
            return 'No error';
          } catch (e) {
            return 'Caught: \${e.toString()}';
          }
        }
      ''';

      final result = await execute(code);
      expect(result, contains('Caught:'));
      expect(result, contains('Test error'));
    });

    test('Nested async* generators', () async {
      const code = '''
        Stream<int> innerGenerator(int start, int count) async* {
          for (int i = 0; i < count; i++) {
            yield start + i;
          }
        }
        
        Stream<int> outerGenerator() async* {
          yield* innerGenerator(1, 2);
          yield* innerGenerator(10, 2);
        }
        
        Future<List<int>> main() async {
          List<int> results = [];
          await for (var value in outerGenerator()) {
            results.add(value);
          }
          return results;
        }
      ''';

      final result = await execute(code);
      expect(result, equals([1, 2, 10, 11]));
    });

    test('Async* generator with complex control flow', () async {
      const code = '''
        Stream<int> complexGenerator() async* {
          for (int i = 1; i <= 5; i++) {
            if (i % 2 == 0) {
              yield i * 2;
            } else {
              yield i;
            }
            
            if (i == 3) {
              await Future.delayed(Duration(milliseconds: 1));
            }
          }
        }
        
        Future<List<int>> main() async {
          List<int> results = [];
          await for (var value in complexGenerator()) {
            results.add(value);
          }
          return results;
        }
      ''';

      final result = await execute(code);
      expect(result, equals([1, 4, 3, 8, 5]));
    });

    test('Multiple async* generators running concurrently', () async {
      const code = '''
        Stream<String> generator1() async* {
          for (int i = 1; i <= 3; i++) {
            await Future.delayed(Duration(milliseconds: 1));
            yield 'A\$i';
          }
        }
        
        Stream<String> generator2() async* {
          for (int i = 1; i <= 3; i++) {
            await Future.delayed(Duration(milliseconds: 1));
            yield 'B\$i';
          }
        }
        
        Future<List<String>> main() async {
          List<String> results1 = [];
          List<String> results2 = [];
          
          // Run generators concurrently
          await Future.wait([
            () async {
              await for (var value in generator1()) {
                results1.add(value);
              }
            }(),
            () async {
              await for (var value in generator2()) {
                results2.add(value);
              }
            }()
          ]);
          
          return [results1, results2];
        }
      ''';

      final result = await execute(code);
      expect(
        result,
        equals([
          ['A1', 'A2', 'A3'],
          ['B1', 'B2', 'B3'],
        ]),
      );
    });

    test('await-for scopes shadow and reuse existing variables', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          var value = 90;
          final seen = <int>[];
          await for (var value in Stream<int>.fromIterable([1, 2])) {
            await Future.value();
            seen.add(value);
          }
          seen.add(value);
          await for (value in Stream<int>.empty()) { seen.add(value); }
          await for (value in Stream<int>.fromIterable([3, 4])) {
            seen.add(value);
          }
          seen.add(value);
          return seen;
        }
      ''';
      expect(await execute(code), [1, 2, 90, 3, 4, 4]);
    });

    test('nested await-for loops retain their owning lexical scopes', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          final seen = <String>[];
          for (var value in [1, 2]) {
            await for (var value in Stream<int>.fromIterable([3, 4])) {
              await Future.value();
              seen.add('inner:\$value');
            }
            seen.add('outer:\$value');
          }
          return seen;
        }
      ''';
      expect(await execute(code), [
        'inner:3',
        'inner:4',
        'outer:1',
        'inner:3',
        'inner:4',
        'outer:2',
      ]);
    });

    test('nested await-for loops restore each outer variable', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          final seen = <int>[];
          await for (var outer in Stream<int>.fromIterable([1, 2])) {
            await for (var inner in Stream<int>.fromIterable([3, 4])) {
              await Future.value();
              seen.add(outer * 10 + inner);
            }
            seen.add(outer);
          }
          return seen;
        }
      ''';
      expect(await execute(code), [13, 14, 1, 23, 24, 2]);
    });

    test('await-for break and continue leave reusable loop state', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          final seen = <int>[];
          for (var round in [1, 2]) {
            await for (var value in Stream<int>.fromIterable([1, 2, 3])) {
              await Future.value();
              if (value == 1) continue;
              seen.add(round * 10 + value);
              break;
            }
          }
          return seen;
        }
      ''';
      expect(await execute(code), [12, 22]);
    });

    test('await-for body error unwinds only the exited loop', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          var value = 9;
          final seen = <int>[];
          try {
            await for (var value in Stream<int>.fromIterable([1, 2])) {
              seen.add(value);
              if (value == 2) throw 'failure';
            }
          } catch (_) {
            seen.add(value);
          }
          await for (var value in Stream<int>.fromIterable([3])) {
            seen.add(value);
          }
          return seen;
        }
      ''';
      expect(await execute(code), [1, 2, 9, 3]);
    });

    test(
      'awaited body error preserves only scopes containing the catch',
      () async {
        const code = '''
        import 'dart:async';
        Future<List> main() async {
          var value = 9;
          final seen = <int>[];
          await for (var value in Stream<int>.fromIterable([1])) {
            try {
              await Future.error('inner');
            } catch (_) {
              seen.add(value);
            }
          }
          try {
            await for (var value in Stream<int>.fromIterable([2])) {
              await Future.error('outer');
            }
          } catch (_) {
            seen.add(value);
          }
          return seen;
        }
      ''';
        expect(await execute(code), [1, 9]);
      },
    );

    test('awaited error unwinds nested ordinary and await-for loops', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          var value = 9;
          final seen = <int>[];
          try {
            await for (var value in Stream<int>.fromIterable([1])) {
              for (var value = 2; value < 4; value++) {
                await Future.error('failure');
              }
            }
          } catch (_) {
            seen.add(value);
          }
          for (var value = 4; value < 6; value++) {
            seen.add(value);
          }
          await for (var value in Stream<int>.fromIterable([6])) {
            seen.add(value);
          }
          seen.add(value);
          return seen;
        }
      ''';
      expect(await execute(code), [9, 4, 5, 6, 9]);
    });

    test(
      'return unwinds nested ordinary and await-for loops before finally',
      () async {
        const code = '''
        import 'dart:async';
        Future<int> work(List<int> seen) async {
          var value = 9;
          try {
            await for (var value in Stream<int>.fromIterable([1])) {
              for (var value in [2]) {
                await Future.value();
                return value;
              }
            }
          } finally {
            seen.add(value);
          }
          return 0;
        }
        Future<List> main() async {
          final seen = <int>[];
          final result = await work(seen);
          for (var value in [3, 4]) { seen.add(value); }
          return [result, seen];
        }
      ''';
        expect(await execute(code), [
          2,
          [9, 3, 4],
        ]);
      },
    );

    test('return from await-for restores outer scope in finally', () async {
      const code = '''
        import 'dart:async';
        Future<int> work(List<int> seen) async {
          var value = 9;
          try {
            await for (var value in Stream<int>.fromIterable([1, 2])) {
              return value;
            }
          } finally {
            seen.add(value);
          }
          return 0;
        }
        Future<List> main() async {
          final seen = <int>[];
          final result = await work(seen);
          return [result, seen];
        }
      ''';
      expect(await execute(code), [
        1,
        [9],
      ]);
    });

    test('return unwinds scopes between nested finalizers', () async {
      const code = '''
        import 'dart:async';
        Future<int> work(List<int> seen) async {
          var value = 9;
          try {
            await for (var value in Stream<int>.fromIterable([1])) {
              try {
                return value;
              } finally {
                seen.add(value);
              }
            }
          } finally {
            seen.add(value);
          }
          return 0;
        }
        Future<List> main() async {
          final seen = <int>[];
          final result = await work(seen);
          return [result, seen];
        }
      ''';
      expect(await execute(code), [
        1,
        [1, 9],
      ]);
    });

    test('awaited errors unwind scopes between nested finalizers', () async {
      const code = '''
        import 'dart:async';
        Future<List> main() async {
          var value = 9;
          final seen = <int>[];
          try {
            try {
              await for (var value in Stream<int>.fromIterable([1])) {
                try {
                  await Future.error('failure');
                } finally {
                  seen.add(value);
                }
              }
            } finally {
              seen.add(value);
            }
          } catch (_) {
            seen.add(value);
          }
          return seen;
        }
      ''';
      expect(await execute(code), [1, 9, 9]);
    });

    test('cancellation unwinds scopes between nested finalizers', () async {
      final entered = Completer<void>();
      final gate = Completer<void>();
      final seen = <int>[];
      final interpreter = D4rt()
        ..registertopLevelFunction('waitGate', (visitor, args, named, types) {
          entered.complete();
          return gate.future;
        })
        ..registertopLevelFunction('mark', (visitor, args, named, types) {
          seen.add(args.single as int);
          return null;
        });
      final stream =
          interpreter.execute(
                source: '''
        import 'dart:async';
        Stream<int> main() async* {
          var value = 9;
          try {
            await for (var value in Stream<int>.fromIterable([1])) {
              try {
                await waitGate();
                yield value;
              } finally {
                mark(value);
              }
            }
          } finally {
            mark(value);
          }
        }
      ''',
              )
              as Stream;
      final subscription = stream.listen((_) {});
      await entered.future;
      await subscription.cancel();
      expect(seen, [1, 9]);
      gate.complete();
      await gate.future;
      await Future<void>.value();
      expect(seen, [1, 9]);
    });

    test(
      'failed await-for conversion releases scope before catch and reuse',
      () async {
        const code = '''
        import 'dart:async';
        Future<List> main() async {
          var value = 7;
          final seen = <int>[];
          try {
            await for (var value in Stream<int>.error('failure')) {
              seen.add(value);
            }
          } catch (_) {
            seen.add(value);
          } finally {
            seen.add(value + 1);
          }
          await for (var value in Stream<int>.fromIterable([2])) {
            seen.add(value);
          }
          seen.add(value);
          return seen;
        }
      ''';
        expect(await execute(code), [7, 8, 2, 7]);
      },
    );

    test('Async* generator yielding complex objects', () async {
      const code = '''
        Stream<Map<String, dynamic>> dataGenerator() async* {
          yield {'id': 1, 'name': 'First'};
          await Future.delayed(Duration(milliseconds: 1));
          yield {'id': 2, 'name': 'Second'};
          yield {'id': 3, 'name': 'Third'};
        }
        
        Future<List<Map<String, dynamic>>> main() async {
          List<Map<String, dynamic>> results = [];
          await for (var data in dataGenerator()) {
            results.add(data);
          }
          return results;
        }
      ''';

      final result = await execute(code);
      expect(
        result,
        equals([
          {'id': 1, 'name': 'First'},
          {'id': 2, 'name': 'Second'},
          {'id': 3, 'name': 'Third'},
        ]),
      );
    });
  });
}
