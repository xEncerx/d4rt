import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/native_collection_types.dart';

/// Reified type information supplied by a native enum bridge.
///
/// [supertypeDeclarations] describes generic hierarchy edges, for example
/// `{'Readable<T>': ['Value<T>']}`. Type arguments omitted from a registration
/// are recovered once from the native constants' reified runtime types.
class EnumTypeMetadata {
  /// Generic parameter names in declaration order.
  final List<String> typeParameters;

  /// Dart type names for each parameter's bound.
  final Map<String, String> typeBounds;

  /// Direct mixin and interface type names, with generic parameter references.
  final List<String> supertypes;

  /// Transitive generic hierarchy edges keyed by declaration type.
  final Map<String, List<String>> supertypeDeclarations;

  final Environment? _environment;
  late final Map<String, _NativeEnumDeclaredType> _declarations = () {
    final declarations = <String, _NativeEnumDeclaredType>{};
    for (final entry in supertypeDeclarations.entries) {
      final type = parseEnumTypeName(entry.key);
      final base = type is AppliedRuntimeType ? type.baseType : type;
      declarations[base.name] = _NativeEnumDeclaredType(this, base.name,
          parameters: type is AppliedRuntimeType
              ? type.typeArguments.map((argument) => argument.name).toList()
              : const [],
          parentSources: entry.value);
    }
    return declarations;
  }();

  EnumTypeMetadata._resolved(EnumTypeMetadata source, this._environment)
      : typeParameters = source.typeParameters,
        typeBounds = source.typeBounds,
        supertypes = source.supertypes,
        supertypeDeclarations = source.supertypeDeclarations;

  /// Binds native declarations to their owning imported namespace.
  EnumTypeMetadata inEnvironment(Environment environment) =>
      EnumTypeMetadata._resolved(this, environment);

  /// The real declaration represented by a retained native metadata type.
  static RuntimeType nominalIdentity(RuntimeType type) {
    if (type is AppliedRuntimeType && type.typeArguments.isEmpty) {
      return nominalIdentity(type.baseType);
    }
    return type is _NativeEnumDeclaredType ? type.identity : type;
  }

  /// The hierarchy owner of a retained native declaration, when present.
  static EnumTypeMetadata? ownerOf(RuntimeType type) =>
      type is _NativeEnumDeclaredType ? type.owner : null;

  _NativeEnumDeclaredType _declaration(String name) => _declarations
      .putIfAbsent(name, () => _NativeEnumDeclaredType(this, name));

  /// Resolves a supplied type template without erasing declaration identity.
  RuntimeType resolveType(RuntimeType type) {
    if (type is NamedRuntimeType) {
      if (typeParameters.contains(type.name)) return type;
      if (isEnumCoreTypeName(type.name) &&
          !_declarations.containsKey(type.name)) {
        return type;
      }
      return _declaration(type.name);
    }
    if (type is NullableEnumArgument) {
      final resolved = resolveType(type.type);
      return identical(resolved, type.type) ? type : nullableEnumType(resolved);
    }
    if (type is AppliedRuntimeType) {
      final base = resolveType(type.baseType);
      final arguments = type.typeArguments.map(resolveType).toList();
      if (identical(base, type.baseType) &&
          List.generate(
                  arguments.length,
                  (index) =>
                      identical(arguments[index], type.typeArguments[index]))
              .every((same) => same)) {
        return type;
      }
      return AppliedRuntimeType(base, arguments);
    }
    if (type is FunctionRuntimeType) {
      return FunctionRuntimeType(
        returnType: resolveType(type.returnType),
        positionalParameterTypes:
            type.positionalParameterTypes.map(resolveType).toList(),
        requiredPositionalParameterCount: type.requiredPositionalParameterCount,
        namedParameterTypes: type.namedParameterTypes
            .map((name, value) => MapEntry(name, resolveType(value))),
        requiredNamedParameters: type.requiredNamedParameters,
        typeParameterCount: type.typeParameterCount,
        isUntyped: type.isUntyped,
      );
    }
    return type;
  }

