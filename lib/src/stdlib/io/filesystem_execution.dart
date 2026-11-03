import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'descriptor_filesystem.dart';
import 'filesystem_error.dart' as errors;
import 'filesystem_mode.dart';

typedef FilesystemAuthorization =
    String Function(String path, {bool write, bool read, bool followLinks});

void _checkFileWriteMode(FileMode mode) {
  if (mode != FileMode.write &&
      mode != FileMode.append &&
      mode != FileMode.writeOnly &&
      mode != FileMode.writeOnlyAppend) {
    throw ArgumentError.value(
      mode,
      'mode',
      'Invalid file mode for this operation',
    );
  }
}

/// Internal operation adapters. These never escape as result entities: every
/// durable result is rebuilt with its caller's path, not a /proc descriptor path.
final class FilesystemExecution {
  final FilesystemAuthorization authorize;
  final DescriptorFilesystem backend;
  final Map<String, String> originalPaths;

  FilesystemExecution(this.authorize, this.backend, this.originalPaths);

  // Native operands are translated before the captured caller spelling. Keeping
  // these stages separate also covers descendants and two-endpoint diagnostics.
  Object filesystemError(Object error, Map<String, String> operands) => errors
      .filesystemError(errors.filesystemError(error, operands), originalPaths);

  T filesystemErrorSync<T>(T Function() action, Map<String, String> operands) =>
      errors.filesystemErrorSync(
        () => errors.filesystemErrorSync(action, operands),
        originalPaths,
      );

  Future<T> filesystemErrorAsync<T>(
    Future<T> Function() action,
    Map<String, String> operands,
  ) => errors.filesystemErrorAsync(
    () => errors.filesystemErrorAsync(action, operands),
    originalPaths,
  );

  T sync<T>(
    String path,
    T Function(File) action, {
    bool write = false,
    bool read = false,
    bool metadata = false,
    bool create = false,
  }) {
    final canonical = authorize(
      path,
      write: write,
      read: read,
      followLinks: true,
    );
    final operands = <String, String>{canonical: path};
    Descriptor? handle;
    try {
      handle = backend.open(
        canonical,
        metadata: metadata,
        write: write,
        create: create,
      );
      operands[handle.path] = path;
      return action(File(handle.path));
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      handle?.close();
    }
  }

  Future<T> async<T>(
    String path,
    Future<T> Function(File) action, {
    bool write = false,
    bool read = false,
    bool metadata = false,
    bool create = false,
  }) async {
    final canonical = authorize(
      path,
      write: write,
      read: read,
      followLinks: true,
    );
    final operands = <String, String>{canonical: path};
    Descriptor? handle;
    try {
      handle = backend.open(
        canonical,
        metadata: metadata,
        write: write,
        create: create,
      );
      operands[handle.path] = path;
      return await action(File(handle.path));
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      handle?.close();
    }
  }

  // A failed parent walk belongs to the full requested entry, not its shorter
  // canonical parent. Translate here, before any descriptor operand exists.
  Descriptor _parent(String canonical, String path) => filesystemErrorSync(
    () => backend.parent(canonical),
    {p.dirname(canonical): path},
  );

  ({String path, Descriptor? parent, Map<String, String> operands})
  _entryLocation(String path, {required bool write, String? linkTarget}) {
    final canonical = authorize(path, write: write, followLinks: false);
    if (linkTarget != null) {
      authorize(
        p.isAbsolute(linkTarget)
            ? linkTarget
            : p.join(p.dirname(canonical), linkTarget),
        write: false,
        followLinks: true,
      );
    }
    if (write) authorize(p.dirname(canonical), write: true, followLinks: true);
    final operands = <String, String>{
      canonical: path,
      p.dirname(canonical): p.dirname(path),
    };
    if (canonical == '/') return (path: '/', parent: null, operands: operands);
    return filesystemErrorSync(() {
      final parent = _parent(canonical, path);
      final anchored = p.join(parent.path, p.basename(canonical));
      operands[parent.path] = p.dirname(path);
      operands[anchored] = path;
      return (path: anchored, parent: parent, operands: operands);
    }, operands);
  }

  T entry<T>(
    String path,
    T Function(String) action, {
    bool write = true,
    String? linkTarget,
  }) {
    final location = _entryLocation(path, write: write, linkTarget: linkTarget);
    try {
      return filesystemErrorSync(
        () => action(location.path),
        location.operands,
      );
    } finally {
      location.parent?.close();
    }
  }

