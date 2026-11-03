import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;

import '../../security/permission_path.dart';
import 'descriptor_filesystem.dart';
import 'filesystem_execution.dart';
import 'filesystem_handle.dart';
import 'filesystem_mode.dart';

FilesystemExecution? filesystemExecution(
  InterpreterVisitor visitor, {
  Map<String, String> originalPaths = const {},
}) {
  final backend = DescriptorFilesystem.instance;
  if (backend == null) return null;
  return FilesystemExecution(
    (path, {bool write = false, bool read = false, bool followLinks = true}) {
      // Resolve before asking permission and execute exactly this canonical name.
      // A subsequent symlink substitution is rejected by the no-follow walk.
      _validateFilesystemPath(path);
      final canonical = resolvePermissionPath(path, followLinks: followLinks);
      // Separate grants may supply read and write authority. Check both against
      // this one canonical operand, matching the portable permission boundary.
      if (read || !write) {
        _checkFilesystemPermission(
          visitor,
          canonical,
          operation: 'access filesystem',
          read: true,
          followLinks: followLinks,
        );
      }
      if (write) {
        _checkFilesystemPermission(
          visitor,
          canonical,
          operation: 'access filesystem',
          write: true,
          followLinks: followLinks,
        );
      }
      return canonical;
    },
    backend,
    originalPaths,
  );
}

T executionFilesystemEntity<T extends FileSystemEntity>(
  InterpreterVisitor visitor,
  T entity, {
  Map<String, String> originalPaths = const {},
}) {
  final absolute = absoluteFilesystemEntity(entity);
  final execution = filesystemExecution(
    visitor,
    originalPaths: absolute.path == entity.path
        ? originalPaths
        : {...originalPaths, absolute.path: entity.path},
  );
  if (execution == null) return absolute;
  if (absolute is File) return ExecutionFile(execution, absolute.path) as T;
  if (absolute is Directory) {
    return ExecutionDirectory(execution, absolute.path) as T;
  }
  if (absolute is Link) return ExecutionLink(execution, absolute.path) as T;
  throw ArgumentError.value(entity, 'entity');
}

FileStat filesystemStatSync(InterpreterVisitor visitor, String path) =>
    filesystemExecution(visitor)?.stat(path) ?? FileStat.statSync(path);

Future<FileStat> filesystemStat(InterpreterVisitor visitor, String path) =>
    filesystemExecution(visitor)?.statAsync(path) ?? FileStat.stat(path);

FileSystemEntityType filesystemTypeSync(
  InterpreterVisitor visitor,
  String path, {
  bool followLinks = true,
}) =>
    filesystemExecution(visitor)?.type(path, followLinks: followLinks) ??
    FileSystemEntity.typeSync(path, followLinks: followLinks);

Future<FileSystemEntityType> filesystemType(
  InterpreterVisitor visitor,
  String path, {
  bool followLinks = true,
}) =>
    filesystemExecution(visitor)?.typeAsync(path, followLinks: followLinks) ??
    FileSystemEntity.type(path, followLinks: followLinks);

bool filesystemIdenticalSync(
  InterpreterVisitor visitor,
  String first,
  String second, {
  Map<String, String> originalPaths = const {},
}) =>
    filesystemExecution(
      visitor,
      originalPaths: originalPaths,
    )?.identical(first, second) ??
    FileSystemEntity.identicalSync(first, second);

Future<bool> filesystemIdentical(
  InterpreterVisitor visitor,
  String first,
  String second, {
  Map<String, String> originalPaths = const {},
}) =>
    filesystemExecution(
      visitor,
      originalPaths: originalPaths,
    )?.identicalAsync(first, second) ??
    FileSystemEntity.identical(first, second);

RandomAccessFile filesystemHandleAt(RandomAccessFile handle, String path) =>
    handle.path == path ? handle : FilesystemHandle(handle, path);

/// Decode once into an immutable string. Native raw-path constructors may retain
/// a caller-owned terminated buffer and decode malformed bytes lossily.
String filesystemPathFromBytes(Uint8List bytes) {
  final nul = bytes.indexOf(0);
  if (nul != -1 && nul != bytes.length - 1) {
    throw RuntimeError('Filesystem permission denied: invalid raw path.');
  }
  try {
    return utf8.decode(
      nul == -1 ? bytes : Uint8List.sublistView(bytes, 0, nul),
    );
  } on FormatException {
    throw RuntimeError('Filesystem permission denied: raw path is not UTF-8.');
  }
}

