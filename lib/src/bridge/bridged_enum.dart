import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/module_loader.dart';
import 'package:d4rt/src/native_collection_types.dart';

/// Represents an enum type defined in the host Dart environment and bridged into the interpreter.
/// It holds the definition and provides access to its values.
class BridgedEnum implements RuntimeType, Callable {
  /// The name of the enum.
  @override
  final String name;

  /// A map of the enum's value names to their corresponding BridgedEnumValue instances.
  final Map<String, BridgedEnumValue> values;

  /// Instance getter adapters (shared by all values).
  Map<String, BridgedInstanceGetterAdapter> getters = {};

  /// Instance method adapters (shared by all values).
  Map<String, BridgedMethodAdapter> methods = {};

  /// Declared native instance setters, without permitting field mutation.
  Map<String, BridgedInstanceSetterAdapter> setters = {};

  /// Static getter adapters.
  Map<String, BridgedStaticGetterAdapter> staticGetters = {};

  /// Static method adapters.
  Map<String, BridgedStaticMethodAdapter> staticMethods = {};

  /// Static setter adapters.
  Map<String, BridgedStaticSetterAdapter> staticSetters = {};

  /// Actual native factories and their compiled specialization capabilities.
  Map<String, BridgedEnumFactory> factories = const {};

  /// Native enum generic and hierarchy metadata, when supplied.
  final EnumTypeMetadata? typeMetadata;
  List<BridgedEnumValue>? _enumValues;
  Map<String, Callable>? _staticReferences;
  late final RuntimeType _bareType =
      _NativeEnumRuntimeType(this, typeMetadata?.arguments() ?? const []);

  /// Creates a definition for a bridged enum.
  BridgedEnum(this.name, this.values, {this.typeMetadata});

  @override
  int get arity =>
      factories['']
          ?.signature
          .parameters
          .where((parameter) => !parameter.isNamed && parameter.isRequired)
          .length ??
      0;
  @override
  RuntimeType get callableRuntimeType => FunctionRuntimeType.untyped();

  /// Invokes only a registered unnamed factory, never a generative constructor.
  @override
  Object? call(InterpreterVisitor visitor, List<Object?> positional,
      [Map<String, Object?> named = const {}, List<RuntimeType>? types]) {
    final factory = factories[''];
    if (factory == null) {
      throw RuntimeError('No unnamed native enum factory for $name.');
    }
    return factory.bind(this, '').call(visitor, positional, named, types);
  }

  @override
  String toString() => 'BridgedEnum($name)';

  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) {
    return instantiate(null).isSubtypeOf(other, value: value);
  }

  /// Retrieves an enum value by its name.
  BridgedEnumValue? getValue(String valueName) {
    return values[valueName];
  }

  /// Returns the list of all values for this enum.
  List<BridgedEnumValue> get enumValues =>
      _enumValues ??= List.unmodifiable(values.values);

  /// Returns the stable immutable values list with its declared enum element type.
  List<BridgedEnumValue> valuesFor(InterpreterVisitor visitor) {
    final list = enumValues;
    if (visitor.environment.getAnnotatedRuntimeType(list) == null) {
      markInterpreterOwnedCollection(list);
      visitor.environment.annotateRuntimeType(
          list,
          AppliedRuntimeType(visitor.environment.get('List') as RuntimeType,
              [instantiate(null)]));
    }
    return list;
  }

  /// Resolves native enum static members while preserving adapter failures.
  Object? getStaticMember(String member, InterpreterVisitor visitor) {
    if (member == 'values') return valuesFor(visitor);
    if (values.containsKey(member)) return values[member];
    final factory = factories[member == 'new' ? '' : member];
    if (factory != null) {
      final name = member == 'new' ? '' : member;
      return (_staticReferences ??= {})
          .putIfAbsent(name, () => factory.bind(this, name));
    }
    final getter = staticGetters[member];
    if (getter != null) return getter(visitor);
    final method = staticMethods[member];
    if (method != null) {
      return (_staticReferences ??= {}).putIfAbsent(
          member, () => BridgedEnumStaticMethodCallable(this, method, member));
    }
    throw RuntimeError('Undefined static native enum member $name.$member.');
  }

  /// Invokes only a registered native static setter.
  void setStaticMember(
      String member, Object? value, InterpreterVisitor visitor) {
    final setter = staticSetters[member];
    if (setter == null) {
      throw RuntimeError('Cannot assign native enum member $name.$member.');
    }
    setter(visitor, value);
  }

  /// Resolves a native enum type to explicit arguments or its declared bounds.
  RuntimeType instantiate(List<RuntimeType>? arguments) {
    if (arguments == null) return _bareType;
    if (typeMetadata == null) {
      if (arguments.isNotEmpty) {
        throw RuntimeError(
            'Non-generic native enum $name cannot take type arguments.');
      }
      return _bareType;
    }
    return _NativeEnumRuntimeType(this, typeMetadata!.arguments(arguments));
  }
}