  /// Parses only retained nominal metadata, never inferred expression types.
  RuntimeType parse(String source,
          [Map<String, RuntimeType> substitutions = const {}]) =>
      resolveType(parseEnumTypeName(source, {
        for (final name in typeParameters) name: NamedRuntimeType(name),
        ...substitutions,
      }));

  final _directDeclarations = <RuntimeType, _NativeEnumDeclaredType>{};

  /// Projects retained hierarchy edges for an actual compiled declaration.
  List<RuntimeType>? directSupertypes(RuntimeType type) {
    final base = type is AppliedRuntimeType ? type.baseType : type;
    _NativeEnumDeclaredType? declaration;
    if (base is _NativeEnumDeclaredType && identical(base.owner, this)) {
      declaration = base;
    } else {
      declaration = _directDeclarations[base];
      if (declaration == null) {
        for (final candidate in _declarations.values) {
          if (enumNominalTypesEquivalent(candidate, base)) {
            declaration = candidate;
            _directDeclarations[base] = candidate;
            break;
          }
        }
      }
    }
    if (declaration == null) return null;
    return declaration
        .parents(type is AppliedRuntimeType ? type.typeArguments : const []);
  }

  /// Creates immutable native enum type metadata without executing adapters.
  EnumTypeMetadata(
      {List<String> typeParameters = const [],
      Map<String, String> typeBounds = const {},
      List<String> supertypes = const [],
      Map<String, List<String>> supertypeDeclarations = const {}})
      : _environment = null,
        typeParameters = List.unmodifiable(typeParameters),
        typeBounds = Map.unmodifiable(typeBounds),
        supertypes = List.unmodifiable(supertypes),
        supertypeDeclarations = Map.unmodifiable(supertypeDeclarations.map(
            (key, value) => MapEntry(key, List<String>.unmodifiable(value))));

  /// Resolved bound templates, shared by inference and argument validation.
  late final Map<String, RuntimeType?> resolvedBounds = Map.unmodifiable(
      {for (final entry in typeBounds.entries) entry.key: parse(entry.value)});

  /// Resolves explicit arguments, or instantiates an omitted enum type to bounds.
  List<RuntimeType> arguments([List<RuntimeType>? explicit]) {
    if (explicit == null) return _defaultArguments;
    List<RuntimeType>? normalized;
    for (var index = 0; index < explicit.length; index++) {
      final resolved = resolveType(explicit[index]);
      if (!identical(resolved, explicit[index])) {
        normalized ??= List<RuntimeType>.of(explicit);
      }
      if (normalized != null) normalized[index] = resolved;
    }
    return resolveEnumTypeArguments(
        'native enum', typeParameters, resolvedBounds, normalized ?? explicit);
  }

  late final List<RuntimeType> _defaultArguments = resolveEnumTypeArguments(
      'native enum', typeParameters, resolvedBounds, null);

  /// Reads a native constant's actual type arguments once during registration.
  List<RuntimeType> nativeArguments(Enum value) {
    if (typeParameters.isEmpty) return const [];
    final type = parseEnumTypeName(value.runtimeType.toString());
    if (type is! AppliedRuntimeType) {
      throw RuntimeError('Missing native generic enum type information.');
    }
    return arguments(type.typeArguments);
  }

  /// Resolves substituted direct supertypes; projection owns transitive traversal.
  List<RuntimeType> resolveSupertypes(List<RuntimeType> arguments) {
    final substitutions = {
      for (var index = 0; index < arguments.length; index++)
        typeParameters[index]: arguments[index],
    };
    return [for (final source in supertypes) parse(source, substitutions)];
  }
}

class _NativeEnumDeclaredType implements RuntimeType {
  final EnumTypeMetadata owner;
  @override
  final String name;
  RuntimeType? _resolvedIdentity;
  final List<String> parameters;
  final List<String> parentSources;
  _NativeEnumDeclaredType(this.owner, this.name,
      {this.parameters = const [], this.parentSources = const []});

