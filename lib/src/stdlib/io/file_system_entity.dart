import 'dart:io';
import 'package:d4rt/d4rt.dart';

import 'filesystem_permission_helper.dart';

class FileSystemEntityIo {
  static BridgedClass get definition => BridgedClass(
    nativeType: FileSystemEntity,
    name: 'FileSystemEntity',
    typeParameterCount: 0,
    isSubtypeOfFunc: (value) => value is FileSystemEntity,
    staticMethods: {
      'identical': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 2 ||
            positionalArgs[0] is! String ||
            positionalArgs[1] is! String) {
          throw RuntimeError(
            'FileSystemEntity.identical requires two String arguments (path1, path2).',
          );
        }
        final first = absoluteFilesystemPath(positionalArgs[0] as String);
        final second = absoluteFilesystemPath(positionalArgs[1] as String);
        checkFilesystemReadPermission(
          visitor,
          first,
          operation: 'compare file system entities',
          followLinks: false,
        );
        checkFilesystemReadPermission(
          visitor,
          second,
          operation: 'compare file system entities',
          followLinks: false,
        );
        return filesystemIdentical(
          visitor,
          first,
          second,
          originalPaths: {
            first: positionalArgs[0] as String,
            second: positionalArgs[1] as String,
          },
        );
      },
      'identicalSync': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 2 ||
            positionalArgs[0] is! String ||
            positionalArgs[1] is! String) {
          throw RuntimeError(
            'FileSystemEntity.identicalSync requires two String arguments (path1, path2).',
          );
        }
        final first = absoluteFilesystemPath(positionalArgs[0] as String);
        final second = absoluteFilesystemPath(positionalArgs[1] as String);
        checkFilesystemReadPermission(
          visitor,
          first,
          operation: 'compare file system entities',
          followLinks: false,
        );
        checkFilesystemReadPermission(
          visitor,
          second,
          operation: 'compare file system entities',
          followLinks: false,
        );
        return filesystemIdenticalSync(
          visitor,
          first,
          second,
          originalPaths: {
            first: positionalArgs[0] as String,
            second: positionalArgs[1] as String,
          },
        );
      },
      'isDirectory': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.isDirectory requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(visitor, path, operation: 'inspect path');
        return filesystemType(
          visitor,
          path,
        ).then((type) => type == FileSystemEntityType.directory);
      },
      'isDirectorySync': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.isDirectorySync requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(visitor, path, operation: 'inspect path');
        return filesystemTypeSync(visitor, path) ==
            FileSystemEntityType.directory;
      },
      'isFile': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.isFile requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(visitor, path, operation: 'inspect path');
        return filesystemType(
          visitor,
          path,
        ).then((type) => type == FileSystemEntityType.file);
      },
      'isFileSync': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.isFileSync requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(visitor, path, operation: 'inspect path');
        return filesystemTypeSync(visitor, path) == FileSystemEntityType.file;
      },
      'isLink': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.isLink requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(
          visitor,
          path,
          operation: 'inspect path',
          followLinks: false,
        );
        return filesystemType(
          visitor,
          path,
          followLinks: false,
        ).then((type) => type == FileSystemEntityType.link);
      },
      'isLinkSync': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.isLinkSync requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(
          visitor,
          path,
          operation: 'inspect path',
          followLinks: false,
        );
        return filesystemTypeSync(visitor, path, followLinks: false) ==
            FileSystemEntityType.link;
      },
      'type': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.type requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(
          visitor,
          path,
          operation: 'inspect path',
          followLinks: namedArgs['followLinks'] as bool? ?? true,
        );
        return filesystemType(
          visitor,
          path,
          followLinks: namedArgs['followLinks'] as bool? ?? true,
        );
      },
      'typeSync': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.typeSync requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(
          visitor,
          path,
          operation: 'inspect path',
          followLinks: namedArgs['followLinks'] as bool? ?? true,
        );
        return filesystemTypeSync(
          visitor,
          path,
          followLinks: namedArgs['followLinks'] as bool? ?? true,
        );
      },
      'parentOf': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.parentOf requires one String argument (path).',
          );
        }
        checkFilesystemReadPermission(
          visitor,
          positionalArgs[0] as String,
          operation: 'inspect path',
          followLinks: false,
        );
        return FileSystemEntity.parentOf(positionalArgs[0] as String);
      },
    },
    methods: {
      'exists': (visitor, target, positionalArgs, namedArgs) {
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
        );
        checkFilesystemReadPermission(
          visitor,
          entity.path,
          operation: 'check existence',
          followLinks: entity is! Link,
        );
        return entity.exists();
      },
      'existsSync': (visitor, target, positionalArgs, namedArgs) {
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
        );
        checkFilesystemReadPermission(
          visitor,
          entity.path,
          operation: 'check existence',
          followLinks: entity is! Link,
        );
        return entity.existsSync();
      },
      'delete': (visitor, target, positionalArgs, namedArgs) {
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
        );
        checkFilesystemEntryWrite(
          visitor,
          entity.path,
          operation: 'delete entity',
        );
        return entity
            .delete(recursive: namedArgs['recursive'] as bool? ?? false)
            .then((_) => target);
      },
      'deleteSync': (visitor, target, positionalArgs, namedArgs) {
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
        );
        checkFilesystemEntryWrite(
          visitor,
          entity.path,
          operation: 'delete entity',
        );
        entity.deleteSync(recursive: namedArgs['recursive'] as bool? ?? false);
        return null;
      },
      'rename': (visitor, target, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.rename requires one String argument (newPath).',
          );
        }
        final newPath = absoluteFilesystemPath(positionalArgs[0] as String);
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
          originalPaths: {newPath: positionalArgs[0] as String},
        );
        checkFilesystemEntryWrite(
          visitor,
          entity.path,
          operation: 'rename entity',
        );
        checkFilesystemEntryWrite(visitor, newPath, operation: 'rename entity');
        return entity
            .rename(newPath)
            .then(
              (result) =>
                  filesystemEntityAt(result, positionalArgs[0] as String),
            );
      },
      'renameSync': (visitor, target, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileSystemEntity.renameSync requires one String argument (newPath).',
          );
        }
        final newPath = absoluteFilesystemPath(positionalArgs[0] as String);
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
          originalPaths: {newPath: positionalArgs[0] as String},
        );
        checkFilesystemEntryWrite(
          visitor,
          entity.path,
          operation: 'rename entity',
        );
        checkFilesystemEntryWrite(visitor, newPath, operation: 'rename entity');
        entity.renameSync(newPath);
        return null;
      },
      'stat': (visitor, target, positionalArgs, namedArgs) {
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
        );
        checkFilesystemReadPermission(
          visitor,
          entity.path,
          operation: 'stat entity',
        );
        return entity.stat();
      },
      'statSync': (visitor, target, positionalArgs, namedArgs) {
        final entity = executionFilesystemEntity(
          visitor,
          target as FileSystemEntity,
        );
        checkFilesystemReadPermission(
          visitor,
          entity.path,
          operation: 'stat entity',
        );
        return entity.statSync();
      },
      'watch': (visitor, target, positionalArgs, namedArgs) {
        return watchFilesystem(
          visitor,
          target as FileSystemEntity,
          events: namedArgs['events'] as int? ?? FileSystemEvent.all,
          recursive: namedArgs['recursive'] as bool? ?? false,
        );
      },
      'resolveSymbolicLinks': (visitor, target, positionalArgs, namedArgs) {
        return resolveFilesystemLinks(visitor, target as FileSystemEntity);
      },
      'resolveSymbolicLinksSync': (visitor, target, positionalArgs, namedArgs) {
        return resolveFilesystemLinksSync(visitor, target as FileSystemEntity);
      },
    },
    getters: {
      'absolute': (visitor, target) =>
          absoluteFilesystemEntity(target as FileSystemEntity),
      'uri': (visitor, target) => (target as FileSystemEntity).uri,
      'parent': (visitor, target) => (target as FileSystemEntity).parent,
      'path': (visitor, target) => (target as FileSystemEntity).path,
      'isAbsolute': (visitor, target) =>
          (target as FileSystemEntity).isAbsolute,
    },
    staticGetters: {
      'isWatchSupported': (visitor) => FileSystemEntity.isWatchSupported,
    },
  );
}

