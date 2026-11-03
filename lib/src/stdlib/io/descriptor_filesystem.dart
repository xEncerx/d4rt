import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// Deliberately Linux x64 only. openat uses Dart's VarArgs ABI. All other C
// interfaces have fixed arity. libc stat/dirent/timespec layouts are not decoded:
// the SDK owns metadata, timestamps and enumeration. Identity uses Linux's
// explicitly fixed-width, 256-byte statx UAPI, not libc's ABI-dependent stat.
// /proc must permit reopening our own descriptors. Other targets retain the
// portable permission checks, without a descriptor-isolation guarantee.
// The active backend requires usable libc openat/mkdirat/statx and a mounted
// /proc/self/fd supporting SDK reopen/stat/enumeration. Detection runs once.
//
// This is not an OS sandbox: hard links, mounts, already-open native handles and
// directories moved across scopes remain outside this boundary. Namespace calls
// act on an entry in a held parent; concurrent replacement of that entry remains
// possible, but cannot make traversal follow a replacement symbolic link.
//
// Supported operation families: content/RAF/streams/sinks/copy and target
// metadata (including timestamps) use held descriptors; namespace operations
// use held parents; recursive traversal opens each child without following
// links; temporary directories use secure random names and mkdirat(0700). Static
// no-follow metadata and link identity inspect entries under held parents.
// Watch, process-global cwd and resolveSymbolicLinks remain permission-checked
// SDK path operations, not descriptor-isolated operations.
final class DescriptorFilesystem {
  static final DescriptorFilesystem? instance = _probe();

  final int Function(int, Pointer<Char>, int, int) _openat;
  final int Function(int) _close;
  final Pointer<Void> Function(int) _malloc;
  final void Function(Pointer<Void>) _free;
  final Pointer<Int32> Function() _errno;
  final int Function(int, Pointer<Char>, int) _mkdirat;
  final int Function(int, Pointer<Char>, int, int, Pointer<Void>) _statx;

