part of 'interpreter_visitor.dart';

class _EnumDeclarationInterpreter {
  final InterpreterVisitor visitor;
  _EnumDeclarationInterpreter(this.visitor);

  Object? populate(EnumDeclaration node) {
    if (!identical(InterpreterVisitor.currentCollectionVisitor, visitor)) {
      return visitor.runCollectionInvocation(() => populate(node));
    }
    final enumType = visitor.environment.get(node.namePart.typeName.lexeme)
        as InterpretedEnum;
    return enumType.populateDeclaration(
        visitor, () => _populate(node, enumType));
  }

  Object? _populate(EnumDeclaration node, InterpretedEnum enumType) {
    for (final constant in node.body.constants) {
      constant.arguments?.argumentList.accept(_EnumMutationValidator());
    }
    if (node.body.constants.isEmpty) {
      throw RuntimeError('An enum must declare at least one constant.');
    }
    if (node.body.constants.any((constant) => const [
          'values',
          'index',
          'hashCode',
          'toString',
          'runtimeType',
          'noSuchMethod'
        ].contains(constant.name.lexeme))) {
      throw RuntimeError('Enum constant conflicts with an inherited member.');
    }
    final scope = enumType.memberEnvironment();
    final typeScope = Environment(enclosing: scope);
    for (final name in enumType.typeParameterNames) {
      typeScope.define(name, TypeParameter(name));
    }
    for (final parameter
        in node.namePart.typeParameters?.typeParameters ?? const []) {
      enumType.typeParameterBounds[parameter.name.lexeme] =
          parameter.bound == null
              ? null
              : resolveRuntimeTypeArgument(parameter.bound!, typeScope);
    }
    for (final name in enumType.typeParameterNames) {
      typeScope.assign(
          name, TypeParameter(name, bound: enumType.typeParameterBounds[name]));
    }
    enumType.interfaceTypes
        .addAll(node.implementsClause?.interfaces ?? const <NamedType>[]);
    for (final annotation
        in node.withClause?.mixinTypes ?? const <NamedType>[]) {
      var type = resolveRuntimeTypeAnnotation(annotation, typeScope);
      final base = type is AppliedRuntimeType ? type.baseType : type;
      if (base is InterpretedClass) {
        base.ensureEnumDependency(visitor);
        if (type is! AppliedRuntimeType && base.typeParameterNames.isNotEmpty) {
          type = AppliedRuntimeType(
              base,
              instantiateEnumTypeBounds(
                  base.typeParameterNames, base.typeParameterBounds));
        }
        enumType.validateMixinArguments(
            base, type is AppliedRuntimeType ? type.typeArguments : const []);
        if (!base.isMixin || base.fieldDeclarations.any((f) => !f.isStatic)) {
          throw RuntimeError('Enum mixins cannot introduce instance fields.');
        }
        for (final forbidden in ['index', 'hashCode', '==', 'values']) {
          if (base.methods.containsKey(forbidden) ||
              base.getters.containsKey(forbidden) ||
              base.setters.containsKey(forbidden) ||
              base.operators.containsKey(forbidden)) {
            throw RuntimeError('Forbidden enum mixin member $forbidden.');
          }
        }
        final constraintEnv =
            Environment(enclosing: base.classDefinitionEnvironment);
        for (var i = 0; i < base.typeParameterNames.length; i++) {
          constraintEnv.define(
              base.typeParameterNames[i],
              type is AppliedRuntimeType
                  ? type.typeArguments[i]
                  : base.typeParameterBounds[base.typeParameterNames[i]] ??
                      const NamedRuntimeType('dynamic'));
        }
        for (final constraint in base.onConstraintTypes) {
          final expected =
              resolveRuntimeTypeAnnotation(constraint, constraintEnv);
          if (!enumType.satisfiesMixinConstraint(expected)) {
            throw RuntimeError(
                'Enum ${enumType.name} does not satisfy mixin constraint ${expected.name}.');
          }
        }
      } else if (base is BridgedClass) {
        if (!base.canBeUsedAsMixin) {
          throw RuntimeError('Native type ${base.name} is not a mixin.');
        }
        final metadata = base.enumMixinMetadata;
        if (metadata != null) {
          if (metadata.hasInstanceFields) {
            throw RuntimeError('Enum mixins cannot introduce instance fields.');
          }
          final nativeTypes = metadata.typeMetadata.inEnvironment(typeScope);
          enumType.nativeMixinTypeMetadata[base] = nativeTypes;
          final arguments = nativeTypes.arguments(
              type is AppliedRuntimeType ? type.typeArguments : null);
          if (type is! AppliedRuntimeType && arguments.isNotEmpty) {
            type = AppliedRuntimeType(base, arguments);
          }
          final substitutions = {
            for (var i = 0; i < arguments.length; i++)
              metadata.typeMetadata.typeParameters[i]: arguments[i]
          };
          for (final constraint in metadata.constraints) {
            final expected = nativeTypes.parse(constraint, substitutions);
            if (!enumType.satisfiesMixinConstraint(expected)) {
              throw RuntimeError(
                  'Unsatisfied native enum mixin constraint ${expected.name}.');
            }
          }
        }
        for (final forbidden in ['index', 'hashCode', '==', 'values']) {
          if (base.getters.containsKey(forbidden) ||
              base.methods.containsKey(forbidden) ||
              base.setters.containsKey(forbidden)) {
            throw RuntimeError(
                'Forbidden native enum mixin member $forbidden.');
          }
        }
      } else {
        throw RuntimeError('Invalid enum mixin ${base.name}.');
      }
      enumType.mixinTypes.add(type);
    }
    final constructors = <String, ConstructorDeclaration>{};
    for (final member in node.body.members) {
      if (member is MethodDeclaration) {
        final name = member.name.lexeme;
        if (name == 'values' ||
            const ['index', 'hashCode', '=='].contains(name) ||
            (member.isStatic &&
                const ['toString', 'runtimeType', 'noSuchMethod']
                    .contains(name))) {
          throw RuntimeError('Forbidden enum member $name.');
        }
        if (!member.isComplete) {
          throw RuntimeError('Enums cannot declare abstract members.');
        }
        final function =
            InterpretedFunction.method(member, typeScope, enumType);
        final map = member.isStatic
            ? (member.isGetter
                ? enumType.staticGetters
                : member.isSetter
                    ? enumType.staticSetters
                    : enumType.staticMethods)
            : (member.isGetter
                ? enumType.getters
                : member.isSetter
                    ? enumType.setters
                    : enumType.methods);
        map[name] = function;
      } else if (member is FieldDeclaration) {
        if (!member.isStatic &&
            (!member.fields.isFinal || member.fields.lateKeyword != null)) {
          throw RuntimeError(
              'Enum instance fields must be final and not late.');
        }
        for (final variable in member.fields.variables) {
          if (const ['values', 'index', 'hashCode']
                  .contains(variable.name.lexeme) ||
              (member.isStatic &&
                  const ['toString', 'runtimeType', 'noSuchMethod']
                      .contains(variable.name.lexeme))) {
            throw RuntimeError('Forbidden enum field ${variable.name.lexeme}.');
          }
          if (member.isStatic) {
            enumType.declareStaticField(
                variable.name.lexeme, variable, member.fields);
          }
        }
        if (!member.isStatic) enumType.fieldDeclarations.add(member);
      } else if (member is ConstructorDeclaration) {
        final name = member.name?.lexeme ?? '';
        if (member.factoryKeyword != null && member.constKeyword != null) {
          throw RuntimeError('Enum factories cannot be const.');
        }
        if (member.factoryKeyword == null && member.constKeyword == null) {
          throw RuntimeError('Generative enum constructors must be const.');
        }
        if (member.factoryKeyword == null &&
            member.body is! EmptyFunctionBody) {
          throw RuntimeError(
              'Generative enum constructors cannot have a body.');
        }
        constructors[name] = member;
        enumType.constructors[name] =
            InterpretedFunction.constructor(member, typeScope, enumType);
      }
    }
    for (final constructor in enumType.constructors.values) {
      if (!constructor.isFactory) {
        constructor.validateEnumConstantConstructor(visitor);
      }
    }
    _validateObligations(enumType, typeScope);
    for (var index = 0; index < node.body.constants.length; index++) {
      final constant = node.body.constants[index];
      enumType.declareConstantInitializer(constant.name.lexeme, (visitor) {
        final interpreter = _EnumDeclarationInterpreter(visitor);
        final previous = visitor.environment;
        final previousConstantContext = visitor._enumConstantContext;
        visitor.environment = typeScope;
        visitor._enumConstantContext = true;
        try {
          final invocation = constant.arguments;
          final constructorName =
              invocation?.constructorSelector?.name.name ?? '';
          final declaration = constructors[constructorName];
          if (declaration?.factoryKeyword != null) {
            throw RuntimeError('Enum entries cannot invoke factories.');
          }
          if (declaration == null &&
              (constructors.values.any(
                      (constructor) => constructor.factoryKeyword == null) ||
                  constructors.containsKey('') ||
                  constructorName.isNotEmpty)) {
            throw RuntimeError('Missing enum constructor $constructorName.');
          }
          final args = invocation == null
              ? (<Object?>[], <String, Object?>{})
              : interpreter._constantArguments(invocation.argumentList, node);
          if (declaration == null &&
              (args.$1.isNotEmpty || args.$2.isNotEmpty)) {
            throw RuntimeError(
                'The implicit enum constructor takes no arguments.');
          }
          final explicit = invocation?.typeArguments?.arguments
              .map((t) => resolveRuntimeTypeArgument(t, typeScope))
              .toList();
          final types = enumType.validateTypeArguments(explicit ??
              enumType.inferTypeArguments(
                  visitor, declaration?.parameters, args.$1, args.$2));
          final value = InterpretedEnumValue(
              enumType, constant.name.lexeme, index,
              typeArguments: types);
          final fieldScope = enumType.memberEnvironment(receiver: value);
          enumType.bindTypeParameters(enumType, types, fieldScope);
          visitor.environment = fieldScope;
          for (final field in enumType.fieldDeclarations) {
            for (final variable in field.fields.variables) {
              if (variable.initializer != null) {
                value.set(variable.name.lexeme,
                    interpreter._constantValue(variable.initializer!, node));
              }
            }
          }
          if (declaration != null) {
            value.initialize(visitor, constructorName, args.$1, args.$2);
          }
          value.finishInitialization();
          return value;
        } finally {
          visitor.environment = previous;
          visitor._enumConstantContext = previousConstantContext;
        }
      });
    }
    final previousScope = visitor.environment;
    visitor.environment = typeScope;
    try {
      for (final constant in node.body.constants) {
        final arguments = constant.arguments?.argumentList;
        if (arguments != null) visitor.validateEnumConstant(arguments);
      }
      for (final field in enumType.fieldDeclarations) {
        for (final variable in field.fields.variables) {
          if (variable.initializer != null) {
            visitor.validateEnumConstant(variable.initializer!);
          }
        }
      }
    } finally {
      visitor.environment = previousScope;
    }
    enumType.valuesList;
    return null;
  }

