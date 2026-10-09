import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/d4rt.dart';

/// Resolves a generic argument while retaining its nullable marker.
RuntimeType resolveRuntimeTypeArgument(TypeAnnotation node, Environment env) {
  final type = resolveRuntimeTypeAnnotation(node, env);
  return node.question == null || type is NullableEnumArgument
      ? type
      : NullableEnumArgument(type);
}

/// Resolves an annotation in its lexical scope, retaining enum instantiations.
RuntimeType resolveRuntimeTypeAnnotation(
  TypeAnnotation? typeNode,
  Environment env, {
  bool isAsync = false,
}) {
  if (typeNode == null) {
    return const NamedRuntimeType('dynamic');
  }

  if (typeNode is NamedType) {
    if (isAsync && typeNode.name.lexeme == 'Future') {
      final futureTypeArguments = typeNode.typeArguments?.arguments;
      if (futureTypeArguments != null && futureTypeArguments.isNotEmpty) {
        return resolveRuntimeTypeAnnotation(futureTypeArguments.first, env);
      }
      return const NamedRuntimeType('dynamic');
    }

    final typeName = typeNode.name.lexeme;
    if (typeName == 'void') {
      return const NamedRuntimeType('void');
    }
    if (typeName == 'Never') {
      return const NamedRuntimeType('Never');
    }
    if (typeName == 'dynamic') {
      return const NamedRuntimeType('dynamic');
    }
    if (typeName == 'Function') {
      return FunctionRuntimeType.untyped();
    }
    if (typeName == 'Record') {
      return RecordRuntimeType(const [], const {});
    }

    final resolved = env.get(typeNode.importPrefix == null
        ? typeName
        : '${typeNode.importPrefix!.name.lexeme}.$typeName');
    if (resolved is! RuntimeType) {
      throw RuntimeError(
          "Symbol '$typeName' resolved to non-type value: $resolved");
    }

    if (typeNode.typeArguments != null &&
        typeNode.typeArguments!.arguments.isNotEmpty) {
      final resolvedTypeArguments = typeNode.typeArguments!.arguments
          .map((argument) => resolveRuntimeTypeArgument(argument, env))
          .toList();
      if (resolved is InterpretedEnum) {
        return resolved.instantiate(resolvedTypeArguments);
      }
      if (resolved is BridgedEnum) {
        return resolved.instantiate(resolvedTypeArguments);
      }
      return AppliedRuntimeType(resolved, resolvedTypeArguments);
    }

    if (resolved is InterpretedEnum) return resolved.instantiate(null);
    if (resolved is BridgedEnum) return resolved.instantiate(null);
    return resolved;
  }

  if (typeNode is GenericFunctionType) {
    return resolveFunctionRuntimeType(
        typeNode.returnType, typeNode.parameters, env,
        typeParameterCount:
            typeNode.typeParameters?.typeParameters.length ?? 0);
  }

  if (typeNode is RecordTypeAnnotation) {
    final positionalTypes = typeNode.positionalFields
        .map((field) => resolveRuntimeTypeAnnotation(field.type, env))
        .toList();
    final namedTypes = <String, RuntimeType>{};
    final namedFields = typeNode.namedFields;

    if (namedFields != null) {
      for (final field in namedFields.fields) {
        namedTypes[field.name.lexeme] =
            resolveRuntimeTypeAnnotation(field.type, env);
      }
    }

    return RecordRuntimeType(positionalTypes, namedTypes);
  }

  throw RuntimeError(
      'Unsupported type annotation for constraint: ${typeNode.runtimeType}');
}

/// Normalizes actual callback formals without reconstructing source or AST nodes.
FunctionRuntimeType resolveFunctionRuntimeType(TypeAnnotation? returnType,
    FormalParameterList parameters, Environment environment,
    {int typeParameterCount = 0}) {
  final positional = <RuntimeType>[];
  final named = <String, RuntimeType>{};
  final requiredNamed = <String>{};
  var requiredPositional = 0;
  for (final parameter in parameters.parameters) {
    final type = _resolveFormalParameterType(parameter, environment);
    final name = _resolveFormalParameterName(parameter);
    if (parameter.isNamed && name != null) {
      named[name] = type;
      if (parameter.isRequiredNamed) requiredNamed.add(name);
    } else {
      positional.add(type);
      if (parameter.isRequiredPositional) requiredPositional++;
    }
  }
  return FunctionRuntimeType(
      returnType: resolveRuntimeTypeArgumentOrDynamic(returnType, environment),
      positionalParameterTypes: positional,
      requiredPositionalParameterCount: requiredPositional,
      namedParameterTypes: named,
      requiredNamedParameters: requiredNamed,
      typeParameterCount: typeParameterCount);
}

/// Resolves an optional annotation while preserving genuine nullable type nodes.
RuntimeType resolveRuntimeTypeArgumentOrDynamic(
        TypeAnnotation? annotation, Environment environment) =>
    annotation == null
        ? const NamedRuntimeType('dynamic')
        : resolveRuntimeTypeArgument(annotation, environment);

RuntimeType _resolveFormalParameterType(
    FormalParameter parameter, Environment env) {
  if (parameter is RegularFormalParameter) {
    if (parameter.functionTypedSuffix != null) {
      final suffix = parameter.functionTypedSuffix!;
      final function = resolveFunctionRuntimeType(
          parameter.type, suffix.formalParameters, env,
          typeParameterCount:
              suffix.typeParameters?.typeParameters.length ?? 0);
      return suffix.question == null ? function : nullableEnumType(function);
    }
    return resolveRuntimeTypeArgumentOrDynamic(parameter.type, env);
  }

  if (parameter is FieldFormalParameter) {
    return resolveRuntimeTypeArgumentOrDynamic(parameter.type, env);
  }

  return const NamedRuntimeType('dynamic');
}

String? _resolveFormalParameterName(FormalParameter parameter) {
  if (parameter is RegularFormalParameter ||
      parameter is FieldFormalParameter) {
    return parameter.name?.lexeme;
  }

  return null;
}
