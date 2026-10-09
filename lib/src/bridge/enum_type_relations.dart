import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/type_annotation_utils.dart';

const _coreTypes = <String, Type>{
  'Object': Object,
  'Enum': Enum,
  'Null': Null,
  'Type': Type,
  'bool': bool,
  'int': int,
  'double': double,
  'num': num,
  'String': String,
  'List': List,
  'Set': Set,
  'Map': Map,
  'Iterable': Iterable,
  'Iterator': Iterator,
  'Comparable': Comparable,
  'Future': Future,
  'FutureOr': FutureOr,
  'Function': Function,
};

/// Whether a descriptor identifies the actual core declaration, not a namesake.
bool isEnumCoreType(RuntimeType type, String name) {
  final identity = EnumTypeMetadata.nominalIdentity(type);
  if (identity is BridgedClass) return identity.nativeType == _coreTypes[name];
  return identity is NamedRuntimeType && identity.name == name;
}

/// Whether a metadata spelling can identify a core type without a source graph.
bool isEnumCoreTypeName(String name) =>
    _coreTypes.containsKey(name) ||
    const ['dynamic', 'void', 'Never', 'Record'].contains(name);

/// Compares real nominal declaration identity, retaining native library identity.
bool enumNominalTypesEquivalent(RuntimeType first, RuntimeType second) {
  first = EnumTypeMetadata.nominalIdentity(first);
  second = EnumTypeMetadata.nominalIdentity(second);
  if (identical(first, second)) return true;
  if (first is BridgedClass && second is BridgedClass) {
    return first.nativeType == second.nativeType;
  }
  if (first is BridgedEnum &&
      second is BridgedEnum &&
      first.values.isNotEmpty &&
      second.values.isNotEmpty) {
    return identical(first.enumValues.first.nativeValue,
        second.enumValues.first.nativeValue);
  }
  if (first is NamedRuntimeType && isEnumCoreTypeName(first.name)) {
    return isEnumCoreType(second, first.name);
  }
  if (second is NamedRuntimeType && isEnumCoreTypeName(second.name)) {
    return isEnumCoreType(first, second.name);
  }
  return false;
}

/// Hashes the declaration identity used by [enumNominalTypesEquivalent].
int enumNominalTypeHash(RuntimeType type) {
  final identity = EnumTypeMetadata.nominalIdentity(type);
  if (identity is BridgedClass) {
    for (final entry in _coreTypes.entries) {
      if (entry.value == identity.nativeType) return entry.key.hashCode;
    }
    return identity.nativeType.hashCode;
  }
  if (identity is NamedRuntimeType && isEnumCoreTypeName(identity.name)) {
    return identity.name.hashCode;
  }
  if (identity is BridgedEnum && identity.values.isNotEmpty) {
    return identityHashCode(identity.enumValues.first.nativeValue);
  }
  return identityHashCode(identity);
}

/// Projects an actual enum argument onto a nominal superclass or interface.
///
/// Generic arguments are substituted on each hierarchy edge. Consumers compare
/// the projected arguments, never unrelated positions in the original types.
RuntimeType? projectEnumType(RuntimeType actual, RuntimeType target,
    {EnumTypeMetadata? nativeMetadata}) {
  final targetBase = target is AppliedRuntimeType ? target.baseType : target;
  final actualBase = actual is AppliedRuntimeType ? actual.baseType : actual;
  if (enumNominalTypesEquivalent(actualBase, targetBase)) return actual;
  final metadata = nativeMetadata ??
      EnumTypeMetadata.ownerOf(targetBase) ??
      EnumTypeMetadata.ownerOf(
          actual is AppliedRuntimeType ? actual.baseType : actual);
  final seen = <Object>{};
  RuntimeType? project(RuntimeType type, [EnumTypeMetadata? context]) {
    final base = type is AppliedRuntimeType ? type.baseType : type;
    if (enumNominalTypesEquivalent(base, targetBase)) return type;
    if (!seen.add(EnumTypeMetadata.nominalIdentity(base))) return null;
    final arguments =
        type is AppliedRuntimeType ? type.typeArguments : const <RuntimeType>[];
    if (isEnumCoreType(targetBase, 'Iterable') &&
        (isEnumCoreType(base, 'List') || isEnumCoreType(base, 'Set'))) {
      return arguments.isEmpty
          ? targetBase
          : AppliedRuntimeType(targetBase, arguments);
    }
    if (isEnumCoreType(targetBase, 'num') &&
        (isEnumCoreType(base, 'int') || isEnumCoreType(base, 'double'))) {
      return targetBase;
    }
    if (isEnumCoreType(targetBase, 'Comparable')) {
      if (isEnumCoreType(base, 'String')) {
        return AppliedRuntimeType(targetBase, [base]);
      }
      if (isEnumCoreType(base, 'int') ||
          isEnumCoreType(base, 'double') ||
          isEnumCoreType(base, 'num')) {
        return AppliedRuntimeType(targetBase, [const NamedRuntimeType('num')]);
      }
    }
    if ((base is InterpretedEnum || base is BridgedEnum) &&
        isEnumCoreType(targetBase, 'Enum')) {
      return targetBase;
    }
    final retained = (EnumTypeMetadata.ownerOf(base) ?? context ?? metadata)
        ?.directSupertypes(type);
    if (retained != null) {
      for (final parent in retained) {
        final result = project(parent);
        if (result != null) return result;
      }
      return null;
    }
    if (base is InterpretedClass) {
      final scope = Environment(enclosing: base.classDefinitionEnvironment);
      for (var index = 0; index < base.typeParameterNames.length; index++) {
        final name = base.typeParameterNames[index];
        scope.define(
            name,
            index < arguments.length
                ? arguments[index]
                : base.typeParameterBounds[name] ??
                    const NamedRuntimeType('dynamic'));
      }
      for (final annotation in [
        if (base.superclassType != null) base.superclassType!,
        ...base.interfaceTypes,
        ...base.onConstraintTypes,
        ...base.mixinApplicationTypes,
      ]) {
        final result = project(resolveRuntimeTypeArgument(annotation, scope));
        if (result != null) return result;
      }
    } else if (base is InterpretedEnum) {
      final resolved =
          arguments.isEmpty ? base.validateTypeArguments(null) : arguments;
      final scope = Environment(enclosing: base.declarationEnvironment);
      base.bindTypeParameters(base, resolved, scope);
      for (final annotation in base.interfaceTypes) {
        final result = project(resolveRuntimeTypeArgument(annotation, scope));
        if (result != null) return result;
      }
      for (final mixin in base.mixinTypes) {
        final mixinBase = mixin is AppliedRuntimeType ? mixin.baseType : mixin;
        final result = project(
            substituteEnumType(mixin, base.typeParameterNames, resolved),
            base.nativeMixinTypeMetadata[mixinBase]);
        if (result != null) return result;
      }
      if (isEnumCoreType(targetBase, 'Enum')) return targetBase;
    } else if (base is BridgedEnum) {
      if (isEnumCoreType(targetBase, 'Enum')) return targetBase;
      for (final parent in base.typeMetadata?.resolveSupertypes(arguments) ??
          const <RuntimeType>[]) {
        final result = project(parent);
        if (result != null) return result;
      }
    } else if (base is BridgedClass && context != null) {
      for (final parent in context.resolveSupertypes(arguments)) {
        final result = project(parent);
        if (result != null) return result;
      }
    }
    return null;
  }

  return project(actual);
}
