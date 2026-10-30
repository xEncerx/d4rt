import 'dart:io' as io;
import 'package:test/test.dart';
import '../../interpreter_test.dart';

final _executable = io.Platform.resolvedExecutable;
final _fixture = io.File('test/fixtures/native_process.dart').absolute.path;

void main() {
  group('Process portable native adapters', () {
    for (final method in ['run', 'runSync']) {
      test('$method forwards arguments and result', () async {
        final result = await execute(
          '''
          import 'dart:io';
          main(executable, fixture) async {
            final result = ${method == 'run' ? 'await ' : ''}Process.$method(
                executable, [fixture, 'echo', 'Hello', 'World']);
            return [result.exitCode, result.stdout.trim(), result.pid > 0,
                result.stderr];
          }
        ''',
          args: [_executable, _fixture],
        );
        expect(result, [0, 'Hello World', true, '']);
      });
    }

    test('start exposes owned child streams and stdin', () async {
      final result = await execute(
        '''
        import 'dart:io'; import 'dart:convert';
        main(executable, fixture) async {
          final child = await Process.start(executable, [fixture, 'stdin']);
          child.stdin.writeln('Hello Child');
          await child.stdin.close();
          final output = await child.stdout.transform(utf8.decoder).join();
          final error = await child.stderr.transform(utf8.decoder).join();
          return [await child.exitCode, output.trim(), error, child.pid > 0];
        }
      ''',
        args: [_executable, _fixture],
      );
      expect(result, [0, 'Hello Child', '', true]);
    });

    test('environment options reach native child', () async {
      final result = await execute(
        '''
        import 'dart:io';
        main(executable, fixture) async {
          final result = await Process.run(executable, [fixture, 'env', 'M05_VALUE'],
              environment: {'M05_VALUE': 'test_value'}, includeParentEnvironment: false);
          return [result.exitCode, result.stdout.trim()];
        }
      ''',
        args: [_executable, _fixture],
      );
      expect(result, [0, 'test_value']);
    });

    test('working directory reaches native child', () async {
      final directory = io.Directory.systemTemp.createTempSync('m05-cwd-');
      try {
        final result = await execute(
          '''
          import 'dart:io';
          main(executable, fixture, directory) async {
            final result = await Process.run(executable, [fixture, 'cwd'],
                workingDirectory: directory);
            return [result.exitCode, result.stdout.trim()];
          }
        ''',
          args: [_executable, _fixture, directory.path],
        );
        expect(result, [0, directory.path]);
      } finally {
        directory.deleteSync(recursive: true);
      }
    });

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
