import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('scoped filesystem production bridges and cwd isolation', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      p.absolute('test/fixtures/filesystem_scopes.dart'),
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    for (final marker in [
      'METADATA_AMBIENT_PASS',
      'CANONICAL_NAMESPACE_PASS',
      'LINK_POLICY_PASS',
      'TEMP_PREFIX_PASS',
      'LIST_RESOLUTION_REVOKE_PASS',
      'HANDLE_ISSUANCE_PASS',
      'WATCH_BROADCAST_REVOKE_DESTINATION_PASS',
      'CWD_DEFERRED_IDENTITY_PASS',
      'FILESYSTEM_SCOPES_PASS',
    ]) {
      expect(result.stdout, contains(marker));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('raw ownership, recursive effects and deferred native IO', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      p.absolute('test/fixtures/filesystem_operations.dart'),
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    for (final marker in [
      'RAW_PATH_OWNERSHIP_PASS',
      'RECURSIVE_EFFECT_BOUNDARIES_PASS',
      'LISTED_ENTRY_SEMANTICS_PASS',
      'DEFERRED_OPERATIONS_AND_NATIVE_RESULTS_PASS',
      'FILESYSTEM_OPERATIONS_PASS',
    ]) {
      expect(result.stdout, contains(marker));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('original paths and watch result paths retain their meaning', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      p.absolute('test/fixtures/filesystem_paths.dart'),
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    for (final marker in [
      'EMPTY_RECEIVERS_STREAMS_PASS',
      'EMPTY_STATIC_AND_CWD_PASS',
      'EMPTY_DESTINATIONS_DESTRUCTIVE_NO_EFFECTS_PASS',
      'EXPLICIT_DOT_RELATIVE_PATHS_PASS',
      'WATCH_SELF_CHILD_MOVE_PATHS_PASS',
      'FILESYSTEM_PATHS_PASS',
    ]) {
      expect(result.stdout, contains(marker));
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
