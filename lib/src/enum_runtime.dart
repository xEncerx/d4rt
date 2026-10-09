part of 'runtime_types.dart';

/// A reified enum type expression retaining factory type-argument context.
abstract class EnumTypeReference extends AppliedRuntimeType {
  /// Creates an immutable instantiated reference to an owning enum definition.
  EnumTypeReference(super.baseType, super.typeArguments);

  /// Resolves factories and the normal string representation of a type object.
  Object? getStaticMember(String member, InterpreterVisitor visitor) {
    if (member == 'toString') {
      return NativeFunction((visitor, args, named, types) => name,
          arity: 0, name: '$name.toString');
    }
    return resolveFactory(member, visitor);
  }

  /// Resolves a factory through the owning definition with fixed arguments.
  Object? resolveFactory(String member, InterpreterVisitor visitor);
}

/// An enum definition, its lexical members and its unique constant instances.
class InterpretedEnum implements RuntimeType, Callable {
  @override
  final String name;

  /// The lexical environment containing the declaration.
  final Environment declarationEnvironment;

  /// Constant names in declaration order.
  final List<String> valueNames;

  final Map<String, InterpretedEnumValue> _values = {};

  /// The read-only unique constants created by this declaration.
  late final Map<String, InterpretedEnumValue> values =
      UnmodifiableMapView(_values);
  final Map<String, InterpretedEnumValue Function(InterpreterVisitor)>
      _constantInitializers = {};
  // Active entries retain a single allocation permit until their value is created.
  final Map<String, bool> _initializingConstants = {};

  /// Declared instance methods.
  final Map<String, InterpretedFunction> methods = {};

  /// Declared instance getters.
  final Map<String, InterpretedFunction> getters = {};

  /// Declared instance setters.
  final Map<String, InterpretedFunction> setters = {};

  /// Declared static methods.
  final Map<String, InterpretedFunction> staticMethods = {};

  /// Declared static getters.
  final Map<String, InterpretedFunction> staticGetters = {};

  /// Declared static setters.
  final Map<String, InterpretedFunction> staticSetters = {};

  /// Declared constructors; only factories are callable outside construction.
  final Map<String, InterpretedFunction> constructors = {};
  Map<String, EnumFactoryTearoff>? _factoryReferences;

  /// Immutable instance field declarations.
  final List<FieldDeclaration> fieldDeclarations = [];

  /// Generic parameters in declaration order.
  final List<String> typeParameterNames;

  /// Bounds resolved in the enum's generic declaration scope.
  final Map<String, RuntimeType?> typeParameterBounds = {};

  /// Implemented interface annotations, retaining generic arguments.
  final List<NamedType> interfaceTypes = [];

  /// Mixins in source application order, including native mixins.
  final List<RuntimeType> mixinTypes = [];

  /// Native mixin hierarchy templates bound to this enum's lexical namespace.
  final Map<BridgedClass, EnumTypeMetadata> nativeMixinTypeMetadata = {};
  final Map<String, _EnumStaticField> _staticFields = {};
  List<InterpretedEnumValue>? _valuesList;

  /// Source retained for forward references before the declaration's normal pass.
  final EnumDeclaration? declaration;
  bool _populated = false;
  bool _populating = false;

  /// Creates an enum declaration to populate in the interpretation pass.
  InterpretedEnum(
      this.name, this.declarationEnvironment, List<String> valueNames,
      {this.typeParameterNames = const [], this.declaration})
      : valueNames = List.unmodifiable(valueNames);

  /// Creates the declaration-pass placeholder without evaluating members.
  InterpretedEnum.placeholder(
      this.name, this.declarationEnvironment, List<String> valueNames,
      {this.typeParameterNames = const [], this.declaration})
      : valueNames = List.unmodifiable(valueNames);

  /// Populates exactly once in the original library scope, including forward reads.
  Object? populateDeclaration(
      InterpreterVisitor visitor, Object? Function() populate) {
    if (_populated || _populating) return null;
    final previous = visitor.environment;
    visitor.environment = declarationEnvironment;
    _populating = true;
    try {
      final result = populate();
      _populated = true;
      return result;
    } finally {
      _populating = false;
      visitor.environment = previous;
    }
  }

  void _ensureDeclaration(InterpreterVisitor visitor) {
    if (!_populated && !_populating && declaration != null) {
      final previous = visitor.environment;
      visitor.environment = declarationEnvironment;
      try {
        visitor.visitEnumDeclaration(declaration!);
      } finally {
        visitor.environment = previous;
      }
    }
  }

  /// The immutable, source-ordered constant list, shared across reads.
  List<InterpretedEnumValue> get valuesList {
    if (_valuesList != null) return _valuesList!;
    for (final constant in valueNames) {
      _ensureConstant(constant);
    }
    final list = List<InterpretedEnumValue>.unmodifiable(valueNames.map(
        (name) =>
            values[name] ??
            (throw RuntimeError('Enum $this is not initialized.'))));
    markInterpreterOwnedCollection(list);
    final listType = declarationEnvironment.get('List') as RuntimeType;
    declarationEnvironment.annotateRuntimeType(
        list, AppliedRuntimeType(listType, [instantiate(null)]));
    return _valuesList = list;
  }

