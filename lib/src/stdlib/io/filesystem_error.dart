import 'dart:io';

/// Translates temporary execution operands in both diagnostic fields. Maps are
/// operation-local: two-endpoint calls supply both names, recursive operations
/// add their held subtree, and durable handles retain their opening operand.
/// Non-filesystem errors and unchanged native filesystem exceptions keep their
/// identity; translated exceptions retain their native category and OS error.
Object filesystemError(Object error, Map<String, String> operands) {
  if (error is! FileSystemException) {
    return error;
  }
  final keys = operands.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  String translate(String value) {
    for (final key in keys) {
      if (key == operands[key]) {
        continue;
      }
      value = value.replaceAllMapped(
        RegExp('${RegExp.escape(key)}(?=\$|[/\\\\\\s\'":,)])'),
        (_) => operands[key]!,
      );
    }
    return value;
  }

  final message = translate(error.message);
  final path = error.path == null ? null : translate(error.path!);
  if (message == error.message && path == error.path) {
    return error;
  }
  return filesystemOperationError(error, message, path);
}

/// Applies an operation's native diagnostic context to descriptor setup errors.
/// Non-filesystem failures (including policy denials) are never normalized.
Object filesystemOperationError(Object error, String message, String? path) {
  if (error is! FileSystemException) return error;
  final osError = error.osError;
  if (error is PathNotFoundException && osError != null) {
    return PathNotFoundException(path!, osError, message);
  }
  if (error is PathExistsException && osError != null) {
    return PathExistsException(path!, osError, message);
  }
  if (error is PathAccessException && osError != null) {
    return PathAccessException(path!, osError, message);
  }
  return FileSystemException(message, path, osError);
}

T filesystemErrorSync<T>(T Function() action, Map<String, String> operands) {
  try {
    return action();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(filesystemError(error, operands), stack);
  }
}

Future<T> filesystemErrorAsync<T>(
  Future<T> Function() action,
  Map<String, String> operands,
) {
  try {
    return action().then<T>(
      (value) => value,
      onError: (Object error, StackTrace stack) {
        Error.throwWithStackTrace(filesystemError(error, operands), stack);
      },
    );
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(filesystemError(error, operands), stack);
  }
}