/// Represents a specific value of a [BridgedEnum].
/// It holds the value's name, index, and the original native enum value.
class BridgedEnumValue implements RuntimeValue {
  /// The [BridgedEnum] definition this value belongs to.
  final BridgedEnum enumType;

  /// The name of the enum value (e.g., 'red' for Color.red).
  final String name;

  /// The index of the enum value in its definition order.
  final int index;

  /// The original native Dart enum value.
  final Object nativeValue;

  /// The native constant's actual generic arguments.
  final List<RuntimeType> typeArguments;
  late final RuntimeType _valueType = enumType.instantiate(typeArguments);

  /// Instance getter adapters (potentially specific to this value if needed in the future,
  /// but currently shared via BridgedEnum).
  final Map<String, BridgedInstanceGetterAdapter> _getters;

  /// Instance method adapters.
  final Map<String, BridgedMethodAdapter> _methods;

  BridgedEnumValue(this.enumType, this.name, this.index, this.nativeValue,
      {Map<String, BridgedInstanceGetterAdapter>? getters,
      Map<String, BridgedMethodAdapter>? methods,
      List<RuntimeType> typeArguments = const []})
      : typeArguments = List.unmodifiable(typeArguments),
        _getters = getters ?? {},
        _methods = methods ?? {};

  // Implement the required getter from RuntimeValue
  @override
  RuntimeType get valueType => _valueType;

  @override
  Object? get(String identifier, [InterpreterVisitor? visitor]) {
    final getter = _getters[identifier] ?? enumType.getters[identifier];
    if (getter != null) return getter(visitor, nativeValue);
    final method = _methods[identifier] ?? enumType.methods[identifier];
    if (method != null || identifier == 'toString') {
      return NativeFunction(
          (visitor, args, named, types) =>
              invoke(visitor, identifier, args, named),
          arity: 0,
          name: identifier);
    }
    return switch (identifier) {
      'index' => index,
      'name' => name,
      'hashCode' => nativeValue.hashCode,
      'runtimeType' => valueType,
      _ => throw RuntimeError(
          'Property "$identifier" not found on enum value ${enumType.name}.$name'),
    };
  }

  @override
  void set(String identifier, Object? value, [InterpreterVisitor? visitor]) {
    final setter = enumType.setters[identifier];
    if (setter != null && visitor != null) {
      setter(visitor, nativeValue,
          value is BridgedEnumValue ? value.nativeValue : value);
      return;
    }
    throw RuntimeError(
        'Cannot set property "$identifier" on enum value ${enumType.name}.$name');
  }

  Object? invoke(InterpreterVisitor visitor, String method, List<Object?> args,
      Map<String, Object?> namedArgs) {
    final methodAdapter = _methods[method] ?? enumType.methods[method];
    if (methodAdapter == null) {
      // Special case: if calling .toString() and there is no specific adapter,
      // return the standard representation.
      if (method == 'toString' && args.isEmpty && namedArgs.isEmpty) {
        return '${enumType.name}.$name';
      }
      throw RuntimeError(
          'Method "$method" not found on enum value ${enumType.name}.$name');
    }

    try {
      // Call the bridged method adapter
      return methodAdapter(
        visitor, // Pass the visitor
        nativeValue, // The native enum object is the target
        args, // Interpreted positional arguments
        namedArgs, // Interpreted named arguments (if supported by the adapter)
      );
    } catch (e) {
      throw RuntimeError(
          'Error executing bridged method "$method" on ${enumType.name}.$name: $e');
    }
  }

  @override
  String toString() {
    // Try to call the toString() adapter if it exists
    final toStringAdapter =
        _methods['toString'] ?? enumType.methods['toString'];
    if (toStringAdapter != null) {
      try {
        // Call without specific visitor or argument here, as it's just for representation
        return toStringAdapter(
            InterpreterVisitor(
                globalEnvironment: Environment(),
                moduleLoader: ModuleLoader(Environment(), {}, [], [])),
            nativeValue,
            [],
            {}).toString();
      } catch (_) {
        // Fallback if the adapter fails
        return '${enumType.name}.$name (native toString failed)';
      }
    }
    // Provide a default representation if no toString adapter is provided
    return '${enumType.name}.$name';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is BridgedEnumValue) {
      return nativeValue == other.nativeValue;
    }
    if (other is Enum) {
      return nativeValue == other;
    }
    return false;
  }

  @override
  int get hashCode => nativeValue.hashCode;
}

class _NativeEnumRuntimeType extends EnumTypeReference {
  _NativeEnumRuntimeType(BridgedEnum super.enumType, super.arguments);

  @override
  Object? resolveFactory(String member, InterpreterVisitor visitor) {
    final owner = baseType as BridgedEnum;
    final name = member == 'new' ? '' : member;
    final factory = owner.factories[name];
    if (factory == null) {
      throw RuntimeError(
          'Instantiated native enum types expose factories only.');
    }
    return factory.bind(owner, name, typeArguments);
  }

  @override
  String get name => typeArguments.isEmpty ? baseType.name : super.name;
  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) =>
      enumTypeArgumentSatisfies(this, other);
}
