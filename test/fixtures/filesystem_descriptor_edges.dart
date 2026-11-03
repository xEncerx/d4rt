import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/stdlib/io/descriptor_filesystem.dart';
import 'package:path/path.dart' as p;

import 'filesystem_operations.dart' as operations;
import 'filesystem_scopes.dart' as checks;

String _q(String path) => jsonEncode(path);

dynamic _call(D4rt host, String expression) =>
    checks.execute(host, '=> $expression;');

Future<Object?> _failure(FutureOr<Object?> Function() operation) async {
  try {
    await operation();
    return null;
  } on Object catch (error) {
    return error;
  }
}

Future<void> runDescriptorEdges(
  D4rt host,
  Directory allowed,
  Directory outside,
) async {
  await operations.listingKinds(allowed, outside);
  final root = Directory(p.join(allowed.path, 'descriptor_edges'))
    ..createSync();
  final descriptorsBefore = _ownedDescriptors(root.path);
  await _cycleParity(host, root);
  await _missingQueries(host, root, outside);
  await _workingLinkBoundary(host, root, outside);
  await _modeAuthority(root);
  await _diagnostics(host, root);
  await _relativeDiagnostics(host, root);
  await _setupDiagnostics(host, root);
  await _responsiveness(host, root);
  checks.require(
    _ownedDescriptors(root.path) == descriptorsBefore,
    'edge failures and asynchronous mutations release all owned root descriptors',
  );
  print('FILESYSTEM_DESCRIPTOR_EDGES_PASS');
}

int _ownedDescriptors(String root) {
  if (!Platform.isLinux) return 0;
  var count = 0;
  for (final entry in Directory('/proc/self/fd').listSync(followLinks: false)) {
    try {
      if (Link(entry.path).targetSync().startsWith(root)) count++;
    } on FileSystemException {
      /* Enumeration's own descriptor already closed. */
    }
  }
  return count;
}

Future<void> _cycleParity(D4rt host, Directory root) async {
  final directory = Directory(p.join(root.path, 'link_descent'))..createSync();
  Link(p.join(directory.path, 'one')).createSync(directory.path);
  Link(p.join(directory.path, 'two')).createSync(directory.path);
  File(p.join(directory.path, 'value')).writeAsStringSync('value');
  Link(p.join(directory.path, 'broken')).createSync('absent');
  Link(p.join(directory.path, 'self')).createSync('self');
  Link(p.join(directory.path, 'cycle_a')).createSync('cycle_b');
  Link(p.join(directory.path, 'cycle_b')).createSync('cycle_a');
  List<String> shape(Iterable<FileSystemEntity> entries) =>
      entries
          .map(
            (entry) =>
                '${entry is Link
                    ? 'link'
                    : entry is Directory
                    ? 'directory'
                    : 'file'}:${p.relative(entry.path, from: directory.path)}',
          )
          .toList()
        ..sort();
  for (final recursive in [false, true]) {
    for (final followLinks in [false, true]) {
      final expected = shape(
        directory.listSync(recursive: recursive, followLinks: followLinks),
      );
      for (final method in ['listSync', 'list']) {
        final result = _call(
          host,
          'Directory(${_q(directory.path)}).$method(recursive: $recursive, followLinks: $followLinks)',
        );
        final entries = result is Stream
            ? await result.toList()
            : result as List;
        final actual = shape(entries.cast<FileSystemEntity>());
        checks.require(
          jsonEncode(actual) == jsonEncode(expected),
          '$method retains native link-entry identities and paths: actual=$actual expected=$expected',
        );
      }
    }
  }
  print('FILESYSTEM_LINK_DESCENT_PARITY_PASS');
}

Future<void> _missingQueries(
  D4rt host,
  Directory root,
  Directory outside,
) async {
  final missing = p.join(root.path, 'missing', 'leaf');
  for (final suffix in ['', 'Sync']) {
    checks.require(
      await _call(host, 'Link(${_q(missing)}).exists$suffix()') == false,
      'missing parent Link.exists$suffix returns false',
    );
    checks.require(
      await _call(host, 'FileSystemEntity.isLink$suffix(${_q(missing)})') ==
          false,
      'missing parent isLink$suffix returns false',
    );
    checks.require(
      await _call(
            host,
            'FileSystemEntity.type$suffix(${_q(missing)}, followLinks: false)',
          ) ==
          FileSystemEntityType.notFound,
      'missing parent no-follow type$suffix returns notFound',
    );
    await checks.expectDenied(
      () => _call(
        host,
        'Link(${_q(p.join(outside.path, 'missing', 'leaf'))}).exists$suffix()',
      ),
      'missing lookup does not hide policy denial',
    );
  }
  print('FILESYSTEM_MISSING_QUERY_PARITY_PASS');
}