  Future<T> entryAsync<T>(
    String path,
    Future<T> Function(String) action, {
    bool write = true,
    String? linkTarget,
  }) async {
    final location = _entryLocation(path, write: write, linkTarget: linkTarget);
    try {
      return await filesystemErrorAsync(
        () => action(location.path),
        location.operands,
      );
    } finally {
      location.parent?.close();
    }
  }

  FileStat stat(String path) {
    try {
      return sync(path, (file) => file.statSync(), metadata: true);
    } on FileSystemException {
      return FileStat.statSync('/proc/self/fd/-1');
    }
  }

  FileSystemEntityType type(String path, {bool followLinks = true}) {
    if (followLinks) return stat(path).type;
    try {
      return entry(
        path,
        (entry) => FileSystemEntity.typeSync(entry, followLinks: false),
        write: false,
      );
    } on FileSystemException {
      // SDK type queries normalize lookup failures, but never policy denials
      // (which are RuntimeError, not FileSystemException).
      return FileSystemEntityType.notFound;
    }
  }

  bool identical(String first, String second) => entry(
    first,
    (a) => entry(
      second,
      (b) => filesystemErrorSync(() => FileSystemEntity.identicalSync(a, b), {
        a: first,
        b: second,
      }),
      write: false,
    ),
    write: false,
  );

  Future<FileStat> statAsync(String path) async {
    try {
      return await async(path, (file) => file.stat(), metadata: true);
    } on FileSystemException {
      return FileStat.stat('/proc/self/fd/-1');
    }
  }

  Future<FileSystemEntityType> typeAsync(
    String path, {
    bool followLinks = true,
  }) async {
    if (followLinks) return (await statAsync(path)).type;
    try {
      return await entryAsync(
        path,
        (entry) => FileSystemEntity.type(entry, followLinks: false),
        write: false,
      );
    } on FileSystemException {
      return FileSystemEntityType.notFound;
    }
  }

  Future<bool> identicalAsync(String first, String second) => entryAsync(
    first,
    (a) => entryAsync(
      second,
      (b) => filesystemErrorAsync(() => FileSystemEntity.identical(a, b), {
        a: first,
        b: second,
      }),
      write: false,
    ),
    write: false,
  );

