import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;

import 'filesystem_scopes.dart' as checks;

String q(String value) => jsonEncode(value);

dynamic run(D4rt host, String body) => host.execute(
  source:
      '''
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
dynamic main() $body
''',
);

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    checks.require(args.single == '--child', 'known child mode');
    await childScenarios();
    return;
  }
  // Even a regression which redirects an empty recursive delete to cwd can
  // only affect this disposable child working directory, never the checkout.
  final root = Directory.systemTemp.createTempSync('d4rt_filesystem_paths_');
  try {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      Platform.script.toFilePath(),
      '--child',
    ], workingDirectory: root.path);
    checks.require(result.exitCode == 0, '${result.stdout}\n${result.stderr}');
    stdout.write(result.stdout);
    print('FILESYSTEM_PATHS_PASS');
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<void> childScenarios() async {
  final original = Directory.current;
  // A second disposable directory also protects standalone --child execution.
  final sandbox = Directory.systemTemp.createTempSync('d4rt_empty_paths_');
  try {
    Directory.current = sandbox;
    final data = File('data')..writeAsStringSync('sentinel');
    final directory = Directory('directory')..createSync();
    File(p.join(directory.path, 'nested')).writeAsStringSync('nested sentinel');
    final link = Link('link')..createSync('data');
    final host = checks.interpreter([FilesystemPermission.any]);
    final initialEntries = sandbox
        .listSync(recursive: true, followLinks: false)
        .map((entry) => entry.path)
        .toSet();

    void unchanged(String label) {
      checks.require(
        Directory.current.path == sandbox.path &&
            data.readAsStringSync() == 'sentinel' &&
            File(p.join(directory.path, 'nested')).readAsStringSync() ==
                'nested sentinel' &&
            link.targetSync() == 'data',
        '$label preserves cwd, contents and link target',
      );
      final entries = sandbox
          .listSync(recursive: true, followLinks: false)
          .map((entry) => entry.path)
          .toSet();
      checks.require(
        entries.length == initialEntries.length &&
            entries.containsAll(initialEntries),
        '$label creates, deletes or renames no entries',
      );
    }

    Future<void> denied(String expression) async {
      await checks.expectDenied(() async {
        final result = await run(host, '=> $expression;');
        // Exercise stream entrypoints through subscription too if a regression
        // defers validation instead of rejecting at issuance.
        return result is Stream ? await result.toList() : result;
      }, expression);
      unchanged(expression);
    }

    for (final kind in ['File', 'Directory', 'Link']) {
      final methods = [
        'exists()',
        'existsSync()',
        'stat()',
        'statSync()',
        'resolveSymbolicLinks()',
        'resolveSymbolicLinksSync()',
        'delete(recursive: true)',
        'deleteSync(recursive: true)',
        "rename('destination')",
        "renameSync('destination')",
      ];
      if (kind != 'Link') {
        methods.addAll([
          'create(recursive: true)',
          'createSync(recursive: true)',
        ]);
      } else {
        methods.addAll([
          "create('data', recursive: true)",
          "createSync('data', recursive: true)",
          "update('data')",
          "updateSync('data')",
          'target()',
          'targetSync()',
        ]);
      }
      if (kind != 'Link') methods.add('watch()');
      if (kind == 'Directory') methods.addAll(['list()', 'listSync()']);
      if (kind == 'File') {
        methods.addAll([
          'readAsString()',
          'readAsStringSync()',
          'readAsBytes()',
          'readAsBytesSync()',
          'readAsLines()',
          'readAsLinesSync()',
          'length()',
          'lengthSync()',
          'lastAccessed()',
          'lastAccessedSync()',
          'lastModified()',
          'lastModifiedSync()',
          'setLastAccessed(DateTime(2020))',
          'setLastAccessedSync(DateTime(2020))',
          'setLastModified(DateTime(2020))',
          'setLastModifiedSync(DateTime(2020))',
          "writeAsString('changed')",
          "writeAsStringSync('changed')",
          'writeAsBytes([1])',
          'writeAsBytesSync([1])',
          'open()',
          'openSync()',
          'openRead()',
          'openWrite()',
          "copy('destination')",
          "copySync('destination')",
        ]);
      }
      for (final method in methods) {
        await denied("$kind('').$method");
      }
      await denied("$kind('').absolute");
      // Constructors must not turn empty byte/URI paths into ambient authority.
      await denied("$kind.fromRawPath(Uint8List.fromList([0])).statSync()");
      await denied("$kind.fromUri(Uri()).statSync()");
    }
    print('EMPTY_RECEIVERS_STREAMS_PASS');

    for (final method in ['stat', 'statSync']) {
      await denied("FileStat.$method('')");
    }
    for (final method in [
      'isDirectory',
      'isDirectorySync',
      'isFile',
      'isFileSync',
      'isLink',
      'isLinkSync',
      'type',
      'typeSync',
      'parentOf',
    ]) {
      await denied("FileSystemEntity.$method('')");
    }
    for (final method in ['type', 'typeSync']) {
      await denied("FileSystemEntity.$method('', followLinks: false)");
    }
    for (final method in ['identical', 'identicalSync']) {
      await denied("FileSystemEntity.$method('', 'data')");
      await denied("FileSystemEntity.$method('data', '')");
    }
    for (final value in ["''", "Directory('')"]) {
      await checks.expectDenied(
        () => run(host, '{ Directory.current = $value; }'),
        'empty cwd $value',
      );
      unchanged('empty cwd $value');
    }
    print('EMPTY_STATIC_AND_CWD_PASS');

    for (final (kind, name) in [
      ('File', 'data'),
      ('Directory', 'directory'),
      ('Link', 'link'),
    ]) {
      for (final method in ['rename', 'renameSync']) {
        await denied("$kind('$name').$method('')");
      }
    }
    for (final method in ['copy', 'copySync']) {
      await denied("File('data').$method('')");
    }
    for (final method in ['create', 'createSync', 'update', 'updateSync']) {
      final name = method.startsWith('create') ? 'new_link' : 'link';
      final recursive = method.startsWith('create') ? ', recursive: true' : '';
      await denied("Link('$name').$method(''$recursive)");
    }
    // Native createTemp already rejects an empty receiver. The existing bridge
    // wraps synchronous ArgumentErrors; async errors retain their native type.
    for (final method in ['createTemp', 'createTempSync']) {
      final error = await run(host, '''async {
        try { await Directory('').$method(); } catch (error) { return error; }
        return null;
      }''');
      const message = 'Directory.createTemp called with an empty path.';
      checks.require(
        method == 'createTemp'
            ? error is ArgumentError && error.message == message
            : error is RuntimeError && error.message.contains(message),
        '$method keeps its existing empty-path failure: $error',
      );
      unchanged(method);
    }
    print('EMPTY_DESTINATIONS_DESTRUCTIVE_NO_EFFECTS_PASS');

    checks.require(
      run(host, "=> Directory('.').existsSync();") == true &&
          (await run(host, "=> FileStat.stat('.');") as FileStat).type ==
              FileSystemEntityType.directory &&
          await run(host, "=> File('data').readAsString();") == 'sentinel',
      'explicit dot and ordinary relative paths remain valid',
    );
    for (final method in ['listSync', 'list']) {
      final nativePaths = Directory(
        '.',
      ).listSync(followLinks: false).map((entry) => entry.path).toSet();
      final result = run(
        host,
        "=> Directory('.').$method(followLinks: false);",
      );
      final entries = result is Stream ? await result.toList() : result as List;
      checks.require(
        entries.length == nativePaths.length &&
            entries.every(
              (entry) => nativePaths.contains((entry as FileSystemEntity).path),
            ),
        '$method keeps native relative entry spelling',
      );
    }
    for (final value in ["'.'", "Directory('.')"]) {
      run(host, '{ Directory.current = $value; }');
      unchanged('explicit dot cwd');
    }
    final copied = await run(host, "=> File('data').copy('copy');") as File;
    checks.require(
      copied.path == 'copy' && copied.readAsStringSync() == 'sentinel',
      'relative destination keeps its native spelling',
    );
    copied.deleteSync();
    print('EXPLICIT_DOT_RELATIVE_PATHS_PASS');

    await watchPaths(host, sandbox);
  } finally {
    Directory.current = original;
    sandbox.deleteSync(recursive: true);
  }
}

