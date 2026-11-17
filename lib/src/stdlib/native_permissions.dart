import 'dart:isolate';
import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/exceptions.dart' show InterpreterPolicyError;

// Operation guards deliberately recheck the owning interpreter, including for
// retained native objects and method tearoffs. Absence of an owner is denial.
void requireNativePermission(
  InterpreterVisitor? visitor,
  Map<String, dynamic> operation,
  String grant,
) {
  if (visitor?.moduleLoader.d4rt?.checkPermission(operation) ?? false) return;
  throw InterpreterPolicyError('Native operation requires $grant.');
}

void requireDeveloperPermission(InterpreterVisitor? visitor) =>
    requireNativePermission(visitor, {
      'type': 'dangerous',
      'operation': 'developer tools',
    }, 'DangerousPermission.developerTools');

void requireIsolatePermission(
  InterpreterVisitor? visitor, {
  bool control = false,
  bool communicate = false,
}) {
  // Check separately: D4rt accepts any matching grant, so separate grants must
  // compose without allowing either one to substitute for the other.
  if (control) {
    requireNativePermission(visitor, {
      'type': 'isolate',
      'spawn': true,
    }, 'IsolatePermission.spawn');
  }
  if (communicate) {
    requireNativePermission(visitor, {
      'type': 'isolate',
      'communicate': true,
    }, 'IsolatePermission.communicate');
  }
}

void requireReceivePortCommunication(
  InterpreterVisitor? visitor,
  Object? source,
) {
  final native = source is BridgedInstance ? source.nativeObject : source;
  if (native is ReceivePort) {
    requireIsolatePermission(visitor, communicate: true);
  }
}

// ReceivePort is also a Stream. Generic stream dispatch must guard the native
// receiver without changing Stream subtype tests or restricting issued streams.
BridgedClass guardReceivePortStream(BridgedClass bridge) {
  bridge.methods = bridge.methods.map(
    (name, call) => MapEntry(name, (visitor, target, args, named) {
      requireReceivePortCommunication(visitor, target);
      return call(visitor, target, args, named);
    }),
  );
  bridge.getters = bridge.getters.map(
    (name, call) => MapEntry(name, (visitor, target) {
      requireReceivePortCommunication(visitor, target);
      return call(visitor, target);
    }),
  );
  return bridge;
}