  /// Registers a constant initializer; forward references share this owner.
  void declareConstantInitializer(String constant,
      InterpretedEnumValue Function(InterpreterVisitor) initialize) {
    if (!valueNames.contains(constant) ||
        _constantInitializers.containsKey(constant)) {
      throw RuntimeError('Invalid or duplicate enum constant $constant.');
    }
    _constantInitializers[constant] = initialize;
  }

  void _ensureConstant(String constant) {
    if (_values.containsKey(constant)) return;
    final initialize = _constantInitializers[constant];
    if (initialize == null) {
      throw RuntimeError('Constant $name.$constant is not initialized.');
    }
    if (_initializingConstants.containsKey(constant)) {
      throw RuntimeError('Cyclic enum constant $name.$constant.');
    }
    _initializingConstants[constant] = true;
    try {
      final visitor = InterpreterVisitor.currentCollectionVisitor;
      if (visitor == null) {
        throw RuntimeError(
            'An invocation is required for enum initialization.');
      }
      final value = initialize(visitor);
      if (!identical(value.parentEnum, this) ||
          value.name != constant ||
          value._initializing) {
        throw RuntimeError('Enum initializer must return its sealed constant.');
      }
      _values[constant] = value;
      _constantInitializers.remove(constant);
    } finally {
      _initializingConstants.remove(constant);
    }
  }

  /// Creates a lexical member boundary; locals enclosing it can shadow members.
  Environment memberEnvironment(
          {InterpretedEnumValue? receiver,
          Environment? enclosing,
          RuntimeType? owner}) =>
      EnumMemberEnvironment(this, receiver, owner,
          enclosing: enclosing ?? declarationEnvironment);

  /// Registers a static field without evaluating its initializer.
  void declareStaticField(String name, VariableDeclaration variable,
      VariableDeclarationList declaration) {
    _staticFields[name] = _EnumStaticField(
        variable.initializer, declaration.type,
        isLate: declaration.lateKeyword != null,
        isFinal: declaration.isFinal || declaration.isConst,
        isConst: declaration.isConst);
  }

  /// Whether a member is a compile-time constant owned by this declaration.
  bool hasConstantMember(String member) =>
      member == 'values' ||
      valueNames.contains(member) ||
      (_staticFields[member]?.isConst ?? false);

  /// Returns declared static const provenance without evaluating enum state.
  Expression? staticConstantInitializer(String member) {
    final field = _staticFields[member];
    if (field != null) return field.isConst ? field.initializer : null;
    for (final declaration in this.declaration?.body.members ?? const []) {
      if (declaration is FieldDeclaration &&
          declaration.isStatic &&
          declaration.fields.isConst) {
        for (final variable in declaration.fields.variables) {
          if (variable.name.lexeme == member) return variable.initializer;
        }
      }
    }
    return null;
  }

  /// Whether this enum declares a static member, including an unpopulated scope.
  bool hasStaticMember(String member) {
    if (member == 'values' ||
        valueNames.contains(member) ||
        _staticFields.containsKey(member) ||
        staticGetters.containsKey(member) ||
        staticSetters.containsKey(member) ||
        staticMethods.containsKey(member) ||
        constructors.containsKey(member)) {
      return true;
    }
    for (final declaration in this.declaration?.body.members ?? const []) {
      if (declaration is FieldDeclaration && declaration.isStatic) {
        for (final variable in declaration.fields.variables) {
          if (variable.name.lexeme == member) return true;
        }
      } else if (declaration is MethodDeclaration &&
          declaration.isStatic &&
          declaration.name.lexeme == member) {
        return true;
      } else if (declaration is ConstructorDeclaration &&
          declaration.factoryKeyword != null &&
          (declaration.name?.lexeme ?? '') == member) {
        return true;
      }
    }
    return false;
  }

  /// Whether a declared static method or factory can be retained as a tearoff.
  bool hasStaticCallable(String member) {
    if (member == 'new') member = '';
    if (staticMethods.containsKey(member) ||
        constructors[member]?.isFactory == true) {
      return true;
    }
    for (final declaration in this.declaration?.body.members ?? const []) {
      if (declaration is MethodDeclaration &&
          declaration.isStatic &&
          !declaration.isGetter &&
          !declaration.isSetter &&
          declaration.name.lexeme == member) {
        return true;
      }
      if (declaration is ConstructorDeclaration &&
          declaration.factoryKeyword != null &&
          (declaration.name?.lexeme ?? '') == member) {
        return true;
      }
    }
    return false;
  }

  @override
  int get arity => constructors['']?.arity ?? 0;
  @override
  RuntimeType get callableRuntimeType => FunctionRuntimeType.untyped();
  @override
  Object? call(InterpreterVisitor visitor, List<Object?> positionalArguments,
          [Map<String, Object?> namedArguments = const {},
          List<RuntimeType>? typeArguments]) =>
      invokeFactory(
          visitor, '', positionalArguments, namedArguments, typeArguments);

