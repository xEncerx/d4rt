import 'dart:collection';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/native_collection_types.dart';

/// Distinguishes omitted native callback arguments from explicitly supplied null.
const Object enumCallbackArgumentAbsent = _AbsentEnumCallbackArgument();

class _AbsentEnumCallbackArgument {
  const _AbsentEnumCallbackArgument();
}

/// Owns an immutable enum type vector once at an external binding boundary.
///
/// Already owned vectors are reused by specialized references and adapters.
List<RuntimeType> ownEnumTypeArguments(List<RuntimeType> arguments) =>
    arguments.isEmpty
        ? const []
        : arguments is _OwnedEnumTypeArguments
            ? arguments
            : _OwnedEnumTypeArguments(arguments);

class _OwnedEnumTypeArguments extends ListBase<RuntimeType> {
  final List<RuntimeType> _values;
  _OwnedEnumTypeArguments(List<RuntimeType> values)
      : _values = List<RuntimeType>.unmodifiable(values);
  @override
  int get length => _values.length;
  @override
  set length(int value) =>
      throw UnsupportedError('Immutable enum type arguments.');
  @override
  RuntimeType operator [](int index) => _values[index];
  @override
  void operator []=(int index, RuntimeType value) =>
      throw UnsupportedError('Immutable enum type arguments.');
}

/// A normalized enum constructor formal, retaining its type template.
class EnumFormalParameter {
  /// The source parameter name.
  final String name;

  /// The declared type, before owner type-parameter substitution.
  final RuntimeType type;

  /// Whether the argument is passed by name.
  final bool isNamed;

  /// Whether an argument must be supplied.
  final bool isRequired;

  /// Creates a formal without evaluating its default expression.
  const EnumFormalParameter(this.name, this.type,
      {this.isNamed = false, this.isRequired = true});
}

/// Shared argument inference and shape checking for enum constructors.
class EnumSignature {
  /// Formals in source order.
  final List<EnumFormalParameter> parameters;

  /// Creates an immutable signature from already resolved type templates.
  EnumSignature(List<EnumFormalParameter> parameters)
      : parameters = List.unmodifiable(parameters);

  /// Exposes the specialized callback shape with its actual enum return type.
  FunctionRuntimeType functionType(RuntimeType returnType) =>
      FunctionRuntimeType(
          returnType: returnType,
          positionalParameterTypes: [
            for (final parameter in parameters)
              if (!parameter.isNamed) parameter.type,
          ],
          requiredPositionalParameterCount: parameters
              .where((parameter) => !parameter.isNamed && parameter.isRequired)
              .length,
          namedParameterTypes: {
            for (final parameter in parameters)
              if (parameter.isNamed) parameter.name: parameter.type,
          },
          requiredNamedParameters: {
            for (final parameter in parameters)
              if (parameter.isNamed && parameter.isRequired) parameter.name,
          });

  /// Normalizes retained native templates against one owning type namespace.
  EnumSignature resolveTypes(EnumTypeMetadata metadata) => EnumSignature([
        for (final parameter in parameters)
          EnumFormalParameter(
              parameter.name, metadata.resolveType(parameter.type),
              isNamed: parameter.isNamed, isRequired: parameter.isRequired),
      ]);

  /// Resolves formal templates once when a factory reference is specialized.
  EnumSignature specialize(List<String> names, List<RuntimeType> arguments) {
    if (names.isEmpty || parameters.isEmpty) return this;
    return EnumSignature([
      for (final parameter in parameters)
        EnumFormalParameter(parameter.name,
            substituteEnumType(parameter.type, names, arguments),
            isNamed: parameter.isNamed, isRequired: parameter.isRequired)
    ]);
  }

  /// Checks positional arity and named arguments before entering a factory.
  void validateArguments(List<Object?> positional, Map<String, Object?> named) {
    var total = 0;
    var required = 0;
    for (final parameter in parameters) {
      if (!parameter.isNamed) {
        total++;
        if (parameter.isRequired) required++;
      } else if (parameter.isRequired && !named.containsKey(parameter.name)) {
        throw RuntimeError('Missing enum argument ${parameter.name}.');
      }
    }
    if (positional.length < required || positional.length > total) {
      throw RuntimeError('Wrong enum positional argument count.');
    }
    for (final name in named.keys) {
      if (!parameters.any((p) => p.isNamed && p.name == name)) {
        throw RuntimeError('Unknown enum named argument $name.');
      }
    }
  }

