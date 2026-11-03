import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/stdlib/io/descriptor_filesystem.dart';
import 'package:path/path.dart' as p;

import 'filesystem_descriptor_edges.dart' as edges;
import 'filesystem_scopes.dart' as checks;

String q(String value) => jsonEncode(value);

dynamic call(D4rt host, String expression) =>
    checks.execute(host, '=> $expression;');

/// A local deterministic scheduling fixture, not a production hook. The native
/// namespace changes immediately after a real policy decision returns true.
class SubstitutionPermission extends Permission {
  final Permission grant;
  final String path;
  final int at;
  final void Function() substitute;
  int count = 0;
  bool changed = false;

  SubstitutionPermission(this.grant, this.path, this.at, this.substitute);

  @override
  String get type => 'filesystem';

  @override
  String get description => 'synthetic local filesystem schedule';

  @override
  bool allows(dynamic operation) {
    final allowed = grant.allows(operation);
    if (allowed &&
        operation is Map &&
        operation['path'] == path &&
        ++count == at) {
      substitute();
      changed = true;
    }
    return allowed;
  }
}

class DenySecondEntryPermission extends Permission {
  final Permission grant;
  final Set<String> paths;
  final seen = <String>{};

  DenySecondEntryPermission(this.grant, this.paths);

  @override
  String get type => 'filesystem';

  @override
  String get description => 'synthetic incremental listing policy';

  @override
  bool allows(dynamic operation) {
    if (!grant.allows(operation)) {
      return false;
    }
    if (operation is Map && paths.contains(operation['path'])) {
      seen.add(operation['path'] as String);
      if (seen.length > 1) {
        return false;
      }
    }
    return true;
  }
}

Future<Object?> failure(FutureOr<Object?> Function() operation) async {
  try {
    await operation();
    return null;
  } on Object catch (error) {
    return error;
  }
}

int ownedDescriptors(String root) {
  if (!Platform.isLinux) return 0;
  var count = 0;
  for (final entry in Directory('/proc/self/fd').listSync(followLinks: false)) {
    try {
      if (Link(entry.path).targetSync().startsWith(root)) count++;
    } on FileSystemException {
      /* The enumeration descriptor has already closed. */
    }
  }
  return count;
}

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('d4rt_descriptor_contract_');
  try {
    final supported = DescriptorFilesystem.instance != null;
    if (Platform.isLinux && Abi.current() == Abi.linuxX64) {
      checks.require(supported, 'Linux x64 runtime capability probe is active');
    } else {
      checks.require(!supported, 'unsupported ABI uses portable policy checks');
    }
    print(
      'FILESYSTEM_BACKEND ${supported ? 'linux_x64_descriptor' : 'portable'}',
    );
    final allowed = Directory(p.join(root.path, 'allowed'))..createSync();
    final outside = Directory(p.join(root.path, 'outside'))..createSync();
    final sentinel = File(p.join(outside.path, 'sentinel'))
      ..writeAsStringSync('outside');
    final originalTime = sentinel.lastModifiedSync();
    final host = checks.interpreter([FilesystemPermission.path(allowed.path)]);
    await allowedOperations(host, allowed);
    await nativeParity(host, allowed);
    await resources(host, allowed, root.path);
    await edges.runDescriptorEdges(host, allowed, outside);
    await checks.expectDenied(
      () => call(host, 'File(${q(sentinel.path)}).readAsStringSync()'),
      'outside content',
    );
    if (supported) {
      await substitutions(allowed, outside);
      print('FILESYSTEM_SUBSTITUTION_BOUNDARY_PASS');
    } else {
      print('FILESYSTEM_SUBSTITUTION_UNSUPPORTED');
    }
    checks.require(
      sentinel.readAsStringSync() == 'outside' &&
          sentinel.lastModifiedSync() == originalTime,
      'outside content and metadata remain unchanged',
    );
    checks.require(
      outside.listSync().length == 1,
      'outside namespace remains unchanged',
    );
    print('FILESYSTEM_OUTSIDE_NON_EFFECTS_PASS');
    print('FILESYSTEM_DESCRIPTOR_CONTRACT_PASS');
  } finally {
    root.deleteSync(recursive: true);
  }
}