  void create(
    String path, {
    required bool directory,
    bool recursive = false,
    bool exclusive = false,
  }) {
    final canonical = authorize(path, write: true, followLinks: !exclusive);
    final operands = <String, String>{canonical: path};
    Descriptor? parent;
    Descriptor? held;
    try {
      if (recursive && canonical != '/') {
        try {
          _parent(canonical, path).close();
        } on PathNotFoundException {
          create(p.dirname(canonical), directory: true, recursive: true);
        }
      }
      if (directory) {
        if (canonical == '/') return;
        parent = _parent(canonical, path);
        operands[parent.path] = p.dirname(path);
        try {
          backend.mkdir(parent, p.basename(canonical));
        } on PathExistsException catch (error) {
          held = backend.open(canonical, metadata: true);
          operands[held.path] = path;
          if (FileStat.statSync(held.path).type !=
              FileSystemEntityType.directory) {
            throw FileSystemException('Creation failed', path, error.osError);
          }
        }
      } else {
        if (!exclusive) {
          try {
            held = backend.open(canonical, metadata: true);
            operands[held.path] = path;
            if (FileStat.statSync(held.path).type ==
                FileSystemEntityType.file) {
              return;
            }
            throw FileSystemException(
              'Cannot create a file of this type',
              path,
            );
          } on PathNotFoundException {
            // Only a genuinely missing file permits creation.
          } finally {
            held?.close();
            held = null;
          }
        }
        try {
          held = backend.open(
            canonical,
            write: true,
            create: true,
            exclusive: true,
          );
        } on PathExistsException {
          if (exclusive) rethrow;
          held = backend.open(canonical, metadata: true);
        }
        operands[held.path] = path;
        if (FileStat.statSync(held.path).type != FileSystemEntityType.file) {
          throw FileSystemException('Cannot create a file of this type', path);
        }
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      try {
        held?.close();
      } finally {
        parent?.close();
      }
    }
  }

  Future<void> createAsync(
    String path, {
    required bool directory,
    bool recursive = false,
    bool exclusive = false,
  }) async {
    final canonical = authorize(path, write: true, followLinks: !exclusive);
    final operands = <String, String>{canonical: path};
    Descriptor? parent;
    try {
      if (canonical == '/' && directory) {
        await Directory('/').create();
        return;
      }
      try {
        parent = _parent(canonical, path);
      } on PathNotFoundException {
        if (!recursive) rethrow;
        await createAsync(
          p.dirname(canonical),
          directory: true,
          recursive: true,
        );
        parent = _parent(canonical, path);
      }
      final anchored = p.join(parent.path, p.basename(canonical));
      operands[parent.path] = p.dirname(path);
      operands[anchored] = path;
      if (directory) {
        await Directory(anchored).create();
      } else {
        try {
          await File(anchored).create(exclusive: true);
        } on FileSystemException catch (error) {
          if (exclusive || error.osError?.errorCode != 17) rethrow;
        }
      }
      // SDK creation is asynchronous. Inspect any existing/replaced final entry
      // without following it before reporting success. File creation uses
      // O_EXCL even for nonexclusive calls, so it cannot follow a final link.
      final held = backend.openAnchored(anchored);
      try {
        operands[held.path] = path;
        final mode = backend.identity(held).mode & 0xf000;
        if (mode != (directory ? 0x4000 : 0x8000)) {
          throw FileSystemException(
            'Cannot create an entity of this type',
            path,
          );
        }
      } finally {
        held.close();
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      parent?.close();
    }
  }

  void delete(FileSystemEntity entity, bool recursive) {
    entry(entity.path, (path) {
      if (!recursive) {
        if (entity is Directory) {
          Directory(path).deleteSync();
        } else if (entity is Link) {
          Link(path).deleteSync();
        } else {
          File(path).deleteSync();
        }
        return;
      }
      _deleteTree(path, entity.path);
    });
  }

  void _deleteTree(String anchored, String original) {
    final operands = <String, String>{anchored: original};
    Descriptor? held;
    try {
      final type = FileSystemEntity.typeSync(anchored, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        held = backend.openAnchored(anchored, directory: true);
        operands[held.path] = original;
        for (final child in Directory(held.path).listSync(followLinks: false)) {
          _deleteTree(child.path, p.join(original, p.basename(child.path)));
        }
        Directory(anchored).deleteSync();
      } else if (type == FileSystemEntityType.link) {
        Link(anchored).deleteSync();
      } else {
        File(anchored).deleteSync();
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      held?.close();
    }
  }

  Future<void> deleteAsync(FileSystemEntity entity, bool recursive) =>
      entryAsync(entity.path, (path) async {
        if (recursive) {
          await _deleteTreeAsync(path, entity.path);
        } else if (entity is Directory) {
          await Directory(path).delete();
        } else if (entity is Link) {
          await Link(path).delete();
        } else {
          await File(path).delete();
        }
      });

  Future<void> _deleteTreeAsync(String anchored, String original) async {
    final operands = <String, String>{anchored: original};
    Descriptor? held;
    try {
      final type = await FileSystemEntity.type(anchored, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        held = backend.openAnchored(anchored, directory: true);
        operands[held.path] = original;
        await for (final child in Directory(
          held.path,
        ).list(followLinks: false)) {
          await _deleteTreeAsync(
            child.path,
            p.join(original, p.basename(child.path)),
          );
        }
        await Directory(anchored).delete();
      } else if (type == FileSystemEntityType.link) {
        await Link(anchored).delete();
      } else {
        await File(anchored).delete();
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      held?.close();
    }
  }

  FileSystemEntity rename(FileSystemEntity entity, String destination) {
    var setupComplete = false;
    try {
      return entry(
        entity.path,
        (source) => entry(
          destination,
          (target) => filesystemErrorSync(() {
            setupComplete = true;
            if (entity is Directory) {
              Directory(source).renameSync(target);
              return Directory(destination);
            }
            if (entity is Link) {
              Link(source).renameSync(target);
              return Link(destination);
            }
            File(source).renameSync(target);
            return File(destination);
          }, {source: entity.path, target: destination}),
        ),
      );
    } on Object catch (error, stack) {
      if (setupComplete) rethrow;
      Error.throwWithStackTrace(
        _renameSetupError(error, entity, destination),
        stack,
      );
    }
  }

  Future<FileSystemEntity> renameAsync(
    FileSystemEntity entity,
    String destination,
  ) async {
    var setupComplete = false;
    try {
      return await entryAsync(
        entity.path,
        (source) => entryAsync(
          destination,
          (target) => filesystemErrorAsync(() async {
            setupComplete = true;
            if (entity is Directory) {
              await Directory(source).rename(target);
              return Directory(destination);
            }
            if (entity is Link) {
              await Link(source).rename(target);
              return Link(destination);
            }
            await File(source).rename(target);
            return File(destination);
          }, {source: entity.path, target: destination}),
        ),
      );
    } on Object catch (error, stack) {
      if (setupComplete) rethrow;
      Error.throwWithStackTrace(
        _renameSetupError(error, entity, destination),
        stack,
      );
    }
  }

  Object _renameSetupError(
    Object error,
    FileSystemEntity entity,
    String destination,
  ) {
    final kind = entity is Directory
        ? 'directory'
        : entity is Link
        ? 'link'
        : 'file';
    return errors.filesystemOperationError(
      error,
      "Cannot rename $kind to '${originalPaths[destination] ?? destination}'",
      originalPaths[entity.path] ?? entity.path,
    );
  }

  File copy(String source, String destination) {
    final canonicalSource = authorize(source, write: false, followLinks: true);
    final canonicalTarget = authorize(
      destination,
      write: true,
      followLinks: true,
    );
    final operands = <String, String>{
      canonicalSource: source,
      canonicalTarget: destination,
    };
    Descriptor? input;
    try {
      input = backend.open(canonicalSource);
      operands[input.path] = source;
      // Validate source before opening/truncating any destination, including
      // self-copy and hard-link aliases. Compare the held inode identities.
      if (FileStat.statSync(input.path).type != FileSystemEntityType.file) {
        throw FileSystemException('Cannot copy a non-file', source);
      }
      final output = backend.open(canonicalTarget, write: true, create: true);
      operands[output.path] = destination;
      try {
        if (!backend.sameObject(input, output)) {
          File(input.path).copySync(output.path);
        }
      } finally {
        output.close();
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        errors.filesystemOperationError(
          filesystemError(error, operands),
          "Cannot copy file to '${originalPaths[destination] ?? destination}'",
          originalPaths[source] ?? source,
        ),
        stack,
      );
    } finally {
      input?.close();
    }
    return File(destination);
  }

  Future<File> copyAsync(String source, String destination) async {
    final canonicalSource = authorize(source, write: false, followLinks: true);
    final canonicalTarget = authorize(
      destination,
      write: true,
      followLinks: true,
    );
    final operands = <String, String>{
      canonicalSource: source,
      canonicalTarget: destination,
    };
    Descriptor? input;
    try {
      input = backend.open(canonicalSource);
      operands[input.path] = source;
      if ((await FileStat.stat(input.path)).type != FileSystemEntityType.file) {
        throw FileSystemException('Cannot copy a non-file', source);
      }
      final output = backend.open(canonicalTarget, write: true, create: true);
      operands[output.path] = destination;
      try {
        if (!backend.sameObject(input, output)) {
          await File(input.path).copy(output.path);
        }
      } finally {
        output.close();
      }
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        errors.filesystemOperationError(
          filesystemError(error, operands),
          "Cannot copy file to '${originalPaths[destination] ?? destination}'",
          originalPaths[source] ?? source,
        ),
        stack,
      );
    } finally {
      input?.close();
    }
    return File(destination);
  }

  ({
    FileSystemEntity entity,
    String canonical,
    Descriptor? directory,
    (int, int, int)? followedLink,
  })
  _listedEntry(
    FileSystemEntity entry,
    String logical,
    String resultParent,
    bool followLinks,
    Set<(int, int, int)> followedLinks,
    bool recursive,
  ) {
    final name = p.basename(entry.path);
    final child = p.join(logical, name);
    final result = p.join(resultParent, name);
    if (entry is Link && !followLinks) {
      authorize(child, write: false, followLinks: false);
      return (
        entity: Link(result),
        canonical: child,
        directory: null,
        followedLink: null,
      );
    }
    (int, int, int)? linkIdentity;
    if (entry is Link) {
      authorize(child, write: false, followLinks: false);
      if (recursive) {
        linkIdentity = _linkIdentity(entry.path, child);
        // The SDK follows each link once per descent, not each directory target.
        // Ordinary ancestors (including the root) do not seed this set.
        if (followedLinks.contains(linkIdentity)) {
          return (
            entity: Link(result),
            canonical: child,
            directory: null,
            followedLink: null,
          );
        }
      }
      // Native listing reports broken and self-cyclic links as entries without
      // requiring authority over a nonexistent target. This private existence
      // classification exposes no target metadata; working targets still pass
      // canonical authorization before being opened or yielded.
      if (FileSystemEntity.typeSync(entry.path) ==
          FileSystemEntityType.notFound) {
        return (
          entity: Link(result),
          canonical: child,
          directory: null,
          followedLink: null,
        );
      }
    }
    final target = authorize(child, write: false, followLinks: true);
    final operands = <String, String>{entry.path: child, target: child};
    Descriptor? next;
    try {
      next = entry is Link
          ? backend.open(target, metadata: true)
          : backend.openAnchored(entry.path);
      operands[next.path] = child;
      final identity = backend.identity(next);
      final mode = identity.mode & 0xf000;
      if (mode == 0xa000) {
        throw FileSystemException(
          'Symbolic link changed after authorization',
          child,
        );
      }
      if (mode == 0x4000) {
        final directory = next;
        next = null;
        return (
          entity: Directory(result),
          canonical: target,
          directory: directory,
          followedLink: linkIdentity,
        );
      }
      return (
        entity: File(result),
        canonical: target,
        directory: null,
        followedLink: null,
      );
    } on PathNotFoundException catch (error, stack) {
      if (entry is! Link) {
        Error.throwWithStackTrace(filesystemError(error, operands), stack);
      }
      return (
        entity: Link(result),
        canonical: target,
        directory: null,
        followedLink: null,
      );
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      next?.close();
    }
  }

  (int, int, int) _linkIdentity(String anchored, String original) {
    final operands = <String, String>{anchored: original};
    Descriptor? held;
    try {
      held = backend.openAnchored(anchored);
      operands[held.path] = original;
      final identity = backend.identity(held);
      if ((identity.mode & 0xf000) != 0xa000) {
        throw FileSystemException(
          'Symbolic link changed after enumeration',
          original,
        );
      }
      return (identity.major, identity.minor, identity.inode);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      held?.close();
    }
  }

  List<FileSystemEntity> list(
    String path, {
    required bool recursive,
    required bool followLinks,
  }) {
    final canonical = authorize(path, write: false, followLinks: true);
    final root = filesystemErrorSync(
      () => backend.open(canonical, metadata: true),
      {canonical: path},
    );
    final results = <FileSystemEntity>[];
    final followedLinks = <(int, int, int)>{};
    void walk(Descriptor held, String logical, String resultParent) {
      try {
        for (final entry in Directory(held.path).listSync(followLinks: false)) {
          final next = _listedEntry(
            entry,
            logical,
            resultParent,
            followLinks,
            followedLinks,
            recursive,
          );
          try {
            results.add(next.entity);
            if (recursive && next.directory != null) {
              final key = next.followedLink;
              if (key != null) followedLinks.add(key);
              try {
                walk(next.directory!, next.canonical, next.entity.path);
              } finally {
                if (key != null) followedLinks.remove(key);
              }
            }
          } finally {
            next.directory?.close();
          }
        }
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(
          filesystemError(error, {
            held.path: resultParent,
            logical: resultParent,
          }),
          stack,
        );
      }
    }

    try {
      walk(root, canonical, path);
    } finally {
      root.close();
    }
    return results;
  }

  Stream<FileSystemEntity> listStream(
    String path, {
    required bool recursive,
    required bool followLinks,
  }) async* {
    // Acquisition happens on listen. Await-for and async* finally blocks release
    // both native enumeration and child/root anchors on errors and cancellation.
    // Yield entries incrementally, including entries preceding a later error.
    final canonical = authorize(path, write: false, followLinks: true);
    final root = filesystemErrorSync(
      () => backend.open(canonical, metadata: true),
      {canonical: path},
    );
    final followedLinks = <(int, int, int)>{};
    Stream<FileSystemEntity> walk(
      Descriptor held,
      String logical,
      String resultParent,
    ) async* {
      try {
        await for (final entry in Directory(
          held.path,
        ).list(followLinks: false)) {
          final next = _listedEntry(
            entry,
            logical,
            resultParent,
            followLinks,
            followedLinks,
            recursive,
          );
          try {
            yield next.entity;
            if (recursive && next.directory != null) {
              final key = next.followedLink;
              if (key != null) followedLinks.add(key);
              try {
                yield* walk(next.directory!, next.canonical, next.entity.path);
              } finally {
                if (key != null) followedLinks.remove(key);
              }
            }
          } finally {
            next.directory?.close();
          }
        }
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(
          filesystemError(error, {
            held.path: resultParent,
            logical: resultParent,
          }),
          stack,
        );
      }
    }

    try {
      yield* walk(root, canonical, path);
    } finally {
      root.close();
    }
  }

  String _tempName(String? prefix, Random random) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return '${prefix ?? ''}${String.fromCharCodes(List.generate(12, (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length))))}';
  }

  Directory temp(String path, String? prefix) {
    final canonical = authorize(path, write: true, followLinks: true);
    final operands = <String, String>{canonical: path};
    Descriptor? held;
    try {
      held = backend.open(canonical, metadata: true);
      operands[held.path] = path;
      final random = Random.secure();
      for (var attempt = 0; attempt < 64; attempt++) {
        final name = _tempName(prefix, random);
        try {
          backend.mkdir(held, name, mode: 0x1c0);
          return Directory(p.join(path, name));
        } on PathExistsException {
          // A collision never authorizes opening or reusing the existing entry.
        }
      }
      throw FileSystemException(
        'Cannot create a unique temporary directory',
        path,
      );
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      held?.close();
    }
  }

  Future<Directory> tempAsync(String path, String? prefix) async {
    final canonical = authorize(path, write: true, followLinks: true);
    final operands = <String, String>{canonical: path};
    Descriptor? held;
    try {
      held = backend.open(canonical, metadata: true);
      operands[held.path] = path;
      final random = Random.secure();
      for (var attempt = 0; attempt < 64; attempt++) {
        final name = _tempName(prefix, random);
        try {
          // A fixed mkdirat setup call preserves 0700 without starting a worker.
          // Bulk content and traversal continue through asynchronous SDK IO.
          backend.mkdir(held, name, mode: 0x1c0);
          return Directory(p.join(path, name));
        } on PathExistsException {
          // Match the synchronous collision rule without opening the entry.
        }
      }
      throw FileSystemException(
        'Cannot create a unique temporary directory',
        path,
      );
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(filesystemError(error, operands), stack);
    } finally {
      held?.close();
    }
  }
}

abstract class _Entity implements FileSystemEntity {
  final FilesystemExecution execution;

  _Entity(this.execution, this.path);

  FileSystemEntity get native;

  @override
  final String path;

  @override
  bool get isAbsolute => p.isAbsolute(path);

  @override
  Uri get uri => native.uri;

  @override
  Directory get parent => native.parent;

  @override
  FileSystemEntity get absolute => native.absolute;

  FileSystemEntityType get _expectedType => this is Directory
      ? FileSystemEntityType.directory
      : this is Link
      ? FileSystemEntityType.link
      : FileSystemEntityType.file;

  @override
  Future<bool> exists() async =>
      await execution.typeAsync(path, followLinks: this is! Link) ==
      _expectedType;

  @override
  bool existsSync() =>
      execution.type(path, followLinks: this is! Link) == _expectedType;

  @override
  Future<FileStat> stat() => execution.statAsync(path);

  @override
  FileStat statSync() => execution.stat(path);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await execution.deleteAsync(native, recursive);
    return native;
  }

  @override
  void deleteSync({bool recursive = false}) =>
      execution.delete(native, recursive);

  @override
  Future<FileSystemEntity> rename(String newPath) =>
      execution.renameAsync(native, newPath);

  @override
  FileSystemEntity renameSync(String newPath) =>
      execution.rename(native, newPath);

  @override
  Future<String> resolveSymbolicLinks() => native.resolveSymbolicLinks();

  @override
  String resolveSymbolicLinksSync() => native.resolveSymbolicLinksSync();

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => native.watch(events: events, recursive: recursive);
}

final class ExecutionFile extends _Entity implements File {
  ExecutionFile(super.execution, super.path);