  /// Reads one own static member, preserving lookup and execution errors.
  Object? getStaticMember(String member, InterpreterVisitor visitor) {
    if (!identical(InterpreterVisitor.currentCollectionVisitor, visitor)) {
      return visitor
          .runCollectionInvocation(() => getStaticMember(member, visitor));
    }
    _ensureDeclaration(visitor);
    if (member == 'new') member = '';
    if (member == 'values') return valuesList;
    if (valueNames.contains(member)) {
      _ensureConstant(member);
      return values[member] ??
          (throw RuntimeError('Constant $name.$member is not initialized.'));
    }
    final field = _staticFields[member];
    if (field != null) return field.read(this, visitor, member);
    final getter = staticGetters[member];
    if (getter != null) return getter.call(visitor, [], {});
    final method = staticMethods[member];
    if (method != null) return method;
    if (constructors.containsKey(member)) {
      if (!constructors[member]!.isFactory) {
        throw RuntimeError(
            'Generative enum constructors cannot be called or torn off.');
      }
      return (_factoryReferences ??= {})
          .putIfAbsent(member, () => EnumFactoryTearoff(this, member));
    }
    throw RuntimeError('Undefined static member $name.$member.');
  }

  /// Writes a static field or invokes its setter against the live owning state.
  void setStaticMember(
      String member, Object? value, InterpreterVisitor visitor) {
    if (!identical(InterpreterVisitor.currentCollectionVisitor, visitor)) {
      visitor.runCollectionInvocation(
          () => setStaticMember(member, value, visitor));
      return;
    }
    final setter = staticSetters[member];
    if (setter != null) {
      setter.call(visitor, [value], {});
      return;
    }
    final field = _staticFields[member];
    if (field != null) {
      field.write(value, this, visitor, member);
      return;
    }
    throw RuntimeError('Cannot assign to enum member $name.$member.');
  }

  /// Checks generic mixin arguments using the enum's substituted type context.
  void validateMixinArguments(
      InterpretedClass mixin, List<RuntimeType> arguments) {
    if (arguments.length != mixin.typeParameterNames.length) {
      throw RuntimeError('Wrong enum mixin type argument count.');
    }
    final scope = Environment(enclosing: mixin.classDefinitionEnvironment);
    for (var index = 0; index < arguments.length; index++) {
      scope.define(mixin.typeParameterNames[index], arguments[index]);
    }
    for (final parameter in mixin.typeParameterNames) {
      final bound = mixin.typeParameterBounds[parameter];
      if (bound != null &&
          !enumTypeArgumentSatisfies(scope.get(parameter) as RuntimeType,
              substituteEnumType(bound, mixin.typeParameterNames, arguments),
              forBound: true)) {
        throw RuntimeError('Invalid enum mixin type argument $parameter.');
      }
    }
  }

  /// Checks an `on` constraint against Enum and earlier mixins, not implements.
  bool satisfiesMixinConstraint(RuntimeType expected) {
    if (isEnumCoreType(expected, 'Enum') ||
        isEnumCoreType(expected, 'Object') ||
        isEnumCoreType(expected, 'dynamic')) {
      return true;
    }
    final arguments = validateTypeArguments(null);
    final target = substituteEnumType(expected, typeParameterNames, arguments);
    for (final mixin in mixinTypes) {
      final resolved = substituteEnumType(mixin, typeParameterNames, arguments);
      final base =
          resolved is AppliedRuntimeType ? resolved.baseType : resolved;
      final projected = projectEnumType(resolved, target,
          nativeMetadata: nativeMixinTypeMetadata[base]);
      if (projected != null && enumTypeArgumentSatisfies(projected, target)) {
        return true;
      }
    }
    return false;
  }

  final Map<FormalParameterList, EnumSignature> _signatures = {};
  late final Environment _signatureEnvironment = () {
    final scope = Environment(enclosing: declarationEnvironment);
    for (final parameter in typeParameterNames) {
      scope.define(parameter, NamedRuntimeType(parameter));
    }
    return scope;
  }();

  /// Infers owner arguments through the shared normalized enum signature.
  List<RuntimeType>? inferTypeArguments(
      InterpreterVisitor visitor,
      FormalParameterList? parameters,
      List<Object?> arguments,
      Map<String, Object?> named) {
    return signatureFor(parameters).infer(visitor.environment,
        typeParameterNames, typeParameterBounds, arguments, named);
  }

  /// Retains one resolved formal contract for each real constructor declaration.
  EnumSignature signatureFor(FormalParameterList? parameters) {
    if (parameters == null) return EnumSignature(const []);
    return _signatures.putIfAbsent(
        parameters,
        () => EnumSignature([
              for (final parameter in parameters.parameters)
                EnumFormalParameter(
                    parameter.name?.lexeme ?? '', _formalType(parameter),
                    isNamed: parameter.isNamed,
                    isRequired: parameter.isRequiredPositional ||
                        parameter.isRequiredNamed),
            ]));
  }