  (List<Object?>, Map<String, Object?>) _constantArguments(
      ArgumentList arguments, EnumDeclaration node) {
    final positional = <Object?>[];
    final named = <String, Object?>{};
    for (final argument in arguments.arguments) {
      if (argument is NamedArgument) {
        named[argument.name.lexeme] =
            _constantValue(argument.argumentExpression, node);
      } else {
        positional.add(_constantValue(argument.argumentExpression, node));
      }
    }
    return (positional, named);
  }

  Object? _constantValue(Expression expression, EnumDeclaration node) =>
      visitor.evaluateEnumConstant(expression, visitor.environment);

  void _validateObligations(InterpretedEnum type, Environment env) {
    final seen = <RuntimeType>{};
    void check(RuntimeType runtimeType) {
      final base = runtimeType is AppliedRuntimeType
          ? runtimeType.baseType
          : runtimeType;
      if (!seen.add(base)) return;
      if (base is InterpretedClass) base.ensureEnumDependency(visitor);
      final methods = base is InterpretedClass
          ? base.methods
          : base is BridgedClass
              ? base.methods
              : const <String, Object?>{};
      final getters = base is InterpretedClass
          ? base.getters
          : base is BridgedClass
              ? base.getters
              : const <String, Object?>{};
      final setters = base is InterpretedClass
          ? base.setters
          : base is BridgedClass
              ? base.setters
              : const <String, Object?>{};
      for (final entry in {
        'method': methods,
        'getter': getters,
        'setter': setters
      }.entries) {
        for (final member in entry.value.keys) {
          if (member == 'values') {
            throw RuntimeError('Enum interfaces cannot require values.');
          }
          if (!type.hasConcreteInstanceMember(member, entry.key)) {
            throw RuntimeError(
                'Enum ${type.name} does not implement ${entry.key} $member.');
          }
        }
      }
      if (base is! InterpretedClass) return;
      for (final field in base.fieldDeclarations) {
        if (field.isStatic) continue;
        for (final variable in field.fields.variables) {
          if (!type.hasConcreteInstanceMember(variable.name.lexeme, 'getter') ||
              (!field.fields.isFinal &&
                  !type.hasConcreteInstanceMember(
                      variable.name.lexeme, 'setter'))) {
            throw RuntimeError(
                'Enum ${type.name} does not implement ${variable.name.lexeme}.');
          }
        }
      }
      for (final parent in base.interfaces) {
        check(parent);
      }
      if (base.superclass != null) check(base.superclass!);
    }

    for (final annotation in type.interfaceTypes) {
      check(resolveRuntimeTypeAnnotation(annotation, env));
    }
    for (final mixin in type.mixinTypes) {
      final base = mixin is AppliedRuntimeType ? mixin.baseType : mixin;
      if (base is InterpretedClass) {
        for (final entry in {
          'method': base.methods,
          'getter': base.getters,
          'setter': base.setters
        }.entries) {
          for (final member in entry.value.entries) {
            if (member.value.isAbstract &&
                !type.hasConcreteInstanceMember(member.key, entry.key)) {
              throw RuntimeError(
                  'Unimplemented enum mixin member ${member.key}.');
            }
          }
        }
      } else if (base is BridgedClass && base.enumMixinMetadata != null) {
        for (final requirement
            in base.enumMixinMetadata!.abstractMembers.entries) {
          if (!type.hasConcreteInstanceMember(
              requirement.key, requirement.value)) {
            throw RuntimeError(
                'Unimplemented native enum mixin member ${requirement.key}.');
          }
        }
      }
    }
  }
}

