import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('IO Features & Bridges Stdlib Tests', () {
    late D4rt d4rt;
    setUp(() {
      d4rt = D4rt()..grant(FilesystemPermission.read);
    });

    test('HttpStatus constants are accessible', () {
      final result =
          d4rt.execute(
                source: '''
        import 'dart:io';

        main() {
          return [
            HttpStatus.ok,
            HttpStatus.created,
            HttpStatus.badRequest,
            HttpStatus.unauthorized,
            HttpStatus.forbidden,
            HttpStatus.notFound,
            HttpStatus.internalServerError,
          ];
        }
      ''',
              )
              as List;

      expect(result[0], equals(200));
      expect(result[1], equals(201));
      expect(result[2], equals(400));
      expect(result[3], equals(401));
      expect(result[4], equals(403));
      expect(result[5], equals(404));
      expect(result[6], equals(500));
    });
  });
}