Future<void> _workingLinkBoundary(
  D4rt host,
  Directory root,
  Directory outside,
) async {
  final directory = Directory(p.join(root.path, 'forbidden_link'))
    ..createSync();
  final target = File(p.join(outside.path, 'working_link_target'))
    ..writeAsStringSync('outside');
  try {
    Link(p.join(directory.path, 'entry')).createSync(target.path);
    for (final method in ['listSync', 'list']) {
      final error = await _failure(() async {
        final value = _call(
          host,
          'Directory(${_q(directory.path)}).$method(recursive: true)',
        );
        if (value is Stream) {
          await value.toList();
        }
        return value;
      });
      checks.require(
        error != null && checks.denied(error),
        '$method still denies a working outside target',
      );
    }
    checks.require(
      target.readAsStringSync() == 'outside',
      'listing has no outside content effect',
    );
  } finally {
    target.deleteSync();
  }
}

Future<void> _modeAuthority(Directory root) async {
  final file = File(p.join(root.path, 'mode'));
  for (final scope in ['read', 'write', 'both']) {
    final host = checks.interpreter([
      if (scope != 'write') FilesystemPermission.readPath(root.path),
      if (scope != 'read') FilesystemPermission.writePath(root.path),
    ]);
    for (final mode in [
      'read',
      'write',
      'append',
      'writeOnly',
      'writeOnlyAppend',
    ]) {
      for (final suffix in ['', 'Sync']) {
        file.writeAsStringSync('unchanged');
        final expected =
            scope == 'both' ||
            (scope == 'read' && mode == 'read') ||
            (scope == 'write' && mode.startsWith('writeOnly'));
        RandomAccessFile? handle;
        final error = await _failure(() async {
          handle =
              await _call(
                    host,
                    'File(${_q(file.path)}).open$suffix(mode: FileMode.$mode)',
                  )
                  as RandomAccessFile;
          return handle;
        });
        try {
          checks.require(
            (error == null) == expected,
            '$scope grant / $mode / open$suffix authority',
          );
          if (!expected) {
            checks.require(
              file.readAsStringSync() == 'unchanged',
              'denied open cannot truncate',
            );
          }
        } finally {
          await handle?.close();
        }
      }
    }
  }
  print('FILESYSTEM_MODE_AUTHORITY_PASS');
}

void _sameError(
  Object? actual,
  Object? native,
  String label, {
  bool sameMessage = true,
}) {
  checks.require(
    actual is FileSystemException && native is FileSystemException,
    '$label preserves filesystem exception delivery/category: actual=$actual native=$native',
  );
  final a = actual as FileSystemException, b = native as FileSystemException;
  checks.require(
    a.runtimeType == b.runtimeType &&
        a.osError?.errorCode == b.osError?.errorCode,
    '$label preserves native category and OS error: actual=$a native=$b',
  );
  checks.require(
    a.path == b.path &&
        (!sameMessage || a.message == b.message) &&
        !a.toString().contains('/proc/self/fd/'),
    '$label preserves public diagnostic operands: actual=$a native=$b',
  );
}