Future<void> watchPaths(D4rt host, Directory sandbox) async {
  final watched = Directory('watched')..createSync();
  File(p.join(watched.path, 'child')).writeAsStringSync('child');
  for (final (kind, original) in [
    ('File', 'data'),
    ('File', './data'),
    ('File', p.join('watched', 'child')),
    ('Directory', '.'),
    ('Directory', './watched'),
  ]) {
    final absolute = p.join(sandbox.path, original);
    final controller = StreamController<FileSystemEvent>.broadcast(sync: true);
    late Stream stream;
    String? producerPath;
    // Native Windows regular-file watches are unsupported. This deterministic
    // native event producer tests the real interpreter bridge's mapping only;
    // filesystem_scopes.dart separately exercises an actual directory watcher.
    IOOverrides.runZoned(
      () {
        stream = run(host, '=> $kind(${q(original)}).watch();') as Stream;
      },
      fsWatch: (path, events, recursive) {
        producerPath = path;
        return controller.stream;
      },
    );
    final sibling = p.join(p.dirname(p.normalize(absolute)), 'renamed');
    final siblingResult = original == '.'
        ? p.join('..', 'renamed')
        : p.dirname(original) == '.'
        ? 'renamed'
        : p.join(p.dirname(original), 'renamed');
    final nativeEvents = <FileSystemEvent>[
      FileSystemModifyEvent(absolute, kind == 'Directory', true),
      FileSystemMoveEvent(absolute, kind == 'Directory', sibling),
      FileSystemMoveEvent(sibling, kind == 'Directory', absolute),
      FileSystemDeleteEvent(absolute, kind == 'Directory'),
      FileSystemMoveEvent(absolute, kind == 'Directory', null),
      if (kind == 'Directory') ...[
        FileSystemCreateEvent(p.join(absolute, 'child'), false),
        FileSystemMoveEvent(
          p.join(absolute, 'child'),
          false,
          p.join(absolute, 'renamed_child'),
        ),
      ],
    ];
    final expectedPaths = [
      original,
      original,
      siblingResult,
      original,
      original,
      if (kind == 'Directory') ...[
        p.join(original, 'child'),
        p.join(original, 'child'),
      ],
    ];
    final received = <FileSystemEvent>[];
    final done = Completer<void>();
    final subscription = stream.listen(
      (event) {
        received.add(event as FileSystemEvent);
        if (received.length == nativeEvents.length) done.complete();
      },
      onError: (Object error, StackTrace stack) =>
          done.completeError(error, stack),
    );
    try {
      for (final event in nativeEvents) {
        controller.add(event);
      }
      await done.future.timeout(const Duration(seconds: 5));
      checks.require(
        p.equals(producerPath!, absolute),
        'watch uses anchored producer',
      );
      for (var i = 0; i < received.length; i++) {
        final event = received[i];
        checks.require(
          event.path == expectedPaths[i] &&
              event.type == nativeEvents[i].type &&
              event.isDirectory == nativeEvents[i].isDirectory,
          '$kind $original preserves self/child event spelling and kind at $i',
        );
      }
      checks.require(
        (received.first as FileSystemModifyEvent).contentChanged,
        'modify event retains its content flag',
      );
      checks.require(
        (received[1] as FileSystemMoveEvent).destination == siblingResult &&
            (received[2] as FileSystemMoveEvent).destination == original &&
            (received[4] as FileSystemMoveEvent).destination == null,
        'move destinations preserve sibling, self and absent paths',
      );
      if (kind == 'Directory') {
        checks.require(
          (received.last as FileSystemMoveEvent).destination ==
              p.join(original, 'renamed_child'),
          'child move destination mapping',
        );
      } else {
        checks.require(
          run(host, '=> File(${q(received.first.path)}).existsSync();') == true,
          'self event remains a usable file path, not traversal through a file',
        );
      }
    } finally {
      await subscription.cancel();
      await controller.close();
    }
  }
  print('WATCH_SELF_CHILD_MOVE_PATHS_PASS');
}