/// Recursion may create directories above a narrowly granted leaf. Check every
/// missing directory before asking the native implementation to create any.
void _checkMissingDirectories(InterpreterVisitor visitor, Directory directory) {
  while (!directory.existsSync()) {
    checkFilesystemWritePermission(
      visitor,
      directory.path,
      operation: 'create ancestor directory',
    );
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
}

void checkFilesystemCreate(
  InterpreterVisitor visitor,
  String path, {
  required bool recursive,
  bool directory = false,
}) {
  checkFilesystemWritePermission(visitor, path, operation: 'create entity');
  if (recursive) {
    final entry = Directory(path);
    _checkMissingDirectories(visitor, directory ? entry : entry.parent);
  }
}

FileSystemEntity filesystemEntityAt(FileSystemEntity entity, String path) {
  if (entity is File) return File(path);
  if (entity is Directory) return Directory(path);
  if (entity is Link) return Link(path);
  throw ArgumentError.value(entity, 'entity', 'Unknown filesystem entity');
}

// Reject invalid original inputs before absolute conversion or target joining
// can turn an empty path into authority over the working directory.
void _validateFilesystemPath(String path) {
  if (path.isEmpty || path.contains('\u0000')) {
    throw RuntimeError(
      'Filesystem permission denied: invalid filesystem path.',
    );
  }
}

String absoluteFilesystemPath(String path) {
  _validateFilesystemPath(path);
  return File(path).absolute.path;
}

T absoluteFilesystemEntity<T extends FileSystemEntity>(T entity) {
  _validateFilesystemPath(entity.path);
  if (entity is File || entity is Directory) return entity.absolute as T;
  if (entity is Link) return Link(entity.path).absolute as T;
  throw ArgumentError.value(entity, 'entity', 'Unknown filesystem entity');
}

String _childResultPath(String original, String absolute, String result) {
  final suffix = p.relative(result, from: absolute);
  if (suffix == '.') return original;
  if (p.isWithin(absolute, result)) return p.join(original, suffix);
  // A file watcher can report a sibling destination. Never present that as
  // traversal through the watched file (for example, "data/../renamed").
  final parent = p.dirname(original);
  final sibling = p.relative(result, from: p.dirname(absolute));
  return parent == '.' ? sibling : p.join(parent, sibling);
}

void checkFilesystemReadPermission(
  InterpreterVisitor visitor,
  String path, {
  String operation = 'read',
  bool followLinks = true,
}) {
  _checkFilesystemPermission(
    visitor,
    path,
    operation: operation,
    read: true,
    followLinks: followLinks,
  );
}

void checkFilesystemWritePermission(
  InterpreterVisitor visitor,
  String path, {
  String operation = 'write',
  bool followLinks = true,
}) {
  _checkFilesystemPermission(
    visitor,
    path,
    operation: operation,
    write: true,
    followLinks: followLinks,
  );
}

void checkFilesystemExecutePermission(
  InterpreterVisitor visitor,
  String path, {
  String operation = 'execute',
}) {
  _checkFilesystemPermission(
    visitor,
    path,
    operation: operation,
    execute: true,
  );
}

void _checkFilesystemPermission(
  InterpreterVisitor visitor,
  String path, {
  required String operation,
  bool read = false,
  bool write = false,
  bool execute = false,
  bool followLinks = true,
}) {
  _validateFilesystemPath(path);
  final d4rt = visitor.moduleLoader.d4rt;
  if (d4rt == null) {
    throw RuntimeError('Filesystem permission denied: no interpreter owner.');
  }
  var allowed = false;
  try {
    allowed = d4rt.checkPermission({
      'type': 'filesystem',
      'path': path,
      'read': read,
      'write': write,
      'execute': execute,
      'followLinks': followLinks,
    });
  } on Object {
    allowed = false;
  }
  if (!allowed) {
    throw RuntimeError(
      'Filesystem permission denied for $operation on "$path". '
      'Grant an appropriate FilesystemPermission for this path.',
    );
  }
}

/// Namespace operations affect entries, not the contents of their final targets.
void checkFilesystemEntryWrite(
  InterpreterVisitor visitor,
  String path, {
  required String operation,
}) {
  checkFilesystemWritePermission(
    visitor,
    path,
    operation: operation,
    followLinks: false,
  );
  final entry = resolvePermissionPath(path, followLinks: false);
  checkFilesystemWritePermission(
    visitor,
    p.dirname(entry),
    operation: operation,
  );
}

void checkFilesystemLinkTarget(
  InterpreterVisitor visitor,
  String entry,
  String target, {
  required String operation,
}) {
  _validateFilesystemPath(target);
  final parent = p.dirname(resolvePermissionPath(entry, followLinks: false));
  checkFilesystemReadPermission(
    visitor,
    p.isAbsolute(target) ? target : p.join(parent, target),
    operation: operation,
  );
}

void checkFilesystemLinkChange(
  InterpreterVisitor visitor,
  String entry,
  String target, {
  required String operation,
  bool recursive = false,
}) {
  checkFilesystemEntryWrite(visitor, entry, operation: operation);
  checkFilesystemLinkTarget(visitor, entry, target, operation: operation);
  if (recursive) _checkMissingDirectories(visitor, Directory(entry).parent);
}

void checkFilesystemOpen(
  InterpreterVisitor visitor,
  String path,
  FileMode mode,
) {
  if (mode.requiresFilesystemRead) {
    checkFilesystemReadPermission(visitor, path, operation: 'open file');
  }
  if (mode.requiresFilesystemWrite) {
    checkFilesystemWritePermission(visitor, path, operation: 'open file');
  }
}

String resolveFilesystemLinksSync(
  InterpreterVisitor visitor,
  FileSystemEntity entity,
) {
  entity = absoluteFilesystemEntity(entity);
  checkFilesystemReadPermission(
    visitor,
    entity.path,
    operation: 'resolve links',
  );
  final result = entity.resolveSymbolicLinksSync();
  checkFilesystemReadPermission(
    visitor,
    result,
    operation: 'expose resolved path',
  );
  return result;
}

Future<String> resolveFilesystemLinks(
  InterpreterVisitor visitor,
  FileSystemEntity entity,
) async {
  entity = absoluteFilesystemEntity(entity);
  checkFilesystemReadPermission(
    visitor,
    entity.path,
    operation: 'resolve links',
  );
  final result = await entity.resolveSymbolicLinks();
  checkFilesystemReadPermission(
    visitor,
    entity.path,
    operation: 'resolve links',
  );
  checkFilesystemReadPermission(
    visitor,
    result,
    operation: 'expose resolved path',
  );
  return result;
}

/// Keeps native broadcast/cancellation behavior while guarding each subscription
/// and exposure. The producer must already use an anchored absolute path.
Stream<T> guardFilesystemStream<T>(
  Stream<T> source,
  void Function() check,
  void Function(T) checkValue,
) => _FilesystemStream(source, check, checkValue);

class _FilesystemStream<T> extends Stream<T> {
  final Stream<T> _source;
  final void Function() _check;
  final void Function(T) _checkValue;
  final bool? _broadcast;

  _FilesystemStream(
    this._source,
    this._check,
    this._checkValue, {
    bool? broadcast,
  }) : _broadcast = broadcast;

  @override
  bool get isBroadcast => _broadcast ?? _source.isBroadcast;

  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    try {
      _check();
    } on Object catch (error, stack) {
      return Stream<T>.error(error, stack).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
    return _source
        .map((value) {
          _check();
          _checkValue(value);
          return value;
        })
        .listen(
          onData,
          onError: onError,
          onDone: onDone,
          cancelOnError: cancelOnError,
        );
  }
}

Stream<FileSystemEntity> listFilesystem(
  InterpreterVisitor visitor,
  Directory directory, {
  required bool recursive,
  required bool followLinks,
}) {
  final original = directory.path;
  directory = executionFilesystemEntity(visitor, directory);
  void check() => checkFilesystemReadPermission(
    visitor,
    directory.path,
    operation: 'list directory',
  );
  check();
  final stream = guardFilesystemStream(
    directory.list(recursive: recursive, followLinks: followLinks),
    check,
    (entry) => checkFilesystemReadPermission(
      visitor,
      entry.path,
      operation: 'expose directory entry',
      followLinks: entry is! Link,
    ),
  );
  if (p.isAbsolute(original)) return stream;
  return stream.map(
    (entry) => filesystemEntityAt(
      entry,
      _childResultPath(original, directory.path, entry.path),
    ),
  );
}

List<FileSystemEntity> listFilesystemSync(
  InterpreterVisitor visitor,
  Directory directory, {
  required bool recursive,
  required bool followLinks,
}) {
  final original = directory.path;
  directory = executionFilesystemEntity(visitor, directory);
  checkFilesystemReadPermission(
    visitor,
    directory.path,
    operation: 'list directory',
  );
  final entries = directory.listSync(
    recursive: recursive,
    followLinks: followLinks,
  );
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    checkFilesystemReadPermission(
      visitor,
      entry.path,
      operation: 'expose directory entry',
      followLinks: entry is! Link,
    );
    if (!p.isAbsolute(original)) {
      entries[index] = filesystemEntityAt(
        entry,
        _childResultPath(original, directory.path, entry.path),
      );
    }
  }
  return entries;
}