Future<void> allowedOperations(D4rt host, Directory allowed) async {
  final file = File(p.join(allowed.path, 'content'));
  final f = 'File(${q(file.path)})';
  await call(host, '$f.writeAsString("one\\ntwo")');
  checks.require(
    call(host, '$f.readAsStringSync()') == 'one\ntwo',
    'sync content',
  );
  checks.require(
    await call(host, '$f.readAsString()') == 'one\ntwo',
    'async content',
  );
  checks.require(
    (call(host, '$f.readAsBytesSync()') as List).length == 7,
    'bytes',
  );
  checks.require(
    (await call(host, '$f.readAsLines()') as List).length == 2,
    'lines',
  );
  checks.require(call(host, '$f.lengthSync()') == 7, 'length');
  checks.require((await call(host, '$f.stat()') as FileStat).size == 7, 'stat');
  await call(host, '$f.setLastModified(DateTime(2021))');
  checks.require(
    (call(host, '$f.lastModifiedSync()') as DateTime).year == 2021,
    'modification time',
  );
  call(host, '$f.setLastAccessedSync(DateTime(2022))');
  checks.require(
    (await call(host, '$f.lastAccessed()') as DateTime).year == 2022,
    'access time',
  );
  final tree = p.join(allowed.path, 'tree', 'child');
  await call(host, 'Directory(${q(tree)}).create(recursive: true)');
  final link = p.join(allowed.path, 'alias');
  call(host, 'Link(${q(link)}).createSync(${q(file.path)})');
  checks.require(
    call(host, 'File(${q(link)}).readAsStringSync()') == 'one\ntwo',
    'authorized alias resolves to canonical target',
  );
  checks.require(
    call(host, 'FileSystemEntity.typeSync(${q(link)}, followLinks: false)') ==
        FileSystemEntityType.link,
    'no-follow static metadata',
  );
  checks.require(
    await call(host, 'FileSystemEntity.isFile(${q(link)})') == true,
    'follow static metadata',
  );
  checks.require(
    call(
          host,
          'FileSystemEntity.identicalSync(${q(file.path)}, ${q(file.path)})',
        ) ==
        true,
    'static identity',
  );
  checks.require(
    call(host, 'FileSystemEntity.identicalSync(${q(file.path)}, ${q(link)})') ==
        false,
    'link identity is not target identity',
  );
  final copied = p.join(allowed.path, 'copied');
  final copy = await call(host, '$f.copy(${q(copied)})') as File;
  checks.require(
    copy.path == copied && copy.readAsStringSync() == 'one\ntwo',
    'durable copy result',
  );
  final renamed = p.join(allowed.path, 'renamed');
  final result =
      await call(host, 'File(${q(copied)}).rename(${q(renamed)})') as File;
  checks.require(
    result.path == renamed && result.existsSync(),
    'durable rename result',
  );
  final temp =
      await call(host, 'Directory(${q(allowed.path)}).createTemp("synthetic_")')
          as Directory;
  checks.require(
    temp.existsSync() && p.isWithin(allowed.path, temp.path),
    'durable secure temporary directory',
  );
  if (DescriptorFilesystem.instance != null) {
    checks.require(
      temp.statSync().mode & 0x1ff == 0x1c0,
      'temporary directory mode is 0700',
    );
  }
  final listed =
      await (call(
                host,
                'Directory(${q(allowed.path)}).list(recursive: true, followLinks: false)',
              )
              as Stream)
          .toList();
  checks.require(
    listed.any((entry) => entry is Link && entry.path == link),
    'listing preserves link kind',
  );
  final loop = p.join(tree, 'loop');
  call(host, 'Link(${q(loop)}).createSync(${q(p.dirname(tree))})');
  final followed =
      call(host, 'Directory(${q(p.dirname(tree))}).listSync(recursive: true)')
          as List;
  checks.require(followed.length < 10, 'directory-link cycles terminate');
  await call(host, 'Directory(${q(p.dirname(tree))}).delete(recursive: true)');
  checks.require(
    !Directory(p.dirname(tree)).existsSync() && file.existsSync(),
    'recursive deletion never traverses final links',
  );
  await call(host, 'Link(${q(link)}).delete()');
  checks.require(file.existsSync(), 'link deletion leaves canonical target');
  await call(host, 'File(${q(renamed)}).delete()');
  await call(host, 'Directory(${q(temp.path)}).delete()');
  print('FILESYSTEM_ALLOWED_OPERATIONS_PASS');
}

