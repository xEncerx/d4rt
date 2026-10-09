import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('invokeInterpretedFunction tests', () {
    late D4rt d4rt;

    setUp(() {
      d4rt = D4rt();
    });

    test('Constant function', () {
      final source = """
        main() => () => 5;
        """;
      final InterpretedFunction fn = d4rt.execute(source: source);
      final result = d4rt.invokeInterpretedFunction(fn, []);

      expect(result, equals(5));
    });

    test('One argument function', () {
      final source = """
        main() => (int p) => p+5;
        """;
      final InterpretedFunction fn = d4rt.execute(source: source);
      final result = d4rt.invokeInterpretedFunction(fn, [3]);

      expect(result, equals(8));
    });

    test('Constant closure', () {
      final source = """
        final a = 3;
        main() => (int p) => a+p;
        """;
      final InterpretedFunction fn = d4rt.execute(source: source);
      final result = d4rt.invokeInterpretedFunction(fn, [3]);

      expect(result, equals(6));
    });

    test('Side effect', () {
      final source = """
        int a = 3;
        main() => (int p){
          int ret = a;
          a = p;
          return ret;
        };
        """;
      final InterpretedFunction fn = d4rt.execute(source: source);
      d4rt.invokeInterpretedFunction(fn, [2]);
      final result = d4rt.invokeInterpretedFunction(fn, [3]);

      expect(result, equals(2));
    });

    test('Function that returns a function', () {
      final source = """
        int a = 3;
        main() => () => (int p){
          int ret = a;
          a = p;
          return ret;
        };
        """;
      final InterpretedFunction fn1 = d4rt.execute(source: source);
      final InterpretedFunction fn2 = d4rt.invokeInterpretedFunction(fn1, []);
      final result1 = d4rt.invokeInterpretedFunction(fn2, [4]);
      expect(result1, equals(3));
      final result2 = d4rt.invokeInterpretedFunction(fn2, [5]);
      expect(result2, equals(4));
    });

    test('Function generator', () {
      final source = """
        Iterable<int> range(int start, int end) sync* {
          for (var i = start; i < end; i++) {
            yield i;
          }
        }
          
        main() => range;
        """;
      final InterpretedFunction gen = d4rt.execute(source: source);
      final iterable = d4rt.invokeInterpretedFunction(gen, [0, 3]);
      final list = iterable.toList();
      expect(list, equals([0, 1, 2]));
    });

    test('explicit generator host consumption shares a terminal step budget',
        () {
      var effects = 0;
      d4rt.registertopLevelFunction('touch', (visitor, args, named, types) {
        effects++;
        return 1;
      });
      final iterable = d4rt.execute(
          source:
              'Iterable<int> work() sync* {var n=0;while(n<1000){n++;}touch();yield n;}',
          name: 'work',
          maxSteps: 100) as Iterable;
      expect(() => iterable.toList(), throwsA(isA<ExecutionLimitException>()));
      expect(() => iterable.toList(), throwsA(isA<ExecutionLimitException>()));
      expect(effects, 0,
          reason: 'host retries cannot renew the explicit budget');
    });

    test('active generator consumption supersedes expired explicit entry',
        () async {
      var effects = 0;
      d4rt.registertopLevelFunction('touch', (visitor, args, named, types) {
        effects++;
        return 1;
      });
      final iterable = d4rt.execute(
          source: 'Iterable<int> work() sync* {touch();yield 7;}',
          name: 'work',
          timeout: const Duration(milliseconds: 50)) as Iterable;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
          () => iterable.toList(), throwsA(isA<ExecutionTimeoutException>()));
      expect(effects, 0);
      d4rt.registertopLevelFunction(
          'retained', (visitor, args, named, types) => iterable);
      expect(
          d4rt.execute(
              source: 'main()=>retained().toList();',
              timeout: const Duration(seconds: 1)),
          [7]);
      expect(effects, 1);
    });

    test('explicit Callable generator entry permits bounded host consumption',
        () {
      d4rt.registertopLevelFunction(
          'explicit',
          (visitor, args, named, types) =>
              Zone.root.run(() => (args.single as Callable).call(visitor, [])));
      final iterable = d4rt.execute(
              source:
                  'Iterable<int> work() sync* {yield 1;yield 2;}main()=>explicit(work);')
          as Iterable;
      expect(iterable.toList(), [1, 2]);
    });

    test('explicit async generator deadline terminates host continuation',
        () async {
      var effects = 0;
      d4rt.registertopLevelFunction('touch', (visitor, args, named, types) {
        effects++;
        return 1;
      });
      final stream = d4rt.execute(
          source:
              'Stream<int> work() async* {yield 1;await Future.delayed(Duration(milliseconds:80));touch();yield 2;}',
          name: 'work',
          timeout: const Duration(milliseconds: 50)) as Stream;
      await expectLater(stream.toList().timeout(const Duration(seconds: 2)),
          throwsA(isA<ExecutionTimeoutException>()));
      expect(effects, 0);
    });

    test('Function that receives a function', () {
      final source = """
      double squared(double x) => x * x;

      T applyTwice<T>(T arg, T Function(T) fn) => fn(fn(arg));

      main() => (squared,applyTwice);
      """;
      final InterpretedRecord tuple = d4rt.execute(source: source);
      final InterpretedFunction squared =
          tuple.positionalFields[0] as InterpretedFunction;
      final InterpretedFunction applyTwice =
          tuple.positionalFields[1] as InterpretedFunction;

      final result = d4rt.invokeInterpretedFunction(applyTwice, [2, squared]);

      expect(result, equals(16));
    });

    test('Function that receives a function', () {
      final source = """
      double squared(double x) => x * x;

      T applyTwice<T>(T arg, T Function(T) fn) => fn(fn(arg));

      main() => (squared,applyTwice);
      """;
      final InterpretedRecord tuple = d4rt.execute(source: source);
      final InterpretedFunction squared =
          tuple.positionalFields[0] as InterpretedFunction;
      final InterpretedFunction applyTwice =
          tuple.positionalFields[1] as InterpretedFunction;

      final result = d4rt.invokeInterpretedFunction(applyTwice, [2, squared]);

      expect(result, equals(16));
    });

    test('Function that receives host function', () {
      double squared(double x) => x * x;

      final source = """
      T applyTwice<T>(T arg, T Function(T) fn) => fn(fn(arg));

      main() => applyTwice;
      """;
      final InterpretedFunction applyTwice = d4rt.execute(source: source);

      final result = d4rt.invokeInterpretedFunction(applyTwice, [2, squared]);
      // result is squared function itself, not as expected
      // it seems that it is not possible to extract information about the raw dart function (arity, type of parameters...)
      // TODO: maybe delete this test, meanwhile is left here as sort of documentation of this limitation

      expect(result, equals(16));
    }, skip: true);

    test('Function that receives a complex type', () {
      final source = """
      String joinAList(List arg) => arg.join();

      main() => joinAList;
      """;
      final InterpretedFunction joinAList = d4rt.execute(source: source);
      final list = [1, 2, "join me"];
      final result = d4rt.invokeInterpretedFunction(joinAList, [list]);
      expect(result, equals(list.join()));
    });

    test('Strong interpreted function integration documentation example', () {
      T Function(A) bindFunction1<T, A>(D4rt d, InterpretedFunction fn) {
        return (A a) => d.invokeInterpretedFunction(fn, [a]);
      }

      final source = """
        String joinAList(List arg) => arg.join();

        main() => joinAList;
      """;

      final InterpretedFunction interpretedFn = d4rt.execute(source: source);
      final hostFN = bindFunction1(d4rt, interpretedFn);
      final list = [1, 2, "join me"];

      expect(list.join(), hostFN(list));
    });
  });
}
