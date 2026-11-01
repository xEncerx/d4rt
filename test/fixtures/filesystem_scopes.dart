import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;

String literal(String value) => jsonEncode(value);

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

bool denied(Object error) =>
    error is RuntimeError &&
    error.message.contains('Filesystem permission denied');

Future<void> expectDenied(
  FutureOr<Object?> Function() action,
  String label,
) async {
  try {
    await action();
  } on Object catch (error) {
    if (denied(error)) return;
    throw StateError('$label: expected permission denial, got $error');
  }
  throw StateError('$label: unexpectedly authorized');
}

D4rt interpreter(Iterable<Permission> grants) {
  final result = D4rt();
  for (final grant in grants) {
    result.grant(grant);
  }
  return result;
}

dynamic execute(D4rt host, String body) => host.execute(
  source:
      '''
import 'dart:io';
import 'dart:async';
dynamic main() $body
''',
);

Future<void> main() async {
  final original = Directory.current;
  final root = Directory.systemTemp.createTempSync('d4rt_filesystem_scopes_');
  try {
    final allowed = Directory(p.join(root.path, 'allowed'))..createSync();
    final outside = Directory(p.join(root.path, 'outside'))..createSync();
    final inside = File(p.join(allowed.path, 'inside'))
      ..writeAsStringSync('inside');
    final secret = File(p.join(outside.path, 'secret'))
      ..writeAsStringSync('secret');
    final read = FilesystemPermission.readPath(allowed.path);
    final write = FilesystemPermission.writePath(allowed.path);
    final host = interpreter([read, write]);
    final file = 'File(${literal(inside.path)})';
    final forbidden = 'File(${literal(secret.path)})';
    final directory = 'Directory(${literal(allowed.path)})';
    final initialTime = secret.lastModifiedSync();

    for (final method in [
      'lengthSync()',
      'length()',
      'lastAccessedSync()',
      'lastAccessed()',
      'lastModifiedSync()',
      'lastModified()',
      'statSync()',
      'stat()',
      'setLastAccessedSync(DateTime(2020))',
      'setLastAccessed(DateTime(2020))',
      'setLastModifiedSync(DateTime(2020))',
      'setLastModified(DateTime(2020))',
    ]) {
      await expectDenied(() => execute(host, '=> $forbidden.$method;'), method);
      await execute(host, '=> $file.$method;');
    }
    for (final method in ['statSync', 'stat']) {
      await expectDenied(
        () => execute(host, '=> FileStat.$method(${literal(secret.path)});'),
        'static $method',
      );
      final stat =
          await execute(host, '=> FileStat.$method(${literal(inside.path)});')
              as FileStat;
      require(stat.size == 6, 'permitted static metadata');
    }
    require(
      secret.lastModifiedSync() == initialTime,
      'denied metadata has no effect',
    );
    require(
      secret.readAsStringSync() == 'secret',
      'denied content has no effect',
    );
    for (final ambient in ['Directory.current', 'Directory.systemTemp']) {
      await expectDenied(() => execute(host, '=> $ambient;'), ambient);
    }
    final ambientHost = interpreter([
      FilesystemPermission.readPath(original.path),
      FilesystemPermission.readPath(Directory.systemTemp.path),
    ]);
    require(
      await execute(ambientHost, '=> Directory.current.path;') == original.path,
      'permitted current getter',
    );
    require(
      await execute(ambientHost, '=> Directory.systemTemp.path;') ==
          Directory.systemTemp.path,
      'permitted temporary getter',
    );
    print('METADATA_AMBIENT_PASS');

    final outward = Link(p.join(allowed.path, 'outward'))
      ..createSync(outside.path);
    final broken = Link(p.join(allowed.path, 'broken'))
      ..createSync(p.join(outside.path, 'missing'));
    final alias = Link(p.join(outside.path, 'alias'))..createSync(inside.path);
    final loop = Link(p.join(allowed.path, 'loop'));
    loop.createSync(loop.path);
    for (final path in [
      p.join(outward.path, 'secret'),
      broken.path,
      p.join(outward.path, 'missing', 'child'),
      loop.path,
    ]) {
      await expectDenied(
        () => execute(host, '=> File(${literal(path)}).statSync();'),
        'effective path $path',
      );
    }
    final stableHash = read.hashCode;
    require(
      read == FilesystemPermission.readPath(allowed.path),
      'value equality',
    );
    require(
      read.hashCode == stableHash,
      'stable hash after filesystem changes',
    );
    for (final expr in [
      'Link(${literal(outward.path)}).existsSync()',
      'FileSystemEntity.isLinkSync(${literal(outward.path)})',
      'FileSystemEntity.typeSync(${literal(outward.path)}, followLinks: false) == FileSystemEntityType.link',
      'FileSystemEntity.identicalSync(${literal(outward.path)}, ${literal(outward.path)})',
    ]) {
      require(await execute(host, '=> $expr;') == true, 'entry metadata $expr');
    }
    await expectDenied(
      () => execute(
        host,
        '=> FileSystemEntity.typeSync(${literal(outward.path)});',
      ),
      'following type',
    );
    final targetOnly = interpreter([FilesystemPermission.path(inside.path)]);
    require(
      execute(
            targetOnly,
            '=> File(${literal(alias.path)}).readAsStringSync();',
          ) ==
          'inside',
      'content authority follows the target, not the outside entry',
    );
    for (final body in [
      '{ Link(${literal(alias.path)}).deleteSync(); }',
      '=> Link(${literal(alias.path)}).renameSync(${literal(p.join(allowed.path, 'stolen'))});',
      '=> Link(${literal(alias.path)}).targetSync();',
    ]) {
      await expectDenied(
        () => execute(targetOnly, body),
        'target is not entry authority',
      );
    }
    require(
      alias.existsSync() && inside.readAsStringSync() == 'inside',
      'outside entry preserved',
    );
    final missing = p.join(allowed.path, 'missing', 'child');
    await execute(
      host,
      '{ File(${literal(missing)}).createSync(recursive: true); }',
    );
    require(File(missing).existsSync(), 'permitted missing descendants');
    final sibling = p.join('${allowed.path}_sibling', 'new');
    await expectDenied(
      () => execute(
        host,
        '{ File(${literal(sibling)}).createSync(recursive: true); }',
      ),
      'sibling prefix',
    );
    require(!File(sibling).existsSync(), 'no sibling creation');
    File(p.join(root.path, 'inside')).writeAsStringSync('outside');
    final throughParent = '${outward.path}${p.separator}..${p.separator}inside';
    if (Platform.isWindows) {
      // Windows normalizes dot segments before following links.
      require(
        execute(
              host,
              '=> File(${literal(throughParent)}).readAsStringSync();',
            ) ==
            'inside',
        'Windows lexical dot traversal matches the native operation',
      );
    } else {
      await expectDenied(
        () => execute(
          host,
          '=> File(${literal(throughParent)}).readAsStringSync();',
        ),
        'POSIX dot traversal follows the link first',
      );
    }
    print('CANONICAL_NAMESPACE_PASS');

    final created = p.join(allowed.path, 'created');
    final noParent = interpreter([
      FilesystemPermission.writePath(created),
      FilesystemPermission.readPath(secret.path),
    ]);
    await expectDenied(
      () => execute(
        noParent,
        '{ Link(${literal(created)}).createSync(${literal(secret.path)}); }',
      ),
      'link parent authority is independent of entry and target grants',
    );
    require(!Link(created).existsSync(), 'denied parent check has no effects');
    final createHost = interpreter([
      write,
      FilesystemPermission.readPath(outside.path),
    ]);
    await execute(
      createHost,
      '{ Link(${literal(created)}).createSync(${literal(p.relative(secret.path, from: allowed.path))}); }',
    );
    require(
      File(created).readAsStringSync() == 'secret',
      'relative target from link parent',
    );
    final oldTarget = Link(created).targetSync();
    await expectDenied(
      () => execute(
        host,
        '{ Link(${literal(created)}).updateSync(${literal(secret.path)}); }',
      ),
      'update denied before deletion',
    );
    await expectDenied(
      () => execute(
        host,
        '=> Link(${literal(created)}).update(${literal(secret.path)});',
      ),
      'async update denied before deletion',
    );
    require(
      Link(created).targetSync() == oldTarget,
      'denied updates preserve old link',
    );
    for (final method in ['targetSync()', 'target()']) {
      await expectDenied(
        () => execute(host, '=> Link(${literal(created)}).$method;'),
        'target inspection',
      );
    }
    final inspectHost = interpreter([
      read,
      FilesystemPermission.readPath(outside.path),
    ]);
    require(
      await execute(inspectHost, '=> Link(${literal(created)}).target();') ==
          oldTarget,
      'composed target inspection',
    );
    final newMissingTarget = p.join(outside.path, 'future');
    await execute(
      createHost,
      '=> Link(${literal(created)}).update(${literal(newMissingTarget)});',
    );
    require(
      Link(created).targetSync() == newMissingTarget,
      'permitted missing link target',
    );
    final deniedCreate = p.join(allowed.path, 'denied_link');
    await expectDenied(
      () => execute(
        host,
        '=> Link(${literal(deniedCreate)}).create(${literal(secret.path)});',
      ),
      'create target denial',
    );
    require(!Link(deniedCreate).existsSync(), 'denied create has no effect');
    final moved = p.join(allowed.path, 'moved');
    await execute(
      host,
      '=> Link(${literal(created)}).rename(${literal(moved)});',
    );
    await execute(host, '{ Link(${literal(moved)}).deleteSync(); }');
    require(
      !Link(moved).existsSync() && secret.existsSync(),
      'namespace changes need no target write',
    );
    final entryOnly = interpreter([
      FilesystemPermission.writePath(broken.path),
      FilesystemPermission.writePath(allowed.path),
    ]);
    await execute(entryOnly, '{ Link(${literal(broken.path)}).deleteSync(); }');
    require(
      !broken.existsSync(),
      'broken entries can be removed without target authority',
    );
    for (final (kind, targetPath) in [
      ('File', secret.path),
      ('Directory', outside.path),
    ]) {
      final nativeLink = Link(p.join(allowed.path, '${kind}_native'))
        ..createSync(targetPath);
      final bridgedLink = Link(p.join(allowed.path, '${kind}_bridged'))
        ..createSync(targetPath);
      final nativeDestination = '${nativeLink.path}_moved';
      final bridgedDestination = '${bridgedLink.path}_moved';
      var nativeFailed = false;
      try {
        if (kind == 'File') {
          File(nativeLink.path).renameSync(nativeDestination);
        } else {
          await Directory(nativeLink.path).rename(nativeDestination);
        }
      } on FileSystemException {
        nativeFailed = true;
      }
      var bridgedFailed = false;
      try {
        await execute(
          host,
          '=> $kind(${literal(bridgedLink.path)}).renameSync(${literal(bridgedDestination)});',
        );
      } on RuntimeError catch (error) {
        require(
          !denied(error) && error.message.contains('FileSystemException') ||
              !denied(error) && error.message.contains('PathNotFoundException'),
          '$kind rename preserves native errors',
        );
        bridgedFailed = true;
      }
      require(nativeFailed == bridgedFailed, '$kind rename native parity');
      require(
        Link(nativeFailed ? nativeLink.path : nativeDestination).existsSync() &&
            Link(
              bridgedFailed ? bridgedLink.path : bridgedDestination,
            ).existsSync() &&
            secret.readAsStringSync() == 'secret',
        '$kind rename preserves final link targets',
      );
    }
    final destination = Link(p.join(allowed.path, 'destination'))
      ..createSync(secret.path);
    final source = File(p.join(allowed.path, 'source'))
      ..writeAsStringSync('replacement');
    await execute(
      host,
      '=> File(${literal(source.path)}).renameSync(${literal(destination.path)});',
    );
    require(
      File(destination.path).readAsStringSync() == 'replacement' &&
          secret.readAsStringSync() == 'secret',
      'rename replaces entry not target',
    );
    final tree = Directory(p.join(allowed.path, 'tree'))..createSync();
    Link(p.join(tree.path, 'outside')).createSync(outside.path);
    await execute(
      host,
      '{ Directory(${literal(tree.path)}).deleteSync(recursive: true); }',
    );
    require(
      !tree.existsSync() && secret.existsSync(),
      'recursive delete does not follow links',
    );
    print('LINK_POLICY_PASS');

    for (final prefix in [
      '../escape',
      '/escape',
      r'..\escape',
      r'C:\escape',
      r'\\host\share',
      'bad\u0000name',
      'bad:name',
      'bad*name',
      'bad\nname',
    ]) {
      final before = allowed.listSync(followLinks: false).length;
      for (final method in ['createTempSync', 'createTemp']) {
        try {
          await execute(host, '=> $directory.$method(${literal(prefix)});');
          throw StateError('invalid prefix allowed: $prefix');
        } on RuntimeError catch (error) {
          require(
            error.message.contains('Invalid temporary'),
            'prefix error: $error',
          );
        }
      }
      require(
        allowed.listSync(followLinks: false).length == before,
        'invalid prefix has no effects',
      );
    }
    for (final prefix in ['', 'simple_', null]) {
      for (final method in ['createTempSync', 'createTemp']) {
        final result =
            await execute(host, '=> $directory.$method(${jsonEncode(prefix)});')
                as Directory;
        require(
          p.isWithin(allowed.path, result.path),
          'temporary result in scope',
        );
        result.deleteSync();
      }
    }
    final omitted =
        await execute(host, '=> $directory.createTemp();') as Directory;
    omitted.deleteSync();
    print('TEMP_PREFIX_PASS');

    for (final method in ['listSync', 'list']) {
      await expectDenied(() async {
        final result = execute(host, '=> $directory.$method(recursive: true);');
        return result is Stream ? await result.toList() : result;
      }, 'listing follows forbidden targets');
      final result = execute(
        host,
        '=> $directory.$method(recursive: true, followLinks: false);',
      );
      final entries = result is Stream ? await result.toList() : result as List;
      require(
        entries.any(
          (entry) => (entry as FileSystemEntity).path == outward.path,
        ),
        'no-follow listing exposes permitted link entries',
      );
    }
    for (final kind in ['File', 'Directory', 'Link']) {
      for (final method in [
        'resolveSymbolicLinks',
        'resolveSymbolicLinksSync',
      ]) {
        await expectDenied(
          () => execute(host, '=> $kind(${literal(outward.path)}).$method();'),
          'forbidden resolution',
        );
        final value = await execute(
          host,
          '=> $kind(${literal(allowed.path)}).$method();',
        );
        require(
          value == allowed.resolveSymbolicLinksSync(),
          'permitted resolution',
        );
      }
    }
    final deferred =
        execute(host, '=> $directory.list(followLinks: false);') as Stream;
    host.revoke(FilesystemPermission.readPath(allowed.path));
    await expectDenied(() => deferred.toList(), 'revoke before listen');
    host.grant(read);
    final bytes = execute(host, '=> $file.openRead();') as Stream;
    host.revoke(read);
    await expectDenied(
      () => bytes.toList(),
      'file stream revoked before listen',
    );
    host.grant(read);
    print('LIST_RESOLUTION_REVOKE_PASS');

    for (final method in ['openSync', 'open']) {
      for (final mode in ['write', 'append']) {
        final writeOnly = interpreter([write]);
        await expectDenied(
          () => execute(writeOnly, '=> $file.$method(mode: FileMode.$mode);'),
          'readable handle issuance',
        );
        require(
          inside.readAsStringSync() == 'inside',
          'denied open cannot truncate',
        );
        final handle =
            await execute(host, '=> $file.$method(mode: FileMode.$mode);')
                as RandomAccessFile;
        await handle.close();
        inside.writeAsStringSync('inside');
      }
      final writeOnly = interpreter([write]);
      final handle =
          await execute(
                writeOnly,
                '=> $file.$method(mode: FileMode.writeOnlyAppend);',
              )
              as RandomAccessFile;
      await handle.close();
    }
    print('HANDLE_ISSUANCE_PASS');

    await watchScenarios(host, read, allowed, inside, secret);
    await cwdScenarios(host, read, allowed, outside, inside);
    if (Platform.isWindows) {
      final spelling = inside.path.toUpperCase().replaceAll('\\', '/');
      require(
        await execute(
              host,
              '=> File(${literal(spelling)}).readAsStringSync();',
            ) ==
            'inside',
        'Windows case and separators',
      );
      for (final path in [
        '${inside.path}:stream',
        '${inside.path}.',
        '${inside.path} ',
      ]) {
        await expectDenied(
          () => execute(host, '=> File(${literal(path)}).statSync();'),
          'ambiguous Windows spelling',
        );
      }
    }
    print('FILESYSTEM_SCOPES_PASS');
  } finally {
    Directory.current = original;
    root.deleteSync(recursive: true);
  }
}