Future<void> _diagnostics(D4rt host, Directory root) async {
  final source = File(p.join(root.path, 'diagnostic_source'))
    ..writeAsStringSync('source');
  final expression = 'File(${_q(source.path)})';
  final native = source.openSync();
  final returned = await _call(host, '$expression.open()') as RandomAccessFile;
  native.closeSync();
  await returned.close();
  _sameError(
    await _failure(returned.readByteSync),
    await _failure(native.readByteSync),
    'closed RAF synchronous error',
  );
  _sameError(
    await _failure(returned.length),
    await _failure(native.length),
    'closed RAF asynchronous error',
  );
  final interpreted = checks.execute(host, '''{
    final handle = $expression.openSync(); handle.closeSync();
    try { handle.readByteSync(); } catch (error) { return error.toString(); }
    return 'missing error';
  }''');
  checks.require(
    interpreted is String &&
        interpreted.contains(source.path) &&
        !interpreted.contains('/proc/self/fd/'),
    'closed RAF diagnostics through registered bridge',
  );

  final destination = Directory(p.join(root.path, 'diagnostic_destination'))
    ..createSync();
  File(p.join(destination.path, 'child')).writeAsStringSync('child');
  _sameError(
    await _failure(
      () => _call(host, '$expression.rename(${_q(destination.path)})'),
    ),
    await _failure(() => source.rename(destination.path)),
    'two-endpoint asynchronous rename',
  );
  final syncRename = await _failure(
    () => _call(host, '$expression.renameSync(${_q(destination.path)})'),
  );
  checks.require(
    syncRename != null &&
        syncRename.toString().contains(source.path) &&
        syncRename.toString().contains(destination.path) &&
        !syncRename.toString().contains('/proc/self/fd/'),
    'two-endpoint synchronous rename diagnostics',
  );
  final stream =
      _call(host, 'File(${_q(destination.path)}).openRead()') as Stream;
  _sameError(
    await _failure(() => stream.drain<void>()),
    await _failure(() => File(destination.path).openRead().drain<void>()),
    'read stream error',
  );
  final sink =
      _call(host, 'File(${_q(destination.path)}).openWrite()') as IOSink;
  final sinkError = _failure(() => sink.done);
  await _failure(sink.close);
  final nativeSink = File(destination.path).openWrite();
  final nativeSinkError = _failure(() => nativeSink.done);
  await _failure(nativeSink.close);
  _sameError(
    await sinkError,
    await nativeSinkError,
    'sink asynchronous open error',
    sameMessage: false,
  );

  if (Platform.isLinux && File('/dev/full').existsSync()) {
    // A nonpersistent local kernel device: writes fail with ENOSPC and cannot
    // modify filesystem contents. This exercises errors after a native open.
    final modeBefore = FileStat.statSync('/dev/full').mode;
    final fullBefore = _ownedDescriptors('/dev/full');
    final fullHost = checks.interpreter([
      FilesystemPermission.readPath(root.path),
      FilesystemPermission.writePath('/dev/full'),
    ]);
    final full = _call(fullHost, 'File("/dev/full").openWrite()') as IOSink;
    final fullDone = _failure(() => full.done);
    full.write('synthetic');
    await _failure(full.close);
    final raw = File('/dev/full').openWrite();
    final rawDone = _failure(() => raw.done);
    raw.write('synthetic');
    await _failure(raw.close);
    _sameError(await fullDone, await rawDone, 'sink asynchronous write error');
    _sameError(
      await _failure(() => _call(fullHost, '$expression.copy("/dev/full")')),
      await _failure(() => source.copy('/dev/full')),
      'two-endpoint asynchronous copy',
    );
    final syncCopy = await _failure(
      () => _call(fullHost, '$expression.copySync("/dev/full")'),
    );
    checks.require(
      syncCopy != null &&
          syncCopy.toString().contains(source.path) &&
          syncCopy.toString().contains('/dev/full') &&
          !syncCopy.toString().contains('/proc/self/fd/'),
      'two-endpoint synchronous copy diagnostics',
    );
    checks.require(
      FileStat.statSync('/dev/full').mode == modeBefore,
      'kernel error fixture permissions are unchanged',
    );
    checks.require(
      _ownedDescriptors('/dev/full') == fullBefore,
      'failed native writes and copies release both anchor and SDK descriptors',
    );
  }
  print('FILESYSTEM_PUBLIC_ERROR_PATHS_PASS');
}

Future<void> _relativeDiagnostics(D4rt host, Directory root) async {
  final previous = Directory.current;
  try {
    Directory.current = root;
    final source = File('relative_source')..writeAsStringSync('source');
    final destination = Directory('relative_destination')..createSync();
    File(p.join(destination.path, 'child')).writeAsStringSync('child');
    final error = await _failure(
      () =>
          _call(host, 'File("relative_source").rename("relative_destination")'),
    );
    final expected = await _failure(() => source.rename(destination.path));
    if (DescriptorFilesystem.instance != null) {
      _sameError(error, expected, 'relative two-endpoint rename');
      _sameError(
        await _failure(
          () => _call(
            host,
            'File("relative_source").copy("absent/relative_copy")',
          ),
        ),
        await _failure(() => source.copy('absent/relative_copy')),
        'relative failed second-endpoint copy',
      );
      final stream =
          _call(host, 'File("relative_destination").openRead()') as Stream;
      _sameError(
        await _failure(() => stream.drain<void>()),
        await _failure(() => File(destination.path).openRead().drain<void>()),
        'relative read stream',
      );
      final sink =
          _call(host, 'File("relative_destination").openWrite()') as IOSink;
      final done = _failure(() => sink.done);
      await _failure(sink.close);
      final nativeSink = File(destination.path).openWrite();
      final nativeDone = _failure(() => nativeSink.done);
      await _failure(nativeSink.close);
      _sameError(
        await done,
        await nativeDone,
        'relative sink',
        sameMessage: false,
      );
    } else {
      checks.require(
        error != null && !error.toString().contains('/proc/self/fd/'),
        'portable diagnostics retain usable paths',
      );
    }
  } finally {
    Directory.current = previous;
  }
  print('FILESYSTEM_RELATIVE_DIAGNOSTICS_PASS');
}

