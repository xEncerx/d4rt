import 'dart:io';
import 'package:d4rt/d4rt.dart';

/// Package release reported by the command-line interface.
const String version = '0.5.0';

enum _Mode { file, eval, repl, introspection, jsonIntrospection, help, version }

/// Parsed once, before the target boundary. Script arguments and code are opaque.
class _Command {
  final _Mode mode;
  final String? target;
  final List<String> scriptArgs;
  final bool debug;
  final Set<String> capabilities;

  _Command(
    this.mode,
    this.target,
    this.scriptArgs,
    this.debug,
    this.capabilities,
  );

  factory _Command.parse(List<String> args) {
    var debug = false;
    final capabilities = <String>{};
    _Command command(
      _Mode mode, [
      String? target,
      List<String> rest = const [],
    ]) => _Command(mode, target, rest, debug, capabilities);

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--debug':
          debug = true;
        case '--allow-fs':
        case '--allow-net':
        case '--allow-process':
        case '--allow-isolate':
        case '--allow-dangerous':
        case '--allow-all':
          capabilities.add(arg);
        case '-h':
        case '--help':
          return command(_Mode.help);
        case '-v':
        case '--version':
          return command(_Mode.version);
        case '-e':
        case '--eval':
        case '-i':
        case '--introspection':
        case '--json-introspection':
          if (i + 1 >= args.length) {
            throw FormatException('$arg requires an operand.');
          }
          if (i + 2 != args.length) {
            throw FormatException('Unexpected arguments after $arg operand.');
          }
          return command(
            arg == '-e' || arg == '--eval'
                ? _Mode.eval
                : arg == '--json-introspection'
                ? _Mode.jsonIntrospection
                : _Mode.introspection,
            args[i + 1],
          );
        case '--':
          if (i + 1 >= args.length) {
            throw const FormatException('-- requires a script path.');
          }
          return command(_Mode.file, args[i + 1], args.sublist(i + 2));
        case 'repl':
          if (i + 1 != args.length) {
            throw const FormatException('Unexpected arguments after repl.');
          }
          return command(_Mode.repl);
        default:
          if (arg.startsWith('-')) {
            throw FormatException('Unknown option: $arg');
          }
          return command(_Mode.file, arg, args.sublist(i + 1));
      }
    }
    return command(_Mode.repl);
  }

  /// The only CLI grant recipe, also used when resetting a REPL.
  D4rt createInterpreter(String root, {required bool evaluation}) {
    final d4rt = D4rt(enableAstCache: evaluation);
    if (debug) d4rt.setDebug(true);
    d4rt.grant(FilesystemPermission.readPath(root));
    bool allows(String flag) =>
        capabilities.contains('--allow-all') || capabilities.contains(flag);
    if (allows('--allow-fs')) d4rt.grant(FilesystemPermission.any);
    if (allows('--allow-net')) d4rt.grant(NetworkPermission.any);
    if (allows('--allow-process')) {
      d4rt.grant(ProcessRunPermission.any);
      d4rt.grant(DangerousPermission.processExecution);
    }
    if (allows('--allow-isolate')) d4rt.grant(IsolatePermission.any);
    if (allows('--allow-dangerous')) d4rt.grant(DangerousPermission.any);
    if (evaluation) d4rt.grant(DangerousPermission.codeEvaluation);
    return d4rt;
  }
}

void main(List<String> args) async {
  final _Command command;
  try {
    command = _Command.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 1;
    return;
  }
  switch (command.mode) {
    case _Mode.help:
      _printUsage();
    case _Mode.version:
      stdout.writeln('d4rt version $version');
    case _Mode.eval:
      await _evalCode(command.target!, command);
    case _Mode.introspection:
    case _Mode.jsonIntrospection:
      await _introspectFile(
        command.target!,
        asJson: command.mode == _Mode.jsonIntrospection,
      );
    case _Mode.file:
      await _executeFile(command.target!, command.scriptArgs, command);
    case _Mode.repl:
      await _startRepl(command);
  }
}

void _printUsage() {
  stdout.writeln('''
d4rt - Dart Code Interpreter & Runtime CLI

Usage:
  d4rt [options] <script.dart> [args...]       Execute a Dart script file
  d4rt [options] -e "<code>"                  Evaluate a Dart code string
  d4rt [options] -i <script.dart>             Analyze declarations
  d4rt [options] --json-introspection <script.dart>
  d4rt [options] repl                        Start interactive REPL shell
  d4rt [options]                             Start interactive REPL shell

Options:
  -h, --help                Show this help message
  -v, --version             Show d4rt version
  -e, --eval "<code>"       Evaluate a single Dart code string
  -i, --introspection       Print code structure and declaration analysis
  --json-introspection      Print code structure analysis in JSON format
  --debug                   Enable verbose debug logging
  --allow-fs                Unrestricted filesystem access
  --allow-net               Unrestricted network access
  --allow-process           Native process execution (not signals)
  --allow-isolate           Native isolate operations
  --allow-dangerous         All dangerous operations
  --allow-all               All of the above capabilities
  -- <script.dart>          Execute an option-like filename

Place options before the script, repl, or -e CODE. Script arguments are unchanged.
Defaults: read-only script directory subtree, or cwd subtree for eval/REPL.
Eval/REPL explicitly enable code evaluation. Native opt-ins are not a sandbox
for hostile code.
''');
}