Future<void> nativeParity(D4rt host, Directory allowed) async {
  final rootHost = checks.interpreter([FilesystemPermission.read]);
  final volumeRoot = p.rootPrefix(allowed.absolute.path);
  checks.require(
    call(rootHost, 'Directory(${q(volumeRoot)}).existsSync()') ==
        Directory(volumeRoot).existsSync(),
    'root existence',
  );
  checks.require(
    (call(rootHost, 'FileStat.statSync(${q(volumeRoot)})') as FileStat).type ==
        FileStat.statSync(volumeRoot).type,
    'root stat',
  );
  final file = File(p.join(allowed.path, 'parity'))..writeAsStringSync('abc');
  final f = 'File(${q(file.path)})';
  final native = File(p.join(allowed.path, 'native'))..writeAsStringSync('abc');
  for (final mode in ['append', 'writeOnlyAppend']) {
    file.writeAsStringSync('abc');
    native.writeAsStringSync('abc');
    final nativeHandle = native.openSync(
      mode: mode == 'append' ? FileMode.append : FileMode.writeOnlyAppend,
    );
    nativeHandle.setPositionSync(0);
    nativeHandle.writeStringSync('Z');
    nativeHandle.closeSync();
    checks.execute(host, '''{
      final handle = $f.openSync(mode: FileMode.$mode);
      handle.setPositionSync(0); handle.writeStringSync('Z'); handle.closeSync();
      return handle.path;
    }''');
    checks.require(
      file.readAsStringSync() == native.readAsStringSync(),
      '$mode seek parity',
    );
  }
  file.writeAsStringSync('intact');
  await call(host, '$f.copy(${q(file.path)})');
  checks.require(
    file.readAsStringSync() == 'intact',
    'same-file copy validates before truncate',
  );
  if (Platform.isLinux) {
    final alias = p.join(allowed.path, 'hardlink');
    final result = await Process.run('ln', [file.path, alias]);
    checks.require(result.exitCode == 0, 'native hard-link fixture');
    call(host, '$f.copySync(${q(alias)})');
    checks.require(
      file.readAsStringSync() == 'intact',
      'hard-link copy does not truncate source',
    );
  }
  final missing = p.join(allowed.path, 'missing');
  checks.require(
    await failure(
          () => call(host, 'File(${q(missing)}).copy(${q(missing)})'),
        ) !=
        null,
    'missing self-copy fails',
  );
  checks.require(
    await failure(
          () => call(host, 'File(${q(allowed.path)}).copy(${q(allowed.path)})'),
        ) !=
        null,
    'directory self-copy fails',
  );
  checks.require(
    await failure(() => call(host, '$f.create(exclusive: true)')) != null,
    'exclusive create rejects existing file',
  );
  checks.require(
    file.readAsStringSync() == 'intact',
    'exclusive failure does not truncate',
  );
  final dangling = p.join(allowed.path, 'exclusive_link');
  final danglingTarget = p.join(allowed.path, 'exclusive_target');
  Link(dangling).createSync(danglingTarget);
  final nativeDangling = '${dangling}_native';
  final nativeDanglingTarget = '${danglingTarget}_native';
  Link(nativeDangling).createSync(nativeDanglingTarget);
  final nativeExclusiveError = await failure(
    () => File(nativeDangling).createSync(exclusive: true),
  );
  final bridgeExclusiveError = await failure(
    () => call(host, 'File(${q(dangling)}).create(exclusive: true)'),
  );
  checks.require(
    (nativeExclusiveError == null) == (bridgeExclusiveError == null) &&
        File(danglingTarget).existsSync() ==
            File(nativeDanglingTarget).existsSync(),
    'exclusive creation of dangling links follows the platform native contract',
  );
  checks.require(
    await failure(
              () => call(
                host,
                'File(${q(missing)}).writeAsString("invalid", mode: FileMode.read)',
              ),
            ) !=
            null &&
        !File(missing).existsSync(),
    'invalid write mode has no creation side effect',
  );
  for (final kind in ['File', 'Directory', 'Link']) {
    final nativePath = p.join(allowed.path, 'native_wrong_$kind');
    final bridgedPath = p.join(allowed.path, 'bridge_wrong_$kind');
    for (final path in [nativePath, bridgedPath]) {
      if (kind == 'File') {
        Directory(path).createSync();
      } else {
        File(path).writeAsStringSync('wrong kind');
      }
    }
    final nativeWrong = kind == 'File'
        ? File(nativePath)
        : kind == 'Directory'
        ? Directory(nativePath)
        : Link(nativePath);
    checks.require(
      call(host, '$kind(${q(bridgedPath)}).existsSync()') ==
          nativeWrong.existsSync(),
      '$kind wrong-kind existence',
    );
    final nativeError = await failure(
      () => nativeWrong.renameSync('${nativePath}_renamed'),
    );
    final bridgedError = await failure(
      () => call(
        host,
        '$kind(${q(bridgedPath)}).rename(${q('${bridgedPath}_renamed')})',
      ),
    );
    checks.require(
      (nativeError == null) == (bridgedError == null),
      '$kind wrong-kind rename parity',
    );
  }
  for (final kind in ['File', 'Directory', 'Link']) {
    for (final action in [
      'createSync',
      'deleteSync',
      if (kind == 'Link') 'updateSync',
    ]) {
      final nativePath = p.join(allowed.path, 'native_${kind}_$action');
      final bridgePath = p.join(allowed.path, 'bridge_${kind}_$action');
      for (final path in [nativePath, bridgePath]) {
        if (kind == 'File') {
          Directory(path).createSync();
        } else {
          File(path).writeAsStringSync('wrong kind');
        }
      }
      final nativeError = await failure(() {
        if (action == 'deleteSync') {
          final entry = kind == 'File'
              ? File(nativePath)
              : kind == 'Directory'
              ? Directory(nativePath)
              : Link(nativePath);
          entry.deleteSync();
        } else if (kind == 'File') {
          File(nativePath).createSync();
        } else if (kind == 'Directory') {
          Directory(nativePath).createSync();
        } else if (action == 'createSync') {
          Link(nativePath).createSync(file.path);
        } else {
          Link(nativePath).updateSync(file.path);
        }
        return null;
      });
      final argument = kind == 'Link' && action != 'deleteSync'
          ? q(file.path)
          : '';
      final bridgedError = await failure(
        () => call(host, '$kind(${q(bridgePath)}).$action($argument)'),
      );
      checks.require(
        (nativeError == null) == (bridgedError == null) &&
            (nativeError == null ||
                bridgedError.toString().contains(
                  nativeError.runtimeType.toString(),
                )),
        '$kind wrong-kind $action native failure contract',
      );
    }
  }
  final asyncError = checks.execute(host, '''{
    final future = File(${q(missing)}).readAsString();
    return future;
  }''');
  checks.require(
    asyncError is Future && await failure(() => asyncError) != null,
    'async open failure remains a Future failure',
  );
  final stream = call(host, 'File(${q(missing)}).openRead()') as Stream;
  checks.require(
    await failure(() => stream.drain<void>()) != null,
    'read stream failure is deferred',
  );
  final sink =
      call(host, 'File(${q(p.join(missing, 'sink'))}).openWrite()') as IOSink;
  final done = failure(() => sink.done);
  await failure(() => sink.close());
  checks.require(
    await done != null,
    'sink open failure reaches done, not factory',
  );
  print('FILESYSTEM_NATIVE_PARITY_PASS');
}

