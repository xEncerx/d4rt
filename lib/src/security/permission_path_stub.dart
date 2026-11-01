import 'package:path/path.dart' as p;

/// Non-IO platforms have no native filesystem or symbolic links to resolve.
String resolvePermissionPath(String path, {bool followLinks = true}) =>
    p.normalize(p.absolute(path));
