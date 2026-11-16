import 'dart:async';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

final _denied = isA<RuntimeError>().having(
  (error) => error.message,
  'permission denial',
  contains('NetworkPermission'),
);

D4rt _interpreter([Iterable<Permission> grants = const []]) {
  final result = D4rt()..grant(FilesystemPermission.any);
  for (final grant in grants) {
    result.grant(grant);
  }
  return result;
}

Future<dynamic> _run(D4rt interpreter, String body, {String imports = ''}) =>
    Future.sync(
      () => interpreter.execute(
        source: "import 'dart:io'; $imports main() async { $body }",
      ),
    ).timeout(const Duration(seconds: 8));

// Embedders can restrict listener/bind hosts through the public Permission API.
class _ScopedNetworkOperation extends Permission {
  final String host;
  final String action;
  _ScopedNetworkOperation(this.host, this.action);
  @override
  String get type => 'network';
  @override
  String get description => '$action on $host';
  @override
  bool allows(dynamic operation) =>
      operation is Map<String, dynamic> &&
      operation['type'] == type &&
      operation[action] == true &&
      operation['host'] == host;
}

void main() {
  group('Native network boundaries', () {
    test(
      'listener String zones decode, but DNS and UDP binding zones do not',
      () async {
        for (final kind in ['ServerSocket', 'RawServerSocket', 'HttpServer']) {
          await expectLater(
            _run(
              _interpreter([_ScopedNetworkOperation('fe80::1%252', 'listen')]),
              "return await $kind.bind('fe80::1%252', 0);",
            ),
            throwsA(_denied),
          );
          await expectLater(
            _run(
              _interpreter([_ScopedNetworkOperation('fe80::1%2', 'listen')]),
              "return await $kind.bind(InternetAddress('fe80::1%252'), 0);",
            ),
            throwsA(_denied),
          );
        }
        await expectLater(
          Future.sync(
            () =>
                _interpreter([
                  _ScopedNetworkOperation('fe80::1%252', 'listen'),
                ]).execute(
                  source: '''
        import 'dart:io'; main(context) => HttpServer.bindSecure('fe80::1%252', 0, context);
      ''',
                  positionalArgs: [SecurityContext()],
                ),
          ),
          throwsA(_denied),
        );
        await expectLater(
          _run(
            _interpreter([NetworkPermission.connectTo('fe80::1%2')]),
            "return await InternetAddress.lookup('fe80::1%252');",
          ),
          throwsA(_denied),
        );
        await expectLater(
          _run(
            _interpreter([_ScopedNetworkOperation('fe80::1%2', 'bind')]),
            "return await RawDatagramSocket.bind('fe80::1%252', 0);",
          ),
          throwsA(_denied),
        );
      },
    );
  });
}
