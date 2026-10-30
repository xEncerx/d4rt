import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;
import '../native_permissions.dart';

// Windows can dispatch batch executables through cmd.exe even with the native
// runInShell option disabled. Include DOS trailing-dot/space spelling variants.
final _windowsBatchCommand =
    RegExp(r'\.(?:bat|cmd)[ .]*"?[ ]*$', caseSensitive: false);

/// Bridged implementation of dart:io Process functionality
class ProcessIo {
  static BridgedClass get definition => BridgedClass(
        nativeType: Process,
        name: 'Process',
        typeParameterCount: 0,
        staticMethods: {
          'start': _start,
          'run': _run,
          'runSync': _runSync,
          'killPid': (visitor, positionalArgs, namedArgs) {
            _checkSignals(visitor);
            return _killPid(positionalArgs, namedArgs);
          },
        },
        methods: {
          'kill': (visitor, target, positionalArgs, namedArgs) {
            _checkSignals(visitor);
            return _kill(target, positionalArgs, namedArgs);
          },
        },
        getters: {
          'exitCode': (visitor, target) => (target as Process).exitCode,
          'pid': (visitor, target) => (target as Process).pid,
          'stdin': (visitor, target) => (target as Process).stdin,
          'stdout': (visitor, target) => (target as Process).stdout,
          'stderr': (visitor, target) => (target as Process).stderr,
        },
      );

  static Future<Process> _start(
    InterpreterVisitor visitor,
    List<dynamic> positionalArgs,
    Map<String, dynamic> namedArgs,
  ) {
    final input = _ProcessInput(positionalArgs, namedArgs);
    input.authorize(visitor);
    return Process.start(
      input.executable,
      input.arguments,
      workingDirectory: input.workingDirectory,
      environment: input.environment,
      includeParentEnvironment: input.includeParentEnvironment,
      runInShell: input.runInShell,
      mode: namedArgs['mode'] as ProcessStartMode? ?? ProcessStartMode.normal,
    );
  }

  static Future<ProcessResult> _run(
    InterpreterVisitor visitor,
    List<dynamic> positionalArgs,
    Map<String, dynamic> namedArgs,
  ) {
    final input = _ProcessInput(positionalArgs, namedArgs);
    input.authorize(visitor);
    return Process.run(
      input.executable,
      input.arguments,
      workingDirectory: input.workingDirectory,
      environment: input.environment,
      includeParentEnvironment: input.includeParentEnvironment,
      runInShell: input.runInShell,
      stdoutEncoding:
          namedArgs['stdoutEncoding'] as Encoding? ?? systemEncoding,
      stderrEncoding:
          namedArgs['stderrEncoding'] as Encoding? ?? systemEncoding,
    );
  }

  static ProcessResult _runSync(
    InterpreterVisitor visitor,
    List<dynamic> positionalArgs,
    Map<String, dynamic> namedArgs,
  ) {
    final input = _ProcessInput(positionalArgs, namedArgs);
    input.authorize(visitor);
    return Process.runSync(
      input.executable,
      input.arguments,
      workingDirectory: input.workingDirectory,
      environment: input.environment,
      includeParentEnvironment: input.includeParentEnvironment,
      runInShell: input.runInShell,
      stdoutEncoding:
          namedArgs['stdoutEncoding'] as Encoding? ?? systemEncoding,
      stderrEncoding:
          namedArgs['stderrEncoding'] as Encoding? ?? systemEncoding,
    );
  }

  static bool _killPid(
      List<dynamic> positionalArgs, Map<String, dynamic> namedArgs) {
    if (positionalArgs.isEmpty) {
      throw ArgumentError('Process.killPid requires pid');
    }

    final pid = positionalArgs[0] as int;
    final signal = positionalArgs.length > 1
        ? positionalArgs[1] as ProcessSignal
        : namedArgs['signal'] as ProcessSignal? ?? ProcessSignal.sigterm;

    return Process.killPid(pid, signal);
  }

  static bool _kill(dynamic instance, List<dynamic> positionalArgs,
      Map<String, dynamic> namedArgs) {
    if (instance is! Process) {
      throw ArgumentError('Invalid process instance');
    }

    final signal = positionalArgs.isNotEmpty
        ? positionalArgs[0] as ProcessSignal
        : namedArgs['signal'] as ProcessSignal? ?? ProcessSignal.sigterm;
    return instance.kill(signal);
  }

  static void _checkSignals(InterpreterVisitor? visitor) =>
      requireNativePermission(
          visitor,
          {
            'type': 'dangerous',
            'operation': 'process signals',
          },
          'DangerousPermission.processSignals');
}

// One immutable input snapshot owns both authorization and native launch.
class _ProcessInput {
  late final String executable;
  late final List<String> arguments;
  late final String workingDirectory;
  late final Map<String, String>? environment;
  late final bool includeParentEnvironment;
  late final bool runInShell;