  /// Checks supplied types without inspecting native collection contents.
  void validateTypes(
      Environment environment,
      List<String> names,
      List<RuntimeType> arguments,
      List<Object?> positional,
      Map<String, Object?> named) {
    var position = 0;
    for (final parameter in parameters) {
      final supplied = parameter.isNamed
          ? named.containsKey(parameter.name)
          : position < positional.length;
      final value = parameter.isNamed
          ? named[parameter.name]
          : supplied
              ? positional[position++]
              : null;
      if (!supplied) continue;
      _validateType(environment, parameter,
          substituteEnumType(parameter.type, names, arguments), value);
    }
  }

  /// Checks evaluated defaults in their existing invocation bindings.
  void validateBoundValues(
      Environment scope, List<String> names, List<RuntimeType> arguments) {
    for (final parameter in parameters) {
      _validateType(
          scope,
          parameter,
          substituteEnumType(parameter.type, names, arguments),
          scope.get(parameter.name));
    }
  }

  void _validateType(Environment environment, EnumFormalParameter parameter,
      RuntimeType expected, Object? value) {
    if (expected is FunctionRuntimeType && value is Function) return;
    final actual = environment.getRuntimeType(value);
    if (actual == null || !enumTypeArgumentSatisfies(actual, expected)) {
      throw RuntimeError('Invalid enum factory argument ${parameter.name}: '
          'expected ${expected.name}, got ${actual?.name}.');
    }
  }

  /// Infers owner arguments from supplied values, not omitted defaults.
  List<RuntimeType> infer(
      Environment environment,
      List<String> names,
      Map<String, RuntimeType?> bounds,
      List<Object?> positional,
      Map<String, Object?> named) {
    if (names.isEmpty) return const [];
    final lower = <String, RuntimeType>{};
    final upper = <String, RuntimeType>{};
    var position = 0;
    for (final parameter in parameters) {
      final supplied = parameter.isNamed
          ? named.containsKey(parameter.name)
          : position < positional.length;
      final actual = parameter.isNamed
          ? named[parameter.name]
          : supplied
              ? positional[position++]
              : null;
      if (supplied) {
        _infer(parameter.type, environment.getRuntimeType(actual), names, lower,
            upper);
      }
    }
    final inferred = <String, RuntimeType>{};
    for (final name in names) {
      final minimum = lower[name];
      final maximum = upper[name];
      if (minimum != null &&
          maximum != null &&
          !enumTypeArgumentSatisfies(minimum, maximum)) {
        throw RuntimeError(
            'Inconsistent enum inference constraints for $name.');
      }
      final argument = minimum ?? maximum;
      if (argument != null) inferred[name] = argument;
    }
    return instantiateEnumTypeBounds(names, bounds, inferred: inferred);
  }

  void _infer(RuntimeType formal, RuntimeType? actual, List<String> names,
      Map<String, RuntimeType> lower, Map<String, RuntimeType> upper,
      {bool covariant = true}) {
    if (actual == null || isEnumCoreType(actual, 'dynamic')) {
      if (_containsOwner(formal, names)) {
        throw RuntimeError('Enum owner inference requires a declared type; '
            'supply explicit owner type arguments.');
      }
      return;
    }
    if (actual is NativeCollectionType) {
      actual =
          actual.nullable ? NullableEnumArgument(actual.base) : actual.base;
    }
    if (formal is NullableEnumArgument) {
      if (isEnumCoreType(actual, 'Null')) return;
      return _infer(
          formal.type,
          actual is NullableEnumArgument ? actual.type : actual,
          names,
          lower,
          upper,
          covariant: covariant);
    }
    if (names.contains(formal.name)) {
      final constraints = covariant ? lower : upper;
      final previous = constraints[formal.name];
      constraints[formal.name] = previous == null
          ? actual
          : covariant
              ? _join(previous, actual)
              : _meet(previous, actual);
    } else if (formal is AppliedRuntimeType) {
      final projected = projectEnumType(actual, formal);
      if (projected is! AppliedRuntimeType ||
          formal.typeArguments.length != projected.typeArguments.length) {
        return;
      }
      for (var index = 0; index < formal.typeArguments.length; index++) {
        _infer(formal.typeArguments[index], projected.typeArguments[index],
            names, lower, upper,
            covariant: covariant);
      }
    } else if (formal is FunctionRuntimeType &&
        actual is FunctionRuntimeType &&
        actual.isUntyped &&
        _containsOwner(formal, names)) {
      throw RuntimeError(
          'Enum callback inference requires a declared signature; '
          'supply explicit owner type arguments.');
    } else if (formal is FunctionRuntimeType &&
        actual is FunctionRuntimeType &&
        !actual.isUntyped) {
      _infer(formal.returnType, actual.returnType, names, lower, upper,
          covariant: covariant);
      for (var index = 0;
          index < formal.positionalParameterTypes.length &&
              index < actual.positionalParameterTypes.length;
          index++) {
        _infer(formal.positionalParameterTypes[index],
            actual.positionalParameterTypes[index], names, lower, upper,
            covariant: !covariant);
      }
      for (final entry in formal.namedParameterTypes.entries) {
        _infer(entry.value, actual.namedParameterTypes[entry.key], names, lower,
            upper,
            covariant: !covariant);
      }
    }
  }

