import 'dart:io';

/// Permission requirements of an SDK open mode, shared by the eager portable
/// policy boundary and the canonical descriptor execution boundary.
extension FilesystemFileModeAccess on FileMode {
  bool get requiresFilesystemRead =>
      this != FileMode.writeOnly && this != FileMode.writeOnlyAppend;
  bool get requiresFilesystemWrite => this != FileMode.read;
}