Future<void> resources(D4rt host, Directory allowed, String root) async {
  final file = File(p.join(allowed.path, 'resources'))
    ..writeAsBytesSync(List<int>.filled(200000, 65));
  final f = 'File(${q(file.path)})';
  // Warm up the runtime before comparing descriptors owned by this fixture.
  await call(host, '$f.readAsBytes()');
  final before = ownedDescriptors(root);
  final listingRoot = Directory(p.join(allowed.path, 'listing_resources'))
    ..createSync();
  final child = Directory(p.join(listingRoot.path, 'child'))..createSync();
  File(p.join(child.path, 'value')).writeAsStringSync('value');
  final listingExpression =
      'Directory(${q(listingRoot.path)}).list(recursive: true)';
  final abandonedListing = call(host, listingExpression) as Stream;
  checks.require(
    ownedDescriptors(root) == before,
    'never-listened directory stream owns no descriptor',
  );
  await (call(host, listingExpression) as Stream).first;
  checks.require(
    ownedDescriptors(root) == before,
    'recursive listing cancellation releases root and child anchors',
  );
  final partialRoot = Directory(p.join(allowed.path, 'partial_listing'))
    ..createSync();
  final paths = {
    p.join(partialRoot.path, 'one'),
    p.join(partialRoot.path, 'two'),
  };
  for (final path in paths) {
    File(path).writeAsStringSync('entry');
  }
  final partialHost = checks.interpreter([
    DenySecondEntryPermission(FilesystemPermission.path(allowed.path), paths),
  ]);
  final partial = <FileSystemEntity>[];
  final partialError = await failure(() async {
    await for (final entry
        in call(partialHost, 'Directory(${q(partialRoot.path)}).list()')
            as Stream) {
      partial.add(entry as FileSystemEntity);
    }
    return null;
  });
  checks.require(
    partialError != null && partial.length == 1,
    'directory streams retain entries delivered before a later policy error',
  );
  checks.require(
    ownedDescriptors(root) == before,
    'failed directory enumeration releases anchors',
  );
  checks.require(
    !abandonedListing.isBroadcast,
    'directory stream retains native single-subscription shape',
  );
  final abandoned = <Stream>[];
  for (var index = 0; index < 12; index++) {
    abandoned.add(call(host, '$f.openRead()') as Stream);
  }
  checks.require(
    ownedDescriptors(root) == before,
    'never-listened streams allocate no owned descriptors',
  );
  final reading = call(host, '$f.readAsBytes()');
  await reading;
  for (var index = 0; index < 8; index++) {
    final stream = call(host, '$f.openRead()') as Stream;
    final subscription = stream.listen((_) {});
    await subscription.cancel();
    final sink = call(host, '$f.openWrite()') as IOSink;
    sink.write('content');
    await sink.close();
    await sink.done;
    final failedSink = call(host, '$f.openWrite()') as IOSink;
    final failedDone = failure(() => failedSink.done);
    final inputFailure = await failure(
      () => failedSink.addStream(
        Stream<List<int>>.error(StateError('input failed')),
      ),
    );
    await failure(failedSink.close);
    await failedDone;
    checks.require(
      inputFailure != null,
      'sink input failure reaches its caller',
    );
    await failure(
      () =>
          call(host, '$f.copy(${q(p.join(allowed.path, 'absent', 'target'))})'),
    );
    await failure(
      () => call(
        host,
        '$f.rename(${q(p.join(allowed.path, 'absent', 'target'))})',
      ),
    );
  }
  final original =
      checks.execute(host, '''{
    final handle = $f.openSync();
    handle.closeSync();
    return [handle.path, handle.toString()];
  }''')
          as List;
  checks.require(
    original[0] == file.path &&
        !(original[1] as String).contains('/proc/self/fd/'),
    'closed RAF metadata keeps original path',
  );
  final returned =
      await call(host, '$f.open(mode: FileMode.append)') as RandomAccessFile;
  checks.require(
    returned.path == file.path,
    'embedding callers also receive original RAF metadata',
  );
  checks.require(
    identical(await returned.writeString('Q'), returned) &&
        identical(await returned.setPosition(0), returned) &&
        identical(await returned.truncate(4), returned) &&
        identical(await returned.flush(), returned),
    'fluent RAF operations retain the same durable owner',
  );
  await returned.close();
  checks.require(
    returned.path == file.path &&
        !returned.toString().contains('/proc/self/fd/'),
    'embedding RAF metadata survives anchor and native-handle closure',
  );
  checks.require(
    ownedDescriptors(root) == before,
    'success, failure, cancellation and sink completion release descriptors',
  );
  checks.require(
    abandoned.length == 12,
    'unconsumed stream fixtures remain reachable',
  );
  print('FILESYSTEM_RESOURCE_OWNERSHIP_PASS');
}