  bool _containsOwner(RuntimeType type, List<String> names) {
    if (names.contains(type.name)) return true;
    if (type is NullableEnumArgument) return _containsOwner(type.type, names);
    if (type is AppliedRuntimeType) {
      return type.typeArguments
          .any((argument) => _containsOwner(argument, names));
    }
    if (type is FunctionRuntimeType) {
      return _containsOwner(type.returnType, names) ||
          type.positionalParameterTypes
              .any((type) => _containsOwner(type, names)) ||
          type.namedParameterTypes.values
              .any((type) => _containsOwner(type, names));
    }
    return false;
  }

  RuntimeType _meet(RuntimeType previous, RuntimeType actual) {
    if (enumTypeArgumentSatisfies(actual, previous)) return actual;
    if (enumTypeArgumentSatisfies(previous, actual)) return previous;
    return const NamedRuntimeType('Never');
  }

  RuntimeType _join(RuntimeType previous, RuntimeType actual) {
    if (enumTypeArgumentSatisfies(actual, previous)) return previous;
    if (enumTypeArgumentSatisfies(previous, actual)) return actual;
    if (actual.name == 'Null') return NullableEnumArgument(previous);
    if (previous.name == 'Null') return NullableEnumArgument(actual);
    if (const ['int', 'double', 'num'].contains(actual.name) &&
        const ['int', 'double', 'num'].contains(previous.name)) {
      return const NamedRuntimeType('num');
    }
    if (isEnumCoreType(actual, actual.name) &&
        isEnumCoreType(previous, previous.name)) {
      return const NamedRuntimeType('Object');
    }
    throw RuntimeError('Ambiguous enum owner inference; '
        'supply explicit owner type arguments.');
  }
}

/// Substitutes an enum's ordered type vector into a resolved template.
RuntimeType substituteEnumType(
    RuntimeType type, List<String> names, List<RuntimeType> arguments) {
  if (names.isEmpty) return type;
  final index = names.indexOf(type.name);
  if (index >= 0) return arguments[index];
  if (type is TypeParameter) {
    final index = names.indexOf(type.name);
    if (index >= 0) return arguments[index];
  }
  if (type is NullableEnumArgument) {
    return nullableEnumType(substituteEnumType(type.type, names, arguments));
  }
  if (type is AppliedRuntimeType) {
    return AppliedRuntimeType(type.baseType, [
      for (final argument in type.typeArguments)
        substituteEnumType(argument, names, arguments)
    ]);
  }
  if (type is FunctionRuntimeType) {
    return FunctionRuntimeType(
      returnType: substituteEnumType(type.returnType, names, arguments),
      positionalParameterTypes: [
        for (final parameter in type.positionalParameterTypes)
          substituteEnumType(parameter, names, arguments),
      ],
      requiredPositionalParameterCount: type.requiredPositionalParameterCount,
      namedParameterTypes: {
        for (final entry in type.namedParameterTypes.entries)
          entry.key: substituteEnumType(entry.value, names, arguments),
      },
      requiredNamedParameters: type.requiredNamedParameters,
      typeParameterCount: type.typeParameterCount,
      isUntyped: type.isUntyped,
    );
  }
  return type;
}

/// Checks explicit owner arguments, or supplies instantiate-to-bounds arguments.
List<RuntimeType> resolveEnumTypeArguments(String owner, List<String> names,
    Map<String, RuntimeType?> bounds, List<RuntimeType>? explicit) {
  if (explicit == null) return instantiateEnumTypeBounds(names, bounds);
  if (explicit.length != names.length) {
    throw RuntimeError('Wrong type argument count for enum $owner.');
  }
  for (var i = 0; i < names.length; i++) {
    final bound = bounds[names[i]];
    if (bound != null &&
        !enumTypeArgumentSatisfies(
            explicit[i], substituteEnumType(bound, names, explicit),
            forBound: true)) {
      throw RuntimeError(
          'Type ${explicit[i].name} violates enum bound ${bound.name}.');
    }
  }
  return ownEnumTypeArguments(explicit);
}
