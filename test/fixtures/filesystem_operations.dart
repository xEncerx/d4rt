import 'dart:convert';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;
import 'filesystem_scopes.dart' as checks;

String q(String path) => jsonEncode(path);

dynamic run(D4rt host, String body) => host.execute(
  source:
      '''
import 'dart:io';
import 'dart:typed_data';
dynamic main() $body
''',
);

Future<void> main() async {
  final original = Directory.current;
  final root = Directory.systemTemp.createTempSync('d4rt_filesystem_contract_');
  try {
    final allowed = Directory(p.join(root.path, 'a'))..createSync();
    final outside = Directory(p.join(root.path, 'b'))..createSync();
    final data = File(p.join(allowed.path, 'data'))
      ..writeAsStringSync('inside');
    File(p.join(outside.path, 'data')).writeAsStringSync('outside secret');
    final host = checks.interpreter([FilesystemPermission.path(allowed.path)]);
    await rawPaths(host, allowed, outside, data);
    await recursiveEffects(root, data);
    await listingKinds(allowed, outside);
    await deferredOperations(host, allowed, outside, data);
    print('FILESYSTEM_OPERATIONS_PASS');
  } finally {
    Directory.current = original;
    root.deleteSync(recursive: true);
  }
}

Future<void> rawPaths(
  D4rt host,
  Directory allowed,
  Directory outside,
  File data,
) async {
  String mutated(String kind, String good, String bad, String operation) =>
      '''{
    final bytes = Uint8List.fromList(${[...utf8.encode(good), 0]});
    final entry = $kind.fromRawPath(bytes);
    final replacement = ${[...utf8.encode(bad), 0]};
    for (var i = 0; i < bytes.length; i++) { bytes[i] = replacement[i]; }
    return entry.$operation;
  }''';
  checks.require(
    run(
          host,
          mutated(
            'File',
            data.path,
            p.join(outside.path, 'data'),
            'readAsStringSync()',
          ),
        ) ==
        'inside',
    'terminated raw File buffer is immutable after construction',
  );
  final directory = Directory(p.join(allowed.path, 'raw_directory'))
    ..createSync();
  checks.require(
    run(
          host,
          mutated(
            'Directory',
            directory.path,
            p.join(outside.path, 'raw_directory'),
            'existsSync()',
          ),
        ) ==
        true,
    'terminated raw Directory buffer cannot redirect existence',
  );
  final link = Link(p.join(allowed.path, 'raw_link'))..createSync(data.path);
  final outsideLink = Link(p.join(outside.path, 'raw_link'))
    ..createSync(data.path);
  run(host, mutated('Link', link.path, outsideLink.path, 'deleteSync()'));
  checks.require(
    !link.existsSync() && outsideLink.existsSync(),
    'terminated raw Link buffer cannot redirect unlink',
  );
  final unicode = File(p.join(allowed.path, 'synthetic_é'))
    ..writeAsStringSync('utf8');
  for (final terminated in [false, true]) {
    final bytes = [...utf8.encode(unicode.path), if (terminated) 0];
    checks.require(
      run(
            host,
            '''=> File.fromRawPath(Uint8List.fromList($bytes)).readAsStringSync();''',
          ) ==
          'utf8',
      'valid raw UTF-8 remains usable',
    );
  }
  for (final kind in ['File', 'Directory', 'Link']) {
    for (final bytes in [
      [...utf8.encode('${allowed.path}${p.separator}'), 255, 0],
      [...utf8.encode(data.path), 0, 65, 0],
    ]) {
      await checks.expectDenied(
        () => run(host, '=> $kind.fromRawPath(Uint8List.fromList($bytes));'),
        '$kind rejects unfaithful raw bytes',
      );
    }
  }
  checks.require(
    File(p.join(outside.path, 'data')).readAsStringSync() == 'outside secret',
    'raw mutations do not affect outside contents',
  );
  print('RAW_PATH_OWNERSHIP_PASS');
}

Future<void> recursiveEffects(Directory root, File data) async {
  for (final kind in ['File', 'Directory', 'Link']) {
    for (final method in ['create', 'createSync']) {
      final base = p.join(root.path, '${kind}_$method');
      final scope = p.join(base, 'missing', 'scope');
      final leaf = p.join(scope, 'leaf');
      final host = checks.interpreter([
        FilesystemPermission.writePath(scope),
        FilesystemPermission.readPath(data.path),
      ]);
      final call = kind == 'Link'
          ? 'Link(${q(leaf)}).$method(${q(data.path)}, recursive: true)'
          : '$kind(${q(leaf)}).$method(recursive: true)';
      await checks.expectDenied(
        () => run(host, '=> $call;'),
        '$kind.$method checks every missing ancestor',
      );
      checks.require(
        !Directory(base).existsSync(),
        'denied recursion creates no unauthorized ancestors',
      );
      host.grant(FilesystemPermission.writePath(base));
      await run(host, '=> $call;');
      checks.require(
        FileSystemEntity.typeSync(leaf, followLinks: false) !=
            FileSystemEntityType.notFound,
        'permitted $kind recursion succeeds',
      );
    }
  }
  print('RECURSIVE_EFFECT_BOUNDARIES_PASS');
}