  /// Checks evaluated constructor defaults and supplied values before its body.
  void validateBoundConstructorArguments(
      FormalParameterList? parameters, Environment scope) {
    final signature = signatureFor(parameters);
    final types = [
      for (final name in typeParameterNames) scope.get(name) as RuntimeType
    ];
    signature.validateBoundValues(scope, typeParameterNames, types);
  }

  RuntimeType _formalType(FormalParameter parameter) {
    TypeAnnotation? annotation;
    if (parameter is RegularFormalParameter &&
        parameter.functionTypedSuffix != null) {
      final suffix = parameter.functionTypedSuffix!;
      final function = resolveFunctionRuntimeType(
          parameter.type, suffix.formalParameters, _signatureEnvironment,
          typeParameterCount:
              suffix.typeParameters?.typeParameters.length ?? 0);
      return suffix.question == null ? function : nullableEnumType(function);
    }
    if (parameter is RegularFormalParameter) annotation = parameter.type;
    if (parameter is FieldFormalParameter) {
      annotation = parameter.type;
      for (final field in fieldDeclarations) {
        if (field.fields.variables
            .any((field) => field.name.lexeme == parameter.name.lexeme)) {
          annotation ??= field.fields.type;
        }
      }
    }
    return annotation == null
        ? const NamedRuntimeType('dynamic')
        : resolveRuntimeTypeArgument(annotation, _signatureEnvironment);
  }

  /// Resolves omitted arguments and checks bounds with the shared enum contract.
  List<RuntimeType> validateTypeArguments(List<RuntimeType>? arguments) =>
      resolveEnumTypeArguments(
          name, typeParameterNames, typeParameterBounds, arguments);

  /// The actual instantiated type of an enum constant or a type annotation.
  RuntimeType instantiate(List<RuntimeType>? arguments) {
    if (typeParameterNames.isEmpty) {
      if (arguments != null && arguments.isNotEmpty) {
        throw RuntimeError(
            'Non-generic enum $name cannot take type arguments.');
      }
      return this;
    }
    return EnumRuntimeType(this, validateTypeArguments(arguments));
  }

  /// Binds a receiver's enum and applied-mixin parameters to a method scope.
  void bindTypeParameters(
      RuntimeType owner, List<RuntimeType> arguments, Environment environment) {
    for (var i = 0; i < typeParameterNames.length; i++) {
      environment.define(typeParameterNames[i], arguments[i]);
    }
    if (owner is InterpretedClass) {
      for (final mixin in mixinTypes) {
        if (mixin is AppliedRuntimeType && identical(mixin.baseType, owner)) {
          for (var i = 0; i < owner.typeParameterNames.length; i++) {
            environment.define(
                owner.typeParameterNames[i],
                substituteEnumType(
                    mixin.typeArguments[i], typeParameterNames, arguments));
          }
        }
      }
    }
  }

  /// Calls a non-const factory without allocating an enum instance.
  Object? invokeFactory(InterpreterVisitor visitor, String constructorName,
      List<Object?> arguments, Map<String, Object?> named,
      [List<RuntimeType>? types]) {
    if (!identical(InterpreterVisitor.currentCollectionVisitor, visitor)) {
      return visitor.runCollectionInvocation(() =>
          invokeFactory(visitor, constructorName, arguments, named, types));
    }
    return _invokeFactory(
        visitor, constructorName, arguments, named, types, {});
  }

  Object? _invokeFactory(
      InterpreterVisitor visitor,
      String constructorName,
      List<Object?> arguments,
      Map<String, Object?> named,
      List<RuntimeType>? types,
      Set<InterpretedFunction> redirects) {
    _ensureDeclaration(visitor);
    final constructor = constructors[constructorName];
    if (constructor == null || !constructor.isFactory) {
      throw RuntimeError(
          'Only enum factories can be invoked outside constant entries.');
    }
    final resolvedTypes = validateTypeArguments(types ??
        inferTypeArguments(visitor, constructor.parameters, arguments, named));
    final signature = signatureFor(constructor.parameters);
    signature.validateArguments(arguments, named);
    signature.validateTypes(visitor.environment, typeParameterNames,
        resolvedTypes, arguments, named);
    final target = constructor.redirectedConstructor;
    final Object? result;
    if (target != null) {
      if (!redirects.add(constructor)) {
        throw RuntimeError('Cyclic enum factory redirection.');
      }
      final type = target.type;
      final prefix = type.importPrefix?.name.lexeme;
      var targetEnum = declarationEnvironment.get(prefix ?? type.name.lexeme);
      var targetName = target.name?.name ?? '';
      if (targetEnum is Environment) {
        targetEnum = targetEnum.get(type.name.lexeme);
      } else if (prefix != null) {
        targetName = type.name.lexeme;
      }
      if (targetEnum is! InterpretedEnum) {
        throw RuntimeError('Invalid enum factory redirect.');
      }
      final scope = Environment(enclosing: declarationEnvironment);
      bindTypeParameters(this, resolvedTypes, scope);
      final redirectedTypes = type.typeArguments?.arguments
          .map((argument) => resolveRuntimeTypeArgument(argument, scope))
          .toList();
      result = targetEnum._invokeFactory(visitor, targetName, arguments, named,
          redirectedTypes ?? resolvedTypes, redirects);
    } else {
      result = constructor.call(visitor, arguments, named, resolvedTypes);
    }
    if (result is! InterpretedEnumValue ||
        !identical(result.parentEnum, this) ||
        !result.valueType.isSubtypeOf(instantiate(resolvedTypes))) {
      throw RuntimeError(
          'Enum factory $name.$constructorName must return an existing constant of its type.');
    }
    return result;
  }