Stream<FileSystemEvent> watchFilesystem(
  InterpreterVisitor visitor,
  FileSystemEntity entity, {
  required int events,
  required bool recursive,
}) {
  final original = entity.path;
  entity = absoluteFilesystemEntity(entity);
  void check() => checkFilesystemReadPermission(
    visitor,
    entity.path,
    operation: 'watch filesystem',
  );
  check();
  // Some SDK watchers use a multi-listen stream without advertising broadcast.
  // Keep the documented watch contract without wrapping native subscriptions.
  final stream = _FilesystemStream(
    entity.watch(events: events, recursive: recursive),
    check,
    (event) {
      checkFilesystemReadPermission(
        visitor,
        event.path,
        operation: 'expose watch event',
      );
      if (event is FileSystemMoveEvent && event.destination != null) {
        checkFilesystemReadPermission(
          visitor,
          event.destination!,
          operation: 'expose watch destination',
        );
      }
    },
    broadcast: true,
  );
  if (p.isAbsolute(original)) return stream;
  return stream.map((event) => _watchResult(original, entity.path, event));
}

FileSystemEvent _watchResult(
  String original,
  String absolute,
  FileSystemEvent event,
) {
  final path = _childResultPath(original, absolute, event.path);
  final isDirectory = event.isDirectory;
  return switch (event) {
    FileSystemCreateEvent() => FileSystemCreateEvent(path, isDirectory),
    FileSystemModifyEvent() => FileSystemModifyEvent(
      path,
      isDirectory,
      event.contentChanged,
    ),
    FileSystemDeleteEvent() => FileSystemDeleteEvent(path, isDirectory),
    FileSystemMoveEvent() => FileSystemMoveEvent(
      path,
      isDirectory,
      event.destination == null
          ? null
          : _childResultPath(original, absolute, event.destination!),
    ),
  };
}