  RuntimeType get identity {
    if (_resolvedIdentity != null) return _resolvedIdentity!;
    try {
      final resolved = owner._environment?.get(name);
      if (resolved is RuntimeType &&
          resolved is! InterpretedClass &&
          resolved is! InterpretedEnum) {
        return _resolvedIdentity = resolved;
      }
    } on RuntimeError {
      // A later native declaration may not yet be materialized during assembly.
    }
    return this;
  }

  late final List<RuntimeType> _parents = [
    for (final parent in parentSources)
      owner.parse(parent, {
        for (final name in parameters) name: TypeParameter(name),
      }),
  ];

  List<RuntimeType> parents(List<RuntimeType> arguments) {
    final names = parameters;
    if (names.isEmpty) return _parents;
    final resolved = arguments.isEmpty
        ? List<RuntimeType>.filled(
            names.length, const NamedRuntimeType('dynamic'))
        : arguments;
    if (resolved.length != names.length) {
      throw RuntimeError('Wrong retained native type arity for $name.');
    }
    return [
      for (final parent in _parents)
        substituteEnumType(parent, names, resolved),
    ];
  }

  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) =>
      enumTypeArgumentSatisfies(this, other);
}

/// Parses a Dart nominal type name, retaining nested generic arguments.
///
/// Used only while native bridge metadata is materialized, not during member
/// reads. [substitutions] replaces generic parameters along hierarchy edges.
RuntimeType parseEnumTypeName(String source,
    [Map<String, RuntimeType> substitutions = const {}]) {
  source = source.trim();
  if (source.endsWith('?')) {
    return nullableEnumType(parseEnumTypeName(
        source.substring(0, source.length - 1), substitutions));
  }
  final substitution = substitutions[source];
  if (substitution != null) return substitution;
  final start = source.indexOf('<');
  if (start < 0) return NamedRuntimeType(source);
  final end = source.lastIndexOf('>');
  if (end < start) {
    throw ArgumentError.value(source, 'source', 'Invalid type name');
  }
  final arguments = <RuntimeType>[];
  var depth = 0;
  var argumentStart = start + 1;
  for (var i = start + 1; i < end; i++) {
    if (source[i] == '<') {
      depth++;
    } else if (source[i] == '>') {
      depth--;
    } else if (source[i] == ',' && depth == 0) {
      arguments.add(
          parseEnumTypeName(source.substring(argumentStart, i), substitutions));
      argumentStart = i + 1;
    }
  }
  arguments.add(
      parseEnumTypeName(source.substring(argumentStart, end), substitutions));
  return AppliedRuntimeType(
      NamedRuntimeType(source.substring(0, start)), arguments);
}

/// A nullable generic argument retained by enum instantiations and interfaces.
class NullableEnumArgument implements RuntimeType {
  /// The corresponding non-nullable type.
  final RuntimeType type;

  /// Creates a nullable argument without altering unrelated top-level casts.
  const NullableEnumArgument(this.type);
  @override
  String get name => '${type.name}?';
  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) =>
      isEnumCoreType(other, 'dynamic') ||
      (other is NullableEnumArgument &&
          enumTypeArgumentSatisfies(type, other.type));
}

/// Applies Dart nullability without nesting nullable or top-type arguments.
RuntimeType nullableEnumType(RuntimeType type) {
  if (type is NullableEnumArgument ||
      type.name == 'dynamic' ||
      type.name == 'Null') {
    return type;
  }
  if (type.name == 'Never') return const NamedRuntimeType('Null');
  return NullableEnumArgument(type);
}