  /// Whether an instance member exists, without invoking a getter.
  bool hasInstanceMember(String member) {
    if (methods.containsKey(member) ||
        getters.containsKey(member) ||
        setters.containsKey(member) ||
        fieldDeclarations.any((field) =>
            field.fields.variables.any((v) => v.name.lexeme == member))) {
      return true;
    }
    for (final type in mixinTypes.reversed) {
      final base = type is AppliedRuntimeType ? type.baseType : type;
      if (base is InterpretedClass &&
          (base.methods.containsKey(member) ||
              base.getters.containsKey(member) ||
              base.setters.containsKey(member))) {
        return true;
      }
      if (base is BridgedClass &&
          (base.findInstanceGetterAdapter(member) != null ||
              base.findInstanceMethodAdapter(member) != null ||
              base.findInstanceSetterAdapter(member) != null)) {
        return true;
      }
    }
    return const ['index', 'name', 'hashCode', 'toString', 'runtimeType']
        .contains(member);
  }

  /// Whether the enum supplies a concrete member of the required interface kind.
  bool hasConcreteInstanceMember(String member, String kind) {
    final own = switch (kind) {
      'getter' => getters[member],
      'setter' => setters[member],
      _ => methods[member],
    };
    if (own != null) return !own.isAbstract;
    if (kind == 'getter' &&
        fieldDeclarations.any((field) => field.fields.variables
            .any((variable) => variable.name.lexeme == member))) {
      return true;
    }
    for (final type in mixinTypes.reversed) {
      final base = type is AppliedRuntimeType ? type.baseType : type;
      if (base is InterpretedClass) {
        final function = switch (kind) {
          'getter' => base.getters[member],
          'setter' => base.setters[member],
          _ => base.methods[member],
        };
        if (function != null && !function.isAbstract) return true;
      } else if (base is BridgedClass) {
        final adapter = switch (kind) {
          'getter' => base.findInstanceGetterAdapter(member),
          'setter' => base.findInstanceSetterAdapter(member),
          _ => base.findInstanceMethodAdapter(member),
        };
        if (adapter != null) return true;
      }
    }
    return kind == 'getter' &&
            const ['index', 'hashCode', 'runtimeType'].contains(member) ||
        kind == 'method' && member == 'toString';
  }

  /// Looks up a declared member in last-mixin-wins order.
  Object? readInstanceMember(
      InterpretedEnumValue receiver, String member, InterpreterVisitor visitor,
      {int? beforeMixin}) {
    if (beforeMixin == null) {
      if (receiver._fields.containsKey(member)) return receiver._fields[member];
      final getter = getters[member];
      if (getter != null) return getter.bind(receiver).call(visitor, [], {});
      final method = methods[member];
      if (method != null) return method.bind(receiver);
    }
    for (var i = (beforeMixin ?? mixinTypes.length) - 1; i >= 0; i--) {
      final type = mixinTypes[i];
      final base = type is AppliedRuntimeType ? type.baseType : type;
      if (base is InterpretedClass) {
        final getter = base.getters[member];
        if (getter != null && !getter.isAbstract) {
          return getter.bind(receiver).call(visitor, [], {});
        }
        final method = base.methods[member];
        if (method != null && !method.isAbstract) return method.bind(receiver);
      } else if (base is BridgedClass) {
        final getter = base.findInstanceGetterAdapter(member);
        if (getter != null) return getter(visitor, receiver);
        final method = base.findInstanceMethodAdapter(member);
        if (method != null) {
          return BridgedEnumMixinMethodCallable(
              receiver, method, member, base.name);
        }
      }
    }
    return switch (member) {
      'name' => receiver.name,
      'index' => receiver.index,
      'hashCode' => receiver.hashCode,
      'runtimeType' => receiver.valueType,
      'toString' => NativeFunction(
          (_, args, named, types) => receiver.toString(),
          arity: 0,
          name: 'toString'),
      _ => throw RuntimeError(
          "Undefined property '$member' on enum value '$receiver'."),
    };
  }

  /// Writes the nearest concrete setter, respecting a super lookup boundary.
  void writeInstanceMember(InterpretedEnumValue receiver, String member,
      Object? value, InterpreterVisitor visitor,
      {int? beforeMixin}) {
    if (beforeMixin == null) {
      final setter = setters[member];
      if (setter != null && !setter.isAbstract) {
        setter.bind(receiver).call(visitor, [value], {});
        return;
      }
    }
    for (var i = (beforeMixin ?? mixinTypes.length) - 1; i >= 0; i--) {
      final type = mixinTypes[i];
      final base = type is AppliedRuntimeType ? type.baseType : type;
      if (base is InterpretedClass) {
        final setter = base.setters[member];
        if (setter != null && !setter.isAbstract) {
          setter.bind(receiver).call(visitor, [value], {});
          return;
        }
      } else if (base is BridgedClass) {
        final setter = base.findInstanceSetterAdapter(member);
        if (setter != null) {
          setter(visitor, receiver, value);
          return;
        }
      }
    }
    throw RuntimeError('Cannot assign immutable enum field $member.');
  }

  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) =>
      _enumSubtype(this, validateTypeArguments(null), other);
  @override
  String toString() => '<enum $name>';
}