  @override
  File get native => File(path);

  @override
  File get absolute => native.absolute;

  @override
  Future<File> create({bool recursive = false, bool exclusive = false}) async {
    await execution.createAsync(
      path,
      directory: false,
      recursive: recursive,
      exclusive: exclusive,
    );
    return native;
  }

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      execution.create(
        path,
        directory: false,
        recursive: recursive,
        exclusive: exclusive,
      );

  @override
  Future<File> delete({bool recursive = false}) async {
    await super.delete(recursive: recursive);
    return native;
  }

  @override
  Future<File> rename(String newPath) async =>
      await super.rename(newPath) as File;

  @override
  File renameSync(String newPath) => super.renameSync(newPath) as File;

  @override
  Future<File> copy(String newPath) => execution.copyAsync(path, newPath);

  @override
  File copySync(String newPath) => execution.copy(path, newPath);

  @override
  Future<int> length() =>
      execution.async(path, (file) => file.length(), metadata: true);

  @override
  int lengthSync() =>
      execution.sync(path, (file) => file.lengthSync(), metadata: true);

  @override
  Future<DateTime> lastAccessed() =>
      execution.async(path, (file) => file.lastAccessed(), metadata: true);

  @override
  DateTime lastAccessedSync() =>
      execution.sync(path, (file) => file.lastAccessedSync(), metadata: true);