/// Instantiates dependent and recursive enum bounds in declaration order.
List<RuntimeType> instantiateEnumTypeBounds(
    List<String> parameters, Map<String, RuntimeType?> bounds,
    {Map<String, RuntimeType> inferred = const {}}) {
  final resolved = <String, RuntimeType>{...inferred};
  final active = <String>{};
  late RuntimeType Function(String) resolve;
  RuntimeType substitute(RuntimeType type) {
    if (parameters.contains(type.name)) return resolve(type.name);
    if (type is NullableEnumArgument) {
      return nullableEnumType(substitute(type.type));
    }
    if (type is AppliedRuntimeType) {
      return AppliedRuntimeType(
          type.baseType, type.typeArguments.map(substitute).toList());
    }
    return type;
  }

  resolve = (parameter) {
    if (resolved.containsKey(parameter)) return resolved[parameter]!;
    if (!active.add(parameter)) return const NamedRuntimeType('dynamic');
    final bound =
        substitute(bounds[parameter] ?? const NamedRuntimeType('dynamic'));
    active.remove(parameter);
    return resolved[parameter] = bound;
  };
  return ownEnumTypeArguments(
      [for (final parameter in parameters) resolve(parameter)]);
}

/// Checks covariant enum arguments, including nullable and core F-bounds.
///
/// [forBound] permits Dart's dynamic wildcard in bound checks, including
/// super-bounded instantiate-to-bounds types, without weakening runtime `is`.
bool enumTypeArgumentSatisfies(RuntimeType actual, RuntimeType expected,
    {bool forBound = false}) {
  if (expected is NativeCollectionType) {
    expected =
        expected.nullable ? nullableEnumType(expected.base) : expected.base;
  }
  if (forBound && isEnumCoreType(actual, 'dynamic')) return true;
  if (actual is TypeParameter && actual.bound != null) {
    return enumTypeArgumentSatisfies(actual.bound!, expected,
        forBound: forBound);
  }
  if (isEnumCoreType(actual, 'Never') || isEnumCoreType(expected, 'dynamic')) {
    return true;
  }
  if (actual is NativeCollectionType) {
    if (!actual.nullable) {
      return enumTypeArgumentSatisfies(actual.base, expected,
          forBound: forBound);
    }
    return expected is NullableEnumArgument &&
        enumTypeArgumentSatisfies(actual.base, expected.type,
            forBound: forBound);
  }
  if (expected is NullableEnumArgument) {
    if (isEnumCoreType(expected.type, 'Object')) return true;
    return isEnumCoreType(actual, 'Null') ||
        enumTypeArgumentSatisfies(
            actual is NullableEnumArgument ? actual.type : actual,
            expected.type,
            forBound: forBound);
  }
  if (isEnumCoreType(actual, 'Null')) return isEnumCoreType(expected, 'Null');
  if (actual is NullableEnumArgument || isEnumCoreType(actual, 'dynamic')) {
    return false;
  }
  if (isEnumCoreType(expected, 'Object')) {
    return !isEnumCoreType(actual, 'void');
  }
  if (actual is FunctionRuntimeType && expected is FunctionRuntimeType) {
    return _enumFunctionSatisfies(actual, expected, forBound: forBound);
  }
  if (actual is FunctionRuntimeType && isEnumCoreType(expected, 'Function')) {
    return true;
  }
  final projected = projectEnumType(actual, expected);
  if (projected == null) return false;
  if (expected is! AppliedRuntimeType) return true;
  if (projected is! AppliedRuntimeType) {
    return expected.typeArguments
        .every((argument) => isEnumCoreType(argument, 'dynamic'));
  }
  if (projected.typeArguments.length != expected.typeArguments.length) {
    return false;
  }
  for (var index = 0; index < expected.typeArguments.length; index++) {
    if (!enumTypeArgumentSatisfies(
        projected.typeArguments[index], expected.typeArguments[index],
        forBound: forBound)) {
      return false;
    }
  }
  return true;
}

