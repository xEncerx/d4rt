import 'package:test/test.dart';
import 'package:d4rt/d4rt.dart';

dynamic execute(String source, {List<Object?>? args}) {
  final d4rt = D4rt()..setDebug(false);
  return d4rt.execute(
      library: 'package:test/main.dart',
      positionalArgs: args,
      sources: {'package:test/main.dart': source});
}

void main() {
  group('Improved Generics Validation', () {
    test('Generic class constraint validation', () {
      final validCode = '''
        class NumericContainer<T extends num> {
          T value;
          NumericContainer(this.value);
          
          T getValue() => value;
        }
        
        main() {
          var intContainer = NumericContainer<int>(42);
          return intContainer.getValue();
        }
      ''';

      expect(execute(validCode), equals(42));

      final invalidCode = '''
        class NumericContainer<T extends num> {
          T value;
          NumericContainer(this.value);
          
          T getValue() => value;
        }
        
        main() {
          var stringContainer = NumericContainer<String>("hello");
          return stringContainer.getValue();
        }
      ''';

      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('does not satisfy bound'),
        )),
      );
    });

    test('Generic function constraint validation', () {
      final validCode = '''
        T addOne<T extends num>(T value) {
          return value + 1;
        }
        
        main() {
          return addOne<int>(5);
        }
      ''';

      expect(execute(validCode), equals(6));

      final invalidCode = '''
        T addOne<T extends num>(T value) {
          return value + 1;
        }
        
        main() {
          return addOne<String>("hello");
        }
      ''';

      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('does not satisfy bound'),
        )),
      );
    });

    test('Multiple type parameters with bounds', () {
      final validCode = '''
        class Pair<T extends num, U extends String> {
          T first;
          U second;
          Pair(this.first, this.second);
        }
        
        main() {
          var validPair = Pair<double, String>(42, "test");
          return true;
        }
      ''';

      expect(execute(validCode), isTrue);

      final invalidCode = '''
        class Pair<T extends num, U extends String> {
          T first;
          U second;
          Pair(this.first, this.second);
        }
        
        main() {
          var invalidPair = Pair<bool, String>(true, "test");
          return true;
        }
      ''';

      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('does not satisfy bound'),
        )),
      );
    });

    test('Nested generics constraint validation', () {
      final validCode = '''
        class Container<T extends num> {
          List<T> items = [];
        }
        
        main() {
          var container = Container<int>();
          return true;
        }
      ''';

      expect(execute(validCode), isTrue);

      final invalidCode = '''
        class Container<T extends num> {
          List<T> items = [];
        }
        
        main() {
          var container = Container<String>();
          return true;
        }
      ''';

      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains('does not satisfy bound'),
        )),
      );
    });

    test('Applied generic runtime type is preserved for user-defined classes',
        () {
      final code = '''
        class Box<T> {
          T value;
          Box(this.value);
        }

        main() {
          var box = Box<int>(42);
          return [box is Box<int>, box is Box<num>, box is Box<String>];
        }
      ''';

      expect(execute(code), equals([true, true, false]));
    });

    test('Generic return type validation uses applied runtime types', () {
      final validCode = '''
        class Box<T> {
          T value;
          Box(this.value);
        }

        Box<int> makeBox() {
          return Box<int>(42);
        }

        main() {
          return makeBox() is Box<int>;
        }
      ''';

      expect(execute(validCode), isTrue);

      final invalidCode = '''
        class Box<T> {
          T value;
          Box(this.value);
        }

        Box<String> makeBox() {
          return Box<int>(42);
        }

        main() {
          return makeBox();
        }
      ''';

      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("can't be returned"),
        )),
      );
    });

    test('Typed native collection returns preserve applied runtime types', () {
      final validCode = '''
        List<int> numbers() {
          return [1, 2, 3];
        }

        Map<String, int> scores() {
          return {'a': 1, 'b': 2};
        }

        main() {
          return [numbers() is List<int>, scores() is Map<String, int>];
        }
      ''';

      expect(execute(validCode), equals([true, true]));

      final invalidCode = '''
        List<String> numbers() {
          return [1, 2, 3];
        }

        main() {
          return numbers();
        }
      ''';

      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          contains("can't be returned"),
        )),
      );
    });

    test(
        'Inferred generic list returns stay scoped through initializers and nested calls',
        () {
      final code = '''
        enum Kind { first, second }

        List<T> echo<T>(List<T> values) {
          return values;
        }

        List<T> forward<T>(List<T> values) {
          return echo<T>(values);
        }

        class Holder {
          Holder(List<Kind> input)
              : direct = echo(input),
                nested = forward(input);

          final List<Kind> direct;
          final List<Kind> nested;
        }

        main() {
          final holder = Holder(<Kind>[Kind.first, Kind.second]);
          final numbers = echo(<int>[7]);
          final labels = forward(<String>['label']);
          final again = Holder(<Kind>[Kind.second]);
          return [
            echo(<Kind>[Kind.first])[0] == Kind.first,
            holder.direct[1] == Kind.second,
            forward(<Kind>[Kind.second])[0] == Kind.second,
            holder.nested[0] == Kind.first,
            numbers is List<int>,
            numbers[0] == 7,
            labels is List<String>,
            labels[0] == 'label',
            holder.direct[0] == Kind.first,
            again.nested[0] == Kind.second,
          ];
        }
      ''';

      expect(execute(code), equals(List<bool>.filled(10, true)));
    });

    test(
        'Incompatible inferred generic list return is rejected inside nested initializer',
        () {
      final code = '''
        enum Kind { first }

        List<T> malformed<T>(List<T> values) {
          return <int>[7];
        }

        List<T> forward<T>(List<T> values) {
          return malformed<T>(values);
        }

        class Holder {
          Holder(List<Kind> input) : values = forward(input);
          final List<Kind> values;
        }

        main() => Holder(<Kind>[Kind.first]).values;
      ''';

      expect(
        () => execute(code),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          allOf(contains("can't be returned"), contains("malformed")),
        )),
      );
    });

    test('Inferred generic list type respects its declared numeric bound', () {
      final code = '''
        List<T> malformed<T extends num>(List<T> values) {
          return <String>['bad'];
        }

        main() => malformed(<String>['input']);
      ''';

      expect(
        () => execute(code),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          allOf(contains('String'), contains('does not satisfy bound')),
        )),
      );
    });

    test('Repeated inferred list parameters retain a common numeric type', () {
      final code = '''
        List<T> first<T>(List<T> a, List<T> b) {
          return a;
        }

        main() {
          final broadFirst = first(<num>[1.5], <int>[2]);
          final narrowFirst = first(<int>[2], <num>[1.5]);
          final mixedNumbers = first(<int>[2], <double>[1.5]);
          return [
            broadFirst[0] == 1.5,
            narrowFirst[0] == 2,
            mixedNumbers[0] == 2,
          ];
        }
      ''';

      expect(execute(code), equals([true, true, true]));
    });

    test(
        'Explicit generic list returns are checked against their type argument',
        () {
      final validCode = '''
        List<T> echo<T>(List<T> values) {
          return values;
        }

        main() {
          final ints = echo<int>(<int>[7]);
          final strings = echo<String>(<String>['label']);
          return [ints[0] == 7, strings[0] == 'label'];
        }
      ''';
      expect(execute(validCode), equals([true, true]));

      final invalidCode = '''
        List<T> malformed<T>(List<T> values) {
          return <String>['bad'];
        }

        main() => malformed<int>(<int>[7]);
      ''';
      expect(
        () => execute(invalidCode),
        throwsA(isA<RuntimeError>().having(
          (e) => e.message,
          'message',
          allOf(contains("can't be returned"), contains('malformed')),
        )),
      );
    });

    test('Typed variable declarations annotate empty collections', () {
      final code = '''
        List<int> build() {
          List<int> result = [];
          result.add(1);
          result.add(2);
          return result;
        }

        main() {
          return build() is List<int>;
        }
      ''';

      expect(execute(code), isTrue);
    });
  });
}