/// A factory reference carrying enum-owner specialization rather than method types.
abstract class EnumFactoryCallable implements Callable {
  /// The owning declaration, independent of its current specialization.
  RuntimeType get enumOwner;

  /// Whether an explicit or contextual specialization is already fixed.
  bool get isBound;

  /// Binds owner arguments and validates them before returning a typed reference.
  EnumFactoryCallable bindTypeArguments(List<RuntimeType> arguments);

  /// Applies a function return context to an unbound enum factory reference.
  EnumFactoryCallable bindContext(RuntimeType? context) {
    if (isBound || context is! FunctionRuntimeType) return this;
    final returnType = context.returnType;
    final result =
        returnType is NullableEnumArgument ? returnType.type : returnType;
    if (result is! AppliedRuntimeType) return this;
    if (!identical(result.baseType, enumOwner)) return this;
    return bindTypeArguments(result.typeArguments);
  }
}

/// A factory tearoff retaining its enum owner and optional explicit arguments.
class EnumFactoryTearoff extends EnumFactoryCallable {
  /// The definition owning the factory and its generic parameter contract.
  final InterpretedEnum enumType;

  /// The declared constructor name, or empty for an unnamed factory.
  final String constructorName;
  final List<RuntimeType>? _typeArguments;

  /// Creates a factory reference without constructing an enum instance.
  EnumFactoryTearoff(this.enumType, this.constructorName,
      {List<RuntimeType>? typeArguments})
      : _typeArguments = typeArguments == null
            ? null
            : enumType.validateTypeArguments(typeArguments);

  /// Fixes explicit generic arguments instead of inferring them at invocation.
  @override
  EnumFactoryTearoff bindTypeArguments(List<RuntimeType> arguments) =>
      EnumFactoryTearoff(enumType, constructorName, typeArguments: arguments);

  @override
  RuntimeType get enumOwner => enumType;
  @override
  bool get isBound => _typeArguments != null;

  @override
  int get arity => enumType.constructors[constructorName]!.arity;
  late final RuntimeType _runtimeType = _typeArguments == null
      ? FunctionRuntimeType.untyped()
      : enumType
          .signatureFor(enumType.constructors[constructorName]!.parameters)
          .specialize(enumType.typeParameterNames, _typeArguments)
          .functionType(enumType.instantiate(_typeArguments));
  @override
  RuntimeType get callableRuntimeType => _runtimeType;
  @override
  Object? call(InterpreterVisitor visitor, List<Object?> positionalArguments,
          [Map<String, Object?> namedArguments = const {},
          List<RuntimeType>? typeArguments]) =>
      enumType.invokeFactory(visitor, constructorName, positionalArguments,
          namedArguments, _typeArguments ?? typeArguments);
}

/// A captured lexical boundary backed by live enum member state.
class EnumMemberEnvironment extends Environment {
  /// The definition supplying static and instance members.
  final InterpretedEnum enumType;

  /// The current invocation authority, never retained by a captured scope.
  InterpreterVisitor get visitor =>
      InterpreterVisitor.currentCollectionVisitor ??
      (throw RuntimeError('An invocation is required for enum member access.'));

  /// The receiver, absent for static member scope.
  final InterpretedEnumValue? receiver;

  /// The member's lexical declaring type, retained by nested closures.
  final RuntimeType? memberOwner;

  /// Creates a member scope without copying any writable state.
  EnumMemberEnvironment(this.enumType, this.receiver, this.memberOwner,
      {required Environment enclosing})
      : super(enclosing: enclosing);

  InterpretedClass? get _mixinOwner =>
      memberOwner is InterpretedClass ? memberOwner as InterpretedClass : null;
  bool _hasStatic(String name) {
    final owner = _mixinOwner;
    return owner == null
        ? enumType.hasStaticMember(name)
        : owner.staticFields.containsKey(name) ||
            owner.staticMethods.containsKey(name) ||
            owner.staticGetters.containsKey(name) ||
            owner.staticSetters.containsKey(name);
  }