Future<void> _setupDiagnostics(D4rt host, Directory root) async {
  final previous = Directory.current;
  final descriptorsBefore = _ownedDescriptors(root.path);
  try {
    Directory.current = root;
    Directory('setup_real').createSync();
    Link('setup_alias').createSync('setup_real');
    File('setup_target').writeAsStringSync('target');
    final target = File('setup_target').absolute.path;

    Future<void> check(
      String expression,
      FutureOr<Object?> Function() native,
      String operand, {
      String? destination,
      required bool synchronous,
    }) async {
      Object? invocation;
      Object? eagerError;
      try {
        invocation = _call(host, expression);
      } on Object catch (error) {
        eagerError = error;
      }
      checks.require(
        synchronous
            ? eagerError != null
            : eagerError == null && invocation is Future,
        '$expression preserves synchronous/Future failure timing',
      );
      final actual = eagerError ?? await _failure(() => invocation);
      final expected = await _failure(native);
      checks.require(
        expected is FileSystemException,
        '$expression native setup failure is observable',
      );
      final nativeError = expected as FileSystemException;
      checks.require(
        actual != null,
        '$expression fails through its registered bridge',
      );
      if (!synchronous) {
        checks.require(
          actual is FileSystemException &&
              actual.runtimeType == nativeError.runtimeType &&
              actual.osError?.errorCode == nativeError.osError?.errorCode,
          '$expression preserves native exception category and OS error: $actual',
        );
      } else {
        checks.require(
          actual.toString().contains(nativeError.runtimeType.toString()) &&
              actual.toString().contains(
                'errno = ${nativeError.osError?.errorCode}',
              ),
          '$expression preserves native failure inside the synchronous bridge error: $actual',
        );
      }
      final displayedOperand = DescriptorFilesystem.instance != null
          ? operand
          : File(operand).absolute.path;
      final displayedDestination =
          destination == null ||
              (DescriptorFilesystem.instance == null &&
                  !nativeError.toString().contains(destination))
          ? null
          : DescriptorFilesystem.instance != null
          ? destination
          : File(destination).absolute.path;
      checks.require(
        actual.toString().contains(displayedOperand) &&
            (displayedDestination == null ||
                actual.toString().contains(displayedDestination)) &&
            !actual.toString().contains('/proc/self/fd/'),
        '$expression retains full original setup operands: $actual',
      );
      if (!synchronous && destination == null) {
        checks.require(
          (actual as FileSystemException).path == displayedOperand,
          '$expression keeps the full creation operand in the path field',
        );
      }
    }

    for (final kind in ['Directory', 'File', 'Link']) {
      for (final operand in [
        'setup_missing/leaf',
        'setup_alias/missing/leaf',
        p.join(root.path, 'setup_alias', 'missing', 'absolute_leaf'),
      ]) {
        for (final synchronous in [true, false]) {
          final method = synchronous ? 'createSync' : 'create';
          await check(
            '$kind(${_q(operand)}).$method(${kind == 'Link' ? _q(target) : ''})',
            () {
              if (kind == 'Directory') {
                if (synchronous) {
                  Directory(operand).createSync();
                  return null;
                }
                return Directory(operand).create();
              }
              if (kind == 'File') {
                if (synchronous) {
                  File(operand).createSync();
                  return null;
                }
                return File(operand).create();
              }
              if (synchronous) {
                Link(operand).createSync(target);
                return null;
              }
              return Link(operand).create(target);
            },
            operand,
            synchronous: synchronous,
          );
        }
      }
      final source = p.join('setup_alias', 'rename_${kind.toLowerCase()}');
      if (kind == 'Directory') {
        Directory(source).createSync();
      } else if (kind == 'File') {
        File(source).writeAsStringSync('source');
      } else {
        Link(source).createSync(target);
      }
      for (final (operand, destination) in [
        (source, 'setup_alias/absent/rename_destination'),
        ('setup_alias/absent/rename_source', 'setup_alias/rename_destination'),
        (
          'setup_alias/absent/rename_source',
          'setup_alias/absent/rename_destination',
        ),
      ]) {
        for (final synchronous in [true, false]) {
          final method = synchronous ? 'renameSync' : 'rename';
          await check(
            '$kind(${_q(operand)}).$method(${_q(destination)})',
            () {
              final FileSystemEntity entity = kind == 'Directory'
                  ? Directory(operand)
                  : kind == 'File'
                  ? File(operand)
                  : Link(operand);
              return synchronous
                  ? entity.renameSync(destination)
                  : entity.rename(destination);
            },
            operand,
            destination: destination,
            synchronous: synchronous,
          );
        }
      }
    }
    checks.require(
      !Directory('setup_missing').existsSync() &&
          !Directory('setup_real/missing').existsSync() &&
          !Directory('setup_real/absent').existsSync(),
      'failed setup creates no missing ancestor or destination',
    );
    checks.require(
      _ownedDescriptors(root.path) == descriptorsBefore,
      'failed creation and either rename endpoint release every owned descriptor',
    );
  } finally {
    Directory.current = previous;
  }
  print('FILESYSTEM_SETUP_DIAGNOSTICS_PASS');
}

