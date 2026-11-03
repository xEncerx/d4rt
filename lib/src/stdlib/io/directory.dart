import 'dart:io';
import 'dart:typed_data';
import 'package:d4rt/d4rt.dart';

import 'filesystem_permission_helper.dart';

class DirectoryIo {
  static BridgedClass get definition => BridgedClass(
    nativeType: Directory,
    name: 'Directory',
    typeParameterCount: 0,
    isSubtypeOfFunc: (value) => value is Directory,
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
          throw RuntimeError(
            'Directory constructor requires one String argument (path).',
          );
        }
        return Directory(positionalArgs[0] as String);
      },
    },
    staticMethods: {
      'fromRawPath': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! Uint8List) {
          throw RuntimeError(
            'Directory.fromRawPath requires one Uint8List argument.',
          );
        }
        return Directory(
          filesystemPathFromBytes(positionalArgs[0] as Uint8List),
        );
      },
      'fromUri': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! Uri) {
          throw RuntimeError('Directory.fromUri requires one Uri argument.');
        }
        return Directory.fromUri(positionalArgs[0] as Uri);
      },
    },
    methods: {
      'exists': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        checkFilesystemReadPermission(
          visitor,
          directory.path,
          operation: 'check directory existence',
        );
        return directory.exists();
      },
      'existsSync': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        checkFilesystemReadPermission(
          visitor,
          directory.path,
          operation: 'check directory existence',
        );
        return directory.existsSync();
      },
      'create': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        final recursive = namedArgs['recursive'] as bool? ?? false;
        checkFilesystemCreate(
          visitor,
          directory.path,
          recursive: recursive,
          directory: true,
        );
        return directory.create(recursive: recursive).then((_) => target);
      },
      'createSync': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        final recursive = namedArgs['recursive'] as bool? ?? false;
        checkFilesystemCreate(
          visitor,
          directory.path,
          recursive: recursive,
          directory: true,
        );
        directory.createSync(recursive: recursive);
        return null;
      },
      'delete': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        checkFilesystemEntryWrite(
          visitor,
          directory.path,
          operation: 'delete directory',
        );
        return directory
            .delete(recursive: namedArgs['recursive'] as bool? ?? false)
            .then((_) => target);
      },
      'deleteSync': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        checkFilesystemEntryWrite(
          visitor,
          directory.path,
          operation: 'delete directory',
        );
        directory.deleteSync(
          recursive: namedArgs['recursive'] as bool? ?? false,
        );
        return null;
      },
      'list': (visitor, target, positionalArgs, namedArgs) {
        return listFilesystem(
          visitor,
          target as Directory,
          recursive: namedArgs['recursive'] as bool? ?? false,
          followLinks: namedArgs['followLinks'] as bool? ?? true,
        );
      },
      'listSync': (visitor, target, positionalArgs, namedArgs) {
        return listFilesystemSync(
          visitor,
          target as Directory,
          recursive: namedArgs['recursive'] as bool? ?? false,
          followLinks: namedArgs['followLinks'] as bool? ?? true,
        );
      },
      'rename': (visitor, target, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'Directory.rename requires one String argument (newPath).',
          );
        }
        final newPath = absoluteFilesystemPath(positionalArgs[0] as String);
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
          originalPaths: {newPath: positionalArgs[0] as String},
        );
        checkFilesystemEntryWrite(
          visitor,
          directory.path,
          operation: 'rename directory',
        );
        checkFilesystemEntryWrite(
          visitor,
          newPath,
          operation: 'rename directory',
        );
        return directory
            .rename(newPath)
            .then((_) => Directory(positionalArgs[0] as String));
      },
      'renameSync': (visitor, target, positionalArgs, namedArgs) {
        if (positionalArgs.length != 1 || positionalArgs[0] is! String) {
          throw RuntimeError(
            'Directory.renameSync requires one String argument (newPath).',
          );
        }
        final newPath = absoluteFilesystemPath(positionalArgs[0] as String);
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
          originalPaths: {newPath: positionalArgs[0] as String},
        );
        checkFilesystemEntryWrite(
          visitor,
          directory.path,
          operation: 'rename directory',
        );
        checkFilesystemEntryWrite(
          visitor,
          newPath,
          operation: 'rename directory',
        );
        directory.renameSync(newPath);
        return null;
      },
      'stat': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        checkFilesystemReadPermission(
          visitor,
          directory.path,
          operation: 'stat directory',
        );
        return directory.stat();
      },
      'statSync': (visitor, target, positionalArgs, namedArgs) {
        final directory = executionFilesystemEntity(
          visitor,
          target as Directory,
        );
        checkFilesystemReadPermission(
          visitor,
          directory.path,
          operation: 'stat directory',
        );
        return directory.statSync();
      },
      'watch': (visitor, target, positionalArgs, namedArgs) {
        return watchFilesystem(
          visitor,
          target as Directory,
          events: namedArgs['events'] as int? ?? FileSystemEvent.all,
          recursive: namedArgs['recursive'] as bool? ?? false,
        );
      },
      'resolveSymbolicLinks': (visitor, target, positionalArgs, namedArgs) {
        return resolveFilesystemLinks(visitor, target as Directory);
      },
      'resolveSymbolicLinksSync': (visitor, target, positionalArgs, namedArgs) {
        return resolveFilesystemLinksSync(visitor, target as Directory);
      },
      'createTemp': (visitor, target, positionalArgs, namedArgs) {
        return createFilesystemTemp(
          visitor,
          target as Directory,
          positionalArgs.isNotEmpty ? positionalArgs[0] as String? : null,
        );
      },
      'createTempSync': (visitor, target, positionalArgs, namedArgs) {
        return createFilesystemTempSync(
          visitor,
          target as Directory,
          positionalArgs.isNotEmpty ? positionalArgs[0] as String? : null,
        );
      },
      'toString': (visitor, target, positionalArgs, namedArgs) =>
          (target as Directory).toString(),
    },
    getters: {
      'path': (visitor, target) => (target as Directory).path,
      'absolute': (visitor, target) =>
          absoluteFilesystemEntity(target as Directory),
      'uri': (visitor, target) => (target as Directory).uri,
      'parent': (visitor, target) => (target as Directory).parent,
      'isAbsolute': (visitor, target) => (target as Directory).isAbsolute,
    },
    staticGetters: {
      'systemTemp': (visitor) {
        final directory = Directory.systemTemp;
        checkFilesystemReadPermission(
          visitor,
          directory.path,
          operation: 'read system temporary directory',
        );
        return directory;
      },
      'current': (visitor) {
        final directory = Directory.current;
        checkFilesystemReadPermission(
          visitor,
          directory.path,
          operation: 'read working directory',
        );
        return directory;
      },
    },
    staticSetters: {
      'current': (visitor, value) {
        final nativeValue = value is BridgedInstance
            ? value.nativeObject
            : value;
        if (nativeValue is! Directory && nativeValue is! String) {
          // Let the native setter own argument validation and its error.
          Directory.current = nativeValue;
          return;
        }
        final path = nativeValue is Directory
            ? nativeValue.path
            : nativeValue as String;
        final absolute = absoluteFilesystemPath(path);
        checkFilesystemReadPermission(
          visitor,
          absolute,
          operation: 'change working directory',
        );
        Directory.current = absolute;
        return;
      },
    },
  );
}
