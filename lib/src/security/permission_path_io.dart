import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves existing components, including links to missing destinations.
/// Only native not-found errors permit a missing suffix; all other errors escape.
/// Dot segments are processed after links, never lexically across a link.
String resolvePermissionPath(String path, {bool followLinks = true}) {
  if (path.isEmpty || path.contains('\u0000')) {
    throw ArgumentError.value(path, 'path', 'Invalid filesystem path');
  }
  final absolute = File(path).absolute.path;
  // Windows resolves dot segments before following links.
  return _resolve(
    Platform.isWindows ? p.normalize(absolute) : absolute,
    followLinks,
    0,
  );
}

String _resolve(String absolute, bool followLinks, int links) {
  final parts = p.split(Platform.isWindows ? p.normalize(absolute) : absolute);
  var resolved = Directory(parts.first).resolveSymbolicLinksSync();
  for (var index = 1; index < parts.length; index++) {
    final part = parts[index];
    if (part == '.') continue;
    if (part == '..') {
      resolved = p.dirname(resolved);
      continue;
    }
    if (Platform.isWindows &&
        (part.endsWith('.') || part.endsWith(' ') || part.contains(':'))) {
      throw ArgumentError.value(absolute, 'path', 'Ambiguous Windows path');
    }
    final candidate = p.join(resolved, part);
    if (!followLinks && index == parts.length - 1) return candidate;
    final type = FileSystemEntity.typeSync(candidate, followLinks: false);
    if (type == FileSystemEntityType.link) {
      if (++links > 40) {
        throw FileSystemException('Too many symbolic links', absolute);
      }
      final target = Link(candidate).targetSync();
      resolved = _resolve(
        p.isAbsolute(target) ? target : p.join(resolved, target),
        true,
        links,
      );
    } else {
      try {
        resolved = File(candidate).resolveSymbolicLinksSync();
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        if (code != 2 && !(Platform.isWindows && code == 3)) rethrow;
        resolved = candidate;
      }
    }
  }
  return resolved;
}