class FileStatIo {
  static BridgedClass get definition => BridgedClass(
    nativeType: FileStat,
    name: 'FileStat',
    typeParameterCount: 0,
    constructors: {
      // FileStat is typically obtained from stat() operations
    },
    staticMethods: {
      'stat': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileStat.stat requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(visitor, path, operation: 'stat path');
        return filesystemStat(visitor, path);
      },
      'statSync': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'FileStat.statSync requires one String argument (path).',
          );
        }
        final path = absoluteFilesystemPath(positionalArgs[0] as String);
        checkFilesystemReadPermission(visitor, path, operation: 'stat path');
        return filesystemStatSync(visitor, path);
      },
    },
    methods: {
      'modeString': (visitor, target, positionalArgs, namedArgs) {
        return (target as FileStat).modeString();
      },
      'toString': (visitor, target, positionalArgs, namedArgs) =>
          (target as FileStat).toString(),
    },
    getters: {
      'changed': (visitor, target) => (target as FileStat).changed,
      'modified': (visitor, target) => (target as FileStat).modified,
      'accessed': (visitor, target) => (target as FileStat).accessed,
      'type': (visitor, target) => (target as FileStat).type,
      'mode': (visitor, target) => (target as FileStat).mode,
      'size': (visitor, target) => (target as FileStat).size,
    },
  );
}

