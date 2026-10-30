import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

const _host = '127.0.0.1';
const _settle = Duration(milliseconds: 80);
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

T _native<T>(dynamic value) =>
    (value is BridgedInstance ? value.nativeObject : value) as T;

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

// A host-owned real TCP peer counts connections, including ones that never send
// HTTP. Each response closes its connection, making requests deterministic.
class _Peer {
  final ServerSocket server;
  final Set<Socket> sockets = {};
  late final StreamSubscription<Socket> subscription;
  int connections = 0;
  final List<Uri> requests = [];
  final List<String> methods = [];
  String body = '';
  String Function(Uri uri) response = (_) => '200 OK\r\n';

  _Peer(this.server) {
    subscription = server.listen((socket) {
      connections++;
      sockets.add(socket);
      var headers = '';
      socket.listen(
        (data) {
          headers += latin1.decode(data);
          if (!headers.contains('\r\n\r\n')) return;
          final line = headers.split('\r\n').first.split(' ');
          methods.add(line[0]);
          final uri = line[0] == 'CONNECT'
              ? Uri.parse('http://${line[1]}/')
              : Uri.parse(line[1]);
          requests.add(uri);
          socket.write(
            'HTTP/1.1 ${response(uri)}'
            'Content-Length: ${utf8.encode(body).length}\r\nConnection: close\r\n\r\n$body',
          );
          unawaited(
            socket.flush().then((_) => socket.close()).whenComplete(() {
              socket.destroy();
              sockets.remove(socket);
            }),
          );
        },
        onError: (Object _) {
          socket.destroy();
          sockets.remove(socket);
        },
        onDone: () {
          socket.destroy();
          sockets.remove(socket);
        },
      );
    });
  }

  static Future<_Peer> bind() async =>
      _Peer(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
  int get port => server.port;
  String url([String path = '/']) => 'http://$_host:$port$path';
  Future<void> close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
  }
}