  @override
  Future<DateTime> lastModified() =>
      execution.async(path, (file) => file.lastModified(), metadata: true);

  @override
  DateTime lastModifiedSync() =>
      execution.sync(path, (file) => file.lastModifiedSync(), metadata: true);

  @override
  Future<void> setLastAccessed(DateTime time) => execution.async(
    path,
    (file) => file.setLastAccessed(time),
    write: true,
    metadata: true,
  );

  @override
  void setLastAccessedSync(DateTime time) => execution.sync(
    path,
    (file) => file.setLastAccessedSync(time),
    write: true,
    metadata: true,
  );

  @override
  Future<void> setLastModified(DateTime time) => execution.async(
    path,
    (file) => file.setLastModified(time),
    write: true,
    metadata: true,
  );

  @override
  void setLastModifiedSync(DateTime time) => execution.sync(
    path,
    (file) => file.setLastModifiedSync(time),
    write: true,
    metadata: true,
  );

  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      execution.async(
        path,
        (file) => file.open(mode: mode),
        write: mode.requiresFilesystemWrite,
        read: mode.requiresFilesystemRead,
        create: mode.requiresFilesystemWrite,
      );

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) => execution.sync(
    path,
    (file) => file.openSync(mode: mode),
    write: mode.requiresFilesystemWrite,
    read: mode.requiresFilesystemRead,
    create: mode.requiresFilesystemWrite,
  );

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    // Native argument validation is eager; descriptor acquisition is lazy.
    native.openRead(start, end);
    Descriptor? held;
    StreamSubscription<List<int>>? subscription;
    final operands = <String, String>{};
    void release() {
      held?.close();
      held = null;
    }

