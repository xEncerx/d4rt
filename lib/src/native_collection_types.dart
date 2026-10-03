import 'dart:collection';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/type_annotation_utils.dart';

// Shared provenance for literals and collections created by interpreted
// transformations. Native host collections are never tagged by type inference.
final _interpreterOwnedCollections =
    Expando<bool>('d4rt.interpretedCollection');

/// Records interpreter ownership without accessing collection contents.
void markInterpreterOwnedCollection(Object value) {
  _interpreterOwnedCollections[value] = true;
}

/// Identifies interpreter-owned collections and their lazy iterable derivatives.
bool isInterpreterOwnedCollection(Object value) =>
    (value is Iterable || value is Map) &&
    _interpreterOwnedCollections[value] == true;

/// Preserves provenance through collection operations without copying or iterating.
///
/// A callback-produced result is interpreter-owned even when its input is native.
/// Type-preserving operations retain known declarations; transformations do not
/// pretend that an erased callback return acquired a reified native generic type.
T retainCollectionResult<T extends Object>(
    T result, Object source, Environment environment,
    {bool interpretedCallback = false, bool preservesType = true}) {
  if (!interpretedCallback && !isInterpreterOwnedCollection(source)) {
    return result;
  }
  markInterpreterOwnedCollection(result);
  if (preservesType && !interpretedCallback) {
    final annotation = environment.getAnnotatedRuntimeType(source);
    if (annotation is AppliedRuntimeType) {
      final family = result is List
          ? 'List'
          : result is Set
              ? 'Set'
              : result is Map
                  ? 'Map'
                  : 'Iterable';
      environment.annotateRuntimeType(
          result,
          AppliedRuntimeType(environment.get(family) as RuntimeType,
              annotation.typeArguments));
    }
  }
  return result;
}

/// Retains collection provenance at native member invocation, regardless of which
/// concrete collection bridge owns the adapter.
///
/// Only interpreted transformations establish new ownership. Other operations
/// propagate existing ownership; host inputs keep authoritative native checks.
Object? retainCollectionOperationResult(
    Object? result, Object source, String operation, Environment environment,
    [List<Object?> arguments = const []]) {
  if (result == null ||
      (source is! Iterable && source is! Map) ||
      (result is! Iterable && result is! Map)) {
    return result;
  }
  switch (operation) {
    case 'map':
    case 'expand':
      return retainCollectionResult(result, source, environment,
          interpretedCallback:
              arguments.isNotEmpty && arguments.first is Callable,
          preservesType: false);
    case 'where':
    case 'take':
    case 'skip':
    case 'takeWhile':
    case 'skipWhile':
    case 'sublist':
    case 'getRange':
    case 'toList':
    case 'toSet':
    case 'reversed':
    case 'difference':
    case 'intersection':
      return retainCollectionResult(result, source, environment);
    case 'asMap':
    case 'cast':
    case 'whereType':
    case 'followedBy':
    case 'union':
    case 'keys':
    case 'values':
    case 'entries':
      return retainCollectionResult(result, source, environment,
          preservesType: false);
    default:
      return result;
  }
}

/// Retains nullability for collection arguments without changing general types.
final class NativeCollectionType implements RuntimeType {
  /// Wraps a declared argument whose nullability matters at a collection boundary.
  NativeCollectionType(this.base, this.nullable);
  final RuntimeType base;
  final bool nullable;
  @override
  String get name => base.name;
  String get nativeName => '$name${nullable ? '?' : ''}';
  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) =>
      nativeCollectionArgumentMatches(this, other);
}

/// Resolves collection arguments recursively, including substituted parameters.
RuntimeType resolveNativeCollectionType(TypeAnnotation node, Environment env) {
  final type = node is NamedType && node.typeArguments != null
      ? AppliedRuntimeType(
          env.get(node.name.lexeme) as RuntimeType,
          node.typeArguments!.arguments
              .map((argument) => resolveNativeCollectionType(argument, env))
              .toList())
      : resolveRuntimeTypeAnnotation(node, env);
  if (node is NamedType && node.question != null) {
    return NativeCollectionType(
        type is NativeCollectionType ? type.base : type, true);
  }
  return type;
}