  bool _hasInstance(String name) =>
      receiver != null &&
      (name == 'name'
          ? enumType.hasConcreteInstanceMember(name, 'getter') ||
              enumType.hasConcreteInstanceMember(name, 'method') ||
              enumType.hasConcreteInstanceMember(name, 'setter')
          : enumType.hasInstanceMember(name));
  bool _defaultName(String name) =>
      name == 'name' &&
      receiver != null &&
      !_hasInstance(name) &&
      !_hasStatic(name) &&
      super.findDefiningEnvironment(name) == null;
  bool _has(String name) =>
      _hasInstance(name) || _hasStatic(name) || _defaultName(name);
  @override
  dynamic get(String name) {
    if (isDefinedLocally(name)) return super.get(name);
    if (_hasInstance(name)) return receiver!.get(name, visitor);
    if (_hasStatic(name)) {
      final owner = _mixinOwner;
      if (owner == null) return enumType.getStaticMember(name, visitor);
      if (owner.staticFields.containsKey(name)) {
        final value = owner.staticFields[name];
        return value is LateVariable ? value.value : value;
      }
      if (owner.staticGetters.containsKey(name)) {
        return owner.staticGetters[name]!.call(visitor, [], {});
      }
      if (owner.staticMethods.containsKey(name)) {
        return owner.staticMethods[name];
      }
      throw RuntimeError('Cannot read mixin setter $name.');
    }
    if (_defaultName(name)) return receiver!.name;
    return super.get(name);
  }

  @override
  Object? assign(String name, Object? value) {
    if (isDefinedLocally(name)) return super.assign(name, value);
    if (_hasInstance(name) || _defaultName(name)) {
      receiver!.set(name, value, visitor);
    } else if (_hasStatic(name)) {
      final owner = _mixinOwner;
      if (owner == null) {
        enumType.setStaticMember(name, value, visitor);
      } else if (owner.staticSetters.containsKey(name)) {
        owner.staticSetters[name]!.call(visitor, [value], {});
      } else if (owner.staticFields.containsKey(name)) {
        final existing = owner.staticFields[name];
        if (existing is LateVariable) {
          existing.value = value;
        } else {
          owner.staticFields[name] = value;
        }
      } else {
        throw RuntimeError('Cannot assign mixin static $name.');
      }
    } else {
      return super.assign(name, value);
    }
    return value;
  }

  @override
  Environment? findDefiningEnvironment(String name) =>
      isDefinedLocally(name) || _has(name)
          ? this
          : super.findDefiningEnvironment(name);
}

/// A reified enum instantiation with substituted interface and mixin types.
class EnumRuntimeType extends EnumTypeReference {
  /// Creates an instantiated enum type from validated arguments.
  EnumRuntimeType(InterpretedEnum super.enumType, super.arguments);

  @override
  Object? resolveFactory(String member, InterpreterVisitor visitor) {
    final result =
        (baseType as InterpretedEnum).getStaticMember(member, visitor);
    if (result is! EnumFactoryTearoff) {
      throw RuntimeError('Instantiated enum types expose factories only.');
    }
    return result.bindTypeArguments(typeArguments);
  }

  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) =>
      enumTypeArgumentSatisfies(this, other);
}

bool _enumSubtype(InterpretedEnum definition, List<RuntimeType> arguments,
        RuntimeType other) =>
    enumTypeArgumentSatisfies(
        arguments.isEmpty
            ? definition
            : AppliedRuntimeType(definition, arguments),
        other);

class _EnumStaticField {
  final Expression? initializer;
  final TypeAnnotation? annotation;
  RuntimeType? _expected;
  final bool isLate;
  final bool isFinal;
  final bool isConst;
  bool _initialized = false;
  bool _initializing = false;
  Object? _value;
  _EnumStaticField(this.initializer, this.annotation,
      {required this.isLate, required this.isFinal, required this.isConst});
  Object? read(InterpretedEnum owner, InterpreterVisitor visitor, String name) {
    if (_initialized) return _value;
    if (_initializing) throw StackOverflowError();
    if (initializer == null && isLate) {
      throw RuntimeError('Late field $name has not been initialized.');
    }
    _initializing = true;
    final previous = visitor.environment;
    try {
      visitor.environment = owner.memberEnvironment();
      _value = isConst && initializer != null
          ? visitor.evaluateEnumConstant(initializer!, visitor.environment)
          : initializer?.accept<Object?>(visitor);
      _expected ??= annotation == null
          ? null
          : resolveRuntimeTypeArgument(annotation!, visitor.environment);
      _checkEnumFieldValue(name, _value, _expected, visitor.environment);
      _initialized = true;
      return _value;
    } finally {
      visitor.environment = previous;
      _initializing = false;
    }
  }

  void write(Object? value, InterpretedEnum owner, InterpreterVisitor visitor,
      String name) {
    if (isFinal && (!isLate || initializer != null || _initialized)) {
      throw RuntimeError('Cannot assign final enum field $name.');
    }
    _expected ??= annotation == null
        ? null
        : resolveRuntimeTypeArgument(annotation!, owner.memberEnvironment());
    _checkEnumFieldValue(name, value, _expected, visitor.environment);
    _value = value;
    _initialized = true;
  }
}

void _checkEnumFieldValue(
    String name, Object? value, RuntimeType? expected, Environment scope) {
  if (expected == null) return;
  final actual = scope.getRuntimeType(value);
  if (actual == null || !enumTypeArgumentSatisfies(actual, expected)) {
    throw RuntimeError(
        'Invalid value for enum field $name: expected ${expected.name}.');
  }
  if ((value is List || value is Map || value is Set) &&
      actual is! AppliedRuntimeType &&
      expected is AppliedRuntimeType) {
    scope.annotateRuntimeType(value, expected);
  }
}

