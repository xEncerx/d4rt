import 'package:test/test.dart';
import '../../interpreter_test.dart';

void main() {
  group('Process portable native adapters', () {
    test('signal and start-mode constants remain available', () {
      expect(
        execute('''
        import 'dart:io';
        main() => [ProcessSignal.sigterm.name, ProcessSignal.sigint.name,
            ProcessStartMode.normal != null, ProcessStartMode.inheritStdio != null,
            ProcessStartMode.detached != null];
      '''),
        ['SIGTERM', 'SIGINT', true, true, true],
      );
    });
  });
}