class _EnumMutationValidator extends RecursiveAstVisitor<void> {
  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    throw RuntimeError('Enum constant expressions cannot mutate values.');
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    if (node.operator.type == TokenType.PLUS_PLUS ||
        node.operator.type == TokenType.MINUS_MINUS) {
      throw RuntimeError('Enum constant expressions cannot mutate values.');
    }
    super.visitPrefixExpression(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.type != TokenType.BANG) {
      throw RuntimeError('Enum constant expressions cannot mutate values.');
    }
    super.visitPostfixExpression(node);
  }
}

class _EnumConstantValidator extends RecursiveAstVisitor<void> {
  final InterpreterVisitor visitor;
  Set<String> parameters;
  _EnumConstantValidator(this.visitor, {this.parameters = const {}});
  final Set<Expression> _checkingConstants = {};

  bool _constant(String name) {
    final expression = visitor.environment.constantInitializer(name);
    if (expression == null) return false;
    _validateConstant(expression, visitor.environment.constantOwner(name)!);
    return true;
  }

  void _validateConstant(Expression expression, Environment scope) {
    if (!_checkingConstants.add(expression)) {
      throw RuntimeError('Cyclic enum constant expression.');
    }
    final previous = visitor.environment;
    final previousParameters = parameters;
    visitor.environment = scope;
    // Independently declared constants cannot capture constructor parameters.
    parameters = const {};
    try {
      expression.accept(_EnumMutationValidator());
      expression.accept(this);
    } finally {
      visitor.environment = previous;
      parameters = previousParameters;
      _checkingConstants.remove(expression);
    }
  }

