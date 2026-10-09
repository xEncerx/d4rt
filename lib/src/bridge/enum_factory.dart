import 'package:d4rt/d4rt.dart';

/// One compiled native enum factory specialization and its exact owner tuple.
class BridgedEnumFactorySpecialization {
  /// The exact supported tuple, in enum parameter order.
  final List<RuntimeType> typeArguments;

  /// The native call compiled with this tuple, receiving the actual vector.
  final BridgedEnumFactoryAdapter adapter;

  /// Creates an immutable capability; types must describe compiled native types.
  BridgedEnumFactorySpecialization(
      List<RuntimeType> typeArguments, this.adapter)
      : typeArguments = ownEnumTypeArguments(typeArguments);

  bool _matches(List<RuntimeType> requested) {
    if (requested.length != typeArguments.length) return false;
    for (var i = 0; i < requested.length; i++) {
      if (!_nativeType(requested[i]) ||
          !enumTypesEquivalent(requested[i], typeArguments[i])) {
        return false;
      }
    }
    return true;
  }

  bool _nativeType(RuntimeType type) {
    if (type is InterpretedClass ||
        type is InterpretedEnum ||
        type is TypeParameter) {
      return false;
    }
    if (type is NullableEnumArgument) return _nativeType(type.type);
    if (type is AppliedRuntimeType) {
      if (!_nativeType(type.baseType)) return false;
      for (final argument in type.typeArguments) {
        if (!_nativeType(argument)) return false;
      }
    }
    return true;
  }
}

/// A native enum factory's formal signature and finite compiled capabilities.
///
/// Ordinary static methods belong in `staticMethods`, not this registration.
class BridgedEnumFactory {
  /// The normalized source signature, retaining owner parameter references.
  final EnumSignature signature;

  /// The exact supported tuples. There is no bound or dynamic fallback.
  final List<BridgedEnumFactorySpecialization> specializations;
  final EnumTypeMetadata? _resolvedMetadata;

  /// Creates a factory with a finite set of real native implementations.
  BridgedEnumFactory(
      {required EnumSignature signature,
      required List<BridgedEnumFactorySpecialization> specializations})
      : this._resolved(signature, specializations, null);

  BridgedEnumFactory._resolved(
      this.signature,
      List<BridgedEnumFactorySpecialization> specializations,
      this._resolvedMetadata)
      : specializations = List.unmodifiable(specializations) {
    if (specializations.isEmpty) {
      throw ArgumentError('Factory has no specializations.');
    }
    for (var i = 0; i < specializations.length; i++) {
      for (var j = 0; j < i; j++) {
        if (specializations[j]._matches(specializations[i].typeArguments)) {
          throw ArgumentError('Duplicate enum factory specialization.');
        }
      }
    }
  }

  /// Resolves native nominal templates once for the registered enum namespace.
  BridgedEnumFactory resolveTypes(EnumTypeMetadata? metadata) {
    if (metadata == null || identical(metadata, _resolvedMetadata)) return this;
    return BridgedEnumFactory._resolved(
      signature.resolveTypes(metadata),
      [
        for (final specialization in specializations)
          BridgedEnumFactorySpecialization(
              metadata.arguments(specialization.typeArguments),
              specialization.adapter),
      ],
      metadata,
    );
  }

  /// Validates compiled capabilities against the registered enum bounds.
  void validate(BridgedEnum owner) {
    for (final specialization in specializations) {
      if (owner.typeMetadata != null) {
        owner.typeMetadata!.arguments(specialization.typeArguments);
      } else {
        resolveEnumTypeArguments(
            owner.name, const [], const {}, specialization.typeArguments);
      }
    }
  }

  BridgedEnumFactoryAdapter _select(
      BridgedEnum owner, String name, List<RuntimeType> arguments) {
    for (final specialization in specializations) {
      if (specialization._matches(arguments)) return specialization.adapter;
    }
    throw RuntimeError('Unsupported native enum factory ${owner.name}.$name'
        '<${arguments.map((type) => type.name).join(', ')}>: '
        'register or generate this exact compiled specialization.');
  }