Future<void> listingKinds(Directory allowed, Directory outside) async {
  final broken = Directory(p.join(allowed.path, 'broken_only'))..createSync();
  Link(
    p.join(broken.path, 'entry'),
  ).createSync(p.join(outside.path, 'missing'));
  final cycle = Directory(p.join(allowed.path, 'cycle_only'))..createSync();
  Link(p.join(cycle.path, 'back')).createSync(cycle.path);
  for (final directory in [broken, cycle]) {
    final host = checks.interpreter([
      FilesystemPermission.readPath(directory.path),
    ]);
    final native = directory.listSync(recursive: true);
    checks.require(
      native.any((entry) => entry is Link),
      'native listing reports the broken/cycle entry as a Link',
    );
    for (final method in ['listSync', 'list']) {
      final value = run(
        host,
        '=> Directory(${q(directory.path)}).$method(recursive: true);',
      );
      final entries = value is Stream ? await value.toList() : value as List;
      checks.require(
        entries.length == native.length &&
            entries.any((entry) => entry is Link),
        '$method exposes native Link entries without following their targets',
      );
    }
  }
  print('LISTED_ENTRY_SEMANTICS_PASS');
}

Future<void> deferredOperations(
  D4rt host,
  Directory allowed,
  Directory outside,
  File data,
) async {
  dynamic start(String body) {
    Directory.current = allowed;
    final value = run(host, body);
    Directory.current = outside;
    return value;
  }

  // The cwd changes immediately after dispatch, before the future is awaited.
  // Repeated real reads cover native service scheduling without a fake backend.
  for (var attempt = 0; attempt < 16; attempt++) {
    checks.require(
      await start("=> File('data').readAsString();") == 'inside',
      'deferred content read retains its authorized cwd',
    );
  }
  checks.require(
    utf8.decode(
          (await start("=> File('data').readAsBytes();") as List).cast<int>(),
        ) ==
        'inside',
    'deferred bytes read retains cwd',
  );
  checks.require(
    (await start("=> File('data').readAsLines();") as List).single == 'inside',
    'deferred lines read retains cwd',
  );
  checks.require(
    await start("=> File('data').length();") == 6,
    'deferred length retains cwd',
  );
  checks.require(
    (await start("=> File('data').stat();") as FileStat).size == 6,
    'deferred instance stat retains cwd',
  );
  checks.require(
    (await start("=> FileStat.stat('data');") as FileStat).size == 6,
    'deferred static stat retains cwd',
  );
  checks.require(
    await start("=> FileSystemEntity.isFile('data');") == true,
    'deferred static type predicate',
  );
  final markerDirectory = Directory(p.join(allowed.path, 'directory'))
    ..createSync();
  checks.require(
    await start("=> Directory('directory').exists();") == true,
    'deferred directory existence retains cwd',
  );
  checks.require(
    (await start("=> Directory('directory').stat();") as FileStat).type ==
        FileSystemEntityType.directory,
    'deferred directory metadata retains cwd',
  );
  for (final method in ['createTemp', 'createTempSync']) {
    Directory.current = allowed;
    final native = method == 'createTemp'
        ? await Directory('directory').createTemp('native_')
        : Directory('directory').createTempSync('native_');
    final nativeAbsolute = native.isAbsolute;
    native.deleteSync();
    final result =
        await start("=> Directory('directory').$method('bridge_');")
            as Directory;
    checks.require(
      result.isAbsolute == nativeAbsolute &&
          Directory(p.join(allowed.path, result.path)).existsSync(),
      '$method preserves native result spelling and anchors its effect',
    );
    Directory(p.join(allowed.path, result.path)).deleteSync();
  }
  final sourceLink = Link(p.join(allowed.path, 'source_link'))
    ..createSync('data');
  checks.require(
    await start("=> Link('source_link').target();") == 'data',
    'deferred target inspection retains cwd',
  );
  checks.require(
    await start("=> Link('source_link').exists();") == true,
    'deferred link existence retains cwd',
  );
  checks.require(
    (await start("=> Link('source_link').stat();") as FileStat).size == 6,
    'deferred link target metadata retains cwd',
  );
  final issued = await start("=> File('data').open();") as RandomAccessFile;
  try {
    checks.require(
      utf8.decode(await issued.read(6)) == 'inside',
      'handle issuance retains its authorized cwd',
    );
  } finally {
    await issued.close();
  }
  Directory.current = allowed;
  checks.require(
    await run(host, '''async {
    final handle = await File('data').open();
    try { return handle.path; } finally { await handle.close(); }
  }''') ==
        'data',
    'issued handle exposes the original relative path spelling',
  );

  for (final (method, argument) in [
    ('writeAsString', "'changed'"),
    ('writeAsBytes', '[99, 104, 97, 110, 103, 101, 100]'),
  ]) {
    File(p.join(outside.path, 'write')).writeAsStringSync('outside');
    final result = await start("=> File('write').$method($argument);") as File;
    checks.require(
      result.path == 'write' &&
          File(p.join(allowed.path, 'write')).readAsStringSync() == 'changed' &&
          File(p.join(outside.path, 'write')).readAsStringSync() == 'outside',
      '$method anchors effects but preserves the original receiver result',
    );
  }

  for (final kind in ['File', 'Directory', 'Link']) {
    final name = 'relative_$kind';
    final call = kind == 'Link'
        ? "$kind('$name').create('data')"
        : "$kind('$name').create(recursive: true)";
    final result = await start('=> $call;') as FileSystemEntity;
    checks.require(
      result.path == name &&
          FileSystemEntity.typeSync(
                p.join(allowed.path, name),
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound &&
          FileSystemEntity.typeSync(
                p.join(outside.path, name),
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound,
      '$kind creation anchors effects and preserves relative receiver result',
    );
    if (kind == 'Link') {
      final updated = await start("=> Link('$name').update('data');") as Link;
      checks.require(
        updated.path == name &&
            Link(p.join(allowed.path, name)).targetSync() == 'data',
        'relative link update preserves result and anchors delayed recreation',
      );
    }
  }

  File(p.join(allowed.path, 'copy_source')).writeAsStringSync('copy');
  File(p.join(outside.path, 'copy_destination')).writeAsStringSync('outside');
  final copy =
      await start("=> File('copy_source').copy('copy_destination');") as File;
  checks.require(
    copy.path == 'copy_destination' &&
        File(p.join(allowed.path, 'copy_destination')).readAsStringSync() ==
            'copy' &&
        File(p.join(outside.path, 'copy_destination')).readAsStringSync() ==
            'outside',
    'copy freezes receiver/destination and preserves result path',
  );
  for (final kind in ['File', 'Directory', 'Link']) {
    final source = '${kind}_source';
    final destination = '${kind}_destination';
    if (kind == 'File') {
      File(p.join(allowed.path, source)).writeAsStringSync('rename');
      File(p.join(outside.path, destination)).writeAsStringSync('outside');
    } else if (kind == 'Directory') {
      Directory(p.join(allowed.path, source)).createSync();
      Directory(p.join(outside.path, destination)).createSync();
      File(
        p.join(outside.path, destination, 'sentinel'),
      ).writeAsStringSync('outside');
    } else {
      Link(p.join(allowed.path, source)).createSync(data.path);
      Link(p.join(outside.path, destination)).createSync(data.path);
    }
    final renamed =
        await start("=> $kind('$source').rename('$destination');")
            as FileSystemEntity;
    checks.require(
      renamed.path == destination &&
          FileSystemEntity.typeSync(
                p.join(allowed.path, destination),
                followLinks: false,
              ) !=
              FileSystemEntityType.notFound,
      '$kind rename freezes both endpoints and preserves destination spelling',
    );
    if (kind == 'File') {
      checks.require(
        File(p.join(outside.path, destination)).readAsStringSync() == 'outside',
        'outside rename destination unchanged',
      );
    } else if (kind == 'Directory') {
      checks.require(
        File(p.join(outside.path, destination, 'sentinel')).existsSync(),
        'outside directory destination unchanged',
      );
    } else {
      checks.require(
        Link(p.join(outside.path, destination)).existsSync(),
        'outside link destination unchanged',
      );
    }
    final deleted =
        await start("=> $kind('$destination').delete();") as FileSystemEntity;
    checks.require(
      deleted.path == destination &&
          FileSystemEntity.typeSync(
                p.join(allowed.path, destination),
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound,
      '$kind delete freezes receiver and preserves receiver result',
    );
  }
  Directory.current = allowed;
  Object? nativeError;
  try {
    Directory.current = 42;
  } on ArgumentError catch (error) {
    nativeError = error;
  }
  final bridgedError = run(host, '''{
    try { Directory.current = 42; } catch (error) { return error; }
    return null;
  }''');
  checks.require(
    nativeError is ArgumentError &&
        bridgedError is ArgumentError &&
        nativeError.toString() == bridgedError.toString(),
    'invalid cwd preserves the native ArgumentError and message',
  );
  checks.require(
    Directory.current.path == allowed.path,
    'invalid cwd has no effects',
  );
  for (final method in ['listSync', 'list']) {
    final value = start("=> Directory('directory').$method();");
    final entries = value is Stream ? await value.toList() : value as List;
    checks.require(
      entries.isEmpty,
      'relative listing uses authorized directory',
    );
  }
  checks.require(
    markerDirectory.existsSync() && sourceLink.existsSync(),
    'permitted probes leave their unrelated fixtures intact',
  );
  print('DEFERRED_OPERATIONS_AND_NATIVE_RESULTS_PASS');
}