/// Compares declared arguments without reading a collection's contents.
bool nativeCollectionArgumentMatches(RuntimeType actual, RuntimeType expected) {
  final actualNullable = actual is NativeCollectionType && actual.nullable;
  final expectedNullable =
      expected is NativeCollectionType && expected.nullable;
  final a = actual is NativeCollectionType ? actual.base : actual;
  final e = expected is NativeCollectionType ? expected.base : expected;
  if (e.name == 'dynamic') return true;
  if (a.name == 'Never' && !actualNullable) return true;
  if (a.name == 'Null' || (a.name == 'Never' && actualNullable)) {
    return e.name == 'Null' || expectedNullable;
  }
  if (actualNullable && !expectedNullable) return false;
  if (e.name == 'Object') return a.name != 'void';
  if (a is AppliedRuntimeType && e is AppliedRuntimeType) {
    if (a.baseType.name != e.baseType.name ||
        a.typeArguments.length != e.typeArguments.length) {
      return false;
    }
    for (var i = 0; i < a.typeArguments.length; i++) {
      if (!nativeCollectionArgumentMatches(
          a.typeArguments[i], e.typeArguments[i])) {
        return false;
      }
    }
    return true;
  }
  return a.name == e.name || a.isSubtypeOf(e);
}

/// Reifies supported core arguments, preserving erased interfaces for others.
///
/// The erased interface does not claim an arbitrary declared native Dart type.
R reifyNativeCollectionType<R>(RuntimeType type, R Function<T>() create,
    {R Function()? unreified}) {
  final name = type is NativeCollectionType ? type.nativeName : type.name;
  return switch (name) {
    'dynamic' => create<dynamic>(),
    'Object' => create<Object>(),
    'Object?' => create<Object?>(),
    'String' => create<String>(),
    'String?' => create<String?>(),
    'int' => create<int>(),
    'int?' => create<int?>(),
    'double' => create<double>(),
    'double?' => create<double?>(),
    'num' => create<num>(),
    'num?' => create<num?>(),
    'bool' => create<bool>(),
    'bool?' => create<bool?>(),
    'Null' => create<Null>(),
    'Never?' => create<Null>(),
    'Never' => create<Never>(),
    _ => unreified == null ? create<dynamic>() : unreified(),
  };
}

/// Constructs live views, retaining declared metadata separately from reification.
Object nativeCollectionView(String name, Object source, List<RuntimeType> types,
    InterpreterVisitor visitor) {
  bool compatible<T>(int index) {
    if (InterpreterVisitor.isInterpretedCollection(source)) {
      final annotation = visitor.environment.getAnnotatedRuntimeType(source);
      // An untyped callback result has no declared argument to contradict.
      // Enforce access through the lazy native cast rather than scanning it here.
      return annotation == null ||
          (annotation is AppliedRuntimeType &&
              nativeCollectionArgumentMatches(
                  annotation.typeArguments[index], types[index]));
    }
    return source is List
        ? source is List<T>
        : index == 0
            ? source is Map<T, dynamic>
            : source is Map<dynamic, T>;
  }

  Object createList<T>({bool reified = true}) {
    if ((reified || InterpreterVisitor.isInterpretedCollection(source)) &&
        !compatible<T>(0)) {
      throw RuntimeError('Incompatible source for $name<${types[0].name}>.');
    }
    return UnmodifiableListView<T>((source as List).cast<T>());
  }

  Object createMap<K, V>({bool keyReified = true, bool valueReified = true}) {
    if ((keyReified || InterpreterVisitor.isInterpretedCollection(source)) &&
        !compatible<K>(0)) {
      throw RuntimeError('Incompatible map key type.');
    }
    if ((valueReified || InterpreterVisitor.isInterpretedCollection(source)) &&
        !compatible<V>(1)) {
      throw RuntimeError('Incompatible map value type.');
    }
    final map = (source as Map).cast<K, V>();
    return name == 'MapView'
        ? MapView<K, V>(map)
        : UnmodifiableMapView<K, V>(map);
  }

  Object withKey<K>({bool reified = true}) => reifyNativeCollectionType(
      types[1], <V>() => createMap<K, V>(keyReified: reified),
      unreified: () =>
          createMap<K, dynamic>(keyReified: reified, valueReified: false));

  final view = name == 'UnmodifiableListView'
      ? reifyNativeCollectionType(types[0], <T>() => createList<T>(),
          unreified: () => createList<dynamic>(reified: false))
      : reifyNativeCollectionType(types[0], <K>() => withKey<K>(),
          unreified: () => withKey<dynamic>(reified: false));
  visitor.environment.annotateRuntimeType(
      view,
      AppliedRuntimeType(
          visitor.environment
                  .get(name == 'UnmodifiableListView' ? 'List' : 'Map')
              as RuntimeType,
          types));
  return view;
}