  _ProcessInput(List<dynamic> positional, Map<String, dynamic> named) {
    if (positional.isEmpty) {
      throw ArgumentError('Process execution requires executable path');
    }
    final command = positional[0].toString();
    arguments = positional.length > 1
        ? (positional[1] as List).map((arg) => arg.toString()).toList()
        : <String>[];
    final directory = named['workingDirectory']?.toString();
    environment = (named['environment'] as Map?)?.cast<String, String>();
    includeParentEnvironment =
        named['includeParentEnvironment'] as bool? ?? true;
    runInShell = named['runInShell'] as bool? ?? false;
    // Freeze cwd as well as strings. Relative qualified executables resolve
    // against the effective child cwd on every host; bare names remain bare.
    workingDirectory = p.normalize(
      p.absolute(directory ?? Directory.current.path),
    );
    executable = ProcessRunPermission.resolveExecutable(
      command,
      workingDirectory,
    );
  }

  void authorize(InterpreterVisitor? visitor) {
    final usesShell = runInShell ||
        (Platform.isWindows && _windowsBatchCommand.hasMatch(executable));
    requireNativePermission(
        visitor,
        {
          'type': 'process',
          'command': executable,
          'args': arguments,
          'shell': usesShell,
        },
        'ProcessRunPermission${usesShell ? ".any for shell execution" : ""}');
    requireNativePermission(
        visitor,
        {
          'type': 'dangerous',
          'operation': 'process execution',
        },
        'DangerousPermission.processExecution');
  }
}

/// Bridged implementation of ProcessResult
class ProcessResultIo {
  static BridgedClass get definition => BridgedClass(
        nativeType: ProcessResult,
        name: 'ProcessResult',
        typeParameterCount: 0,
        getters: {
          'exitCode': (visitor, target) => (target as ProcessResult).exitCode,
          'pid': (visitor, target) => (target as ProcessResult).pid,
          'stdout': (visitor, target) => (target as ProcessResult).stdout,
          'stderr': (visitor, target) => (target as ProcessResult).stderr,
        },
      );
}

/// Bridged implementation of ProcessSignal
class ProcessSignalIo {
  static BridgedClass get definition => BridgedClass(
        nativeType: ProcessSignal,
        name: 'ProcessSignal',
        typeParameterCount: 0,
        staticGetters: {
          'sighup': (visitor) => ProcessSignal.sighup,
          'sigint': (visitor) => ProcessSignal.sigint,
          'sigquit': (visitor) => ProcessSignal.sigquit,
          'sigill': (visitor) => ProcessSignal.sigill,
          'sigtrap': (visitor) => ProcessSignal.sigtrap,
          'sigabrt': (visitor) => ProcessSignal.sigabrt,
          'sigbus': (visitor) => ProcessSignal.sigbus,
          'sigfpe': (visitor) => ProcessSignal.sigfpe,
          'sigkill': (visitor) => ProcessSignal.sigkill,
          'sigusr1': (visitor) => ProcessSignal.sigusr1,
          'sigsegv': (visitor) => ProcessSignal.sigsegv,
          'sigusr2': (visitor) => ProcessSignal.sigusr2,
          'sigpipe': (visitor) => ProcessSignal.sigpipe,
          'sigalrm': (visitor) => ProcessSignal.sigalrm,
          'sigterm': (visitor) => ProcessSignal.sigterm,
          'sigchld': (visitor) => ProcessSignal.sigchld,
          'sigcont': (visitor) => ProcessSignal.sigcont,
          'sigstop': (visitor) => ProcessSignal.sigstop,
          'sigtstp': (visitor) => ProcessSignal.sigtstp,
          'sigttin': (visitor) => ProcessSignal.sigttin,
          'sigttou': (visitor) => ProcessSignal.sigttou,
          'sigurg': (visitor) => ProcessSignal.sigurg,
          'sigxcpu': (visitor) => ProcessSignal.sigxcpu,
          'sigxfsz': (visitor) => ProcessSignal.sigxfsz,
          'sigvtalrm': (visitor) => ProcessSignal.sigvtalrm,
          'sigprof': (visitor) => ProcessSignal.sigprof,
          'sigwinch': (visitor) => ProcessSignal.sigwinch,
          'sigpoll': (visitor) => ProcessSignal.sigpoll,
          'sigsys': (visitor) => ProcessSignal.sigsys,
        },
        getters: {
          'name': (visitor, target) => (target as ProcessSignal).name,
          'runtimeType': (visitor, target) =>
              (target as ProcessSignal).runtimeType,
          'hashCode': (visitor, target) => (target as ProcessSignal).hashCode,
        },
        methods: {
          'watch': (visitor, target, positionalArgs, namedArgs) {
            ProcessIo._checkSignals(visitor);
            return (target as ProcessSignal).watch();
          },
          'toString': (visitor, target, positionalArgs, namedArgs) =>
              (target as ProcessSignal).toString(),
        },
      );
}

/// Bridged implementation of ProcessStartMode
class ProcessStartModeIo {
  static BridgedClass get definition => BridgedClass(
        nativeType: ProcessStartMode,
        name: 'ProcessStartMode',
        typeParameterCount: 0,
        staticGetters: {
          'normal': (visitor) => ProcessStartMode.normal,
          'inheritStdio': (visitor) => ProcessStartMode.inheritStdio,
          'detached': (visitor) => ProcessStartMode.detached,
          'detachedWithStdio': (visitor) => ProcessStartMode.detachedWithStdio,
        },
      );
}