void main() {
  group('Native network boundaries', () {
    test(
      'scoped native and String destinations do not cross IPv6 zones',
      () async {
        final peer = await _Peer.bind();
        final interpreter = _interpreter([
          NetworkPermission.connectToPort('fe80::1%1', peer.port),
        ]);
        try {
          for (final destination in [
            "'fe80::1%2'",
            "InternetAddress('fe80::1%2')",
          ]) {
            await expectLater(
              _run(
                interpreter,
                'return await Socket.connect($destination, ${peer.port});',
              ),
              throwsA(_denied),
            );
          }
          await Future<void>.delayed(_settle);
          expect(peer.connections, 0);
        } finally {
          await peer.close();
        }
      },
    );

    for (final method in [
      'Socket.connect',
      'Socket.startConnect',
      'RawSocket.connect',
      'RawSocket.startConnect',
    ]) {
      test(
        '$method decodes String zones once, not native address zones',
        () async {
          final peer = await _Peer.bind();
          final raw = _interpreter([
            NetworkPermission.connectToPort('fe80::1%252', peer.port),
          ]);
          final decoded = _interpreter([
            NetworkPermission.connectToPort('fe80::1%2', peer.port),
          ]);
          try {
            await expectLater(
              _run(raw, "return await $method('fe80::1%252', ${peer.port});"),
              throwsA(_denied),
            );
            await expectLater(
              _run(
                decoded,
                "return await $method(InternetAddress('fe80::1%252'), ${peer.port});",
              ),
              throwsA(_denied),
            );
            await expectLater(
              _run(
                decoded,
                "return await $method('fe80::1%25252', ${peer.port});",
              ),
              throwsA(_denied),
            );
            expect(peer.connections, 0);
          } finally {
            await peer.close();
          }
        },
      );
    }

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

    for (final consumer in ['first', 'mapped']) {
      test('UDP retains real Stream $consumer consumers', () async {
        final peer = await RawDatagramSocket.bind(_host, 0);
        RawDatagramSocket? receiver;
        final interpreter = _interpreter([NetworkPermission.bind]);
        try {
          final values =
              await _run(interpreter, '''
            final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
            socket.writeEventsEnabled = false;
            return [socket, () async {
              ${consumer == 'first' ? 'return (await socket.first) == RawSocketEvent.read;' : 'return await socket.where((event) => event == RawSocketEvent.read).map((event) => socket.receive().data.first).first;'}
            }];
          ''')
                  as List;
          receiver = _native<RawDatagramSocket>(values[0]);
          final result = interpreter.invokeInterpretedFunction(
            values[1] as InterpretedFunction,
            [],
          );
          expect(
            peer.send([7], InternetAddress.loopbackIPv4, receiver.port),
            1,
          );
          expect(
            await Future.value(result).timeout(const Duration(seconds: 3)),
            consumer == 'first' ? true : 7,
          );
        } finally {
          receiver?.close();
          peer.close();
        }
      });
    }
    for (final kind in [
      'Socket.connect',
      'Socket.startConnect',
      'RawSocket.connect',
      'RawSocket.startConnect',
    ]) {
      test(
        '$kind checks destination before connecting and after revoke',
        () async {
          final allowed = await _Peer.bind();
          final forbidden = await _Peer.bind();
          final grant = NetworkPermission.connectToPort(_host, allowed.port);
          final interpreter = _interpreter([grant]);
          try {
            for (final destination in [allowed, forbidden]) {
              final operation = _run(
                interpreter,
                'return await $kind(InternetAddress.loopbackIPv4, ${destination.port});',
              );
              if (destination == forbidden) {
                await expectLater(operation, throwsA(_denied));
              } else {
                final result = await operation;
                if (kind.endsWith('startConnect')) {
                  interpreter.revoke(grant);
                }
                final socket = kind.endsWith('startConnect')
                    ? await _native<ConnectionTask<dynamic>>(result).socket
                    : _native<dynamic>(result);
                if (socket is Socket) {
                  socket.destroy();
                }
                if (socket is RawSocket) {
                  socket.close();
                }
              }
            }
            interpreter.revoke(
              NetworkPermission.connectToPort(_host, allowed.port),
            );
            await expectLater(
              _run(
                interpreter,
                "return await $kind('$_host', ${allowed.port});",
              ),
              throwsA(_denied),
            );
            await Future<void>.delayed(_settle);
            expect(allowed.connections, 1);
            expect(forbidden.connections, 0);
            await expectLater(
              _run(
                _interpreter(),
                "return await $kind('$_host', ${forbidden.port});",
              ),
              throwsA(_denied),
            );
          } finally {
            await allowed.close();
            await forbidden.close();
          }
        },
      );
    }

    test(
      'native, parsed, raw and looked-up address values identify the target',
      () async {
        final peer = await _Peer.bind();
        try {
          final interpreter = _interpreter([
            NetworkPermission.connectToPort(_host, peer.port),
            NetworkPermission.connectTo('LOCALHOST'),
          ]);
          for (final address in [
            "'$_host'",
            'InternetAddress.loopbackIPv4',
            "InternetAddress('$_host')",
            "InternetAddress.tryParse('$_host')",
            'InternetAddress.fromRawAddress(InternetAddress.loopbackIPv4.rawAddress)',
            "(await InternetAddress.lookup('localhost', type: InternetAddressType.IPv4)).first",
          ]) {
            final socket = _native<Socket>(
              await _run(
                interpreter,
                'return await Socket.connect($address, ${peer.port}, sourceAddress: InternetAddress.loopbackIPv4, sourcePort: 0);',
              ),
            );
            socket.destroy();
          }
          await Future<void>.delayed(_settle);
          expect(peer.connections, 6);
        } finally {
          await peer.close();
        }
      },
    );

    test(
      'IPv6 literals normalize for real connects and bracketed proxies',
      () async {
        final peer = _Peer(
          await ServerSocket.bind(InternetAddress.loopbackIPv6, 0),
        );
        final origin = await _Peer.bind();
        final interpreter = _interpreter([
          NetworkPermission.connectToPort('[0:0:0:0:0:0:0:1]', peer.port),
          NetworkPermission.connectToPort(_host, origin.port),
        ]);
        try {
          final socket = _native<Socket>(
            await _run(
              interpreter,
              'return await Socket.connect(InternetAddress.loopbackIPv6, ${peer.port});',
            ),
          );
          socket.destroy();
          expect(
            await _run(interpreter, '''
          final client = HttpClient(); try {
            client.findProxy = (uri) => 'PROXY [::1]:${peer.port}';
            return (await (await client.getUrl(Uri.parse('${origin.url()}'))).close()).statusCode;
          } finally { client.close(force: true); }
        '''),
            200,
          );
          expect(peer.connections, 2);
          expect(origin.connections, 0);
        } finally {
          await peer.close();
          await origin.close();
        }
      },
    );

    for (final kind in ['ServerSocket', 'RawServerSocket', 'HttpServer']) {
      test('$kind listens, rather than merely binding or connecting', () async {
        for (final grants in [
          <Permission>[],
          [NetworkPermission.bind],
          [NetworkPermission.connect],
          [NetworkPermission.listenOn(1)],
        ]) {
          await expectLater(
            _run(
              _interpreter(grants),
              'return await $kind.bind(InternetAddress.loopbackIPv4, 0);',
            ),
            throwsA(_denied),
          );
        }
        final interpreter = _interpreter([NetworkPermission.listenOn(0)]);
        final server = _native<dynamic>(
          await _run(
            interpreter,
            'return await $kind.bind(InternetAddress.loopbackIPv4, 0);',
          ),
        );
        try {
          expect(server.port, greaterThan(0));
          interpreter.revoke(NetworkPermission.listenOn(0));
          await expectLater(
            _run(
              interpreter,
              'return await $kind.bind(InternetAddress.loopbackIPv4, 0);',
            ),
            throwsA(_denied),
          );
        } finally {
          await server.close();
        }
      });
    }

    test('revoking listen does not close an issued listener', () async {
      final interpreter = _interpreter([NetworkPermission.listenOn(0)]);
      final server = _native<ServerSocket>(
        await _run(
          interpreter,
          'return await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);',
        ),
      );
      Socket? client;
      Socket? accepted;
      try {
        interpreter.revoke(NetworkPermission.listenOn(0));
        final incoming = server.first;
        client = await Socket.connect(_host, server.port);
        accepted = await incoming.timeout(const Duration(seconds: 3));
        expect(accepted.remotePort, client.port);
      } finally {
        client?.destroy();
        accepted?.destroy();
        await server.close();
      }
    });

    test(
      'listenOn uses the already-bound actual port and secure bind is guarded',
      () async {
        final socket = await ServerSocket.bind(_host, 0);
        final interpreter = _interpreter([NetworkPermission.listenOn(0)]);
        try {
          await expectLater(
            Future.sync(
              () => interpreter.execute(
                source: '''
          import 'dart:io'; main(socket) => HttpServer.listenOn(socket);
        ''',
                positionalArgs: [socket],
              ),
            ),
            throwsA(_denied),
          );
          interpreter.grant(NetworkPermission.listenOn(socket.port));
          final server = _native<HttpServer>(
            interpreter.execute(
              source: '''
          import 'dart:io'; main(socket) => HttpServer.listenOn(socket);
        ''',
              positionalArgs: [socket],
            ),
          );
          await server.close(force: true);
        } finally {
          await socket.close();
        }
        await expectLater(
          Future.sync(
            () => _interpreter().execute(
              source: '''
        import 'dart:io'; main(context) => HttpServer.bindSecure('127.0.0.1', 0, context);
      ''',
              positionalArgs: [SecurityContext()],
            ),
          ),
          throwsA(_denied),
        );
      },
    );

    test(
      'DNS, reverse, interfaces and local address construction are distinct',
      () async {
        final scoped = _interpreter([NetworkPermission.connectTo('LOCALHOST')]);
        expect(
          await _run(
            scoped,
            "return (await InternetAddress.lookup('localhost')).isNotEmpty;",
          ),
          true,
        );
        for (final interpreter in [
          _interpreter(),
          _interpreter([NetworkPermission.connectToPort('localhost', 80)]),
          _interpreter([NetworkPermission.listen]),
        ]) {
          await expectLater(
            _run(
              interpreter,
              "return await InternetAddress.lookup('localhost');",
            ),
            throwsA(_denied),
          );
        }
        await expectLater(
          _run(scoped, 'return await InternetAddress.loopbackIPv4.reverse();'),
          throwsA(_denied),
        );
        final reverse = _interpreter([NetworkPermission.connectTo(_host)]);
        expect(
          _native<InternetAddress>(
            await _run(
              reverse,
              'return await InternetAddress.loopbackIPv4.reverse();',
            ),
          ).address,
          _host,
        );
        for (final interpreter in [_interpreter(), scoped, reverse]) {
          await expectLater(
            _run(interpreter, 'return await NetworkInterface.list();'),
            throwsA(_denied),
          );
        }
        final all = _interpreter([NetworkPermission.connect]);
        expect(
          await _run(
            all,
            'return (await NetworkInterface.list(includeLoopback: true)).isNotEmpty;',
          ),
          true,
        );
        all.revoke(NetworkPermission.connect);
        await expectLater(
          _run(all, "return await InternetAddress.lookup('localhost');"),
          throwsA(_denied),
        );
        await expectLater(
          _run(all, 'return await NetworkInterface.list();'),
          throwsA(_denied),
        );
        expect(
          await _run(
            _interpreter(),
            "return InternetAddress('::1').isLoopback;",
          ),
          true,
        );
      },
    );

    test(
      'UDP bind does not authorize send; each send and join checks current grants',
      () async {
        final allowed = await RawDatagramSocket.bind(_host, 0);
        final forbidden = await RawDatagramSocket.bind(_host, 0);
        var allowedCount = 0;
        var forbiddenCount = 0;
        final received = Completer<void>();
        final a = allowed.listen((event) {
          if (event == RawSocketEvent.read && allowed.receive() != null) {
            allowedCount++;
            if (!received.isCompleted) received.complete();
          }
        });
        final b = forbidden.listen((event) {
          if (event == RawSocketEvent.read && forbidden.receive() != null) {
            forbiddenCount++;
          }
        });
        final interpreter = _interpreter([NetworkPermission.bind]);
        RawDatagramSocket? socket;
        try {
          await expectLater(
            _run(
              _interpreter([NetworkPermission.connect]),
              "return await RawDatagramSocket.bind('$_host', 0);",
            ),
            throwsA(_denied),
          );
          final result =
              await _run(interpreter, '''
          final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
          return [socket, (port) async => socket.send([1], InternetAddress.loopbackIPv4, port),
            () async => socket.joinMulticast(InternetAddress('239.1.2.3'))];
        ''')
                  as List;
          socket = _native<RawDatagramSocket>(result[0]);
          Future<dynamic> send(int port) => Future.sync(
            () => interpreter.invokeInterpretedFunction(
              result[1] as InterpretedFunction,
              [port],
            ),
          );
          await expectLater(send(allowed.port), throwsA(_denied));
          interpreter.grant(
            NetworkPermission.connectToPort(_host, allowed.port),
          );
          expect(await send(allowed.port), 1);
          await received.future.timeout(const Duration(seconds: 3));
          await expectLater(send(forbidden.port), throwsA(_denied));
          interpreter.revoke(
            NetworkPermission.connectToPort(_host, allowed.port),
          );
          await expectLater(send(allowed.port), throwsA(_denied));
          await expectLater(
            Future.sync(
              () => interpreter.invokeInterpretedFunction(
                result[2] as InterpretedFunction,
                [],
              ),
            ),
            throwsA(_denied),
          );
          interpreter.revoke(NetworkPermission.bind);
          await expectLater(
            _run(
              interpreter,
              "return await RawDatagramSocket.bind('$_host', 0);",
            ),
            throwsA(_denied),
          );
          await Future<void>.delayed(_settle);
          expect(allowedCount, 1);
          expect(forbiddenCount, 0);
        } finally {
          socket?.close();
          await a.cancel();
          await b.cancel();
          allowed.close();
          forbidden.close();
        }
      },
    );
  });

  group('HTTP destination authority', () {
    test(
      'HTTP String hosts and proxy origins authorize decoded scope exactly once',
      () async {
        final peer = await _Peer.bind();
        final raw = _interpreter([
          NetworkPermission.connectToPort('fe80::1%252', peer.port),
        ]);
        final decoded = _interpreter([
          NetworkPermission.connectToPort('fe80::1%2', peer.port),
        ]);
        try {
          for (final verb in [
            'get',
            'post',
            'put',
            'delete',
            'head',
            'patch',
            'open',
          ]) {
            for (final url in [false, true]) {
              final method = '$verb${url ? 'Url' : ''}';
              final args =
                  "${verb == 'open' ? "'GET', " : ''}${url ? "Uri.parse('http://[fe80::1%252]:${peer.port}/')" : "'fe80::1%252', ${peer.port}, '/'"}";
              await expectLater(
                _run(raw, '''
              final client = HttpClient(); try { return await client.$method($args); }
              finally { client.close(force: true); }
            '''),
                throwsA(_denied),
              );
            }
          }
          // Native String scope handling rejects uppercase link-local prefixes;
          // retain that exception when the literal permission itself allows it.
          await expectLater(
            _run(raw, '''
            final client = HttpClient(); try {
              return await client.get('FE80::1%252', ${peer.port}, '/');
            } finally { client.close(force: true); }
          '''),
            throwsA(isA<FormatException>()),
          );
          String environment(String zone) =>
              '''
          return HttpClient.findProxyFromEnvironment(Uri.parse('http://[fe80::1%$zone]:${peer.port}/'),
            environment: <String, String>{});
        ''';
          await expectLater(_run(raw, environment('252')), throwsA(_denied));
          expect(await _run(decoded, environment('252')), 'DIRECT');
          await expectLater(
            _run(decoded, environment('25252')),
            throwsA(_denied),
          );
          expect(peer.connections, 0);
        } finally {
          await peer.close();
        }
      },
    );

    test(
      'proxy endpoints and redirects check effective String zones',
      () async {
        final origin = await _Peer.bind();
        final raw = _interpreter([
          NetworkPermission.connectToPort(_host, origin.port),
          NetworkPermission.connectToPort('fe80::1%252', 80),
        ]);
        final decoded = _interpreter([
          NetworkPermission.connectToPort(_host, origin.port),
          NetworkPermission.connectToPort('fe80::1%2', 80),
        ]);
        try {
          await expectLater(
            _run(raw, '''
          final client = HttpClient(); try {
            client.findProxy = (uri) => 'PROXY [fe80::1%252]:80';
            return await client.getUrl(Uri.parse('${origin.url()}'));
          } finally { client.close(force: true); }
        '''),
            throwsA(_denied),
          );
          final environment =
              '''
          return HttpClient.findProxyFromEnvironment(Uri.parse('${origin.url()}'),
            environment: <String, String>{'http_proxy': '[fe80::1%252]:80'});
        ''';
          await expectLater(_run(raw, environment), throwsA(_denied));
          expect(await _run(decoded, environment), 'PROXY [fe80::1%252]:80');
          expect(origin.connections, 0);
          origin.response = (_) =>
              '302 Found\r\nLocation: http://[fe80::1%252]:80/next\r\n';
          await expectLater(
            _run(raw, '''
          final client = HttpClient(); try {
            final response = await (await client.getUrl(Uri.parse('${origin.url()}'))).close();
            return await response.redirect();
          } finally { client.close(force: true); }
        '''),
            throwsA(_denied),
          );
          expect(origin.connections, 1);
        } finally {
          await origin.close();
        }
      },
    );
    test(
      'port zero authorizes native HTTP and HTTPS default destinations',
      () async {
        final proxy = await _Peer.bind();
        proxy.response = (uri) =>
            uri.port == 443 ? '502 Bad Gateway\r\n' : '200 OK\r\n';
        final zero = _interpreter([
          NetworkPermission.connectToPort(_host, 0),
          NetworkPermission.connectToPort(_host, proxy.port),
        ]);
        final effective = _interpreter([
          NetworkPermission.connectToPort(_host, 80),
          NetworkPermission.connectToPort(_host, 443),
          NetworkPermission.connectToPort(_host, proxy.port),
        ]);
        const verbs = ['get', 'post', 'put', 'delete', 'head', 'patch', 'open'];
        String request(String method, String scheme) {
          final args = method.endsWith('Url')
              ? "${method == 'openUrl' ? "'GET', " : ''}Uri.parse('$scheme://$_host:0/')"
              : "${method == 'open' ? "'GET', " : ''}'$_host', 0, '/'";
          return '''
          final client = HttpClient(); try {
            client.findProxy = (uri) => 'PROXY $_host:${proxy.port}';
            final request = await client.$method($args);
            return (await request.close()).statusCode;
          } finally { client.close(force: true); }
        ''';
        }

        try {
          for (final scheme in ['http', 'https']) {
            final methods = [
              if (scheme == 'http') ...verbs,
              ...verbs.map((verb) => '${verb}Url'),
            ];
            for (final method in methods) {
              await expectLater(
                _run(zero, request(method, scheme)),
                throwsA(_denied),
              );
            }
          }
          await Future<void>.delayed(_settle);
          expect(proxy.connections, 0);
          for (final scheme in ['http', 'https']) {
            final methods = [
              if (scheme == 'http') ...verbs,
              ...verbs.map((verb) => '${verb}Url'),
            ];
            for (final method in methods) {
              final operation = _run(effective, request(method, scheme));
              if (scheme == 'https') {
                // The synthetic proxy observes the real CONNECT to 443, then
                // deliberately refuses TLS tunneling; no default port is bound.
                await expectLater(
                  operation,
                  throwsA(
                    isA<HttpException>().having(
                      (error) => error.message,
                      'native proxy rejection',
                      contains('502'),
                    ),
                  ),
                );
              } else {
                expect(await operation, 200);
              }
            }
          }
          expect(proxy.connections, 21);
          expect(
            proxy.methods.where((method) => method == 'CONNECT').length,
            7,
          );
          expect(proxy.requests.where((uri) => uri.port == 443).length, 7);
        } finally {
          await proxy.close();
        }
      },
    );

    for (final scheme in ['http', 'https']) {
      test(
        '$scheme port-zero redirects and proxy origins use the effective port',
        () async {
          final origin = await _Peer.bind();
          final proxy = await _Peer.bind();
          origin.response = (_) =>
              '302 Found\r\nLocation: $scheme://$_host:0/next\r\n';
          proxy.response = (_) =>
              scheme == 'https' ? '502 Bad Gateway\r\n' : '200 OK\r\n';
          final interpreter = _interpreter([
            NetworkPermission.connectToPort(_host, origin.port),
            NetworkPermission.connectToPort(_host, proxy.port),
            NetworkPermission.connectToPort(_host, 0),
          ]);
          final body =
              '''
          final client = HttpClient(); try {
            client.findProxy = (uri) => uri.port == ${origin.port}
                ? 'DIRECT' : 'PROXY $_host:${proxy.port}';
            final response = await (await client.getUrl(Uri.parse('${origin.url()}'))).close();
            return (await response.redirect()).statusCode;
          } finally { client.close(force: true); }
        ''';
          final environment =
              '''
          return HttpClient.findProxyFromEnvironment(Uri.parse('$scheme://$_host:0/'),
            environment: <String, String>{'${scheme}_proxy': '$_host:${proxy.port}'});
        ''';
          try {
            await expectLater(_run(interpreter, body), throwsA(_denied));
            await expectLater(_run(interpreter, environment), throwsA(_denied));
            await Future<void>.delayed(_settle);
            expect(proxy.connections, 0);
            interpreter.grant(
              NetworkPermission.connectToPort(
                _host,
                scheme == 'https' ? 443 : 80,
              ),
            );
            expect(
              await _run(interpreter, environment),
              'PROXY $_host:${proxy.port}',
            );
            final operation = _run(interpreter, body);
            if (scheme == 'https') {
              await expectLater(
                operation,
                throwsA(
                  isA<HttpException>().having(
                    (error) => error.message,
                    'native proxy rejection',
                    contains('502'),
                  ),
                ),
              );
            } else {
              expect(await operation, 200);
            }
            expect(proxy.connections, 1);
          } finally {
            await origin.close();
            await proxy.close();
          }
        },
      );
    }

    for (final consumption in ['transform', 'drain', 'first']) {
      test(
        'HTTP responses retain Stream $consumption with real bodies',
        () async {
          final peer = await _Peer.bind();
          peer.body = 'hello';
          final interpreter = _interpreter([
            NetworkPermission.connectToPort(_host, peer.port),
          ]);
          try {
            final result = await _run(interpreter, '''
            final client = HttpClient(); try {
              final response = await (await client.getUrl(Uri.parse('${peer.url()}'))).close();
              ${switch (consumption) {
              'transform' => 'return await response.transform(utf8.decoder).join();',
              'drain' => 'return await response.drain(17);',
              _ => 'return await response.first;',
            }}
            } finally { client.close(force: true); }
          ''', imports: "import 'dart:convert';");
            if (consumption == 'first') {
              final bytes = (result as List).cast<int>();
              expect(bytes, isNotEmpty);
              expect('hello'.startsWith(utf8.decode(bytes)), true);
            } else {
              expect(result, consumption == 'transform' ? 'hello' : 17);
            }
            expect(peer.connections, 1);
          } finally {
            await peer.close();
          }
        },
      );
    }
    for (final method in [
      'get',
      'post',
      'put',
      'delete',
      'head',
      'patch',
      'open',
      'getUrl',
      'postUrl',
      'putUrl',
      'deleteUrl',
      'headUrl',
      'patchUrl',
      'openUrl',
    ]) {
      test('$method authorizes before native request creation', () async {
        final peer = await _Peer.bind();
        final interpreter = _interpreter();
        final args = method.endsWith('Url')
            ? "${method == 'openUrl' ? "'GET', " : ''}Uri.parse('${peer.url()}')"
            : "${method == 'open' ? "'GET', " : ''}'$_host', ${peer.port}, '/'";
        final body =
            '''
          final client = HttpClient();
          try { final request = await client.$method($args);
            final response = await request.close(); return response.statusCode;
          } finally { client.close(force: true); }
        ''';
        try {
          await expectLater(_run(interpreter, body), throwsA(_denied));
          await Future<void>.delayed(_settle);
          expect(peer.connections, 0);
          interpreter.grant(NetworkPermission.connectToPort(_host, peer.port));
          expect(await _run(interpreter, body), 200);
          expect(peer.connections, 1);
        } finally {
          await peer.close();
        }
      });
    }

    test(
      'scoped redirects stop automatically and cannot enable following',
      () async {
        final origin = await _Peer.bind();
        final forbidden = await _Peer.bind();
        origin.response = (_) =>
            '302 Found\r\nLocation: ${forbidden.url()}\r\n';
        final interpreter = _interpreter([
          NetworkPermission.connectToPort(_host, origin.port),
        ]);
        try {
          expect(
            await _run(interpreter, '''
          final client = HttpClient(); try {
            final request = await client.getUrl(Uri.parse('${origin.url()}'));
            final following = request.followRedirects;
            final response = await request.close();
            return [following, response.statusCode];
          } finally { client.close(force: true); }
        '''),
            [false, 302],
          );
          await expectLater(
            _run(interpreter, '''
          final client = HttpClient(); try {
            final request = await client.getUrl(Uri.parse('${origin.url()}'));
            request.followRedirects = true;
          } finally { client.close(force: true); }
        '''),
            throwsA(_denied),
          );
          await expectLater(
            _run(interpreter, '''
          final client = HttpClient(); try {
            final request = await client.getUrl(Uri.parse('${origin.url()}'));
            final response = await request.close(); return await response.redirect();
          } finally { client.close(force: true); }
        '''),
            throwsA(_denied),
          );
          await Future<void>.delayed(_settle);
          expect(forbidden.connections, 0);
          interpreter.grant(NetworkPermission.connect);
          expect(
            await _run(interpreter, '''
          final client = HttpClient(); try {
            final request = await client.getUrl(Uri.parse('${origin.url()}'));
            return (await request.close()).statusCode;
          } finally { client.close(force: true); }
        '''),
            200,
          );
          expect(forbidden.connections, 1);
        } finally {
          await origin.close();
          await forbidden.close();
        }
      },
    );

    for (final location in [
      'next',
      '/next',
      '?next=1',
      '//127.0.0.1:PORT/next',
      'http://127.0.0.1:PORT/next',
    ]) {
      test(
        'explicit redirect resolves $location, done and chained context',
        () async {
          final peer = await _Peer.bind();
          final resolved = location.replaceAll('PORT', '${peer.port}');
          peer.response = (uri) => uri.path == '/dir/start'
              ? '302 Found\r\nLocation: $resolved\r\n'
              : '302 Found\r\nLocation: child\r\n';
          final interpreter = _interpreter([
            NetworkPermission.connectToPort(_host, peer.port),
          ]);
          try {
            expect(
              await _run(interpreter, '''
            final client = HttpClient(); try {
              final request = await client.getUrl(Uri.parse('${peer.url('/dir/start')}'));
              final done = request.done;
              await request.close();
              final response = await done;
              final next = await response.redirect();
              final last = await next.redirect(null, Uri.parse('child'));
              return last.statusCode;
            } finally { client.close(force: true); }
          '''),
              302,
            );
            final first = Uri.parse(peer.url('/dir/start')).resolve(resolved);
            expect(peer.requests.map((uri) => uri.toString()).toList(), [
              '/dir/start',
              first.path + (first.hasQuery ? '?${first.query}' : ''),
              first.resolve('child').path,
            ]);
          } finally {
            await peer.close();
          }
        },
      );
    }

    for (final sharedClient in [false, true]) {
      test(
        'concurrent responses keep origins (shared client: $sharedClient)',
        () async {
          final a = await _Peer.bind();
          final b = await _Peer.bind();
          a.response = b.response = (_) => '302 Found\r\nLocation: next\r\n';
          final interpreter = _interpreter([
            NetworkPermission.connectToPort(_host, a.port),
            NetworkPermission.connectToPort(_host, b.port),
          ]);
          try {
            expect(
              await _run(interpreter, '''
          final a = HttpClient(); final b = ${sharedClient ? 'a' : 'HttpClient()'}; try {
            final pendingA = a.getUrl(Uri.parse('${a.url('/a/start')}'));
            final pendingB = b.getUrl(Uri.parse('${b.url('/b/start')}'));
            final requestA = await pendingA; final requestB = await pendingB;
            final responseB = await requestB.close(); final responseA = await requestA.close();
            await responseB.redirect(); await responseA.redirect(); return true;
          } finally { a.close(force: true); b.close(force: true); }
        '''),
              true,
            );
            expect(a.requests.last.path, '/a/next');
            expect(b.requests.last.path, '/b/next');
          } finally {
            await a.close();
            await b.close();
          }
        },
      );
    }

    test(
      'existing HTTP client rechecks new opens and redirects after revoke',
      () async {
        final peer = await _Peer.bind();
        peer.response = (_) => '302 Found\r\nLocation: next\r\n';
        final grant = NetworkPermission.connectToPort(_host, peer.port);
        final interpreter = _interpreter([grant]);
        HttpClient? client;
        try {
          final values =
              await _run(interpreter, '''
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse('${peer.url()}'));
          return [client, () async {
            final response = await request.close();
            return [response.statusCode, () async => response.redirect()];
          }, () => client.getUrl(Uri.parse('${peer.url()}'))];
        ''')
                  as List;
          client = _native<HttpClient>(values[0]);
          interpreter.revoke(grant);
          final response =
              await interpreter.invokeInterpretedFunction(
                    values[1] as InterpretedFunction,
                    [],
                  )
                  as List;
          expect(response[0], 302);
          await expectLater(
            Future.sync(
              () => interpreter.invokeInterpretedFunction(
                values[2] as InterpretedFunction,
                [],
              ),
            ),
            throwsA(_denied),
          );
          await expectLater(
            Future.sync(
              () => interpreter.invokeInterpretedFunction(
                response[1] as InterpretedFunction,
                [],
              ),
            ),
            throwsA(_denied),
          );
          expect(peer.connections, 1);
        } finally {
          client?.close(force: true);
          await peer.close();
        }
      },
    );

    test(
      'issued HTTP sockets can detach after revoke without new authority',
      () async {
        final server = await HttpServer.bind(_host, 0);
        final peer = Completer<Socket>();
        final subscription = server.listen((request) async {
          request.response.statusCode = HttpStatus.switchingProtocols;
          request.response.headers.set('connection', 'upgrade');
          request.response.headers.set('upgrade', 'synthetic');
          peer.complete(await request.response.detachSocket());
        });
        final interpreter = _interpreter([
          NetworkPermission.connectToPort(_host, server.port),
        ]);
        Socket? remote;
        Socket? detached;
        HttpClient? client;
        try {
          final values =
              await _run(interpreter, '''
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse('http://$_host:${server.port}/'));
          final response = await request.close();
          return [client, () async => response.detachSocket()];
        ''')
                  as List;
          client = _native<HttpClient>(values[0]);
          remote = await peer.future.timeout(const Duration(seconds: 3));
          interpreter.revoke(
            NetworkPermission.connectToPort(_host, server.port),
          );
          detached = _native<Socket>(
            await interpreter.invokeInterpretedFunction(
              values[1] as InterpretedFunction,
              [],
            ),
          );
          final received = remote.first;
          detached.add([3]);
          await detached.flush();
          expect(await received.timeout(const Duration(seconds: 3)), [3]);
        } finally {
          detached?.destroy();
          remote?.destroy();
          client?.close(force: true);
          await server.close(force: true);
          await subscription.cancel();
        }
      },
    );

    test(
      'proxy callback checks all alternatives, replacement, reset and environment',
      () async {
        final origin = await _Peer.bind();
        final proxy = await _Peer.bind();
        final forbidden = await _Peer.bind();
        final interpreter = _interpreter([
          NetworkPermission.connectToPort(_host, origin.port),
        ]);
        String body(String rule) =>
            '''
        final client = HttpClient(); try {
          client.findProxy = (uri) => '$rule';
          final request = await client.getUrl(Uri.parse('${origin.url()}'));
          return (await request.close()).statusCode;
        } finally { client.close(force: true); }
      ''';
        try {
          for (final rule in [
            'PROXY $_host:${forbidden.port}',
            'DIRECT; PROXY $_host:${forbidden.port}',
          ]) {
            await expectLater(_run(interpreter, body(rule)), throwsA(_denied));
          }
          for (final rule in [
            '',
            'DIRECT;',
            'SOCKS $_host:80',
            'PROXY $_host',
            'PROXY $_host:0',
            'PROXY $_host:65536',
            'PROXY $_host:no',
            'PROXY [::1:80',
            'PROXY user:pass@$_host:80',
            'DIRECT; invalid',
          ]) {
            await expectLater(
              _run(interpreter, body(rule)),
              throwsA(
                isA<RuntimeError>().having(
                  (e) => e.message,
                  'proxy rule',
                  contains('proxy'),
                ),
              ),
            );
          }
          expect(origin.connections, 0);
          expect(forbidden.connections, 0);
          expect(await _run(interpreter, body(' DIRECT ')), 200);
          interpreter.grant(NetworkPermission.connectToPort(_host, proxy.port));
          expect(
            await _run(interpreter, body('PROXY $_host:${proxy.port}; DIRECT')),
            200,
          );
          expect(proxy.requests.single.host, _host);
          expect(proxy.requests.single.port, origin.port);
          expect(
            await _run(interpreter, '''
          final client = HttpClient(); try {
            client.findProxy = (uri) => 'PROXY $_host:${forbidden.port}';
            client.findProxy = (uri) => 'DIRECT';
            await (await client.getUrl(Uri.parse('${origin.url()}'))).close();
            client.findProxy = (uri) => 'PROXY $_host:${forbidden.port}';
            client.findProxy = null;
            return (await (await client.getUrl(Uri.parse('${origin.url()}'))).close()).statusCode;
          } finally { client.close(force: true); }
        '''),
            200,
          );
          await expectLater(
            _run(interpreter, '''
          return HttpClient.findProxyFromEnvironment(Uri.parse('${origin.url()}'),
            environment: <String, String>{'http_proxy': '$_host:${forbidden.port}'});
        '''),
            throwsA(_denied),
          );
          expect(
            await _run(interpreter, '''
          return HttpClient.findProxyFromEnvironment(Uri.parse('${origin.url()}'),
            environment: <String, String>{'http_proxy': '$_host:${proxy.port}'});
        '''),
            'PROXY $_host:${proxy.port}',
          );
          await Future<void>.delayed(_settle);
          expect(forbidden.connections, 0);
        } finally {
          await origin.close();
          await proxy.close();
          await forbidden.close();
        }
      },
    );
  });
}
