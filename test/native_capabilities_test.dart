import 'dart:async';
import 'dart:isolate';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

// The public invokeInterpretedFunction API wraps synchronous errors in strings.
final _denied = anyOf(
  isA<RuntimeError>().having(
    (error) => error.message,
    'explicit authority',
    contains('Permission'),
  ),
  isA<String>().having(
    (error) => error,
    'wrapped native denial',
    allOf(contains('Native operation requires'), contains('Permission')),
  ),
);

D4rt _interpreter(Iterable<Permission> permissions) {
  final interpreter = D4rt();
  for (final permission in permissions) {
    interpreter.grant(permission);
  }
  return interpreter;
}

Future<dynamic> _run(
  D4rt interpreter,
  String source, [
  List<Object?> args = const [],
]) => Future.sync(
  () => interpreter.execute(source: source, positionalArgs: args),
).timeout(const Duration(seconds: 20));

T _native<T>(dynamic value) =>
    (value is BridgedInstance ? value.nativeObject : value) as T;

void main() {
  group('Native permission identity', () {
    test('dangerous grants are independent, revocable and covered by any', () {
      final grants = [
        DangerousPermission.processExecution,
        DangerousPermission.processSignals,
        DangerousPermission.developerTools,
        DangerousPermission.codeEvaluation,
        DangerousPermission.nativePlugins,
      ];
      final operations = [
        'process execution',
        'process signals',
        'developer tools',
        'code evaluation',
        'native plugins',
      ];
      expect(grants.toSet().length, grants.length);
      for (var i = 0; i < grants.length; i++) {
        final interpreter = _interpreter([grants[i]]);
        for (var j = 0; j < operations.length; j++) {
          final operation = {'type': 'dangerous', 'operation': operations[j]};
          expect(interpreter.checkPermission(operation), i == j);
          expect(DangerousPermission.any.allows(operation), isTrue);
        }
        interpreter.revoke(grants[i]);
        expect(
          interpreter.checkPermission({
            'type': 'dangerous',
            'operation': operations[i],
          }),
          isFalse,
        );
      }
    });

    test('only unrestricted process grant authorizes shell', () {
      final operation = {
        'type': 'process',
        'command': 'tool',
        'args': <String>[],
        'shell': true,
      };
      expect(ProcessRunPermission.any.isUnrestricted, isTrue);
      expect(ProcessRunPermission.any.allows(operation), isTrue);
      for (final grant in [
        ProcessRunPermission.command('tool'),
        ProcessRunPermission.commandWithArgs('tool', []),
      ]) {
        expect(grant.isUnrestricted, isFalse);
        expect(grant.allows(operation), isFalse);
      }
    });
  });

  group('Isolate operation authority', () {
    test(
      'spawn-only cannot construct or send through host communication ports',
      () async {
        final receive = ReceivePort();
        final raw = RawReceivePort();
        final interpreter = _interpreter([IsolatePermission.spawn]);
        try {
          for (final body in [
            "ReceivePort();",
            "RawReceivePort();",
            "port.send('forbidden');",
            'raw.sendPort;',
            'raw.keepIsolateAlive = false;',
            'raw.handler = (value) {};',
            'ReceivePort.fromRawReceivePort(raw);',
            'receive.listen((value) {});',
            'receive.first;',
            'Isolate.current.controlPort;',
            'Isolate.current.ping(port);',
            'Isolate.current.addOnExitListener(port);',
            'Isolate.current.addErrorListener(port);',
            'Isolate.current.removeOnExitListener(port);',
            'Isolate.current.removeErrorListener(port);',
          ]) {
            await expectLater(
              _run(
                interpreter,
                '''
            import 'dart:isolate'; main(port, raw, receive) { $body }
          ''',
                [receive.sendPort, raw, receive],
              ),
              throwsA(_denied),
            );
          }
        } finally {
          raw.close();
          receive.close();
        }
      },
    );

    test(
      'communication is rechecked on saved send and retained raw access',
      () async {
        final receive = ReceivePort();
        final raw = RawReceivePort();
        final interpreter = _interpreter([
          IsolatePermission.spawn,
          IsolatePermission.communicate,
        ]);
        try {
          final closures =
              interpreter.execute(
                    source: '''
          import 'dart:isolate'; main(port, raw, receive) {
            final send = port.send;
            final listen = receive.listen;
            return [() => send('forbidden'), () => raw.sendPort,
              () { raw.handler = (value) {}; }, () { raw.keepIsolateAlive = false; },
              () => listen((value) {}), () => receive.first];
          }
        ''',
                    positionalArgs: [receive.sendPort, raw, receive],
                  )
                  as List;
          interpreter.revoke(IsolatePermission.communicate);
          for (final closure in closures) {
            expect(
              () => interpreter.invokeInterpretedFunction(
                closure as InterpretedFunction,
                [],
              ),
              throwsA(_denied),
            );
          }
        } finally {
          raw.close();
          receive.close();
        }
      },
    );

    test(
      'spawnUri requires code evaluation; spawn remains unsupported',
      () async {
        final interpreter = _interpreter([IsolatePermission.spawn]);
        await expectLater(
          _run(interpreter, '''
        import 'dart:isolate'; main() => Isolate.spawnUri(Uri.parse('file:///missing.dart'), [], null);
      '''),
          throwsA(_denied),
        );
        await expectLater(
          _run(interpreter, '''
        import 'dart:isolate'; main() => Isolate.spawn((value) {}, null);
      '''),
          throwsA(
            isA<RuntimeError>().having(
              (e) => e.message,
              'unsupported',
              contains('not fully implemented'),
            ),
          ),
        );
      },
    );

    for (final body in [
      'return StreamIterator(receive);',
      'return transformer.bind(receive);',
      'return Stream.castFrom(receive);',
      'return Stream.eventTransformed(receive, (sink) => sink);',
      'return await controller.addStream(receive);',
      'await for (final value in receive) {}',
      'await for (final (a, b) in receive) {}',
      'return StreamTransformer.fromBind((source) => receive).bind(Stream.empty());',
      'return await Stream.value(1).asyncExpand((value) => receive).first;',
    ]) {
      test('receive-port source admission: $body', () async {
        final receive = ReceivePort();
        final controller = StreamController<Object?>();
        final subscription = controller.stream.listen((_) {});
        final interpreter = _interpreter([
          IsolatePermission.spawn,
          IsolatePermission.communicate,
        ]);
        try {
          final closure =
              interpreter.execute(
                    source:
                        '''
            import 'dart:async'; import 'dart:isolate';
            main(receive, transformer, controller) {
              return () async { $body };
            }
          ''',
                    positionalArgs: [
                      receive,
                      StreamTransformer<Object?, Object?>.fromHandlers(),
                      controller,
                    ],
                  )
                  as InterpretedFunction;
          interpreter.revoke(IsolatePermission.communicate);
          await expectLater(
            Future.sync(
              () => interpreter.invokeInterpretedFunction(closure, []),
            ),
            throwsA(_denied),
          );
          // A forbidden source admission must not have subscribed to the port.
          final message = receive.first;
          receive.sendPort.send('still-owned');
          expect(
            await message.timeout(const Duration(seconds: 3)),
            'still-owned',
          );
        } finally {
          receive.close();
          await controller.close();
          await subscription.cancel();
        }
      });
    }

    test(
      'ordinary stream sources do not require communication authority',
      () async {
        expect(
          await _run(_interpreter([IsolatePermission.spawn]), '''
        import 'dart:async'; import 'dart:isolate'; main() async {
          final iterator = StreamIterator(Stream.fromIterable([1, 2]));
          final moved = await iterator.moveNext();
          final first = iterator.current;
          await iterator.cancel();
          final transformed = StreamTransformer.fromHandlers().bind(Stream.value(7));
          return [moved, first, await transformed.first];
        }
      '''),
          [true, 1, 7],
        );
      },
    );
  });

  group('Developer operation authority', () {
    for (final uri in [
      'dart:developer',
      'dart:developer?audit=1',
      'dart:developer#audit',
    ]) {
      test('import $uri denies before use', () {
        expect(
          () => D4rt().execute(source: "import '$uri'; main() => 17;"),
          throwsA(_denied),
        );
        expect(
          _interpreter([
            DangerousPermission.developerTools,
          ]).execute(source: "import '$uri'; main() => inspect(17);"),
          17,
        );
      });
    }

    test(
      'saved functions, members, getters, constructors and constants revoke',
      () {
        final interpreter = _interpreter([DangerousPermission.developerTools]);
        final closures =
            interpreter.execute(
                  source: '''
        import 'dart:developer'; main() {
          final inspectSaved = inspect;
          final timeline = Timeline.timeSync;
          final tag = UserTag('m05-revoke');
          final current = tag.makeCurrent;
          final task = TimelineTask();
          final instant = task.instant;
          final flow = Flow.begin();
          final response = ServiceExtensionResponse.result('{}');
          return [() => inspectSaved(17), () => log('forbidden'),
            () => debugger(when: false), () => postEvent('m05', {}),
            () => registerExtension('ext.m05.denied', (method, args) => response),
            () => timeline('forbidden', () => 1), () => Timeline.now,
            () => current(), () => tag.label, () => UserTag.defaultTag,
            () => tag.hashCode, () => tag.runtimeType,
            () => UserTag('forbidden'), () => TimelineTask(),
            () => instant('forbidden'), () => flow.id, () => Flow.begin(),
            () => Flow.step(1), () => Flow.end(1),
            () => response.result, () => ServiceExtensionResponse.invalidParams,
            () => ServiceExtensionResponse.result('{}'),
            () => ServiceExtensionResponse.error(-32602, 'forbidden'),
            () => Service.getInfo()];
        }
      ''',
                )
                as List;
        interpreter.revoke(DangerousPermission.developerTools);
        for (final closure in closures) {
          expect(
            () => interpreter.invokeInterpretedFunction(
              closure as InterpretedFunction,
              [],
            ),
            throwsA(_denied),
          );
        }
        expect(
          () => interpreter.execute(
            source: "import 'dart:developer'; main() => 17;",
          ),
          throwsA(_denied),
        );
      },
    );
  });

  group('Converter receive-port source admission', () {
    for (final converter in ['JsonEncoder()', 'JsonEncoder().cast()']) {
      for (final revoked in [false, true]) {
        test(
          '$converter ${revoked ? "revoked" : "spawn-only"} remains unsubscribed',
          () async {
            final receive = ReceivePort();
            final host = _interpreter([
              IsolatePermission.spawn,
              if (revoked) IsolatePermission.communicate,
            ]);
            try {
              final closure =
                  host.execute(
                        source:
                            '''
              import 'dart:convert'; import 'dart:isolate';
              main(source) {
                final bind = $converter.bind;
                return () => bind(source).first;
              }
            ''',
                        positionalArgs: [receive],
                      )
                      as InterpretedFunction;
              if (revoked) host.revoke(IsolatePermission.communicate);
              await expectLater(
                Future.sync(
                  () => host.invokeInterpretedFunction(closure, []),
                ).timeout(const Duration(seconds: 5)),
                throwsA(_denied),
              );
              final message = receive.first;
              receive.sendPort.send('not-consumed');
              expect(
                await message.timeout(const Duration(seconds: 3)),
                'not-consumed',
              );
            } finally {
              receive.close();
            }
          },
        );
      }

      test(
        '$converter permits granted delivery and ordinary streams',
        () async {
          final receive = ReceivePort();
          StreamSubscription<String>? subscription;
          try {
            final host = _interpreter([IsolatePermission.communicate]);
            final stream = _native<Stream<String>>(
              await _run(
                host,
                '''
              import 'dart:convert'; import 'dart:isolate';
              main(source) => $converter.bind(source);
            ''',
                [receive],
              ),
            );
            final output = StringBuffer();
            final done = Completer<String>();
            subscription = stream.listen(
              (chunk) {
                output.write(chunk);
                if (output.toString() == '{"value":7}') receive.close();
              },
              onError: done.completeError,
              onDone: () => done.complete(output.toString()),
            );
            receive.sendPort.send({'value': 7});
            expect(
              await done.future.timeout(const Duration(seconds: 5)),
              '{"value":7}',
            );
            expect(
              await _run(_interpreter([IsolatePermission.spawn]), '''
            import 'dart:async'; import 'dart:convert';
            main() => $converter.bind(Stream.value({'value': 8})).join();
          '''),
              '{"value":8}',
            );
          } finally {
            receive.close();
            await subscription?.cancel();
          }
        },
      );
    }
  });

  group('Generator receive-port delegation', () {
    const source = '''
      import 'dart:async'; import 'dart:isolate';
      int finalizers = 0;
      Stream forward(source, done) async* {
        try { yield* source; }
        finally { finalizers++; done.complete(finalizers); }
      }
      main(source, done) => [
        () => forward(source, done).first,
        () => finalizers,
      ];
    ''';
    for (final revoked in [false, true]) {
      test(
        '${revoked ? "revoked" : "spawn-only"} delegation denies before subscription',
        () async {
          final receive = ReceivePort();
          final finalized = Completer<int>();
          final host = _interpreter([
            IsolatePermission.spawn,
            if (revoked) IsolatePermission.communicate,
          ]);
          try {
            final entries =
                host.execute(
                      source: source,
                      positionalArgs: [receive, finalized],
                    )
                    as List;
            if (revoked) host.revoke(IsolatePermission.communicate);
            await expectLater(
              Future.sync(
                () => host.invokeInterpretedFunction(
                  entries[0] as InterpretedFunction,
                  [],
                ),
              ).timeout(const Duration(seconds: 5)),
              throwsA(_denied),
            );
            expect(
              await finalized.future.timeout(const Duration(seconds: 3)),
              1,
            );
            expect(
              host.invokeInterpretedFunction(
                entries[1] as InterpretedFunction,
                [],
              ),
              1,
            );
            final message = receive.first;
            receive.sendPort.send('not-delegated');
            expect(
              await message.timeout(const Duration(seconds: 3)),
              'not-delegated',
            );
          } finally {
            receive.close();
          }
        },
      );
    }

    test(
      'authorized delegation delivers and cancellation finalizes once',
      () async {
        final receive = ReceivePort();
        final finalized = Completer<int>();
        final host = _interpreter([IsolatePermission.communicate]);
        try {
          final entries =
              host.execute(source: source, positionalArgs: [receive, finalized])
                  as List;
          final result = Future.sync(
            () => host.invokeInterpretedFunction(
              entries[0] as InterpretedFunction,
              [],
            ),
          );
          receive.sendPort.send('delegated');
          expect(await result.timeout(const Duration(seconds: 5)), 'delegated');
          expect(await finalized.future.timeout(const Duration(seconds: 3)), 1);
          expect(
            host.invokeInterpretedFunction(
              entries[1] as InterpretedFunction,
              [],
            ),
            1,
          );
        } finally {
          receive.close();
        }
      },
    );

    test('ordinary delegated streams require no communication grant', () async {
      final finalized = Completer<int>();
      final host = _interpreter([]);
      final entries =
          host.execute(
                source: source.replaceAll("import 'dart:isolate';", ''),
                positionalArgs: [Stream.value('ordinary'), finalized],
              )
              as List;
      expect(
        await Future.sync(
          () => host.invokeInterpretedFunction(
            entries[0] as InterpretedFunction,
            [],
          ),
        ).timeout(const Duration(seconds: 5)),
        'ordinary',
      );
      expect(await finalized.future.timeout(const Duration(seconds: 3)), 1);
      expect(
        host.invokeInterpretedFunction(entries[1] as InterpretedFunction, []),
        1,
      );
    });
  });
}
