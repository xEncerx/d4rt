import '../../interpreter_test.dart';
import 'package:test/test.dart';

void main() {
  group('Socket methods - comprehensive', () {
    test('InternetAddress constants', () {
      const source = '''
     import 'dart:io';
     main() {
        var loopbackIPv4 = InternetAddress.loopbackIPv4.address;
        var loopbackIPv6 = InternetAddress.loopbackIPv6.address;
        var anyIPv4 = InternetAddress.anyIPv4.address;
        var anyIPv6 = InternetAddress.anyIPv6.address;
        
        return [
          loopbackIPv4 == '127.0.0.1',
          loopbackIPv6 == '::1',
          anyIPv4 == '0.0.0.0',
          anyIPv6 == '::'
        ];
      }
      ''';
      final result = execute(source);
      expect(result, equals([true, true, true, true]));
    });

    test('InternetAddress tryParse method', () {
      const source = '''
     import 'dart:io';
     main() {
        var validIPv4 = InternetAddress.tryParse('192.168.1.1');
        var validIPv6 = InternetAddress.tryParse('::1');
        var invalid = InternetAddress.tryParse('invalid.ip');
        
        return [
          validIPv4 != null,
          validIPv6 != null,
          invalid == null
        ];
      }
      ''';
      final result = execute(source);
      expect(result, equals([true, true, true]));
    });

    test('InternetAddress type checking', () {
      const source = '''
     import 'dart:io';
     main() {
        var ipv4 = InternetAddress.tryParse('127.0.0.1');
        var ipv6 = InternetAddress.tryParse('::1');
        
        return [
          ipv4.type == InternetAddressType.IPv4,
          ipv6.type == InternetAddressType.IPv6,
          ipv4.isLoopback,
          ipv6.isLoopback
        ];
      }
      ''';
      final result = execute(source);
      expect(result, equals([true, true, true, true]));
    });
  });
}