Future<void> substitutions(Directory allowed, Directory outside) async {
  final cases = <String>[
    'File(ENTRY).readAsStringSync()',
    'File(ENTRY).readAsString()',
    'File(ENTRY).readAsBytesSync()',
    'File(ENTRY).readAsBytes()',
    'File(ENTRY).readAsLinesSync()',
    'File(ENTRY).readAsLines()',
    'File(ENTRY).writeAsStringSync("changed")',
    'File(ENTRY).writeAsString("changed")',
    'File(ENTRY).lengthSync()',
    'File(ENTRY).length()',
    'File(ENTRY).lastModifiedSync()',
    'File(ENTRY).lastModified()',
    'File(ENTRY).setLastModifiedSync(DateTime(2001))',
    'File(ENTRY).setLastModified(DateTime(2001))',
    'File(ENTRY).setLastAccessed(DateTime(2001))',
    'File(ENTRY).statSync()',
    'File(ENTRY).stat()',
    'FileStat.statSync(ENTRY)',
    'FileStat.stat(ENTRY)',
    'FileSystemEntity.typeSync(ENTRY)',
    'FileSystemEntity.type(ENTRY)',
    'FileSystemEntity.isFile(ENTRY)',
    'File(ENTRY).openSync()',
    'File(ENTRY).open()',
    'File(ENTRY).openRead()',
    'File(ENTRY).openWrite()',
    'File(ENTRY).createSync()',
    'File(ENTRY).create()',
    'File(ENTRY).copySync(DEST)',
    'File(SOURCE).copySync(ENTRY)',
    'File(ENTRY).copy(DEST)',
    'File(SOURCE).copy(ENTRY)',
  ];
  var index = 0;
  for (final expression in cases) {
    for (final at in [1, 2, if (expression.endsWith('.openRead()')) 3]) {
      final entry = File(p.join(allowed.path, 'race_${index++}'))
        ..writeAsStringSync('inside');
      final outsideFile = File(p.join(outside.path, 'race_sentinel'))
        ..writeAsStringSync('outside');
      final time = outsideFile.lastModifiedSync();
      final source = File(p.join(allowed.path, 'source'))
        ..writeAsStringSync('source');
      final destination = p.join(allowed.path, 'destination');
      final permission = SubstitutionPermission(
        FilesystemPermission.path(allowed.path),
        entry.path,
        at,
        () {
          entry.deleteSync();
          Link(entry.path).createSync(outsideFile.path);
        },
      );
      final host = checks.interpreter([permission]);
      Object? value;
      await failure(() async {
        value = await call(
          host,
          expression
              .replaceAll('ENTRY', q(entry.path))
              .replaceAll('DEST', q(destination))
              .replaceAll('SOURCE', q(source.path)),
        );
        if (value is Stream) {
          final chunks = await (value as Stream).toList();
          value = utf8.decode(
            chunks.expand((chunk) => (chunk as List).cast<int>()).toList(),
          );
        } else if (value is List<int>) {
          value = utf8.decode(value as List<int>);
        } else if (value is List) {
          value = (value as List).join('\n');
        }
        if (value is IOSink) {
          final sink = value as IOSink;
          final done = failure(() => sink.done);
          sink.write('changed');
          await failure(() => sink.close());
          await done;
        }
        if (value is RandomAccessFile) {
          final handle = value as RandomAccessFile;
          try {
            value = utf8.decode(await handle.read(64));
          } finally {
            await handle.close();
          }
        }
        return value;
      });
      checks.require(
        permission.changed,
        'schedule reached real authorization: $expression at $at',
      );
      checks.require(
        value != 'outside',
        'substitution cannot expose outside content',
      );
      checks.require(
        value is! int || value != 7,
        'substitution cannot expose outside file length',
      );
      final metadata = value;
      checks.require(
        metadata is! FileStat ||
            metadata.type == FileSystemEntityType.notFound ||
            metadata.size == 6,
        'substitution cannot expose outside file metadata',
      );
      checks.require(
        outsideFile.readAsStringSync() == 'outside' &&
            outsideFile.lastModifiedSync() == time,
        'substitution cannot change outside content/metadata: $expression at $at',
      );
      outsideFile.deleteSync();
    }
  }
  // Ancestor replacement must also fail closed for both namespace endpoints,
  // recursive traversal and temporary-directory creation.
  for (final operation in [
    'File(ENTRY).createSync()',
    'File(ENTRY).create()',
    'Directory(ENTRY).createSync(recursive: true)',
    'Directory(ENTRY).create(recursive: true)',
    'Link(ENTRY).createSync(SOURCE)',
    'Link(ENTRY).create(SOURCE)',
    'Link(ENTRY).updateSync(SOURCE)',
    'Link(ENTRY).update(SOURCE)',
    'Link(ENTRY).targetSync()',
    'Link(ENTRY).target()',
    'File(ENTRY).deleteSync()',
    'File(ENTRY).delete()',
    'Link(ENTRY).deleteSync()',
    'Link(ENTRY).delete()',
    'Directory(PARENT).deleteSync(recursive: true)',
    'Directory(PARENT).delete(recursive: true)',
    'Directory(PARENT).listSync(recursive: true)',
    'Directory(PARENT).list(recursive: true)',
    'Directory(PARENT).createTempSync("safe_")',
    'Directory(PARENT).createTemp("safe_")',
    'File(SOURCE).renameSync(ENTRY)',
    'File(SOURCE).rename(ENTRY)',
    'File(ENTRY).renameSync(DEST)',
    'File(ENTRY).rename(DEST)',
  ]) {
    for (final at in [1, 2]) {
      final parent = Directory(p.join(allowed.path, 'ancestor_${index++}'))
        ..createSync();
      final saved = '${parent.path}_held';
      final target = Directory(p.join(outside.path, 'ancestor'))..createSync();
      final inside = File(p.join(parent.path, 'entry'))
        ..writeAsStringSync('inside');
      final sentinel = File(p.join(target.path, 'entry'))
        ..writeAsStringSync('outside');
      final source = File(p.join(allowed.path, 'namespace_source'))
        ..writeAsStringSync('source');
      final selected = operation.contains('PARENT') ? parent.path : inside.path;
      final permission = SubstitutionPermission(
        FilesystemPermission.path(allowed.path),
        selected,
        at,
        () {
          parent.renameSync(saved);
          Link(parent.path).createSync(target.path);
        },
      );
      final host = checks.interpreter([permission]);
      await failure(() async {
        final value = await call(
          host,
          operation
              .replaceAll('ENTRY', q(inside.path))
              .replaceAll('PARENT', q(parent.path))
              .replaceAll('SOURCE', q(source.path))
              .replaceAll('DEST', q(p.join(allowed.path, 'namespace_dest'))),
        );
        return value is Stream ? await value.drain<void>() : value;
      });
      checks.require(
        permission.changed,
        'ancestor schedule reached authorization',
      );
      checks.require(
        sentinel.readAsStringSync() == 'outside' &&
            target.listSync().length == 1,
        'ancestor substitution leaves outside namespace intact',
      );
      if (Link(parent.path).existsSync()) Link(parent.path).deleteSync();
      if (Directory(saved).existsSync()) {
        Directory(saved).deleteSync(recursive: true);
      }
      target.deleteSync(recursive: true);
    }
  }
  for (final operation in [
    'deleteSync(recursive: true)',
    'delete(recursive: true)',
    'listSync(recursive: true)',
    'list(recursive: true)',
  ]) {
    final parent = Directory(p.join(allowed.path, 'descendants_${index++}'))
      ..createSync();
    final child = Directory(p.join(parent.path, 'child'))..createSync();
    File(p.join(child.path, 'inside')).writeAsStringSync('inside');
    final target = Directory(p.join(outside.path, 'descendant'))..createSync();
    final sentinel = File(p.join(target.path, 'sentinel'))
      ..writeAsStringSync('outside');
    final permission = SubstitutionPermission(
      FilesystemPermission.path(allowed.path),
      parent.path,
      2,
      () {
        child.deleteSync(recursive: true);
        Link(child.path).createSync(target.path);
      },
    );
    final host = checks.interpreter([permission]);
    await failure(() async {
      final value = await call(host, 'Directory(${q(parent.path)}).$operation');
      return value is Stream ? await value.drain<void>() : value;
    });
    checks.require(
      permission.changed &&
          sentinel.readAsStringSync() == 'outside' &&
          target.listSync().length == 1,
      'recursive descendant substitution never traverses outside',
    );
    target.deleteSync(recursive: true);
  }
}
