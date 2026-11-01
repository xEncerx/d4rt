import 'dart:io';
import 'dart:typed_data';
import 'package:d4rt/d4rt.dart';

import 'filesystem_permission_helper.dart';

class LinkIo {
  static BridgedClass get definition => BridgedClass(
        nativeType: Link,
        name: 'Link',
        typeParameterCount: 0,
        isSubtypeOfFunc: (value) => value is Link,
        constructors: {
          '': (visitor, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                'Link constructor requires one String argument (path).',
              );
            }
            return Link(positionalArgs[0] as String);
          },
        },
        staticMethods: {
          'fromRawPath': (visitor, positionalArgs, namedArgs) {
            if (positionalArgs.length != 1 || positionalArgs[0] is! Uint8List) {
              throw RuntimeError(
                'Link.fromRawPath requires one Uint8List argument.',
              );
            }
            return Link(
                filesystemPathFromBytes(positionalArgs[0] as Uint8List));
          },
          'fromUri': (visitor, positionalArgs, namedArgs) {
            if (positionalArgs.length != 1 || positionalArgs[0] is! Uri) {
              throw RuntimeError('Link.fromUri requires one Uri argument.');
            }
            return Link.fromUri(positionalArgs[0] as Uri);
          },
        },
        methods: {
          'exists': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'check link existence',
              followLinks: false,
            );
            return link.exists();
          },
          'existsSync': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'check link existence',
              followLinks: false,
            );
            return link.existsSync();
          },
          'create': (visitor, target, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                'Link.create requires target path String argument.',
              );
            }
            final link = absoluteFilesystemEntity(target as Link);
            final targetPath = positionalArgs[0] as String;
            checkFilesystemLinkChange(
              visitor,
              link.path,
              targetPath,
              operation: 'create link',
              recursive: namedArgs['recursive'] as bool? ?? false,
            );
            return link
                .create(
                  targetPath,
                  recursive: namedArgs['recursive'] as bool? ?? false,
                )
                .then((_) => target);
          },
          'createSync': (visitor, target, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                'Link.createSync requires target path String argument.',
              );
            }
            final link = absoluteFilesystemEntity(target as Link);
            final targetPath = positionalArgs[0] as String;
            checkFilesystemLinkChange(
              visitor,
              link.path,
              targetPath,
              operation: 'create link',
              recursive: namedArgs['recursive'] as bool? ?? false,
            );
            link.createSync(
              targetPath,
              recursive: namedArgs['recursive'] as bool? ?? false,
            );
            return null;
          },
          'update': (visitor, target, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                'Link.update requires target path String argument.',
              );
            }
            final link = absoluteFilesystemEntity(target as Link);
            final targetPath = positionalArgs[0] as String;
            checkFilesystemLinkChange(
              visitor,
              link.path,
              targetPath,
              operation: 'update link',
            );
            return link.update(targetPath).then((_) => target);
          },
          'updateSync': (visitor, target, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                'Link.updateSync requires target path String argument.',
              );
            }
            final link = absoluteFilesystemEntity(target as Link);
            final targetPath = positionalArgs[0] as String;
            checkFilesystemLinkChange(
              visitor,
              link.path,
              targetPath,
              operation: 'update link',
            );
            link.updateSync(targetPath);
            return null;
          },
          'target': (visitor, target, positionalArgs, namedArgs) async {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'read link target',
              followLinks: false,
            );
            final result = await link.target();
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'read link target',
              followLinks: false,
            );
            checkFilesystemLinkTarget(
              visitor,
              link.path,
              result,
              operation: 'expose link target',
            );
            return result;
          },
          'targetSync': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'read link target',
              followLinks: false,
            );
            final result = link.targetSync();
            checkFilesystemLinkTarget(
              visitor,
              link.path,
              result,
              operation: 'expose link target',
            );
            return result;
          },
          'resolveSymbolicLinks': (visitor, target, positionalArgs, namedArgs) {
            return resolveFilesystemLinks(visitor, target as Link);
          },
          'resolveSymbolicLinksSync':
              (visitor, target, positionalArgs, namedArgs) {
            return resolveFilesystemLinksSync(visitor, target as Link);
          },
          'rename': (visitor, target, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                  'Link.rename requires newPath String argument.');
            }
            final link = absoluteFilesystemEntity(target as Link);
            final newPath = absoluteFilesystemPath(positionalArgs[0] as String);
            checkFilesystemEntryWrite(visitor, link.path,
                operation: 'rename link');
            checkFilesystemEntryWrite(visitor, newPath,
                operation: 'rename link');
            return link
                .rename(newPath)
                .then((_) => Link(positionalArgs[0] as String));
          },
          'renameSync': (visitor, target, positionalArgs, namedArgs) {
            if (positionalArgs.isEmpty || positionalArgs[0] is! String) {
              throw RuntimeError(
                'Link.renameSync requires newPath String argument.',
              );
            }
            final link = absoluteFilesystemEntity(target as Link);
            final newPath = absoluteFilesystemPath(positionalArgs[0] as String);
            checkFilesystemEntryWrite(visitor, link.path,
                operation: 'rename link');
            checkFilesystemEntryWrite(visitor, newPath,
                operation: 'rename link');
            link.renameSync(newPath);
            return Link(positionalArgs[0] as String);
          },
          'delete': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemEntryWrite(visitor, link.path,
                operation: 'delete link');
            return link
                .delete(recursive: namedArgs['recursive'] as bool? ?? false)
                .then((_) => target);
          },
          'deleteSync': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemEntryWrite(visitor, link.path,
                operation: 'delete link');
            link.deleteSync(
                recursive: namedArgs['recursive'] as bool? ?? false);
            return null;
          },
          'stat': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'stat link',
            );
            return link.stat();
          },
          'statSync': (visitor, target, positionalArgs, namedArgs) {
            final link = absoluteFilesystemEntity(target as Link);
            checkFilesystemReadPermission(
              visitor,
              link.path,
              operation: 'stat link',
            );
            return link.statSync();
          },
          'toString': (visitor, target, positionalArgs, namedArgs) {
            return (target as Link).toString();
          },
        },
        getters: {
          'path': (visitor, target) => (target as Link).path,
          'uri': (visitor, target) => (target as Link).uri,
          'parent': (visitor, target) => (target as Link).parent,
          'isAbsolute': (visitor, target) => (target as Link).isAbsolute,
          'absolute': (visitor, target) =>
              absoluteFilesystemEntity(target as Link),
          'hashCode': (visitor, target) => (target as Link).hashCode,
          'runtimeType': (visitor, target) => (target as Link).runtimeType,
        },
      );
}
