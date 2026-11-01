import 'dart:convert';
import 'dart:io' as io;

import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

bool allows(Permission permission, Map<String, dynamic> operation) =>
    (D4rt()..grant(permission)).checkPermission(operation);

Map<String, dynamic> filesystem(String path, String action) => {
  'type': 'filesystem',
  'path': path,
  action: true,
};

Map<String, dynamic> process(String command, [Object? args]) => {
  'type': 'process',
  'command': command,
  'args': args,
};

void main() {
  group('Permission values', () {
    test('equivalent scopes deduplicate, query, and revoke by value', () {
      final pairs = <(Permission, Permission)>[
        (
          FilesystemPermission.readPath('scope'),
          FilesystemPermission.readPath('./scope/.'),
        ),
        (
          FilesystemPermission.writePath('scope'),
          FilesystemPermission.writePath('./scope'),
        ),
        (
          FilesystemPermission.executePath('scope'),
          FilesystemPermission.executePath('scope/child/..'),
        ),
        (
          FilesystemPermission.path('scope'),
          FilesystemPermission.path('./scope/'),
        ),
        (
          NetworkPermission.connectTo('EXAMPLE.INVALID'),
          NetworkPermission.connectTo('example.invalid'),
        ),
        (
          NetworkPermission.connectToPort('EXAMPLE.INVALID', 443),
          NetworkPermission.connectToPort('example.invalid', 443),
        ),
        (NetworkPermission.listenOn(8080), NetworkPermission.listenOn(8080)),
        (
          ProcessRunPermission.command('tool'),
          ProcessRunPermission.command('tool'),
        ),
        (
          ProcessRunPermission.command('./tools/runner'),
          ProcessRunPermission.command(p.absolute('tools/runner')),
        ),
        (
          ProcessRunPermission.commandWithArgs('tool', ['a', 'b']),
          ProcessRunPermission.commandWithArgs('tool', ['a', 'b']),
        ),
        (IsolatePermission.spawn, IsolatePermission.spawn),
        (IsolatePermission.communicate, IsolatePermission.communicate),
        (IsolatePermission.any, IsolatePermission.any),
        (
          DangerousPermission.codeEvaluation,
          DangerousPermission.codeEvaluation,
        ),
        (DangerousPermission.nativePlugins, DangerousPermission.nativePlugins),
        (DangerousPermission.any, DangerousPermission.any),
      ];
      for (final (first, second) in pairs) {
        expect(first, second);
        expect(second, first);
        expect(first.hashCode, second.hashCode);
        expect({first, second}, hasLength(1));
        final interpreter = D4rt()
          ..grant(first)
          ..grant(second);
        expect(interpreter.hasPermission(second), isTrue);
        interpreter.revoke(second);
        expect(interpreter.hasPermission(first), isFalse);
      }
      final first = FilesystemPermission.readPath('scope');
      final second = FilesystemPermission.readPath('./scope');
      final third = FilesystemPermission.readPath('scope/child/..');
      expect(first == second && second == third && first == third, isTrue);
    });

    test('different operation authority and scopes remain distinct', () {
      final values = <Permission>[
        FilesystemPermission.read,
        FilesystemPermission.write,
        FilesystemPermission.execute,
        FilesystemPermission.any,
        FilesystemPermission.readPath('scope'),
        FilesystemPermission.writePath('scope'),
        FilesystemPermission.executePath('scope'),
        FilesystemPermission.path('scope'),
        FilesystemPermission.readPath('other'),
        NetworkPermission.connect,
        NetworkPermission.listen,
        NetworkPermission.bind,
        NetworkPermission.any,
        NetworkPermission.connectTo('example.invalid'),
        NetworkPermission.connectToPort('example.invalid', 443),
        NetworkPermission.connectToPort('example.invalid', 80),
        NetworkPermission.connectTo('other.invalid'),
        NetworkPermission.listenOn(443),
        ProcessRunPermission.any,
        ProcessRunPermission.command('tool'),
        ProcessRunPermission.command('other'),
        ProcessRunPermission.command('./tool'),
        ProcessRunPermission.commandWithArgs('tool', []),
        ProcessRunPermission.commandWithArgs('tool', ['a', 'b']),
        ProcessRunPermission.commandWithArgs('tool', ['b', 'a']),
        IsolatePermission.spawn,
        IsolatePermission.communicate,
        IsolatePermission.any,
        DangerousPermission.codeEvaluation,
        DangerousPermission.nativePlugins,
        DangerousPermission.any,
      ];
      expect(values.toSet(), hasLength(values.length));
    });

    test('mutable argument input cannot alter a granted value', () {
      final input = ['--safe', 'value'];
      final permission = ProcessRunPermission.commandWithArgs('tool', input);
      final equivalent = ProcessRunPermission.commandWithArgs('tool', [
        '--safe',
        'value',
      ]);
      final hash = permission.hashCode;
      final description = permission.description;
      final interpreter = D4rt()..grant(permission);
      input
        ..[0] = '--unsafe'
        ..add('extra');
      expect(permission.hashCode, hash);
      expect(permission.description, description);
      expect(permission, equivalent);
      expect(interpreter.hasPermission(equivalent), isTrue);
      expect(
        interpreter.checkPermission(process('tool', ['--safe', 'value'])),
        isTrue,
      );
      expect(interpreter.checkPermission(process('tool', input)), isFalse);
      interpreter.revoke(equivalent);
      expect(
        interpreter.checkPermission(process('tool', ['--safe', 'value'])),
        isFalse,
      );
    });

    test(
      'relative scopes remain anchored when cwd changes in a child process',
      () async {
        final result = await io.Process.run(io.Platform.resolvedExecutable, [
          '--packages=${p.absolute('.dart_tool/package_config.json')}',
          p.absolute('test/fixtures/permission_cwd.dart'),
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stdout.toString().trim(), 'CWD_SCOPE_PASS');
      },
    );
  });

  group('Filesystem scopes', () {
    test('scope, descendants, roots, traversal, and sibling boundaries', () {
      final scope = p.absolute('synthetic_scope');
      final permission = FilesystemPermission.readPath('$scope/');
      for (final path in [
        scope,
        p.join(scope, 'nested', 'file'),
        p.join(scope, 'nested', '..', 'file'),
      ]) {
        expect(
          allows(permission, filesystem(path, 'read')),
          isTrue,
          reason: path,
        );
      }
      for (final path in [
        p.dirname(scope),
        '${scope}_sibling/file',
        p.join(scope, '..', 'outside'),
      ]) {
        expect(
          allows(permission, filesystem(path, 'read')),
          isFalse,
          reason: path,
        );
      }
      final root = p.rootPrefix(scope);
      final rootGrant = FilesystemPermission.readPath(root);
      expect(allows(rootGrant, filesystem(root, 'read')), isTrue);
      expect(allows(rootGrant, filesystem(scope, 'read')), isTrue);
      expect(allows(permission, {'type': 'filesystem', 'read': true}), isFalse);
      expect(
        allows(permission, {'type': 'filesystem', 'path': 1, 'read': true}),
        isFalse,
      );
      expect(
        allows(permission, {
          'type': 'filesystem',
          'read': true,
          'pathAgnostic': true,
        }),
        isTrue,
      );
      expect(allows(permission, filesystem(scope, 'write')), isFalse);
      expect(allows(permission, filesystem(scope, 'execute')), isFalse);
      expect(
        allows(
          FilesystemPermission.writePath(scope),
          filesystem(scope, 'write'),
        ),
        isTrue,
      );
      expect(
        allows(
          FilesystemPermission.executePath(scope),
          filesystem(scope, 'execute'),
        ),
        isTrue,
      );
      expect(
        allows(FilesystemPermission.path(scope), {
          'type': 'filesystem',
          'path': scope,
          'read': true,
          'write': true,
          'execute': true,
        }),
        isTrue,
      );
    });

    test('Windows drive and share roots stay distinct', () {
      final drive = FilesystemPermission.readPath(r'C:\');
      expect(allows(drive, filesystem(r'c:\synthetic\file', 'read')), isTrue);
      expect(allows(drive, filesystem(r'D:\synthetic\file', 'read')), isFalse);
      // UNC identity is lexical; authorization additionally requires a
      // reachable share and must not mistake network failures for absence.
      final share = FilesystemPermission.readPath(r'\\server\share\');
      expect(share, FilesystemPermission.readPath(r'\\server\share\.'));
      expect(
        share,
        isNot(FilesystemPermission.readPath(r'\\server\share_sibling\')),
      );
      expect(share, isNot(FilesystemPermission.readPath(r'\\other\share\')));
    }, skip: !io.Platform.isWindows);

    test('POSIX backslashes do not turn outside names into descendants', () {
      final root = io.Directory.systemTemp.createTempSync('d4rt_posix_scope_');
      try {
        final allowed = io.Directory(p.join(root.path, 'allowed'))
          ..createSync();
        final inside = io.File(p.join(allowed.path, 'child'))
          ..writeAsStringSync('synthetic inside');
        final outside = io.File(p.join(root.path, r'allowed\..\secret'))
          ..writeAsStringSync('synthetic outside');
        final backslashChild = p.join(root.path, r'allowed\child');
        final childGrant = FilesystemPermission.readPath(inside.path);
        final distinctGrant = FilesystemPermission.readPath(backslashChild);
        expect(childGrant, isNot(distinctGrant));
        expect({childGrant, distinctGrant}, hasLength(2));
        final values = D4rt()..grant(childGrant);
        expect(values.hasPermission(distinctGrant), isFalse);
        values.revoke(distinctGrant);
        expect(values.hasPermission(childGrant), isTrue);
        expect(allows(childGrant, filesystem(backslashChild, 'read')), isFalse);
        expect(allows(distinctGrant, filesystem(inside.path, 'read')), isFalse);
        final interpreter = D4rt()
          ..grant(FilesystemPermission.readPath(allowed.path));
        Object? read(io.File file) => interpreter.execute(
          source:
              '''
          import 'dart:io';
          String main() => File(${jsonEncode(file.path)}).readAsStringSync();
        ''',
        );
        expect(read(inside), 'synthetic inside');
        expect(
          () => read(outside),
          throwsA(
            isA<RuntimeError>().having(
              (error) => error.message,
              'message',
              contains('Filesystem permission denied'),
            ),
          ),
        );
        expect(outside.readAsStringSync(), 'synthetic outside');
        final outsideGrant = FilesystemPermission.readPath(outside.path);
        expect(allows(outsideGrant, filesystem(outside.path, 'read')), isTrue);
        expect(
          allows(outsideGrant, filesystem(p.join(root.path, 'secret'), 'read')),
          isFalse,
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    }, skip: io.Platform.isWindows);

    test(
      'interpreter reads only its scope and equivalent revoke takes effect',
      () {
        final root = io.Directory.systemTemp.createTempSync(
          'd4rt_permission_model_',
        );
        try {
          final scope = io.Directory(p.join(root.path, 'allowed'))
            ..createSync();
          final sibling = io.Directory(p.join(root.path, 'allowed_sibling'))
            ..createSync();
          final inside = io.File(p.join(scope.path, 'fixture.txt'))
            ..writeAsStringSync('synthetic inside');
          final outside = io.File(p.join(sibling.path, 'fixture.txt'))
            ..writeAsStringSync('synthetic outside');
          final interpreter = D4rt()
            ..grant(FilesystemPermission.readPath(scope.path))
            // Keep dart:io module admission after revoking the read grant.
            ..grant(FilesystemPermission.writePath(scope.path));
          Object? read(io.File file) => interpreter.execute(
            source:
                '''
          import 'dart:io';
          String main() => File(${jsonEncode(file.path)}).readAsStringSync();
        ''',
          );
          final denied = throwsA(
            isA<RuntimeError>().having(
              (error) => error.message,
              'message',
              contains('Filesystem permission denied'),
            ),
          );
          expect(read(inside), 'synthetic inside');
          expect(() => read(outside), denied);
          interpreter.revoke(
            FilesystemPermission.readPath(p.join(scope.path, '.')),
          );
          expect(() => read(inside), denied);
          expect(inside.readAsStringSync(), 'synthetic inside');
          expect(outside.readAsStringSync(), 'synthetic outside');
        } finally {
          root.deleteSync(recursive: true);
        }
      },
    );
  });

  group('Network scopes', () {
    test('required host and port fail closed and hosts ignore case', () {
      final permission = NetworkPermission.connectToPort(
        'EXAMPLE.INVALID',
        443,
      );
      expect(
        allows(permission, {
          'type': 'network',
          'connect': true,
          'host': 'eXaMpLe.InVaLiD',
          'port': 443,
        }),
        isTrue,
      );
      for (final fields in <Map<String, dynamic>>[
        {},
        {'host': 'example.invalid'},
        {'port': 443},
        {'host': null, 'port': 443},
        {'host': 'example.invalid', 'port': null},
        {'host': 'other.invalid', 'port': 443},
        {'host': 'example.invalid', 'port': 80},
        {'host': 1, 'port': 443},
        {'host': 'example.invalid', 'port': '443'},
        {'host': 'example.invalid', 'port': 443.0},
      ]) {
        expect(
          allows(permission, {'type': 'network', 'connect': true, ...fields}),
          isFalse,
          reason: '$fields',
        );
      }
      expect(
        allows(NetworkPermission.connectTo('example.invalid'), {
          'type': 'network',
          'connect': true,
          'host': 'EXAMPLE.INVALID',
        }),
        isTrue,
      );
      expect(
        allows(NetworkPermission.connectTo('example.invalid'), {
          'type': 'network',
          'connect': true,
        }),
        isFalse,
      );
      expect(
        allows(NetworkPermission.listenOn(8080), {
          'type': 'network',
          'listen': true,
          'port': 8080,
        }),
        isTrue,
      );
      expect(
        allows(NetworkPermission.listenOn(8080), {
          'type': 'network',
          'listen': true,
        }),
        isFalse,
      );
      expect(
        allows(NetworkPermission.listenOn(8080), {
          'type': 'network',
          'listen': true,
          'port': 8081,
        }),
        isFalse,
      );
      expect(
        allows(permission, {
          'type': 'network',
          'listen': true,
          'host': 'example.invalid',
          'port': 443,
        }),
        isFalse,
      );
      expect(
        allows(NetworkPermission.connect, {
          'type': 'network',
          'connect': true,
          'listen': true,
        }),
        isFalse,
      );
      expect(
        allows(NetworkPermission.listen, {'type': 'network', 'listen': true}),
        isTrue,
      );
      expect(
        allows(NetworkPermission.bind, {'type': 'network', 'bind': true}),
        isTrue,
      );
      expect(
        allows(NetworkPermission.bind, {'type': 'network', 'connect': true}),
        isFalse,
      );
    });

    test(
      'literal IPv6 scopes normalize and revoke by value without DNS aliases',
      () {
        final permission = NetworkPermission.connectToPort(
          '[0:0:0:0:0:0:0:1]',
          80,
        );
        final interpreter = D4rt()..grant(permission);
        expect(
          interpreter.checkPermission({
            'type': 'network',
            'connect': true,
            'host': '::1',
            'port': 80,
          }),
          true,
        );
        interpreter.revoke(NetworkPermission.connectToPort('::1', 80));
        expect(
          interpreter.checkPermission({
            'type': 'network',
            'connect': true,
            'host': '::1',
            'port': 80,
          }),
          false,
        );
        expect(
          allows(NetworkPermission.connectTo('localhost'), {
            'type': 'network',
            'connect': true,
            'host': '127.0.0.1',
          }),
          false,
        );
        expect(
          allows(NetworkPermission.listenOn(0), {
            'type': 'network',
            'listen': true,
            'port': 12345,
          }),
          false,
        );
        expect(
          allows(NetworkPermission.connectToPort('239.1.2.3', 80), {
            'type': 'network',
            'connect': true,
            'host': '239.1.2.3',
          }),
          false,
        );
      },
    );

    test(
      'IPv6 zones stay distinct across equality, matching and revocation',
      () {
        final first = NetworkPermission.connectToPort('fe80::1%1', 80);
        final equivalent = NetworkPermission.connectToPort(
          '[FE80:0:0:0:0:0:0:1%1]',
          80,
        );
        final other = NetworkPermission.connectToPort('fe80::1%2', 80);
        expect(first, equivalent);
        expect(first, isNot(other));
        final interpreter = D4rt()
          ..grant(first)
          ..grant(other);
        for (final address in [
          'fe80::1%1',
          io.InternetAddress('FE80:0:0:0:0:0:0:1%1').address,
        ]) {
          expect(
            interpreter.checkPermission({
              'type': 'network',
              'connect': true,
              'host': address,
              'port': 80,
            }),
            true,
          );
        }
        interpreter.revoke(equivalent);
        expect(interpreter.hasPermission(other), true);
        expect(
          interpreter.checkPermission({
            'type': 'network',
            'connect': true,
            'host': io.InternetAddress('fe80::1%1').address,
            'port': 80,
          }),
          false,
        );
        expect(
          interpreter.checkPermission({
            'type': 'network',
            'connect': true,
            'host': 'fe80::1%2',
            'port': 80,
          }),
          true,
        );
        expect(
          allows(first, {
            'type': 'network',
            'connect': true,
            'host': 'fe80::1%2',
            'port': 80,
          }),
          false,
        );
        expect(
          allows(first, {
            'type': 'network',
            'connect': true,
            'host': 'fe80::1',
            'port': 80,
          }),
          false,
        );
      },
    );

    test(
      'permission and native address identities do not decode String transport escapes',
      () {
        final raw = NetworkPermission.connectTo('fe80::1%252');
        final decoded = NetworkPermission.connectTo('fe80::1%2');
        expect(raw, isNot(decoded));
        expect(
          raw,
          NetworkPermission.connectTo(
            io.InternetAddress('fe80::1%252').address,
          ),
        );
        final interpreter = D4rt()
          ..grant(raw)
          ..grant(decoded);
        interpreter.revoke(
          NetworkPermission.connectTo('FE80:0:0:0:0:0:0:1%252'),
        );
        expect(interpreter.hasPermission(raw), false);
        expect(interpreter.hasPermission(decoded), true);
      },
    );
  });

  group('Process scopes', () {
    test(
      'arguments are exact, ordered, typed, and required even when empty',
      () {
        final permission = ProcessRunPermission.commandWithArgs('tool', [
          'a',
          'b',
        ]);
        expect(allows(permission, process('tool', ['a', 'b'])), isTrue);
        expect(
          allows(permission, process('tool', <dynamic>['a', 'b'])),
          isTrue,
        );
        for (final args in <Object?>[
          null,
          'a b',
          [1, 2],
          ['b', 'a'],
          ['a'],
          ['a', 'b', 'c'],
          ['a', 'changed'],
        ]) {
          expect(
            allows(permission, process('tool', args)),
            isFalse,
            reason: '$args',
          );
        }
        expect(
          allows(permission, {'type': 'process', 'command': 'tool'}),
          isFalse,
        );
        expect(allows(permission, process('other', ['a', 'b'])), isFalse);
        final empty = ProcessRunPermission.commandWithArgs('tool', []);
        expect(allows(empty, process('tool', [])), isTrue);
        expect(allows(empty, process('tool')), isFalse);
        expect(
          allows(ProcessRunPermission.command('tool'), process('tool')),
          isTrue,
        );
        expect(
          allows(
            ProcessRunPermission.command('tool'),
            process('tool', ['anything']),
          ),
          isTrue,
        );
      },
    );

    test('bare names never authorize paths and path scopes match exactly', () {
      final bare = ProcessRunPermission.command('tool');
      expect(allows(bare, process('tool')), isTrue);
      for (final command in [
        './tool',
        r'.\tool',
        p.absolute('tool'),
        p.absolute('other/tool'),
        'Tool',
      ]) {
        expect(allows(bare, process(command)), isFalse, reason: command);
      }
      final path = ProcessRunPermission.command('./tools/runner');
      expect(allows(path, process(p.absolute('tools/runner'))), isTrue);
      expect(allows(path, process('./tools/nested/../runner')), isTrue);
      for (final command in [
        'runner',
        './other/runner',
        './tools/runner_sibling',
        './tools/runner/child',
      ]) {
        expect(allows(path, process(command)), isFalse, reason: command);
      }
      expect(allows(path, {'type': 'process'}), isFalse);
      expect(allows(path, {'type': 'process', 'command': 1}), isFalse);
      if (io.Platform.isWindows) {
        expect(
          allows(
            path,
            process(p.absolute('tools/runner').replaceAll('\\', '/')),
          ),
          isTrue,
        );
      }
    });

    test('POSIX backslashes and drive-like names retain exact identity', () {
      final slashPath = p.absolute('tools/runner');
      final backslashPath = p.absolute(r'tools\runner');
      final slashGrant = ProcessRunPermission.command(slashPath);
      final backslashGrant = ProcessRunPermission.command(backslashPath);
      expect(slashGrant, isNot(backslashGrant));
      expect({slashGrant, backslashGrant}, hasLength(2));
      final interpreter = D4rt()..grant(slashGrant);
      expect(interpreter.hasPermission(backslashGrant), isFalse);
      interpreter.revoke(backslashGrant);
      expect(interpreter.hasPermission(slashGrant), isTrue);
      expect(interpreter.checkPermission(process(slashPath)), isTrue);
      expect(interpreter.checkPermission(process(backslashPath)), isFalse);
      expect(allows(backslashGrant, process(backslashPath)), isTrue);
      expect(allows(backslashGrant, process(slashPath)), isFalse);
      for (final bareName in [r'tools\runner', 'C:runner']) {
        final bareGrant = ProcessRunPermission.command(bareName);
        expect(allows(bareGrant, process(bareName)), isTrue);
        expect(allows(bareGrant, process(p.absolute(bareName))), isFalse);
      }
    }, skip: io.Platform.isWindows);
  });

  group('Unrestricted and granular authority', () {
    test('unrestricted grants retain type-only and combined operations', () {
      final cases = <(Permission, Map<String, dynamic>)>[
        (
          FilesystemPermission.any,
          {'type': 'filesystem', 'read': true, 'write': true, 'execute': true},
        ),
        (
          NetworkPermission.any,
          {'type': 'network', 'connect': true, 'listen': true, 'bind': true},
        ),
        (ProcessRunPermission.any, {'type': 'process'}),
        (
          IsolatePermission.any,
          {'type': 'isolate', 'spawn': true, 'communicate': true},
        ),
        (
          DangerousPermission.any,
          {'type': 'dangerous', 'operation': 'arbitrary'},
        ),
      ];
      for (final (permission, operation) in cases) {
        expect(allows(permission, operation), isTrue);
        expect(allows(permission, {'type': permission.type}), isTrue);
        expect(allows(permission, {'type': 'unrelated'}), isFalse);
        expect(permission.allows(null), isFalse);
      }
      expect(
        allows(FilesystemPermission.read, {'type': 'filesystem', 'read': true}),
        isTrue,
      );
      expect(
        allows(FilesystemPermission.read, {
          'type': 'filesystem',
          'write': true,
        }),
        isFalse,
      );
      expect(
        allows(NetworkPermission.connect, {'type': 'network', 'connect': true}),
        isTrue,
      );
    });

    test('isolate actions and dangerous operations stay independent', () {
      expect(
        allows(IsolatePermission.spawn, {'type': 'isolate', 'spawn': true}),
        isTrue,
      );
      expect(
        allows(IsolatePermission.spawn, {
          'type': 'isolate',
          'communicate': true,
        }),
        isFalse,
      );
      expect(
        allows(IsolatePermission.communicate, {
          'type': 'isolate',
          'communicate': true,
        }),
        isTrue,
      );
      expect(
        allows(IsolatePermission.communicate, {
          'type': 'isolate',
          'spawn': true,
        }),
        isFalse,
      );
      for (final permission in [
        IsolatePermission.spawn,
        IsolatePermission.communicate,
      ]) {
        expect(
          allows(permission, {
            'type': 'isolate',
            'spawn': true,
            'communicate': true,
          }),
          isFalse,
        );
        expect(allows(permission, {'type': 'isolate'}), isTrue);
      }
      expect(
        allows(DangerousPermission.codeEvaluation, {
          'type': 'dangerous',
          'operation': 'code evaluation',
        }),
        isTrue,
      );
      expect(
        allows(DangerousPermission.nativePlugins, {
          'type': 'dangerous',
          'operation': 'native plugins',
        }),
        isTrue,
      );
      expect(
        allows(DangerousPermission.codeEvaluation, {
          'type': 'dangerous',
          'operation': 'native plugins',
        }),
        isFalse,
      );
      expect(
        allows(DangerousPermission.nativePlugins, {
          'type': 'dangerous',
          'operation': 'code evaluation',
        }),
        isFalse,
      );
      expect(
        allows(DangerousPermission.codeEvaluation, {'type': 'dangerous'}),
        isFalse,
      );
      expect(
        allows(DangerousPermission.nativePlugins, {'type': 'dangerous'}),
        isFalse,
      );
    });
  });
}
