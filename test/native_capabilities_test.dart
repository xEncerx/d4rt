import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/stdlib/developer.dart';
import 'package:d4rt/src/stdlib/isolate/isolate.dart';
import 'package:d4rt/src/stdlib/io/process.dart';
import 'package:d4rt/src/module_loader.dart';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;

final _executable = Platform.resolvedExecutable;
final _fixture = File('test/fixtures/native_process.dart').absolute.path;
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

int _compute() => 42;
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

Future<Process> _child() async {
  final child = await Process.start(_executable, [_fixture, 'wait']);
  await child.stdout
      .transform(utf8.decoder)
      .first
      .timeout(const Duration(seconds: 10));
  return child;
}

class _ChangingText {
  final String first;
  int calls = 0;
  _ChangingText(this.first);
  @override
  String toString() => calls++ == 0 ? first : 'unauthorized-second-conversion';
}

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

  group('Process operation authority', () {
    for (final method in ['start', 'run', 'runSync']) {
      test(
        '$method authorizes exact launch and denies each missing grant',
        () async {
          final directory = Directory.systemTemp.createTempSync('m05-launch-');
          final marker = File('${directory.path}/marker');
          final args = [_fixture, 'mark', marker.path, 'a', 'b'];
          final source =
              '''
          import 'dart:io';
          main(executable, arguments) async {
            final result = ${method == 'runSync' ? '' : 'await '}Process.$method(executable, arguments);
            return ${method == 'start' ? 'await result.exitCode' : 'result.exitCode'};
          }
        ''';
          final scope = ProcessRunPermission.commandWithArgs(_executable, args);
          try {
            for (final grants in [
              <Permission>[scope],
              <Permission>[DangerousPermission.processExecution],
              <Permission>[
                DangerousPermission.processExecution,
                ProcessRunPermission.commandWithArgs(_executable, [
                  ...args.reversed,
                ]),
              ],
              <Permission>[
                DangerousPermission.processExecution,
                ProcessRunPermission.commandWithArgs('dart', args),
              ],
            ]) {
              final interpreter = _interpreter([
                FilesystemPermission.any,
                ...grants,
              ]);
              await expectLater(
                _run(interpreter, source, [_executable, args]),
                throwsA(_denied),
              );
              expect(marker.existsSync(), isFalse);
            }
            final interpreter = _interpreter([
              FilesystemPermission.any,
              scope,
              DangerousPermission.processExecution,
            ]);
            expect(await _run(interpreter, source, [_executable, args]), 0);
            expect(marker.readAsStringSync(), 'launched');
            marker.deleteSync();
            interpreter.revoke(
              ProcessRunPermission.commandWithArgs(_executable, args),
            );
            await expectLater(
              _run(interpreter, source, [_executable, args]),
              throwsA(_denied),
            );
            expect(marker.existsSync(), isFalse);
          } finally {
            directory.deleteSync(recursive: true);
          }
        },
      );
    }

    for (final method in ['start', 'run', 'runSync']) {
      test(
        '$method snapshots stateful conversions once and anchors relative cwd',
        () async {
          final directory = Directory.systemTemp.createTempSync(
            'm05-normalize-',
          );
          final executable = _ChangingText(
            p.relative(_executable, from: directory.path),
          );
          final argument = _ChangingText('once');
          final cwd = _ChangingText(directory.path);
          final args = [_fixture, 'echo', 'once'];
          final interpreter = _interpreter([
            FilesystemPermission.any,
            ProcessRunPermission.commandWithArgs(_executable, args),
            DangerousPermission.processExecution,
          ]);
          try {
            final result = await _run(
              interpreter,
              '''
            import 'dart:io'; import 'dart:convert';
            main(executable, fixture, argument, cwd) async {
              final result = ${method == 'runSync' ? '' : 'await '}Process.$method(
                  executable, [fixture, 'echo', argument], workingDirectory: cwd);
              return ${method == 'start' ? '[await result.exitCode, (await result.stdout.transform(utf8.decoder).join()).trim()]' : '[result.exitCode, result.stdout.trim()]'};
            }
          ''',
              [executable, _fixture, argument, cwd],
            );
            expect(result, [0, 'once']);
            expect([executable.calls, argument.calls, cwd.calls], [1, 1, 1]);
          } finally {
            directory.deleteSync(recursive: true);
          }
        },
      );
    }

    test(
      'shell requires unrestricted command and native execution separately',
      () async {
        const source = '''
        import 'dart:io';
        main(executable, arguments) async {
          final result = await Process.run(executable, arguments, runInShell: true);
          return [result.exitCode, result.stdout.trim()];
        }
      ''';
        final args = [_fixture, 'echo', 'shell'];
        for (final grants in [
          <Permission>[
            ProcessRunPermission.commandWithArgs(_executable, args),
            DangerousPermission.processExecution,
          ],
          <Permission>[
            ProcessRunPermission.command(_executable),
            DangerousPermission.processExecution,
          ],
          <Permission>[ProcessRunPermission.any],
          <Permission>[DangerousPermission.processExecution],
        ]) {
          await expectLater(
            _run(_interpreter([FilesystemPermission.any, ...grants]), source, [
              _executable,
              args,
            ]),
            throwsA(_denied),
          );
        }
        expect(
          await _run(
            _interpreter([
              FilesystemPermission.any,
              ProcessRunPermission.any,
              DangerousPermission.processExecution,
            ]),
            source,
            [_executable, args],
          ),
          [0, 'shell'],
        );
      },
    );

    for (final method in ['kill', 'killPid']) {
      test(
        '$method checks acquired tearoff after revocation and owned child survives',
        () async {
          final child = await _child();
          final interpreter = _interpreter([
            FilesystemPermission.any,
            ProcessRunPermission.command(_executable),
            DangerousPermission.processExecution,
            DangerousPermission.processSignals,
          ]);
          try {
            final closure =
                interpreter.execute(
                      source:
                          '''
            import 'dart:io';
            main(child) {
              final terminate = ${method == 'kill' ? 'child.kill' : 'Process.killPid'};
              return () => terminate(${method == 'kill' ? 'ProcessSignal.sigterm' : 'child.pid, ProcessSignal.sigterm'});
            }
          ''',
                      positionalArgs: [child],
                    )
                    as InterpretedFunction;
            interpreter.revoke(DangerousPermission.processSignals);
            await expectLater(
              Future.sync(
                () => interpreter.invokeInterpretedFunction(closure, []),
              ),
              throwsA(_denied),
            );
            interpreter.grant(DangerousPermission.processSignals);
            expect(interpreter.invokeInterpretedFunction(closure, []), isTrue);
            await child.exitCode.timeout(const Duration(seconds: 10));
          } finally {
            child.kill();
            await child.exitCode;
          }
        },
      );
    }

    test('signal watch checks saved method after revoke', () async {
      final interpreter = _interpreter([
        FilesystemPermission.any,
        DangerousPermission.processSignals,
      ]);
      final closure =
          interpreter.execute(
                source: '''
        import 'dart:io'; main() {
          final watch = ProcessSignal.sigint.watch;
          return () => watch();
        }
      ''',
              )
              as InterpretedFunction;
      final stream = _native<Stream<ProcessSignal>>(
        interpreter.invokeInterpretedFunction(closure, []),
      );
      final subscription = stream.listen((_) {});
      await subscription.cancel();
      interpreter.revoke(DangerousPermission.processSignals);
      expect(
        () => interpreter.invokeInterpretedFunction(closure, []),
        throwsA(_denied),
      );
    });

    test(
      'saved process launch rechecks native execution and explicit empty args',
      () async {
        final interpreter = _interpreter([
          FilesystemPermission.any,
          ProcessRunPermission.commandWithArgs(_executable, []),
          DangerousPermission.processExecution,
        ]);
        final closure =
            interpreter.execute(
                  source: '''
        import 'dart:io'; main() {
          final run = Process.runSync;
          return (executable) => run(executable, []).pid > 0;
        }
      ''',
                )
                as InterpretedFunction;
        expect(
          interpreter.invokeInterpretedFunction(closure, [_executable]),
          isTrue,
        );
        interpreter.revoke(DangerousPermission.processExecution);
        expect(
          () => interpreter.invokeInterpretedFunction(closure, [_executable]),
          throwsA(_denied),
        );
      },
    );
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

    test('communication-only sends but cannot control or execute', () async {
      final receive = ReceivePort();
      final interpreter = _interpreter([IsolatePermission.communicate]);
      final child = await Isolate.spawnUri(
        File('test/fixtures/native_isolate.dart').absolute.uri,
        [],
        null,
      );
      try {
        final message = receive.first;
        await _run(
          interpreter,
          '''
          import 'dart:isolate'; main(port) { port.send('delivered'); }
        ''',
          [receive.sendPort],
        );
        expect(await message.timeout(const Duration(seconds: 3)), 'delivered');
        for (final body in [
          'Isolate.current;',
          'isolate.pause();',
          'isolate.resume(capability);',
          'isolate.kill();',
          'isolate.setErrorsFatal(false);',
          'isolate.pauseCapability;',
          'isolate.terminateCapability;',
          'isolate.controlPort;',
          'isolate.errors;',
          'Isolate.run(() => 1);',
          'Isolate.spawn((value) {}, null);',
          "Isolate.spawnUri(Uri.parse('file:///missing.dart'), [], null);",
        ]) {
          await expectLater(
            _run(
              interpreter,
              '''
            import 'dart:isolate'; main(isolate, capability) { $body }
          ''',
              [child, Capability()],
            ),
            throwsA(_denied),
          );
        }
      } finally {
        child.kill(priority: Isolate.immediate);
        receive.close();
      }
    });

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

  group('Owned isolate execution and control', () {
    test('run executes native computation only with spawn authority', () async {
      const source =
          "import 'dart:isolate'; main(compute) => Isolate.run(compute);";
      expect(
        await _run(_interpreter([IsolatePermission.spawn]), source, [_compute]),
        42,
      );
      await expectLater(
        _run(_interpreter([IsolatePermission.communicate]), source, [_compute]),
        throwsA(_denied),
      );
    });

    test(
      'spawnUri composes grants and retained control rechecks revocation',
      () async {
        final receive = ReceivePort();
        final interpreter = _interpreter([
          IsolatePermission.spawn,
          IsolatePermission.communicate,
          DangerousPermission.codeEvaluation,
        ]);
        Isolate? child;
        try {
          final message = receive.first;
          final uri = File('test/fixtures/native_isolate.dart').absolute.uri;
          const source = '''
          import 'dart:isolate'; main(uri, port) => Isolate.spawnUri(uri, ['native'], port);
        ''';
          child = _native<Isolate>(
            await _run(interpreter, source, [uri, receive.sendPort]),
          );
          final received =
              await message.timeout(const Duration(seconds: 10)) as List;
          expect(received[0], ['native']);
          expect(received[1], isA<SendPort>());
          final controls =
              interpreter.execute(
                    source: '''
          import 'dart:isolate'; main(child) {
            final kill = child.kill;
            final pause = child.pause;
            return [() => kill(), () => pause(), () => child.pauseCapability,
              () => child.terminateCapability, () => child.controlPort];
          }
        ''',
                    positionalArgs: [child],
                  )
                  as List;
          interpreter.revoke(IsolatePermission.spawn);
          for (final closure in controls) {
            expect(
              () => interpreter.invokeInterpretedFunction(
                closure as InterpretedFunction,
                [],
              ),
              throwsA(_denied),
            );
          }
          interpreter.grant(IsolatePermission.spawn);
          interpreter.revoke(IsolatePermission.communicate);
          await expectLater(
            _run(interpreter, source, [uri, receive.sendPort]),
            throwsA(_denied),
          );
          interpreter.grant(IsolatePermission.communicate);
          interpreter.revoke(DangerousPermission.codeEvaluation);
          await expectLater(
            _run(interpreter, source, [uri, receive.sendPort]),
            throwsA(_denied),
          );
          // Native ownership permits cleanup even after interpreted revocation.
          (received[1] as SendPort).send('close');
        } finally {
          child?.kill(priority: Isolate.immediate);
          receive.close();
        }
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

    test(
      'registered extension rechecks before async handler invocation',
      () async {
        final original = await developer.Service.getInfo();
        final started = original.serverUri == null;
        final info = started
            ? await developer.Service.controlWebServer(
                enable: true,
                silenceOutput: true,
              )
            : original;
        final client = HttpClient();
        final method = 'ext.d4rt.m05_${DateTime.now().microsecondsSinceEpoch}';
        final interpreter = _interpreter([DangerousPermission.developerTools]);
        try {
          final calls =
              interpreter.execute(
                    source: '''
          import 'dart:developer';
          main(method) {
            var calls = 0;
            registerExtension(method, (method, parameters) async {
              calls++;
              if (parameters['fail'] == 'yes') throw StateError('handler-failure');
              return ServiceExtensionResponse.result('{"status":"ok"}');
            });
            return () => calls;
          }
        ''',
                    positionalArgs: [method],
                  )
                  as InterpretedFunction;
          Future<Map<String, dynamic>> invoke({bool fail = false}) async {
            final uri = info.serverUri!
                .resolve(method)
                .replace(
                  queryParameters: {
                    'isolateId': developer.Service.getIsolateId(
                      Isolate.current,
                    )!,
                    if (fail) 'fail': 'yes',
                  },
                );
            final response = await (await client.getUrl(uri)).close();
            return jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;
          }

          expect((await invoke())['result'], containsPair('status', 'ok'));
          expect(interpreter.invokeInterpretedFunction(calls, []), 1);
          interpreter.revoke(DangerousPermission.developerTools);
          expect((await invoke())['error'], isNotNull);
          expect(interpreter.invokeInterpretedFunction(calls, []), 1);
          interpreter.grant(DangerousPermission.developerTools);
          expect((await invoke(fail: true))['error'], isNotNull);
          expect(interpreter.invokeInterpretedFunction(calls, []), 2);
        } finally {
          client.close(force: true);
          if (started) {
            await developer.Service.controlWebServer(
              enable: false,
              silenceOutput: true,
            );
          }
        }
      },
      timeout: const Timeout(Duration(seconds: 40)),
    );

    test('nullable adapter visitor fails closed for host-supplied objects', () {
      final entries = <(BridgedClass, Object, String)>[
        (UserTagDeveloper.definition, developer.UserTag('m05-host'), 'label'),
        (FlowDeveloper.definition, developer.Flow.begin(), 'id'),
        (
          TimelineTaskDeveloper.definition,
          developer.TimelineTask(),
          'hashCode',
        ),
        (
          ServiceExtensionResponseDeveloper.definition,
          developer.ServiceExtensionResponse.result('{}'),
          'result',
        ),
      ];
      for (final (bridge, object, getter) in entries) {
        expect(() => bridge.getters[getter]!(null, object), throwsA(_denied));
      }
      final raw = RawReceivePort();
      try {
        expect(
          () =>
              RawReceivePortIsolate.definition.getters['sendPort']!(null, raw),
          throwsA(_denied),
        );
        expect(
          () => RawReceivePortIsolate.definition.setters['handler']!(
            null,
            raw,
            null,
          ),
          throwsA(_denied),
        );
      } finally {
        raw.close();
      }
    });

    test('missing owning interpreter denies module and operation access', () {
      final environment = Environment();
      final loader = ModuleLoader(environment, {}, [], []);
      final visitor = InterpreterVisitor(
        globalEnvironment: environment,
        moduleLoader: loader,
      );
      for (final uri in ['dart:io', 'dart:isolate', 'dart:developer?audit=1']) {
        expect(() => loader.loadModule(Uri.parse(uri)), throwsA(_denied));
      }
      expect(
        () => ProcessIo.definition.staticMethods['runSync']!(visitor, [
          _executable,
          [_fixture, 'echo'],
        ], {}),
        throwsA(_denied),
      );
      expect(
        () => IsolateIsolate.definition.staticGetters['current']!(visitor),
        throwsA(_denied),
      );
      expect(
        () => TimelineDeveloper.definition.staticGetters['now']!(visitor),
        throwsA(_denied),
      );
    });
  });

  group('Implicit Windows batch authority', () {
    for (final method in ['start', 'run', 'runSync']) {
      for (final extension in ['cmd', 'BAT']) {
        for (final form in ['absolute', 'relative', 'bare']) {
          for (final option in ['', ', runInShell: false']) {
            test(
              '$method .$extension $form ${option.isEmpty ? "default" : "explicit false"}',
              () async {
                final directory = Directory.systemTemp.createTempSync(
                  'm05-batch-',
                );
                final batch = File(
                  p.join(
                    Directory.current.path,
                    'm05_owned_${p.basename(directory.path)}.$extension',
                  ),
                );
                final marker = File(p.join(directory.path, 'marker'));
                try {
                  File('test/fixtures/native_batch.cmd').copySync(batch.path);
                  final executable = switch (form) {
                    'absolute' => batch.path,
                    'relative' => '.${p.separator}${p.basename(batch.path)}',
                    _ => p.basename(batch.path),
                  };
                  final args = [marker.path];
                  final source =
                      '''
                  import 'dart:io'; main(executable, args) async {
                    final result = ${method == 'runSync' ? '' : 'await '}Process.$method(
                        executable, args$option);
                    return ${method == 'start' ? 'await result.exitCode' : 'result.exitCode'};
                  }
                ''';
                  for (final grants in [
                    <Permission>[
                      ProcessRunPermission.commandWithArgs(executable, args),
                      DangerousPermission.processExecution,
                    ],
                    <Permission>[
                      ProcessRunPermission.command(executable),
                      DangerousPermission.processExecution,
                    ],
                    <Permission>[ProcessRunPermission.any],
                    <Permission>[DangerousPermission.processExecution],
                  ]) {
                    await expectLater(
                      _run(
                        _interpreter([FilesystemPermission.any, ...grants]),
                        source,
                        [executable, args],
                      ),
                      throwsA(_denied),
                    );
                    expect(marker.existsSync(), isFalse);
                  }
                  final host = _interpreter([
                    FilesystemPermission.any,
                    ProcessRunPermission.any,
                    DangerousPermission.processExecution,
                  ]);
                  expect(await _run(host, source, [executable, args]), 0);
                  expect(marker.readAsStringSync().trim(), 'launched');
                  marker.deleteSync();
                  host.revoke(ProcessRunPermission.any);
                  await expectLater(
                    _run(host, source, [executable, args]),
                    throwsA(_denied),
                  );
                  expect(marker.existsSync(), isFalse);
                } finally {
                  if (batch.existsSync()) batch.deleteSync();
                  directory.deleteSync(recursive: true);
                }
              },
            );
          }
        }
      }
    }
  }, skip: !Platform.isWindows);

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
