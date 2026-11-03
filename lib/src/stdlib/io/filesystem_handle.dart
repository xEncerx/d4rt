import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'filesystem_error.dart';

/// Owns the SDK handle after descriptor-anchor transfer. Native operations still
/// use its already-open descriptor, never the original name. Both embedding code
/// and interpreted code see durable original metadata, including after close;
/// fluent asynchronous operations return this same owner rather than exposing
/// the SDK object's now-closed temporary opening path.
final class FilesystemHandle implements RandomAccessFile {
  final RandomAccessFile _handle;
  final Map<String, String> _operands;

  FilesystemHandle(this._handle, this.path) : _operands = {_handle.path: path};

  @override
  final String path;

  RandomAccessFile _self(RandomAccessFile _) => this;

  T _sync<T>(T Function() action) => filesystemErrorSync(action, _operands);

  Future<T> _async<T>(Future<T> Function() action) =>
      filesystemErrorAsync(action, _operands);

  @override
  String toString() => _handle.toString().replaceAll(_handle.path, path);

  @override
  Future<void> close() => _async(_handle.close);

  @override
  void closeSync() => _sync(_handle.closeSync);

  @override
  Future<int> readByte() => _async(_handle.readByte);

  @override
  int readByteSync() => _sync(_handle.readByteSync);

  @override
  Future<Uint8List> read(int count) => _async(() => _handle.read(count));

  @override
  Uint8List readSync(int count) => _sync(() => _handle.readSync(count));

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) =>
      _async(() => _handle.readInto(buffer, start, end));

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) =>
      _sync(() => _handle.readIntoSync(buffer, start, end));

  @override
  Future<RandomAccessFile> writeByte(int value) =>
      _async(() => _handle.writeByte(value)).then(_self);

  @override
  int writeByteSync(int value) => _sync(() => _handle.writeByteSync(value));

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) => _async(() => _handle.writeFrom(buffer, start, end)).then(_self);

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) =>
      _sync(() => _handle.writeFromSync(buffer, start, end));

  @override
  Future<RandomAccessFile> writeString(
    String string, {
    Encoding encoding = utf8,
  }) =>
      _async(() => _handle.writeString(string, encoding: encoding)).then(_self);

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) =>
      _sync(() => _handle.writeStringSync(string, encoding: encoding));

  @override
  Future<int> position() => _async(_handle.position);

  @override
  int positionSync() => _sync(_handle.positionSync);

  @override
  Future<RandomAccessFile> setPosition(int position) =>
      _async(() => _handle.setPosition(position)).then(_self);

  @override
  void setPositionSync(int position) =>
      _sync(() => _handle.setPositionSync(position));

  @override
  Future<RandomAccessFile> truncate(int length) =>
      _async(() => _handle.truncate(length)).then(_self);

  @override
  void truncateSync(int length) => _sync(() => _handle.truncateSync(length));

  @override
  Future<int> length() => _async(_handle.length);

  @override
  int lengthSync() => _sync(_handle.lengthSync);

  @override
  Future<RandomAccessFile> flush() => _async(_handle.flush).then(_self);

  @override
  void flushSync() => _sync(_handle.flushSync);

  @override
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) => _async(() => _handle.lock(mode, start, end)).then(_self);

  @override
  void lockSync([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) => _sync(() => _handle.lockSync(mode, start, end));

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) =>
      _async(() => _handle.unlock(start, end)).then(_self);

  @override
  void unlockSync([int start = 0, int end = -1]) =>
      _sync(() => _handle.unlockSync(start, end));
}
