import 'dart:math' as math;

import '../../interpreter_test.dart';
import 'package:test/test.dart';

void main() {
  group('RandomCore tests', () {
    test('Random.nextInt', () {
      const source = '''
      import 'dart:math';
      main() {
        Random random = Random(42);
        return [random.nextInt(100), random.nextInt(100), random.nextInt(100)];
      }
      ''';
      final random = math.Random(42);
      expect(execute(source), [
        random.nextInt(100),
        random.nextInt(100),
        random.nextInt(100),
      ]);
    });

    test('Random.nextDouble', () {
      const source = '''
      import 'dart:math';
      main() {
        Random random = Random(42);
        return [random.nextDouble(), random.nextDouble(), random.nextDouble()];
      }
      ''';
      final random = math.Random(42);
      expect(execute(source), [
        random.nextDouble(),
        random.nextDouble(),
        random.nextDouble(),
      ]);
    });

    test('Random.nextBool', () {
      const source = '''
      import 'dart:math';
      main() {
        Random random = Random(42);
        return [random.nextBool(), random.nextBool(), random.nextBool()];
      }
      ''';
      final random = math.Random(42);
      expect(execute(source), [
        random.nextBool(),
        random.nextBool(),
        random.nextBool(),
      ]);
    });
  });
}
