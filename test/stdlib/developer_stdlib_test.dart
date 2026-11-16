import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('dart:developer stdlib tests', () {
    test('log, inspect, and debugger functions', () {
      final d4rt = D4rt()..grant(DangerousPermission.developerTools);
      final result = d4rt.execute(
        source: '''
        import 'dart:developer';

        main() {
          log('Test log message', name: 'd4rt.test');
          final obj = {'key': 'value'};
          final inspected = inspect(obj);
          final debugResult = debugger(when: false);
          return [inspected != null, debugResult];
        }
      ''',
      );

      expect(result, equals([true, false]));
    });

    test('UserTag', () {
      final d4rt = D4rt()..grant(DangerousPermission.developerTools);
      final result = d4rt.execute(
        source: '''
        import 'dart:developer';

        main() {
          final tag = UserTag('worker');
          final defaultTag = UserTag.defaultTag;
          return [tag.label, defaultTag.label];
        }
      ''',
      );

      expect(result, equals(['worker', 'Default']));
    });

    test('ServiceExtensionResponse', () async {
      final d4rt = D4rt()..grant(DangerousPermission.developerTools);
      final result = await d4rt.execute(
        source: '''
        import 'dart:developer';

        main() async {
          final successResp = ServiceExtensionResponse.result('{"ok": true}');
          final errorResp = ServiceExtensionResponse.error(-32000, 'Internal error');
          return [successResp.result, errorResp.errorCode, errorResp.errorDetail];
        }
      ''',
      );

      expect(result, equals(['{"ok": true}', -32000, 'Internal error']));
    });
  });
}
