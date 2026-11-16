import 'dart:io' as io;

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

bool allows(Permission permission, Map<String, dynamic> operation) =>
    (D4rt()..grant(permission)).checkPermission(operation);

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
    });

    test('different operation authority and scopes remain distinct', () {
      final values = <Permission>[
        FilesystemPermission.read,
        FilesystemPermission.write,
        FilesystemPermission.execute,
        FilesystemPermission.any,
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