  /// Creates a tear-off, selecting an explicit specialization only once.
  EnumFactoryCallable bind(BridgedEnum owner, String name,
      [List<RuntimeType>? types]) {
    final resolvedFactory = resolveTypes(owner.typeMetadata);
    if (!identical(resolvedFactory, this)) {
      return resolvedFactory.bind(owner, name, types);
    }
    if (types == null) {
      return _NativeEnumFactoryCallable(owner, name, this, null, null);
    }
    final resolved = owner.typeMetadata?.arguments(types) ??
        resolveEnumTypeArguments(owner.name, const [], const {}, types);
    return _NativeEnumFactoryCallable(
        owner, name, this, resolved, _select(owner, name, resolved));
  }
}

class _NativeEnumFactoryCallable extends EnumFactoryCallable {
  final BridgedEnum owner;
  final String name;
  final BridgedEnumFactory factory;
  final List<RuntimeType>? boundTypes;
  final BridgedEnumFactoryAdapter? boundAdapter;
  final EnumSignature signature;
  _NativeEnumFactoryCallable(
      this.owner, this.name, this.factory, this.boundTypes, this.boundAdapter)
      : signature = boundTypes == null
            ? factory.signature
            : factory.signature.specialize(
                owner.typeMetadata?.typeParameters ?? const [], boundTypes);
  @override
  RuntimeType get enumOwner => owner;
  @override
  bool get isBound => boundTypes != null;
  @override
  EnumFactoryCallable bindTypeArguments(List<RuntimeType> arguments) {
    if (isBound) throw RuntimeError('Enum factory is already specialized.');
    return factory.bind(owner, name, arguments);
  }

  @override
  int get arity => signature.parameters
      .where((parameter) => !parameter.isNamed && parameter.isRequired)
      .length;
  late final RuntimeType _runtimeType = boundTypes == null
      ? FunctionRuntimeType.untyped()
      : signature.functionType(owner.instantiate(boundTypes));
  @override
  RuntimeType get callableRuntimeType => _runtimeType;
  @override
  Object? call(InterpreterVisitor visitor, List<Object?> positional,
      [Map<String, Object?> named = const {}, List<RuntimeType>? types]) {
    visitor.checkDeadline();
    signature.validateArguments(positional, named);
    if (boundTypes != null && types != null && types.isNotEmpty) {
      throw RuntimeError(
          'Bound enum factory cannot take method type arguments.');
    }
    final metadata = owner.typeMetadata;
    final arguments = boundTypes ??
        (metadata == null
            ? resolveEnumTypeArguments(owner.name, const [], const {}, types)
            : metadata.arguments(types ??
                factory.signature.infer(
                    visitor.environment,
                    metadata.typeParameters,
                    metadata.resolvedBounds,
                    positional,
                    named)));
    final adapter = boundAdapter ?? factory._select(owner, name, arguments);
    signature.validateTypes(
        visitor.environment,
        isBound ? const [] : metadata?.typeParameters ?? const [],
        arguments,
        positional,
        named);
    final Object? result;
    try {
      result = adapter(visitor, positional, named, arguments);
    } finally {
      visitor.checkDeadline();
    }
    final value = result is BridgedEnumValue
        ? result
        : result is Enum
            ? owner.values[result.name]
            : null;
    if (value == null ||
        !identical(value.enumType, owner) ||
        !identical(owner.values[value.name], value) ||
        (result is Enum && !identical(result, value.nativeValue)) ||
        !_resultMatches(value.typeArguments, arguments)) {
      throw RuntimeError('Native enum factory ${owner.name}.$name must return '
          'an existing constant of its enum type.');
    }
    return result;
  }

  bool _resultMatches(List<RuntimeType> actual, List<RuntimeType> expected) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (!enumTypeArgumentSatisfies(actual[i], expected[i])) return false;
    }
    return true;
  }
}
