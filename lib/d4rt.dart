/// D4rt - A powerful Dart code interpreter and runtime environment.
///
/// D4rt is a Dart interpreter that executes code at runtime,
/// with support for bridging between interpreted and native Dart code, async/await,
/// classes, inheritance, enums, and more.
///
/// ## Key Features:
/// - Dart syntax including classes, methods and functions
/// - Async/await execution with proper state management
/// - Bridged types for seamless native-interpreted code integration
/// - Standard library implementation
/// - Module system with import/export support
/// - Extension methods and mixins
///
/// ## Basic Usage:
/// ```dart
/// final interpreter = D4rt();
/// final result = await interpreter.execute('''
///   int add(int a, int b) => a + b;
///
///   void main() {
///     print(add(5, 3));
///   }
/// ''');
/// ```
library;

export 'package:d4rt/src/async_state.dart';
export 'package:d4rt/src/bridge/bridge_annotations.dart';
export 'package:d4rt/src/bridge/bridge_helpers.dart';
export 'package:d4rt/src/bridge/bridge_registry_manager.dart';
export 'package:d4rt/src/bridge/bridged_enum.dart';
export 'package:d4rt/src/bridge/bridged_types.dart';
export 'package:d4rt/src/bridge/enum_factory.dart';
export 'package:d4rt/src/bridge/enum_mixin_metadata.dart';
export 'package:d4rt/src/bridge/enum_signature.dart';
export 'package:d4rt/src/bridge/enum_type_metadata.dart';
export 'package:d4rt/src/bridge/enum_type_relations.dart';
export 'package:d4rt/src/bridge/library_tracking.dart';
export 'package:d4rt/src/bridge/registration.dart' hide BridgedMethodCallable;
export 'package:d4rt/src/callable.dart' hide invokeFunctionFromHost;
export 'package:d4rt/src/d4rt_base.dart';
export 'package:d4rt/src/declaration_visitor.dart';
export 'package:d4rt/src/environment.dart';
export 'package:d4rt/src/exceptions.dart';
export 'package:d4rt/src/interpreter_visitor.dart';
export 'package:d4rt/src/introspection.dart';
export 'package:d4rt/src/late_variable.dart';
export 'package:d4rt/src/runtime_interfaces.dart';
export 'package:d4rt/src/runtime_types.dart';
export 'package:d4rt/src/script.dart';
export 'package:d4rt/src/security/permissions.dart';
export 'package:d4rt/src/stdlib/stdlib.dart';
export 'package:d4rt/src/utils/extensions/iterable.dart';
export 'package:d4rt/src/utils/extensions/list.dart';
export 'package:d4rt/src/utils/extensions/map.dart';
export 'package:d4rt/src/utils/extensions/visitor.dart';
export 'package:d4rt/src/utils/logger/logger.dart';