    late StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () {
        try {
          final canonical = execution.authorize(
            path,
            write: false,
            followLinks: true,
          );
          operands[canonical] = path;
          held = execution.backend.open(canonical);
          operands[held!.path] = path;
          subscription = File(held!.path)
              .openRead(start, end)
              .listen(
                controller.add,
                onError: (Object error, StackTrace stack) =>
                    controller.addError(
                      execution.filesystemError(error, operands),
                      stack,
                    ),
                onDone: () {
                  release();
                  unawaited(controller.close());
                },
              );
        } on Object catch (error, stack) {
          release();
          controller.addError(
            execution.filesystemError(error, operands),
            stack,
          );
          unawaited(controller.close());
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        try {
          await subscription?.cancel();
        } on Object catch (error, stack) {
          Error.throwWithStackTrace(
            execution.filesystemError(error, operands),
            stack,
          );
        } finally {
          release();
        }
      },
    );
    return controller.stream;
  }

  @override
  IOSink openWrite({FileMode mode = FileMode.write, Encoding encoding = utf8}) {
    // IOSink opens asynchronously. Defer secure setup to that same asynchronous
    // native consumer rather than truncating in this synchronous factory.
    final consumer = _SecureFileConsumer(this, mode);
    return IOSink(consumer, encoding: encoding);
  }

  @override
  Future<Uint8List> readAsBytes() =>
      execution.async(path, (file) => file.readAsBytes());

  @override
  Uint8List readAsBytesSync() =>
      execution.sync(path, (file) => file.readAsBytesSync());

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      execution.async(path, (file) => file.readAsString(encoding: encoding));

  @override
  String readAsStringSync({Encoding encoding = utf8}) =>
      execution.sync(path, (file) => file.readAsStringSync(encoding: encoding));

  @override
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      execution.async(path, (file) => file.readAsLines(encoding: encoding));

  @override
  List<String> readAsLinesSync({Encoding encoding = utf8}) =>
      execution.sync(path, (file) => file.readAsLinesSync(encoding: encoding));

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    _checkFileWriteMode(mode);
    await execution.async(
      path,
      (file) => file.writeAsBytes(bytes, mode: mode, flush: flush),
      write: true,
      create: true,
    );
    return native;
  }

  @override
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    _checkFileWriteMode(mode);
    execution.sync(
      path,
      (file) => file.writeAsBytesSync(bytes, mode: mode, flush: flush),
      write: true,
      create: true,
    );
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async => writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) => writeAsBytesSync(encoding.encode(contents), mode: mode, flush: flush);
}