Future<void> _responsiveness(D4rt host, Directory root) async {
  final source = File(p.join(root.path, 'large_source'));
  final writer = source.openSync(mode: FileMode.write);
  final block = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 65);
  try {
    for (var index = 0; index < 64; index++) {
      writer.writeFromSync(block);
    }
  } finally {
    writer.closeSync();
  }
  Future<int> turnsDuring(
    FutureOr<Object?> Function() operation,
    bool Function() substantiveWork,
  ) async {
    var turns = 0;
    final timer = Timer.periodic(Duration.zero, (_) {
      if (substantiveWork()) turns++;
    });
    try {
      await operation();
    } finally {
      timer.cancel();
    }
    checks.require(
      turns > 0,
      'bulk native IO services the caller event loop after setup',
    );
    return turns;
  }

  final copy = p.join(root.path, 'large_copy');
  final copyTurns = await turnsDuring(
    () => _call(host, 'File(${_q(source.path)}).copy(${_q(copy)})'),
    () => File(copy).existsSync(),
  );
  final reader = File(copy).openSync();
  try {
    checks.require(
      File(copy).lengthSync() == source.lengthSync() &&
          reader.readByteSync() == 65,
      'asynchronous copy produces native content',
    );
  } finally {
    reader.closeSync();
  }
  final tree = Directory(p.join(root.path, 'delete_tree'))..createSync();
  for (var index = 0; index < 160; index++) {
    File(p.join(tree.path, '$index')).writeAsStringSync('entry');
  }
  final deleteTurns = await turnsDuring(
    () => _call(host, 'Directory(${_q(tree.path)}).delete(recursive: true)'),
    () {
      try {
        return tree.existsSync() && tree.listSync().length < 160;
      } on FileSystemException {
        // A concurrent Windows delete-pending directory cannot be inspected.
        // Count only observations of a still-readable, partially deleted tree.
        return false;
      }
    },
  );
  checks.require(
    !tree.existsSync(),
    'asynchronous recursive deletion completes',
  );
  final created = p.join(root.path, 'async_parent', 'child');
  await _call(host, 'Directory(${_q(created)}).create(recursive: true)');
  final file = p.join(created, 'file');
  await _call(host, 'File(${_q(file)}).create()');
  final link = p.join(created, 'link');
  await _call(host, 'Link(${_q(link)}).create(${_q(file)})');
  await _call(host, 'Link(${_q(link)}).update(${_q(file)})');
  checks.require(
    await _call(host, 'Link(${_q(link)}).target()') == file,
    'asynchronous link target',
  );
  final renamed = '${link}_renamed';
  await _call(host, 'Link(${_q(link)}).rename(${_q(renamed)})');
  await _call(host, 'Link(${_q(renamed)}).delete()');
  source.deleteSync();
  File(copy).deleteSync();
  print(
    'FILESYSTEM_ASYNC_RESPONSIVENESS_PASS copy_turns=$copyTurns delete_turns=$deleteTurns',
  );
}