class FileSystemEntityTypeIo {
  static BridgedClass get definition => BridgedClass(
    nativeType: FileSystemEntityType,
    name: 'FileSystemEntityType',
    typeParameterCount: 0,
    constructors: {},
    methods: {
      'toString': (visitor, target, positionalArgs, namedArgs) =>
          (target as FileSystemEntityType).toString(),
    },
    staticGetters: {
      'file': (visitor) => FileSystemEntityType.file,
      'directory': (visitor) => FileSystemEntityType.directory,
      'link': (visitor) => FileSystemEntityType.link,
      'unixDomainSock': (visitor) => FileSystemEntityType.unixDomainSock,
      'pipe': (visitor) => FileSystemEntityType.pipe,
      'notFound': (visitor) => FileSystemEntityType.notFound,
    },
    getters: {},
  );
}

class FileSystemEventIo {
  static BridgedClass get definition => BridgedClass(
    nativeType: FileSystemEvent,
    name: 'FileSystemEvent',
    typeParameterCount: 0,
    constructors: {},
    staticGetters: {
      'create': (visitor) => FileSystemEvent.create,
      'delete': (visitor) => FileSystemEvent.delete,
      'modify': (visitor) => FileSystemEvent.modify,
      'move': (visitor) => FileSystemEvent.move,
      'all': (visitor) => FileSystemEvent.all,
    },
    methods: {
      'toString': (visitor, target, positionalArgs, namedArgs) =>
          (target as FileSystemEvent).toString(),
    },
    getters: {
      'type': (visitor, target) => (target as FileSystemEvent).type,
      'path': (visitor, target) => (target as FileSystemEvent).path,
      'isDirectory': (visitor, target) =>
          (target as FileSystemEvent).isDirectory,
      // Convenience getters for type checking
      'isCreate': (visitor, target) =>
          (target as FileSystemEvent).type == FileSystemEvent.create,
      'isModify': (visitor, target) =>
          (target as FileSystemEvent).type == FileSystemEvent.modify,
      'isDelete': (visitor, target) =>
          (target as FileSystemEvent).type == FileSystemEvent.delete,
      'isMove': (visitor, target) =>
          (target as FileSystemEvent).type == FileSystemEvent.move,
    },
  );
}