final class _SecureFileConsumer implements StreamConsumer<List<int>> {
  final ExecutionFile file;
  final FileMode mode;
  IOSink? _sink;
  Descriptor? _held;
  final _operands = <String, String>{};

  _SecureFileConsumer(this.file, this.mode) {
    _checkFileWriteMode(mode);
  }

  Future<IOSink> _open() async {
    if (_sink != null) return _sink!;
    final canonical = file.execution.authorize(
      file.path,
      write: true,
      followLinks: true,
    );
    _operands[canonical] = file.path;
    try {
      final held = file.execution.backend.open(
        canonical,
        write: true,
        create: true,
      );
      _held = held;
      _operands[held.path] = file.path;
      final sink = File(held.path).openWrite(mode: mode);
      _sink = sink;
      // Register error handling immediately, even if the caller abandons a sink.
      unawaited(
        sink.done.then<void>(
          (_) {
            _release();
          },
          onError: (Object _, StackTrace _) {
            _release();
          },
        ),
      );
      return sink;
    } on Object catch (error, stack) {
      _release();
      Error.throwWithStackTrace(
        file.execution.filesystemError(error, _operands),
        stack,
      );
    }
  }

  void _release() {
    _held?.close();
    _held = null;
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    try {
      await (await _open()).addStream(stream);
    } on Object catch (error, stack) {
      try {
        await _sink?.close();
      } on Object {
        // Cleanup must not replace the failed stream operation's diagnostic.
      } finally {
        _release();
      }
      Error.throwWithStackTrace(
        file.execution.filesystemError(error, _operands),
        stack,
      );
    }
  }