Future<void> _evalCode(String code, _Command command) async {
  try {
    final root = Directory.current.absolute.path;
    final d4rt = command.createInterpreter(root, evaluation: true);
    // If source contains main(), run execute(), otherwise use eval
    if (code.contains('main(') || code.contains('main()')) {
      final result = await d4rt.execute(
        source: code,
        basePath: root,
        allowFileSystemImports: true,
      );
      if (result != null) {
        stdout.writeln(result);
      }
    } else {
      d4rt.execute(
        source: 'void main() {}',
        basePath: root,
        allowFileSystemImports: true,
      );
      final result = await d4rt.eval(code);
      if (result != null) {
        stdout.writeln(result);
      }
    }
  } catch (e) {
    stderr.writeln('Runtime Error: $e');
    exitCode = 1;
  }
}

Future<void> _introspectFile(String filePath, {required bool asJson}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    stderr.writeln('Error: File not found: $filePath');
    exitCode = 1;
    return;
  }

  try {
    final source = await file.readAsString();
    final d4rt = D4rt();
    final result = d4rt.analyze(source: source);

    if (asJson) {
      stdout.writeln(result.toJson());
    } else {
      stdout.writeln(result.toString());
    }
  } catch (e) {
    stderr.writeln('Analysis Error: $e');
    exitCode = 1;
  }
}

Future<void> _executeFile(
  String filePath,
  List<String> scriptArgs,
  _Command command,
) async {
  final file = File(filePath);
  if (!await file.exists()) {
    stderr.writeln('Error: File not found: $filePath');
    exitCode = 1;
    return;
  }

  try {
    final source = await file.readAsString();
    final basePath = file.parent.absolute.path;
    final d4rt = command.createInterpreter(basePath, evaluation: false);
    final result = await d4rt.execute(
      source: source,
      name: 'main',
      positionalArgs: [scriptArgs],
      basePath: basePath,
      allowFileSystemImports: true,
    );

    if (result != null && result != 0) {
      if (result is int) {
        exitCode = result;
      }
    }
  } catch (e) {
    stderr.writeln('Runtime Error: $e');
    exitCode = 1;
  }
}

Future<void> _startRepl(_Command command) async {
  stdout.writeln('==============================================');
  stdout.writeln('  d4rt v$version - Interactive Dart REPL');
  stdout.writeln('  Type :help for help, :exit or Ctrl+C to quit');
  stdout.writeln('==============================================\n');

  final root = Directory.current.absolute.path;
  D4rt freshInterpreter() {
    final d4rt = command.createInterpreter(root, evaluation: true);
    d4rt.execute(
      source: 'void main() {}',
      basePath: root,
      allowFileSystemImports: true,
    );
    return d4rt;
  }

  var d4rt = freshInterpreter();

  var buffer = StringBuffer();
  var openBraces = 0;
  var openParens = 0;

  while (true) {
    final prompt = buffer.isEmpty ? 'd4rt> ' : '....> ';
    stdout.write(prompt);
    final line = stdin.readLineSync();

    if (line == null) {
      stdout.writeln();
      break;
    }

    final trimmed = line.trim();

    // REPL commands
    if (buffer.isEmpty) {
      if (trimmed == ':exit' ||
          trimmed == ':quit' ||
          trimmed == 'exit' ||
          trimmed == 'quit') {
        stdout.writeln('Goodbye!');
        break;
      }
      if (trimmed == ':help') {
        _printReplHelp();
        continue;
      }
      if (trimmed == ':clear') {
        d4rt = freshInterpreter();
        stdout.writeln('Environment cleared.');
        continue;
      }
      if (trimmed.isEmpty) {
        continue;
      }
    }

    // Count delimiters for multiline support
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '{') openBraces++;
      if (char == '}') {
        if (openBraces > 0) openBraces--;
      }
      if (char == '(') openParens++;
      if (char == ')') {
        if (openParens > 0) openParens--;
      }
    }

    buffer.writeln(line);

    if (openBraces > 0 || openParens > 0) {
      continue;
    }

    final code = buffer.toString().trim();
    buffer.clear();
    openBraces = 0;
    openParens = 0;

    if (code.isEmpty) continue;

    try {
      final result = await d4rt.eval(code);
      if (result != null) {
        stdout.writeln('=> $result');
      }
    } catch (e) {
      stderr.writeln('Error: $e');
    }
  }
}

void _printReplHelp() {
  stdout.writeln('''
REPL Commands:
  :help          Show this help message
  :clear         Reset the evaluation environment
  :exit, :quit   Exit the REPL

Tips:
  - Enter Dart expressions directly: 2 + 2, "hello".toUpperCase()
  - Define variables: var x = 42; or int y = 100;
  - Define functions: int add(int a, int b) => a + b;
  - Multiline statements with { ... } or ( ... ) are automatically collected.
''');
}