bool _enumFunctionSatisfies(
    FunctionRuntimeType actual, FunctionRuntimeType expected,
    {required bool forBound}) {
  if (expected.isUntyped || actual.isUntyped) return true;
  if (actual.typeParameterCount != expected.typeParameterCount ||
      actual.requiredPositionalParameterCount >
          expected.requiredPositionalParameterCount ||
      actual.positionalParameterTypes.length <
          expected.positionalParameterTypes.length ||
      !expected.requiredNamedParameters
          .containsAll(actual.requiredNamedParameters) ||
      !actual.namedParameterTypes.keys
          .toSet()
          .containsAll(expected.namedParameterTypes.keys)) {
    return false;
  }
  if (!isEnumCoreType(expected.returnType, 'void') &&
      !isEnumCoreType(actual.returnType, 'dynamic') &&
      !enumTypeArgumentSatisfies(actual.returnType, expected.returnType,
          forBound: forBound)) {
    return false;
  }
  bool parameterSatisfies(RuntimeType actual, RuntimeType expected) =>
      isEnumCoreType(actual, 'dynamic') ||
      enumTypeArgumentSatisfies(expected, actual, forBound: forBound);
  for (var index = 0;
      index < expected.positionalParameterTypes.length;
      index++) {
    if (!parameterSatisfies(actual.positionalParameterTypes[index],
        expected.positionalParameterTypes[index])) {
      return false;
    }
  }
  for (final entry in expected.namedParameterTypes.entries) {
    if (!parameterSatisfies(
        actual.namedParameterTypes[entry.key]!, entry.value)) {
      return false;
    }
  }
  return true;
}

/// Compares nominal enum type expressions without erasing nested arguments.
bool enumTypesEquivalent(RuntimeType first, RuntimeType second) {
  if (identical(first, second)) return true;
  if (first is NullableEnumArgument && second is NullableEnumArgument) {
    return enumTypesEquivalent(first.type, second.type);
  }
  if (first is AppliedRuntimeType && second is AppliedRuntimeType) {
    if (!enumTypesEquivalent(first.baseType, second.baseType) ||
        first.typeArguments.length != second.typeArguments.length) {
      return false;
    }
    for (var index = 0; index < first.typeArguments.length; index++) {
      if (!enumTypesEquivalent(
          first.typeArguments[index], second.typeArguments[index])) {
        return false;
      }
    }
    return true;
  }
  if (first is FunctionRuntimeType && second is FunctionRuntimeType) {
    if (first.isUntyped != second.isUntyped ||
        first.typeParameterCount != second.typeParameterCount ||
        first.requiredPositionalParameterCount !=
            second.requiredPositionalParameterCount ||
        first.positionalParameterTypes.length !=
            second.positionalParameterTypes.length ||
        first.namedParameterTypes.length != second.namedParameterTypes.length ||
        first.requiredNamedParameters.length !=
            second.requiredNamedParameters.length ||
        !first.requiredNamedParameters
            .containsAll(second.requiredNamedParameters) ||
        !enumTypesEquivalent(first.returnType, second.returnType)) {
      return false;
    }
    for (var index = 0;
        index < first.positionalParameterTypes.length;
        index++) {
      if (!enumTypesEquivalent(first.positionalParameterTypes[index],
          second.positionalParameterTypes[index])) {
        return false;
      }
    }
    for (final entry in first.namedParameterTypes.entries) {
      final other = second.namedParameterTypes[entry.key];
      if (other == null || !enumTypesEquivalent(entry.value, other)) {
        return false;
      }
    }
    return true;
  }
  return enumNominalTypesEquivalent(first, second);
}

/// Hashes a type expression using the same nominal identity as equality.
int enumTypesHash(RuntimeType type) {
  if (type is NullableEnumArgument) {
    return Object.hash('nullable', enumTypesHash(type.type));
  }
  if (type is AppliedRuntimeType) {
    return type.typeArguments.isEmpty
        ? enumTypesHash(type.baseType)
        : Object.hash(enumTypesHash(type.baseType),
            Object.hashAll(type.typeArguments.map(enumTypesHash)));
  }
  if (type is FunctionRuntimeType) {
    return Object.hash(
        'function',
        type.isUntyped,
        type.typeParameterCount,
        type.requiredPositionalParameterCount,
        enumTypesHash(type.returnType),
        Object.hashAll(type.positionalParameterTypes.map(enumTypesHash)),
        Object.hashAllUnordered(type.namedParameterTypes.entries.map(
            (entry) => Object.hash(entry.key, enumTypesHash(entry.value)))),
        Object.hashAllUnordered(type.requiredNamedParameters));
  }
  return enumNominalTypeHash(type);
}