  bool _enumConstant(InterpretedEnum owner, String member) {
    final expression = owner.staticConstantInitializer(member);
    if (expression != null) {
      _validateConstant(expression, owner.memberEnvironment());
      return true;
    }
    return owner.hasConstantMember(member);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) =>
      node.expression.accept(this);

  @override
  void visitRedirectingConstructorInvocation(
          RedirectingConstructorInvocation node) =>
      node.argumentList.accept(this);

  void _constructor(Object? owner, String name) {
    if (name == 'new') name = '';
    if (owner is InterpretedClass) {
      final declaration = owner.declaration;
      if (declaration is ClassDeclaration) {
        for (final member in declaration.body.members) {
          if (member is ConstructorDeclaration &&
              (member.name?.lexeme ?? '') == name) {
            if (member.constKeyword == null) {
              throw RuntimeError('Enum payload constructors must be const.');
            }
            member.accept(_EnumMutationValidator());
          } else if (member is FieldDeclaration &&
              (!member.isStatic || member.fields.isConst)) {
            member.accept(_EnumMutationValidator());
          }
        }
      }
      owner.ensureEnumDependency(visitor);
      final constructor = owner.constructors[name];
      if (constructor == null || !constructor.isConstConstructor) {
        throw RuntimeError('Enum payload constructors must be const.');
      }
      constructor.validateEnumConstantConstructor(visitor);
    } else if (owner is BridgedClass) {
      if (!owner.constantConstructors.contains(name)) {
        throw RuntimeError(
            'Native enum payload constructors must be registered const.');
      }
    } else {
      throw RuntimeError('Enum entry arguments must be constant expressions.');
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final functionName = node.target == null
        ? node.methodName.name
        : '${node.target!.toSource()}.${node.methodName.name}';
    Object? function;
    try {
      function = visitor.environment.get(functionName);
    } on RuntimeError {
      // Constructor syntax is resolved below, not as a top-level function.
    }
    if (identical(function, CoreStdlib.identicalFunction)) {
      node.argumentList.accept(this);
      return;
    }
    Object? owner;
    var constructor = '';
    if (node.target == null) {
      owner = visitor.environment.get(node.methodName.name);
    } else {
      owner = visitor.environment.get(node.target!.toSource());
      constructor = node.methodName.name;
    }
    _constructor(owner, constructor);
    node.argumentList.accept(this);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = resolveRuntimeTypeAnnotation(
        node.constructorName.type, visitor.environment);
    _constructor(type is AppliedRuntimeType ? type.baseType : type,
        node.constructorName.name?.name ?? '');
    node.argumentList.accept(this);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    throw RuntimeError('Enum entry arguments must be constant expressions.');
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    throw RuntimeError('Anonymous functions are not constant enum arguments.');
  }

  bool _constantMember(Expression target, String member) {
    Object? owner;
    if (target is FunctionReference) {
      target.function.accept(this);
      final definition = visitor.environment.get(target.function.toSource());
      if (definition is InterpretedClass && target.typeArguments != null) {
        throw RuntimeError(
            'Specialized class constructor payloads require compiled support.');
      }
      owner = target.accept<Object?>(visitor);
    } else if (target is TypeLiteral) {
      owner = resolveRuntimeTypeArgument(target.type, visitor.environment);
    } else {
      owner = visitor.environment.get(target.toSource());
    }
    if (owner is EnumTypeReference) owner = owner.baseType;
    if (owner is Environment) {
      if (owner.isFunctionDeclaration(member) ||
          _constant('${target.toSource()}.$member')) {
        return true;
      }
      final value = owner.get(member);
      return value is RuntimeType && value is! NativeFunction;
    }
    if (owner is InterpretedEnum) {
      if (_enumConstant(owner, member)) return true;
      return owner.hasStaticCallable(member);
    }
    if (owner is BridgedEnum) {
      return owner.values.containsKey(member) ||
          member == 'values' ||
          owner.staticMethods.containsKey(member) ||
          owner.factories.containsKey(member == 'new' ? '' : member);
    }
    if (owner is InterpretedClass) {
      final constants = owner.staticConstantEnvironment;
      if (constants.constantInitializer(member) != null) {
        final previous = visitor.environment;
        visitor.environment = constants;
        try {
          return _constant(member);
        } finally {
          visitor.environment = previous;
        }
      }
      final declaration = owner.declaration;
      if (declaration is ClassDeclaration) {
        return declaration.body.members.any((declaration) =>
            declaration is MethodDeclaration &&
                declaration.isStatic &&
                !declaration.isGetter &&
                !declaration.isSetter &&
                declaration.name.lexeme == member ||
            declaration is ConstructorDeclaration &&
                (declaration.name?.lexeme ?? '') ==
                    (member == 'new' ? '' : member));
      }
      return owner.staticMethods.containsKey(member) ||
          owner.constructors.containsKey(member == 'new' ? '' : member);
    }
    if (owner is BridgedClass) {
      return owner.staticMethods.containsKey(member) ||
          owner.constructors.containsKey(member == 'new' ? '' : member);
    }
    return false;
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    final qualified = node.toSource();
    if (_constant(qualified)) return;
    if (_constantMember(node.prefix, node.identifier.name)) return;
    throw RuntimeError('Enum arguments cannot reference nonconstant members.');
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    if (_constantMember(node.realTarget, node.propertyName.name)) return;
    throw RuntimeError('Enum arguments cannot reference nonconstant members.');
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.parent is NamedType ||
        node.parent is Label ||
        parameters.contains(node.name)) {
      return;
    }
    if (_constant(node.name)) return;
    final defining = visitor.environment.findDefiningEnvironment(node.name);
    if (defining is EnumMemberEnvironment) {
      if (_enumConstant(defining.enumType, node.name) ||
          defining.enumType.hasStaticCallable(node.name)) {
        return;
      }
      throw RuntimeError(
          'Enum arguments cannot reference nonconstant members.');
    }
    final value = visitor.environment.get(node.name);
    if (value is InterpretedEnumValue ||
        value is BridgedEnumValue ||
        visitor.environment.isFunctionDeclaration(node.name) ||
        (value is RuntimeType && value is! NativeFunction)) {
      return;
    }
    throw RuntimeError(
        'Enum arguments cannot reference nonconstant variables.');
  }
}
