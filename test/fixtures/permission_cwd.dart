// Runs in a separate process so cwd changes cannot affect concurrent tests.
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:path/path.dart' as p;

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void main() {
  final original = Directory.current;
  final root = Directory.systemTemp.createTempSync('d4rt_permission_cwd_');
  try {
    final first = Directory(p.join(root.path, 'first'))..createSync();
    final second = Directory(p.join(root.path, 'second'))..createSync();
    Directory.current = first;
    final filesystem = FilesystemPermission.readPath('data');
    final executable = ProcessRunPermission.commandWithArgs('./tools/runner', [
      '--safe',
    ]);
    final bare = ProcessRunPermission.command('runner');
    final filesystemHash = filesystem.hashCode;
    final executableHash = executable.hashCode;
    final bareHash = bare.hashCode;
    final filesystemDescription = filesystem.description;
    final executableDescription = executable.description;
    final grants = {filesystem, executable, bare};
    final interpreter = D4rt()
      ..grant(filesystem)
      ..grant(executable)
      ..grant(bare);
    Directory.current = second;
    final absoluteFilesystem = FilesystemPermission.readPath(
      p.join(first.path, 'data'),
    );
    final absoluteExecutable = ProcessRunPermission.commandWithArgs(
      p.join(first.path, 'tools', 'runner'),
      ['--safe'],
    );
    require(filesystem.hashCode == filesystemHash, 'Filesystem hash drifted');
    require(executable.hashCode == executableHash, 'Executable hash drifted');
    require(bare.hashCode == bareHash, 'Bare command hash drifted');
    require(
      filesystem.description == filesystemDescription,
      'Filesystem description drifted',
    );
    require(
      executable.description == executableDescription,
      'Executable description drifted',
    );
    require(
      grants.contains(absoluteFilesystem),
      'Filesystem set membership drifted',
    );
    require(
      grants.contains(absoluteExecutable),
      'Executable set membership drifted',
    );
    require(
      grants.contains(ProcessRunPermission.command('runner')),
      'Bare command identity drifted',
    );
    require(
      interpreter.hasPermission(absoluteFilesystem),
      'Filesystem query failed',
    );
    require(
      interpreter.hasPermission(absoluteExecutable),
      'Executable query failed',
    );
    require(
      interpreter.checkPermission({
        'type': 'filesystem',
        'path': p.join(first.path, 'data', 'file'),
        'read': true,
      }),
      'Original filesystem scope lost',
    );
    require(
      !interpreter.checkPermission({
        'type': 'filesystem',
        'path': 'data/file',
        'read': true,
      }),
      'New cwd filesystem scope authorized',
    );
    require(
      interpreter.checkPermission({
        'type': 'process',
        'command': p.join(first.path, 'tools', 'runner'),
        'args': ['--safe'],
      }),
      'Original executable scope lost',
    );
    require(
      !interpreter.checkPermission({
        'type': 'process',
        'command': './tools/runner',
        'args': ['--safe'],
      }),
      'New cwd executable authorized',
    );
    require(
      interpreter.checkPermission({'type': 'process', 'command': 'runner'}),
      'Bare command meaning drifted',
    );
    interpreter.revoke(absoluteFilesystem);
    interpreter.revoke(absoluteExecutable);
    require(
      !interpreter.checkPermission({
        'type': 'filesystem',
        'path': p.join(first.path, 'data', 'file'),
        'read': true,
      }),
      'Equivalent filesystem revoke failed',
    );
    require(
      !interpreter.checkPermission({
        'type': 'process',
        'command': p.join(first.path, 'tools', 'runner'),
        'args': ['--safe'],
      }),
      'Equivalent executable revoke failed',
    );
  } finally {
    Directory.current = original;
    root.deleteSync(recursive: true);
  }
  print('CWD_SCOPE_PASS');
}
