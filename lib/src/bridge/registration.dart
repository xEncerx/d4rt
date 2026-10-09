import 'package:d4rt/d4rt.dart';

// The idea is that these functions will encapsulate the native call
// and type conversion.

/// Calls a native constructor.
typedef BridgedConstructorCallable = Object? Function(
    InterpreterVisitor
        visitor, // For potential evaluation of args or access env
    List<Object?> positionalArgs, // Interpretted arguments
    Map<String, Object?> namedArgs // Interpretted arguments
    );

/// Calls a native method/getter/setter.
typedef BridgedMethodCallable = Object? Function(
    InterpreterVisitor visitor,
    Object
        target, // The native target object (for instance methods/getters/setters)
    List<Object?> positionalArgs,
    Map<String, Object?> namedArgs);

typedef BridgedMethodAdapter = Object? Function(
    InterpreterVisitor visitor, // The current visitor
    Object target, // The native target object to call the method on
    List<Object?> positionalArguments, // Interpretted arguments
    Map<String, Object?> namedArguments // Interpretted arguments
    );

/// Adapter for bridged static methods.
/// Takes interpreter context, positional args, named args.
/// Returns the result of the native static method call.
typedef BridgedStaticMethodAdapter = Object? Function(
    InterpreterVisitor visitor,
    List<Object?> positionalArguments,
    Map<String, Object?> namedArguments);

/// Calls a compiled native enum factory with the resolved owner type vector.
/// General constructor, static-method and instance-method adapters are unchanged.
typedef BridgedEnumFactoryAdapter = Object? Function(
    InterpreterVisitor visitor,
    List<Object?> positionalArguments,
    Map<String, Object?> namedArguments,
    List<RuntimeType> enumTypeArguments);

/// Adapter for bridged static getters.
/// Takes interpreter context.
/// Returns the result of the native static getter.
typedef BridgedStaticGetterAdapter = Object? Function(
    InterpreterVisitor visitor);

/// Adapter for bridged static setters.
/// Takes interpreter context, the value to set.
typedef BridgedStaticSetterAdapter = void Function(
    InterpreterVisitor visitor, Object? value);

/// Adapter for bridged instance getters.
/// Takes interpreter context, the native target object.
/// Returns the result of the native instance getter.
typedef BridgedInstanceGetterAdapter = Object? Function(
    InterpreterVisitor? visitor, Object target);

/// Adapter for bridged instance setters.
/// Takes interpreter context, the native target object, the value to set.
typedef BridgedInstanceSetterAdapter = void Function(
    InterpreterVisitor? visitor, Object target, Object? value);

/// Registers a native enum while retaining native identities and adapter targets.
class BridgedEnumDefinition<T extends Enum> {
  /// The name under which the enum will be known in the interpreter.
  final String name;

  /// The list of native enum values (e.g. `MyEnum.values`).
  final List<T> values;

  /// Adapters for instance getters on enum values.
  /// The key is the getter name.
  final Map<String, BridgedInstanceGetterAdapter> getters;

  /// Adapters for instance methods on enum values.
  /// The key is the method name.
  final Map<String, BridgedMethodAdapter> methods;

  /// Adapters for declared instance setters; enum fields remain immutable.
  final Map<String, BridgedInstanceSetterAdapter> setters;

  /// Adapters for static getters on the enum class.
  final Map<String, BridgedStaticGetterAdapter> staticGetters;

  /// Adapters for static methods on the enum class.
  final Map<String, BridgedStaticMethodAdapter> staticMethods;

  /// Adapters for static setters on the enum class.
  final Map<String, BridgedStaticSetterAdapter> staticSetters;

  /// Actual enum factories, with signatures and exact compiled capabilities.
  final Map<String, BridgedEnumFactory> factories;

  /// Generic parameter names and bounds, plus substituted hierarchy metadata.
  final EnumTypeMetadata? typeMetadata;

  /// Optional explicit generic arguments, keyed by the native constant name.
  final Map<String, List<RuntimeType>> valueTypeArguments;

  /// Creates a native enum registration with optional reified type information.
  BridgedEnumDefinition({
    required this.name,
    required this.values,
    this.getters = const {},
    this.methods = const {},
    this.setters = const {},
    this.staticGetters = const {},
    this.staticMethods = const {},
    this.staticSetters = const {},
    this.factories = const {},
    this.typeMetadata,
    this.valueTypeArguments = const {},
  }) {
    // Validation: Ensure the value list is not empty
    if (values.isEmpty) {
      throw ArgumentError('Cannot bridge an enum with no values: $name');
    }
    for (final factory in factories.keys) {
      if (staticMethods.containsKey(factory) ||
          staticGetters.containsKey(factory) ||
          staticSetters.containsKey(factory) ||
          values.any((value) => value.name == factory)) {
        throw ArgumentError(
            'Enum factory conflicts with another member: $name.$factory');
      }
    }
  }

  /// Builds a native enum, resolving metadata in its owning library namespace.
  BridgedEnum buildBridgedEnum({Environment? environment}) {
    final metadata = environment == null
        ? typeMetadata
        : typeMetadata?.inEnvironment(environment);
    final bridgedEnum = BridgedEnum(name, {}, typeMetadata: metadata);
    bridgedEnum.getters = getters;
    bridgedEnum.methods = methods;
    bridgedEnum.setters = setters;
    bridgedEnum.staticGetters = staticGetters;
    bridgedEnum.staticMethods = staticMethods;
    bridgedEnum.staticSetters = staticSetters;
    bridgedEnum.factories = Map.unmodifiable({
      for (final entry in factories.entries)
        entry.key: entry.value.resolveTypes(metadata),
    });
    for (final factory in bridgedEnum.factories.values) {
      factory.validate(bridgedEnum);
    }
    for (final nativeValue in values) {
      final valueName = nativeValue.name;
      bridgedEnum.values[valueName] = BridgedEnumValue(
        bridgedEnum,
        valueName,
        nativeValue.index,
        nativeValue,
        getters: getters,
        methods: methods,
        typeArguments: valueTypeArguments[valueName] != null
            ? metadata?.arguments(valueTypeArguments[valueName]) ?? const []
            : metadata?.nativeArguments(nativeValue) ?? const [],
      );
    }
    return bridgedEnum;
  }
}