Future<void> watchScenarios(
  D4rt host,
  FilesystemPermission read,
  Directory allowed,
  File inside,
  File secret,
) async {
  final stream =
      execute(host, '=> Directory(${literal(allowed.path)}).watch();')
          as Stream;
  require(stream.isBroadcast, 'watch remains broadcast');
  final firstEvent = Completer<void>();
  final secondEvent = Completer<void>();
  final revoked = Completer<void>();
  var count = 0;
  final subscription = stream.listen(
    (event) {
      count++;
      if (!firstEvent.isCompleted) firstEvent.complete();
    },
    onError: (Object error) {
      if (denied(error) && !revoked.isCompleted) revoked.complete();
    },
  );
  final second = stream.listen((event) {
    if (!secondEvent.isCompleted) secondEvent.complete();
  }, onError: (Object _) {});
  try {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    inside.writeAsStringSync('inside', flush: true);
    await Future.wait([
      firstEvent.future,
      secondEvent.future,
    ]).timeout(const Duration(seconds: 10));
    subscription.pause();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    inside.writeAsStringSync('inside', flush: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    host.revoke(read);
    final beforeResume = count;
    subscription.resume();
    inside.writeAsStringSync('inside', flush: true);
    await revoked.future.timeout(const Duration(seconds: 10));
    require(count == beforeResume, 'paused/revoked watcher exposes no data');
  } finally {
    await subscription.cancel();
    await second.cancel();
    host.grant(read);
  }

  // Deterministic native event source exercises destination checking even on
  // systems which report a rename as separate create/delete events.
  final controller = StreamController<FileSystemEvent>.broadcast(sync: true);
  late Stream events;
  IOOverrides.runZoned(() {
    events =
        execute(host, '=> Directory(${literal(allowed.path)}).watch();')
            as Stream;
  }, fsWatch: (path, eventMask, recursive) => controller.stream);
  final error = Completer<void>();
  var errors = 0;
  var exposed = false;
  final listener = events.listen(
    (_) => exposed = true,
    onError: (Object value) {
      if (denied(value) && ++errors == 2 && !error.isCompleted) {
        error.complete();
      }
    },
  );
  try {
    controller.add(FileSystemMoveEvent(inside.path, false, secret.path));
    controller.add(
      FileSystemModifyEvent(
        p.join(allowed.path, 'outward', 'secret'),
        false,
        true,
      ),
    );
    await error.future.timeout(const Duration(seconds: 5));
    require(
      errors == 2 && !exposed,
      'forbidden watch path and move destination are not exposed',
    );
  } finally {
    await listener.cancel();
    await controller.close();
  }
  print('WATCH_BROADCAST_REVOKE_DESTINATION_PASS');
}

Future<void> cwdScenarios(
  D4rt host,
  FilesystemPermission read,
  Directory allowed,
  Directory outside,
  File inside,
) async {
  final original = Directory.current;
  try {
    await expectDenied(
      () => execute(host, '{ Directory.current = ${literal(outside.path)}; }'),
      'cwd String denial',
    );
    await expectDenied(
      () => execute(
        host,
        '{ Directory.current = Directory(${literal(outside.path)}); }',
      ),
      'cwd Directory denial',
    );
    require(Directory.current.path == original.path, 'denied cwd unchanged');
    await execute(host, '{ Directory.current = ${literal(allowed.path)}; }');
    final stream = execute(host, "=> File('inside').openRead();") as Stream;
    final list =
        execute(host, "=> Directory('.').list(followLinks: false);") as Stream;
    final watch = execute(host, "=> Directory('.').watch();") as Stream;
    final hash = read.hashCode;
    Directory.current = outside;
    final chunks = await stream.toList();
    require(
      utf8.decode(
            chunks.expand((chunk) => (chunk as List).cast<int>()).toList(),
          ) ==
          'inside',
      'deferred file stream freezes cwd',
    );
    final entries = await list.toList();
    String anchoredEntry(FileSystemEntity entry) =>
        p.normalize(p.join(allowed.path, entry.path));
    require(
      entries.any(
            (entry) =>
                p.equals(anchoredEntry(entry as FileSystemEntity), inside.path),
          ) &&
          entries.every(
            (entry) => p.isWithin(
              allowed.path,
              anchoredEntry(entry as FileSystemEntity),
            ),
          ) &&
          entries.every((entry) => !(entry as FileSystemEntity).isAbsolute),
      'deferred listing freezes cwd',
    );
    final event = Completer<void>();
    final subscription = watch.listen((_) {
      if (!event.isCompleted) event.complete();
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      inside.writeAsStringSync('inside', flush: true);
      await event.future.timeout(const Duration(seconds: 10));
    } finally {
      await subscription.cancel();
    }
    require(
      read.hashCode == hash &&
          host.hasPermission(FilesystemPermission.readPath(allowed.path)),
      'cwd preserves scope identity and query',
    );
    host.revoke(FilesystemPermission.readPath(allowed.path));
    require(!host.hasPermission(read), 'equivalent revoke after cwd change');
    host.grant(read);
    await execute(
      host,
      '{ Directory.current = Directory(${literal(allowed.path)}); }',
    );
    require(
      Directory.current.path == allowed.path,
      'permitted Directory cwd setter',
    );
  } finally {
    Directory.current = original;
  }
  print('CWD_DEFERRED_IDENTITY_PASS');
}
