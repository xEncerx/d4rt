import '../../interpreter_test.dart';
import 'package:test/test.dart';

void main() {
  group('DateTime tests', () {
    test('DateTime.parse', () {
      const source = '''
      main() {
        DateTime date = DateTime.parse("2023-10-01T12:00:00Z");
        return [date.year, date.month, date.day, date.hour, date.minute, date.second];
      }
      ''';
      expect(execute(source), equals([2023, 10, 1, 12, 0, 0]));
    });

    test('DateTime.fromMillisecondsSinceEpoch', () {
      const source = '''
      main() {
        DateTime date = DateTime.fromMillisecondsSinceEpoch(1696156800000, isUtc: true);
        return [date.year, date.month, date.day];
      }
      ''';
      expect(execute(source), equals([2023, 10, 1]));
    });

    test('DateTime.utc', () {
      const source = '''
      main() {
        DateTime date = DateTime.utc(2023, 10, 1, 12, 0, 0);
        return date.toIso8601String();
      }
      ''';
      expect(execute(source), equals('2023-10-01T12:00:00.000Z'));
    });

    test('DateTime.isBefore and isAfter', () {
      const source = '''
      main() {
        DateTime date1 = DateTime.utc(2023, 10, 1);
        DateTime date2 = DateTime.utc(2023, 10, 2);
        return [date1.isBefore(date2), date2.isAfter(date1)];
      }
      ''';
      expect(execute(source), equals([true, true]));
    });

    test('DateTime.add and subtract', () {
      const source = '''
      main() {
        DateTime date = DateTime.utc(2023, 10, 1);
        return [date.add(Duration(days: 1)).toIso8601String(), date.subtract(Duration(days: 1)).toIso8601String()];
      }
      ''';
      final result = execute(source) as List;
      expect(result[0], startsWith('2023-10-02T'));
      expect(result[1], startsWith('2023-09-30T'));
    });

    test('DateTime.difference', () {
      const source = '''
      main() {
        DateTime date1 = DateTime.utc(2023, 10, 2);
        DateTime date2 = DateTime.utc(2023, 10, 1);
        return date1.difference(date2).inDays;
      }
      ''';
      expect(execute(source), equals(1));
    });

    test('DateTime.properties', () {
      const source = '''
      main() {
        DateTime date = DateTime.utc(2023, 10, 1, 12, 30, 45, 123, 456);
        return [
          date.year,
          date.month,
          date.day,
          date.hour,
          date.minute,
          date.second,
          date.millisecond,
          date.microsecond,
          date.weekday,
          date.isUtc
        ];
      }
      ''';
      expect(
        execute(source),
        equals([2023, 10, 1, 12, 30, 45, 123, 456, 7, true]),
      );
    });
  });
}
