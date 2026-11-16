import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('Real Process Execution', () {
    test('Process execution without permission fails', () {
      final interpreter = D4rt();
      interpreter.grant(FilesystemPermission.any); // IO needed but not process

      expect(
        () => interpreter.execute(
          source: '''
          import 'dart:io';
          void main() {
            Process.runSync('echo', ['test']);
          }
        ''',
        ),
        throwsA(
          isA<RuntimeError>().having(
            (e) => e.message,
            'message',
            contains('ProcessRunPermission'),
          ),
        ),
      );
    });
  });

  group('Safe Operations Without Permissions', () {
    test('Pure computation works without any permissions', () {
      final interpreter = D4rt();

      final result = interpreter.execute(
        source: '''
        int main() {
          List<int> numbers = [1, 2, 3, 4, 5];
          return numbers.fold(0, (sum, n) => sum + n);
        }
      ''',
      );

      expect(result, equals(15));
    });

    test('String processing works without permissions', () {
      final interpreter = D4rt();

      final result = interpreter.execute(
        source: '''
        String main() {
          var text = 'hello world';
          return text.split(' ').map((w) => w.toUpperCase()).join('-');
        }
      ''',
      );

      expect(result, equals('HELLO-WORLD'));
    });

    test('Complex data structures work without permissions', () {
      final interpreter = D4rt();

      final result = interpreter.execute(
        source: '''
        Map<String, dynamic> main() {
          var data = {
            'users': [
              {'name': 'Alice', 'age': 30},
              {'name': 'Bob', 'age': 25},
            ]
          };
          
          var users = data['users'] as List;
          var totalAge = users.fold(0, (sum, user) => sum + user['age']);
          
          return {
            'totalUsers': users.length,
            'averageAge': totalAge / users.length,
            'names': users.map((u) => u['name']).toList(),
          };
        }
      ''',
      );

      expect(result['totalUsers'], equals(2));
      expect(result['averageAge'], equals(27.5));
      expect(result['names'], equals(['Alice', 'Bob']));
    });
  });

  group('Network Permission Scenarios', () {
    test('Network lookup requires permission', () {
      final interpreter = D4rt();
      interpreter.grant(FilesystemPermission.any);
      // No network permission

      expect(
        () => interpreter.execute(
          source: '''
          import 'dart:io';
          void main() {
            InternetAddress.lookup('localhost');
          }
        ''',
        ),
        throwsA(
          isA<RuntimeError>().having(
            (e) => e.message,
            'message',
            contains('NetworkPermission'),
          ),
        ),
      );
    });
  });
}
