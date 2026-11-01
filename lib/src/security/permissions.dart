/// Security and sandboxing system for d4rt interpreter.
///
/// This module provides a comprehensive permission system that allows
/// fine-grained control over what operations interpreted code can perform.
/// By default, potentially dangerous operations are blocked unless explicitly
/// granted through the permission system.
///
/// ## Example usage:
/// ```dart
/// final interpreter = D4rt();
///
/// // Grant filesystem access
/// interpreter.grant(FilesystemPermission.read);
/// interpreter.grant(FilesystemPermission.writePath('/tmp'));
///
/// // Grant network access
/// interpreter.grant(NetworkPermission.connectTo('api.example.com'));
///
/// // Grant process execution
/// interpreter.grant(ProcessRunPermission.any);
/// interpreter.grant(DangerousPermission.processExecution);
///
/// // Execute code with restricted permissions
/// final result = interpreter.execute(source: '''
///   // This code can now access filesystem, network, and run processes
///   // within the granted permissions
/// ''');
/// ```
library;

import 'package:path/path.dart' as p;

import 'network_host.dart';
import 'permission_path.dart';

final _drivePrefix = RegExp(r'^[A-Za-z]:');

// Normalize lexically, without requiring the target to exist or resolving links.
// Stored scopes are normalized once; requested paths use the operation's cwd.
String _canonicalizePermissionPath(String path) {
  final normalized = p.normalize(p.absolute(path));
  return p.separator == '\\' && _drivePrefix.hasMatch(normalized)
      ? '${normalized.substring(0, 2).toLowerCase()}${normalized.substring(2)}'
      : normalized;
}

bool _isPathQualifiedCommand(String command) =>
    command.contains('/') ||
    (p.separator == '\\' &&
        (command.contains('\\') || _drivePrefix.hasMatch(command)));

/// Base class for all permissions in the d4rt security system.
abstract class Permission {
  /// The type of permission (e.g., 'filesystem', 'network', 'process').
  String get type;

  /// Human-readable description of what this permission allows.
  String get description;

  /// Checks if this permission allows the given operation.
  bool allows(dynamic operation);

  @override
  String toString() => '$type: $description';
}

/// Filesystem permissions control file and directory operations.
class FilesystemPermission extends Permission {
  @override
  final String type = 'filesystem';

  final String? _path;
  final bool _read;
  final bool _write;
  final bool _execute;

  FilesystemPermission._(String? path, this._read, this._write, this._execute)
    : _path = path == null ? null : _canonicalizePermissionPath(path);

  /// Allows reading any file or directory.
  static final FilesystemPermission read = FilesystemPermission._(
    null,
    true,
    false,
    false,
  );

  /// Allows writing to any file or directory.
  static final FilesystemPermission write = FilesystemPermission._(
    null,
    false,
    true,
    false,
  );

  /// Allows executing any file.
  static final FilesystemPermission execute = FilesystemPermission._(
    null,
    false,
    false,
    true,
  );

  /// Allows all filesystem operations on any path.
  static final FilesystemPermission any = FilesystemPermission._(
    null,
    true,
    true,
    true,
  );

  /// Allows reading files/directories under [path], anchored at construction.
  factory FilesystemPermission.readPath(String path) =>
      FilesystemPermission._(path, true, false, false);

  /// Allows writing files/directories under [path], anchored at construction.
  factory FilesystemPermission.writePath(String path) =>
      FilesystemPermission._(path, false, true, false);

  /// Allows executing files under [path], anchored at construction.
  factory FilesystemPermission.executePath(String path) =>
      FilesystemPermission._(path, false, false, true);

  /// Allows all operations under [path], anchored at construction.
  factory FilesystemPermission.path(String path) =>
      FilesystemPermission._(path, true, true, true);

