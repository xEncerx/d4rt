import 'package:analyzer/dart/ast/ast.dart';

/// Describes an already evaluated value without invoking user formatting,
/// collection iteration, or virtual identity getters. Keep calls inside the
/// debug eligibility guard so disabled diagnostics do no preparation work.
String describeDebugValue(Object? value) {
  if (value == null) return 'null';
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return '<object #${identityHashCode(value)}>';
}

/// Reports a language-level category without querying a program's virtual
/// runtimeType getter, bridge predicates, or runtime-model properties.
String describeDebugValueType(Object? value) {
  if (value == null) return 'Null';
  if (value is bool) return 'bool';
  if (value is int) return 'int';
  if (value is double) return 'double';
  if (value is String) return 'String';
  if (value is List) return 'List';
  if (value is Map) return 'Map';
  if (value is Set) return 'Set';
  if (value is Iterable) return 'Iterable';
  if (value is Function) return 'Function';
  return 'Object';
}

/// Only for parser-owned syntax, never arbitrary interpreted/native values.
/// Syntax kind and source position are structural execution context, unlike
/// runtime-model getters or user-defined value formatting.
String describeDebugNode(AstNode? node) =>
    node == null ? 'none' : '${node.runtimeType} at offset ${node.offset}';