/// A unique constant, immutable after its generative construction completes.
class InterpretedEnumValue implements RuntimeValue {
  /// The owning enum declaration.
  final InterpretedEnum parentEnum;

  /// The underlying constant name, independent of user member overrides.
  final String name;

  /// The source declaration index.
  final int index;

  /// Reified generic arguments for this constant.
  final List<RuntimeType> typeArguments;
  final Map<String, Object?> _fields = {};
  bool _initializing = true;
  final Set<String> _activeConstructors = {};
  late final RuntimeType _type = parentEnum.instantiate(typeArguments);

  /// Creates a constant under the enum declaration's construction authority.
  factory InterpretedEnumValue(
      InterpretedEnum parentEnum, String name, int index,
      {List<RuntimeType> typeArguments = const []}) {
    if (index < 0 ||
        index >= parentEnum.valueNames.length ||
        parentEnum.valueNames[index] != name ||
        parentEnum._initializingConstants[name] != true) {
      throw RuntimeError(
          'Enum values can only be allocated once by their owning entry initializer.');
    }
    parentEnum._initializingConstants[name] = false;
    return InterpretedEnumValue._(parentEnum, name, index, typeArguments);
  }
  InterpretedEnumValue._(
      this.parentEnum, this.name, this.index, List<RuntimeType> typeArguments)
      : typeArguments = List.unmodifiable(typeArguments);

  /// Checks the field invariant and seals the constant against direct writes.
  void finishInitialization() {
    if (!_initializing || parentEnum._initializingConstants[name] != false) {
      throw RuntimeError(
          'Only the owning initializer can seal an enum constant.');
    }
    if (!valueType.isSubtypeOf(parentEnum.instantiate(null))) {
      throw RuntimeError(
          'Enum constants must conform to the declared values element type.');
    }
    for (final field in parentEnum.fieldDeclarations) {
      for (final variable in field.fields.variables) {
        if (!_fields.containsKey(variable.name.lexeme)) {
          throw RuntimeError(
              'Uninitialized enum field ${variable.name.lexeme}.');
        }
      }
    }
    _initializing = false;
  }

  /// Runs a generative constructor while detecting redirect cycles.
  Object? initialize(InterpreterVisitor visitor, String constructor,
      List<Object?> args, Map<String, Object?> named) {
    if (!_initializing || !_activeConstructors.add(constructor)) {
      throw RuntimeError('Invalid enum constructor redirection.');
    }
    try {
      final function = parentEnum.constructors[constructor];
      if (function == null || function.isFactory) {
        throw RuntimeError('Enum entries require generative constructors.');
      }
      return function.bind(this).call(visitor, args, named);
    } finally {
      _activeConstructors.remove(constructor);
    }
  }

  @override
  RuntimeType get valueType => _type;
  @override
  Object? get(String member, [InterpreterVisitor? visitor]) {
    if (visitor == null) {
      throw RuntimeError('An interpreter is required for enum member access.');
    }
    return parentEnum.readInstanceMember(this, member, visitor);
  }

  @override
  void set(String member, Object? value, [InterpreterVisitor? visitor]) {
    if (_initializing && visitor == null) {
      FieldDeclaration? declaration;
      for (final field in parentEnum.fieldDeclarations) {
        if (field.fields.variables
            .any((variable) => variable.name.lexeme == member)) {
          declaration = field;
          break;
        }
      }
      if (declaration == null || _fields.containsKey(member)) {
        throw RuntimeError('Invalid initialization of enum field $member.');
      }
      final scope = Environment(enclosing: parentEnum.declarationEnvironment);
      parentEnum.bindTypeParameters(parentEnum, typeArguments, scope);
      final annotation = declaration.fields.type;
      final expected = annotation == null
          ? null
          : resolveRuntimeTypeArgument(annotation, scope);
      _checkEnumFieldValue(member, value, expected, scope);
      _fields[member] = value;
      return;
    }
    if (visitor == null) {
      throw RuntimeError('An interpreter is required for enum member access.');
    }
    parentEnum.writeInstanceMember(this, member, value, visitor);
  }

  @override
  String toString() => '${parentEnum.name}.$name';
}

/// A receiver with lookup starting before the current enum mixin.
class EnumSuper {
  /// The constant receiving the call.
  final InterpretedEnumValue receiver;

  /// The exclusive mixin lookup limit.
  final int beforeMixin;

  /// Creates a super lookup without changing the receiver.
  EnumSuper(this.receiver, this.beforeMixin);

  /// Reads the inherited member, using the normal enum member rules.
  Object? get(String name, InterpreterVisitor visitor) => receiver.parentEnum
      .readInstanceMember(receiver, name, visitor, beforeMixin: beforeMixin);

  /// Invokes the inherited setter without permitting constant field mutation.
  void set(String name, Object? value, InterpreterVisitor visitor) =>
      receiver.parentEnum.writeInstanceMember(receiver, name, value, visitor,
          beforeMixin: beforeMixin);
}