  static bool _isPathWithinScope(
    String allowedPath,
    String requested, {
    required bool followLinks,
  }) {
    bool contains(String scope, String request) {
      if (p.separator == '\\') {
        scope = scope.toLowerCase();
        request = request.toLowerCase();
      }
      return p.equals(scope, request) || p.isWithin(scope, request);
    }

    try {
      if (!followLinks &&
          contains(
            resolvePermissionPath(allowedPath, followLinks: false),
            requested,
          )) {
        return true;
      }
      return contains(resolvePermissionPath(allowedPath), requested);
    } on Object {
      // Resolution failure must never become lexical authorization.
      return false;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FilesystemPermission &&
      _path == other._path &&
      _read == other._read &&
      _write == other._write &&
      _execute == other._execute;

  @override
  int get hashCode =>
      Object.hash(FilesystemPermission, _path, _read, _write, _execute);

  @override
  String get description {
    final operations = [];
    if (_read) operations.add('read');
    if (_write) operations.add('write');
    if (_execute) operations.add('execute');

    final ops = operations.join('/');
    final path = _path ?? 'any';
    return '$ops operations on $path';
  }

  @override
  bool allows(dynamic operation) {
    if (operation is! Map<String, dynamic>) return false;

    final opType = operation['type'];
    final opPath = operation['path'];

    if (opType != 'filesystem') return false;

    // Check if the operation is allowed
    final requiredRead = operation['read'] ?? false;
    final requiredWrite = operation['write'] ?? false;
    final requiredExecute = operation['execute'] ?? false;

    if ((requiredRead && !_read) ||
        (requiredWrite && !_write) ||
        (requiredExecute && !_execute)) {
      return false;
    }

    if (operation['pathAgnostic'] == true) return true;
    String? resolvedPath;
    if (opPath is String) {
      try {
        resolvedPath = resolvePermissionPath(
          opPath,
          followLinks: operation['followLinks'] != false,
        );
      } on Object {
        return false;
      }
    }
    // Check path restrictions
    if (_path != null) {
      if (resolvedPath == null ||
          !_isPathWithinScope(
            _path,
            resolvedPath,
            followLinks: operation['followLinks'] != false,
          )) {
        return false;
      }
    }

    return true;
  }
}

/// Network permissions control network operations.
class NetworkPermission extends Permission {
  @override
  final String type = 'network';

  final String? _host;
  final int? _port;
  final bool _connect;
  final bool _listen;
  final bool _bind;

  NetworkPermission._(
    String? host,
    this._port,
    this._connect,
    this._listen,
    this._bind,
  ) : _host = host == null ? null : normalizeNetworkHost(host);

  /// Allows connecting to any host/port.
  static final NetworkPermission connect = NetworkPermission._(
    null,
    null,
    true,
    false,
    false,
  );

  /// Allows listening on any port.
  static final NetworkPermission listen = NetworkPermission._(
    null,
    null,
    false,
    true,
    false,
  );

  /// Allows binding to any address/port.
  static final NetworkPermission bind = NetworkPermission._(
    null,
    null,
    false,
    false,
    true,
  );

  /// Allows all network operations.
  static final NetworkPermission any = NetworkPermission._(
    null,
    null,
    true,
    true,
    true,
  );

  /// Allows connecting to the specified host.
  factory NetworkPermission.connectTo(String host) =>
      NetworkPermission._(host, null, true, false, false);

  /// Allows connecting to the specified host and port.
  factory NetworkPermission.connectToPort(String host, int port) =>
      NetworkPermission._(host, port, true, false, false);

  /// Allows listening on the specified port.
  factory NetworkPermission.listenOn(int port) =>
      NetworkPermission._(null, port, false, true, false);

  @override
  bool operator ==(Object other) =>
      other is NetworkPermission &&
      _host == other._host &&
      _port == other._port &&
      _connect == other._connect &&
      _listen == other._listen &&
      _bind == other._bind;

  @override
  int get hashCode =>
      Object.hash(NetworkPermission, _host, _port, _connect, _listen, _bind);

  @override
  String get description {
    final operations = [];
    if (_connect) operations.add('connect');
    if (_listen) operations.add('listen');
    if (_bind) operations.add('bind');

    final ops = operations.join('/');
    if (_host != null && _port != null) {
      return '$ops to $_host:$_port';
    } else if (_host != null) {
      return '$ops to $_host';
    } else if (_port != null) {
      return '$ops on port $_port';
    } else {
      return '$ops on any host/port';
    }
  }

  @override
  bool allows(dynamic operation) {
    if (operation is! Map<String, dynamic>) return false;

    final opType = operation['type'];
    final opHost = operation['host'];
    final opPort = operation['port'];

    if (opType != 'network') return false;

    // Check if the operation is allowed
    final requiredConnect = operation['connect'] ?? false;
    final requiredListen = operation['listen'] ?? false;
    final requiredBind = operation['bind'] ?? false;

    if ((requiredConnect && !_connect) ||
        (requiredListen && !_listen) ||
        (requiredBind && !_bind)) {
      return false;
    }

    // Check host/port restrictions
    if (_host != null &&
        (opHost is! String || normalizeNetworkHost(opHost) != _host)) {
      return false;
    }
    if (_port != null && (opPort is! int || opPort != _port)) {
      return false;
    }

    return true;
  }
}

/// Process permissions control process execution.
class ProcessRunPermission extends Permission {
  @override
  final String type = 'process';

  final String? _command;
  final List<String>? _allowedArgs;

  ProcessRunPermission._(String? command, List<String>? allowedArgs)
    : _command = command != null && _isPathQualifiedCommand(command)
          ? _canonicalizePermissionPath(command)
          : command,
      _allowedArgs = allowedArgs == null
          ? null
          : List<String>.unmodifiable(allowedArgs);

  /// Allows running any command with any arguments.
  static final ProcessRunPermission any = ProcessRunPermission._(null, null);

  /// Allows the exact command with any arguments.
  ///
  /// Path-qualified commands are anchored at construction. Bare names do not
  /// authorize paths with the same basename, or vice versa.
  factory ProcessRunPermission.command(String command) =>
      ProcessRunPermission._(command, null);

  /// Allows the exact command with an immutable snapshot of the ordered [args].
  ///
  /// Operations must supply arguments, including an explicit list for no args.
  factory ProcessRunPermission.commandWithArgs(
    String command,
    List<String> args,
  ) => ProcessRunPermission._(command, args);

  /// Whether this grant permits arbitrary executable and shell command input.
  bool get isUnrestricted => _command == null && _allowedArgs == null;

  /// Resolves a path-qualified executable against the effective child cwd.
  /// Bare names stay bare and therefore cannot acquire path-scoped authority.
  static String resolveExecutable(String command, String workingDirectory) =>
      _isPathQualifiedCommand(command)
      ? p.normalize(p.absolute(p.join(workingDirectory, command)))
      : command;

  static bool _sameArgs(List<String> expected, List<dynamic> actual) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] is! String || actual[i] != expected[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is ProcessRunPermission &&
      _command == other._command &&
      ((_allowedArgs == null && other._allowedArgs == null) ||
          (_allowedArgs != null &&
              other._allowedArgs != null &&
              _sameArgs(_allowedArgs, other._allowedArgs)));

  @override
  int get hashCode => Object.hash(
    ProcessRunPermission,
    _command,
    _allowedArgs == null ? null : Object.hashAll(_allowedArgs),
  );

  @override
  String get description {
    if (_command == null) {
      return 'run any command';
    } else if (_allowedArgs == null) {
      return 'run command: $_command';
    } else {
      return 'run command: $_command with args: ${_allowedArgs.join(', ')}';
    }
  }

  @override
  bool allows(dynamic operation) {
    if (operation is! Map<String, dynamic>) return false;

    final opType = operation['type'];
    final opCommand = operation['command'];
    final opArgs = operation['args'];

    if (opType != 'process') return false;
    if (operation['shell'] == true && !isUnrestricted) return false;

    // Check command restrictions
    if (_command != null) {
      if (opCommand is! String) return false;
      if (_isPathQualifiedCommand(_command)) {
        if (!_isPathQualifiedCommand(opCommand) ||
            _canonicalizePermissionPath(opCommand) != _command) {
          return false;
        }
      } else if (opCommand != _command) {
        return false;
      }
    }

    // Check argument restrictions
    if (_allowedArgs != null &&
        (opArgs is! List || !_sameArgs(_allowedArgs, opArgs))) {
      return false;
    }

    return true;
  }
}

/// Type alias for [ProcessRunPermission] for convenience.
typedef ProcessPermission = ProcessRunPermission;

/// Isolate permissions control isolate creation and communication.
class IsolatePermission extends Permission {
  @override
  final String type = 'isolate';

  final bool _spawn;
  final bool _communicate;

  IsolatePermission._(this._spawn, this._communicate);

  /// Allows spawning and controlling native isolates (not communication).
  static final IsolatePermission spawn = IsolatePermission._(true, false);

  /// Allows communicating with isolates (send/receive messages).
  static final IsolatePermission communicate = IsolatePermission._(false, true);

  /// Allows all isolate operations.
  static final IsolatePermission any = IsolatePermission._(true, true);

  @override
  bool operator ==(Object other) =>
      other is IsolatePermission &&
      _spawn == other._spawn &&
      _communicate == other._communicate;

  @override
  int get hashCode => Object.hash(IsolatePermission, _spawn, _communicate);

  @override
  String get description {
    final operations = [];
    if (_spawn) operations.add('spawn');
    if (_communicate) operations.add('communicate');
    return '${operations.join('/')} isolates';
  }

  @override
  bool allows(dynamic operation) {
    if (operation is! Map<String, dynamic>) return false;

    final opType = operation['type'];
    if (opType != 'isolate') return false;

    final requiredSpawn = operation['spawn'] ?? false;
    final requiredCommunicate = operation['communicate'] ?? false;

    if ((requiredSpawn && !_spawn) || (requiredCommunicate && !_communicate)) {
      return false;
    }

    return true;
  }
}

/// Dangerous permissions that should be granted with extreme caution.
class DangerousPermission extends Permission {
  @override
  final String type = 'dangerous';

  final String _operation;

  DangerousPermission._(this._operation);

  /// Allows evaluation of arbitrary code strings (eval-like functionality).
  static final DangerousPermission codeEvaluation = DangerousPermission._(
    'code evaluation',
  );

  /// Allows loading and executing native plugins/libraries.
  static final DangerousPermission nativePlugins = DangerousPermission._(
    'native plugins',
  );

  /// Allows native child execution outside the interpreter sandbox.
  static final DangerousPermission processExecution = DangerousPermission._(
    'process execution',
  );

  /// Allows watching native signals and terminating processes, including PIDs.
  static final DangerousPermission processSignals = DangerousPermission._(
    'process signals',
  );

  /// Allows VM developer tooling, including registered extension invocation.
  static final DangerousPermission developerTools = DangerousPermission._(
    'developer tools',
  );

  /// Allows all dangerous operations.
  static final DangerousPermission any = DangerousPermission._(
    'any dangerous operation',
  );

  @override
  bool operator ==(Object other) =>
      other is DangerousPermission && _operation == other._operation;

  @override
  int get hashCode => Object.hash(DangerousPermission, _operation);

  @override
  String get description => 'dangerous operation: $_operation';

  @override
  bool allows(dynamic operation) {
    if (operation is! Map<String, dynamic>) return false;

    final opType = operation['type'];
    final opOperation = operation['operation'];

    if (opType != 'dangerous') return false;

    return _operation == 'any dangerous operation' || opOperation == _operation;
  }
}