  DescriptorFilesystem._(DynamicLibrary libc)
    : _openat = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<Char>, Int32, VarArgs<(Uint32,)>),
            int Function(int, Pointer<Char>, int, int)
          >('openat'),
      _close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
        'close',
      ),
      _malloc = libc
          .lookupFunction<
            Pointer<Void> Function(UintPtr),
            Pointer<Void> Function(int)
          >('malloc'),
      _free = libc
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('free'),
      _errno = libc
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            '__errno_location',
          ),
      _mkdirat = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<Char>, Uint32),
            int Function(int, Pointer<Char>, int)
          >('mkdirat'),
      _statx = libc
          .lookupFunction<
            Int32 Function(Int32, Pointer<Char>, Int32, Uint32, Pointer<Void>),
            int Function(int, Pointer<Char>, int, int, Pointer<Void>)
          >('statx');

  static DescriptorFilesystem? _probe() {
    if (!Platform.isLinux || Abi.current() != Abi.linuxX64) return null;
    try {
      final backend = DescriptorFilesystem._(DynamicLibrary.process());
      final root = backend.open('/', metadata: true);
      try {
        final identity = backend.identity(root);
        if ((identity.mode & 0xf000) != 0x4000) return null;
        if (FileStat.statSync(root.path).type !=
                FileSystemEntityType.directory ||
            Directory(root.path).listSync(followLinks: false).isEmpty) {
          return null;
        }
        final reopened = Directory(root.path).statSync();
        if (reopened.type != FileSystemEntityType.directory) return null;
      } finally {
        root.close();
      }
      return backend;
    } on Object {
      return null;
    }
  }

  T _string<T>(String value, T Function(Pointer<Char>) action) {
    if (value.contains('\u0000')) {
      throw ArgumentError.value(value, 'path', 'Embedded NUL');
    }
    final bytes = utf8.encode(value);
    final pointer = _malloc(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Cannot allocate filesystem path');
    try {
      final buffer = pointer.cast<Uint8>().asTypedList(bytes.length + 1);
      buffer.setRange(0, bytes.length, bytes);
      buffer[bytes.length] = 0;
      return action(pointer.cast<Char>());
    } finally {
      _free(pointer);
    }
  }

  Never _error(String path) {
    final code = _errno().value;
    final error = OSError(
      'Descriptor-relative filesystem operation failed',
      code,
    );
    if (code == 2) throw PathNotFoundException(path, error);
    if (code == 17) throw PathExistsException(path, error);
    if (code == 1 || code == 13) throw PathAccessException(path, error);
    throw FileSystemException(
      'Descriptor-relative filesystem operation failed',
      path,
      error,
    );
  }

  // Linux asm-generic/fcntl.h flags; only the probed linuxX64 ABI uses them.
  static const _directory = 0x10000, _nofollow = 0x20000, _cloexec = 0x80000;
  static const _path = 0x200000, _create = 0x40, _exclusive = 0x80;

  Descriptor open(
    String canonical, {
    bool metadata = false,
    bool write = false,
    bool create = false,
    bool exclusive = false,
  }) {
    if (!p.isAbsolute(canonical) ||
        p.normalize(canonical) != canonical ||
        canonical.contains('\u0000')) {
      throw ArgumentError.value(
        canonical,
        'canonical',
        'Expected canonical absolute path',
      );
    }
    var fd = _string(
      '/',
      (name) => _openat(-100, name, _path | _directory | _cloexec, 0),
    );
    if (fd < 0) _error(canonical);
    try {
      final parts = p.split(canonical).skip(1).toList();
      for (var index = 0; index < parts.length; index++) {
        final last = index == parts.length - 1;
        final flags =
            _cloexec |
            _nofollow |
            (!last
                ? _path | _directory
                : metadata
                ? _path
                : write
                ? 1
                : 0) |
            (last && create ? _create : 0) |
            (last && exclusive ? _exclusive : 0);
        final next = _string(
          parts[index],
          (name) => _openat(fd, name, flags, 0x1b6),
        );
        if (next < 0) _error(canonical);
        _close(fd);
        fd = next;
      }
      // O_PATH|O_NOFOLLOW can open a symlink inode. Reject it before any SDK
      // target operation. Ordinary no-follow opens already reject final links.
      if (metadata &&
          (identity(Descriptor._(this, fd)).mode & 0xf000) == 0xa000) {
        throw FileSystemException(
          'Symbolic link changed after authorization',
          canonical,
        );
      }
      final result = Descriptor._(this, fd);
      fd = -1;
      return result;
    } finally {
      if (fd >= 0) _close(fd);
    }
  }

  Descriptor parent(String canonical) =>
      open(p.dirname(canonical), metadata: true);

  // Linux include/uapi/linux/stat.h (statx), with offsets explicitly specified
  // by that kernel interface: mask 0x00, mode 0x1c, inode 0x20, device 0x88.
  // https://github.com/torvalds/linux/blob/v6.6/include/uapi/linux/stat.h
  // AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW pins even a symlink inode itself.
  ({int major, int minor, int inode, int mode}) identity(
    Descriptor descriptor,
  ) {
    final buffer = _malloc(256);
    if (buffer == nullptr) throw StateError('Cannot allocate statx buffer');
    try {
      if (_string(
            '',
            (name) => _statx(descriptor.fd, name, 0x1100, 0x101, buffer),
          ) !=
          0) {
        _error(descriptor.path);
      }
      final bytes = ByteData.sublistView(buffer.cast<Uint8>().asTypedList(256));
      if ((bytes.getUint32(0, Endian.little) & 0x101) != 0x101) {
        throw FileSystemException(
          'Filesystem does not supply inode identity',
          descriptor.path,
        );
      }
      return (
        major: bytes.getUint32(0x88, Endian.little),
        minor: bytes.getUint32(0x8c, Endian.little),
        inode: bytes.getUint64(0x20, Endian.little),
        mode: bytes.getUint16(0x1c, Endian.little),
      );
    } finally {
      _free(buffer);
    }
  }

  bool sameObject(Descriptor first, Descriptor second) {
    final a = identity(first), b = identity(second);
    return a.major == b.major && a.minor == b.minor && a.inode == b.inode;
  }

  // Only internal enumeration supplies these paths. Never accept user-provided
  // /proc paths as authority: the descriptor belongs to the active operation.
  Descriptor openAnchored(String anchored, {bool directory = false}) {
    final parts = p.split(anchored);
    if (parts.length != 6 ||
        parts[1] != 'proc' ||
        parts[2] != 'self' ||
        parts[3] != 'fd' ||
        parts.last == '.' ||
        parts.last == '..') {
      throw ArgumentError.value(anchored, 'anchored');
    }
    final parentFd = int.parse(parts[4]);
    final fd = _string(
      parts.last,
      (name) => _openat(
        parentFd,
        name,
        _path | _nofollow | _cloexec | (directory ? _directory : 0),
        0,
      ),
    );
    if (fd < 0) _error(anchored);
    return Descriptor._(this, fd);
  }

  void mkdir(Descriptor parent, String name, {int mode = 0x1ff}) {
    if (_string(name, (pointer) => _mkdirat(parent.fd, pointer, mode)) != 0) {
      _error(p.join(parent.path, name));
    }
  }
}

final class Descriptor {
  final DescriptorFilesystem _backend;
  int _fd;

  Descriptor._(this._backend, this._fd);

  int get fd {
    if (_fd < 0) throw StateError('Filesystem descriptor is closed');
    return _fd;
  }

  String get path => '/proc/self/fd/$fd';

  void close() {
    final value = _fd;
    _fd = -1;
    if (value >= 0) _backend._close(value);
  }
}