String? validateFilesystemTempPrefix(String? prefix) {
  if (prefix != null &&
      (prefix.contains(RegExp(r'[\\/\x00-\x1f<>:"|?*]')) ||
          prefix == '.' ||
          prefix == '..' ||
          prefix.endsWith(' ') ||
          prefix.endsWith('.'))) {
    throw RuntimeError(
      'Invalid temporary directory prefix. Use a simple name.',
    );
  }
  return prefix;
}

Future<Directory> createFilesystemTemp(
  InterpreterVisitor visitor,
  Directory directory,
  String? prefix,
) async {
  final original = directory.path;
  if (original.isEmpty) {
    throw ArgumentError('Directory.createTemp called with an empty path.');
  }
  directory = executionFilesystemEntity(visitor, directory);
  validateFilesystemTempPrefix(prefix);
  checkFilesystemWritePermission(
    visitor,
    directory.path,
    operation: 'create temporary directory',
  );
  final result = await directory.createTemp(prefix);
  checkFilesystemWritePermission(
    visitor,
    result.path,
    operation: 'expose temporary directory',
  );
  return _tempResult(original, directory.path, result);
}

Directory createFilesystemTempSync(
  InterpreterVisitor visitor,
  Directory directory,
  String? prefix,
) {
  final original = directory.path;
  if (original.isEmpty) {
    throw ArgumentError('Directory.createTemp called with an empty path.');
  }
  directory = executionFilesystemEntity(visitor, directory);
  validateFilesystemTempPrefix(prefix);
  checkFilesystemWritePermission(
    visitor,
    directory.path,
    operation: 'create temporary directory',
  );
  final result = directory.createTempSync(prefix);
  checkFilesystemWritePermission(
    visitor,
    result.path,
    operation: 'expose temporary directory',
  );
  return _tempResult(original, directory.path, result);
}

Directory _tempResult(String original, String absolute, Directory result) =>
    p.isAbsolute(original)
    ? result
    : Directory(_childResultPath(original, absolute, result.path));