  @override
  Future<void> close() async {
    try {
      await (await _open()).close();
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        file.execution.filesystemError(error, _operands),
        stack,
      );
    } finally {
      _release();
    }
  }
}

final class ExecutionDirectory extends _Entity implements Directory {
  ExecutionDirectory(super.execution, super.path);

  @override
  Directory get native => Directory(path);

  @override
  Directory get absolute => native.absolute;

  @override
  Future<Directory> create({bool recursive = false}) async {
    await execution.createAsync(path, directory: true, recursive: recursive);
    return native;
  }

  @override
  void createSync({bool recursive = false}) =>
      execution.create(path, directory: true, recursive: recursive);

  @override
  Future<Directory> createTemp([String? prefix]) =>
      execution.tempAsync(path, prefix);

  @override
  Directory createTempSync([String? prefix]) => execution.temp(path, prefix);

  @override
  Future<Directory> delete({bool recursive = false}) async {
    await super.delete(recursive: recursive);
    return native;
  }

  @override
  Future<Directory> rename(String newPath) async =>
      await super.rename(newPath) as Directory;

  @override
  Directory renameSync(String newPath) =>
      super.renameSync(newPath) as Directory;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => execution.listStream(
    path,
    recursive: recursive,
    followLinks: followLinks,
  );

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => execution.list(path, recursive: recursive, followLinks: followLinks);
}

final class ExecutionLink extends _Entity implements Link {
  ExecutionLink(super.execution, super.path);

  @override
  Link get native => Link(path);

  @override
  Link get absolute => native.absolute;

  @override
  Future<Link> create(String target, {bool recursive = false}) async {
    if (recursive) {
      await execution.createAsync(
        p.dirname(path),
        directory: true,
        recursive: true,
      );
    }
    await execution.entryAsync(
      path,
      (entry) => Link(entry).create(target),
      linkTarget: target,
    );
    return native;
  }

  @override
  void createSync(String target, {bool recursive = false}) {
    if (recursive) {
      execution.create(p.dirname(path), directory: true, recursive: true);
    }
    execution.entry(
      path,
      (entry) => Link(entry).createSync(target),
      linkTarget: target,
    );
  }

  @override
  Future<Link> update(String target) async {
    await execution.entryAsync(
      path,
      (entry) => Link(entry).update(target),
      linkTarget: target,
    );
    return native;
  }

  @override
  Link updateSync(String target) {
    execution.entry(
      path,
      (entry) => Link(entry).updateSync(target),
      linkTarget: target,
    );
    return native;
  }

  @override
  Future<String> target() =>
      execution.entryAsync(path, (entry) => Link(entry).target(), write: false);

  @override
  String targetSync() =>
      execution.entry(path, (entry) => Link(entry).targetSync(), write: false);

  @override
  Future<Link> delete({bool recursive = false}) async {
    await super.delete(recursive: recursive);
    return native;
  }

  @override
  Future<Link> rename(String newPath) async =>
      await super.rename(newPath) as Link;

  @override
  Link renameSync(String newPath) => super.renameSync(newPath) as Link;
}
