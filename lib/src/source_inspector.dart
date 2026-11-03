import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:d4rt/src/source_inspection.dart';

/// Extracts invocation-local facts without constructing an interpreter context.
SourceInspection inspectDartSource(String source) {
  final parsed = parseString(
    content: source,
    throwIfDiagnostics: false,
    featureSet: FeatureSet.latestLanguageVersion(),
  );
  final extractor = _Extractor();
  return SourceInspection(
    _span(parsed.unit),
    parsed.unit.directives.map(extractor.directive),
    parsed.unit.declarations.map(extractor.declaration),
    parsed.errors.map(
      (error) => SourceDiagnostic(
        SourceSpan(error.offset, error.length),
        switch (error.diagnosticCode.severity) {
          DiagnosticSeverity.ERROR => SourceDiagnosticSeverity.error,
          DiagnosticSeverity.WARNING => SourceDiagnosticSeverity.warning,
          _ => SourceDiagnosticSeverity.info,
        },
        error.diagnosticCode.lowerCaseName,
        error.message,
      ),
    ),
  );
}

SourceSpan _span(AstNode node) => SourceSpan(node.offset, node.length);

final class _Extractor {
  final _types = <TypeAnnotation, SourceType>{};
  final _fields = <FieldDeclaration, SourceVariables>{};

  SourceType type(TypeAnnotation node) => _types.putIfAbsent(
    node,
    () => SourceType(
      _span(node),
      kind: switch (node) {
        NamedType() => SourceTypeKind.named,
        GenericFunctionType() => SourceTypeKind.function,
        RecordTypeAnnotation() => SourceTypeKind.record,
      },
      name: node is NamedType ? node.name.lexeme : null,
      prefix: node is NamedType ? node.importPrefix?.name.lexeme : null,
      isNullable: node.question != null,
      hasTypeArguments: node is NamedType && node.typeArguments != null,
      arguments: node is NamedType
          ? node.typeArguments?.arguments.map(type) ?? const []
          : const [],
    ),
  );

  SourceDirective directive(Directive node) => SourceDirective(
    _span(node),
    kind: switch (node) {
      ImportDirective() => SourceDirectiveKind.import,
      ExportDirective() => SourceDirectiveKind.export,
      LibraryDirective() => SourceDirectiveKind.library,
      PartDirective() => SourceDirectiveKind.part,
      PartOfDirective() => SourceDirectiveKind.partOf,
    },
    uri: node is UriBasedDirective ? node.uri.stringValue : null,
    prefix: node is ImportDirective ? node.prefix?.name : null,
    isDeferred: node is ImportDirective && node.deferredKeyword != null,
    isConditional: node is NamespaceDirective && node.configurations.isNotEmpty,
    hasCombinators: node is NamespaceDirective && node.combinators.isNotEmpty,
  );

  SourceDeclaration declaration(AstNode node) {
    switch (node) {
      case ClassDeclaration():
        return owner(
          node,
          SourceDeclarationKind.classType,
          node.namePart.typeName.lexeme,
          node.body.members,
          modifiers: {
            if (node.finalKeyword != null) 'final',
            if (node.abstractKeyword != null) 'abstract',
            if (node.baseKeyword != null) 'base',
            if (node.interfaceKeyword != null) 'interface',
            if (node.sealedKeyword != null) 'sealed',
            if (node.mixinKeyword != null) 'mixin',
          },
          sealedSpan: node.sealedKeyword == null
              ? null
              : SourceSpan(
                  node.sealedKeyword!.offset,
                  node.sealedKeyword!.length,
                ),
          superclass: node.extendsClause?.superclass,
          withClause: node.withClause,
          implementsClause: node.implementsClause,
        );
      case MixinDeclaration():
        return owner(
          node,
          SourceDeclarationKind.mixin,
          node.name.lexeme,
          node.body.members,
          modifiers: {if (node.baseKeyword != null) 'base'},
          constraints: node.onClause?.superclassConstraints ?? const [],
          implementsClause: node.implementsClause,
        );
      case EnumDeclaration():
        return owner(
          node,
          SourceDeclarationKind.enumType,
          node.namePart.typeName.lexeme,
          node.body.members,
          withClause: node.withClause,
          implementsClause: node.implementsClause,
          constants: node.body.constants.map(
            (constant) => SourceEnumConstant(
              _span(constant),
              constant.name.lexeme,
              constant.arguments?.argumentList.arguments.map(
                    (argument) => expression(argument.argumentExpression),
                  ) ??
                  const [],
            ),
          ),
        );
      case ExtensionDeclaration():
        return owner(
          node,
          SourceDeclarationKind.extension,
          node.name?.lexeme,
          node.body.members,
        );
      case ExtensionTypeDeclaration():
        return owner(
          node,
          SourceDeclarationKind.extensionType,
          node.namePart.typeName.lexeme,
          node.body.members,
          implementsClause: node.implementsClause,
        );
      case MethodDeclaration():
        return callable(
          node,
          SourceDeclarationKind.method,
          node.name.lexeme,
          node.parameters,
          node.body,
          returnType: node.returnType,
          hasTypeParameters: node.typeParameters != null,
          isStatic: node.isStatic,
          isGetter: node.isGetter,
          isSetter: node.isSetter,
          isExternal: node.externalKeyword != null,
        );
      case FunctionDeclaration():
        final function = node.functionExpression;
        return callable(
          node,
          SourceDeclarationKind.function,
          node.name.lexeme,
          function.parameters,
          function.body,
          returnType: node.returnType,
          hasTypeParameters: function.typeParameters != null,
          isGetter: node.isGetter,
          isSetter: node.isSetter,
          isExternal: node.externalKeyword != null,
        );
      case ConstructorDeclaration():
        return callable(
          node,
          SourceDeclarationKind.constructor,
          node.name?.lexeme,
          node.parameters,
          node.body,
          isFactory: node.factoryKeyword != null,
          isConst: node.constKeyword != null,
          isExternal: node.externalKeyword != null,
          isRedirecting:
              node.redirectedConstructor != null ||
              node.initializers.any(
                (initializer) =>
                    initializer is RedirectingConstructorInvocation,
              ),
          initializerCount: node.initializers.length,
        );
      case FieldDeclaration():
        return field(node);
      case TopLevelVariableDeclaration():
        return variables(node, node.variables, false);
      case TypeAlias():
        return SourceOtherDeclaration(
          _span(node),
          SourceDeclarationKind.alias,
          node.name.lexeme,
        );
      default:
        return SourceOtherDeclaration(
          _span(node),
          SourceDeclarationKind.other,
          null,
        );
    }
  }

  SourceTypeDeclaration owner(
    AstNode node,
    SourceDeclarationKind kind,
    String? name,
    Iterable<ClassMember> members, {
    Set<String> modifiers = const {},
    SourceSpan? sealedSpan,
    NamedType? superclass,
    WithClause? withClause,
    ImplementsClause? implementsClause,
    Iterable<NamedType> constraints = const [],
    Iterable<SourceEnumConstant> constants = const [],
  }) {
    final extractedMembers = members.map(declaration).toList();
    final visitor = _SyntaxOccurrences(this);
    node.accept(visitor);
    return SourceTypeDeclaration(
      _span(node),
      kind,
      name,
      modifiers: modifiers,
      sealedSpan: sealedSpan,
      superclass: superclass == null ? null : type(superclass),
      mixins: withClause?.mixinTypes.map(type) ?? const [],
      interfaces: implementsClause?.interfaces.map(type) ?? const [],
      constraints: constraints.map(type),
      hasWithClause: withClause != null,
      hasImplementsClause: implementsClause != null,
      members: extractedMembers,
      constants: constants,
      syntax: visitor.occurrences,
    );
  }

  SourceCallable callable(
    AstNode node,
    SourceDeclarationKind kind,
    String? name,
    FormalParameterList? parameters,
    FunctionBody body, {
    TypeAnnotation? returnType,
    bool hasTypeParameters = false,
    bool isStatic = false,
    bool isGetter = false,
    bool isSetter = false,
    bool isExternal = false,
    bool isFactory = false,
    bool isConst = false,
    bool isRedirecting = false,
    int initializerCount = 0,
  }) => SourceCallable(
    _span(node),
    kind,
    name,
    returnType: returnType == null ? null : type(returnType),
    parameters: parameters?.parameters.map(parameter) ?? const [],
    hasTypeParameters: hasTypeParameters,
    isStatic: isStatic,
    isGetter: isGetter,
    isSetter: isSetter,
    isExternal: isExternal,
    isFactory: isFactory,
    isConst: isConst,
    isRedirecting: isRedirecting,
    initializerCount: initializerCount,
    bodyKind: switch (body) {
      EmptyFunctionBody() => SourceBodyKind.empty,
      ExpressionFunctionBody() => SourceBodyKind.expression,
      _ => SourceBodyKind.block,
    },
    bodySpan: _span(body),
    isAsync: body.isAsynchronous,
    isGenerator: body.star != null,
  );

  SourceParameter parameter(FormalParameter node) => SourceParameter(
    _span(node),
    name: node.name?.lexeme,
    type: node.type == null ? null : type(node.type!),
    form: switch (node) {
      FieldFormalParameter() => SourceParameterForm.field,
      SuperFormalParameter() => SourceParameterForm.superFormal,
      RegularFormalParameter() => SourceParameterForm.regular,
    },
    kind: node.isRequiredPositional
        ? SourceParameterKind.requiredPositional
        : node.isOptionalPositional
        ? SourceParameterKind.optionalPositional
        : node.isRequiredNamed
        ? SourceParameterKind.requiredNamed
        : SourceParameterKind.optionalNamed,
    hasModifier: node.constFinalOrVarKeyword != null,
    isCovariant: node.covariantKeyword != null,
    isFunctionTyped: node.functionTypedSuffix != null,
    defaultValue: node.defaultClause == null
        ? null
        : expression(node.defaultClause!.value),
  );

  SourceVariables field(FieldDeclaration node) => _fields.putIfAbsent(
    node,
    () => variables(node, node.fields, node.isStatic),
  );

  SourceVariables variables(
    AstNode node,
    VariableDeclarationList list,
    bool isStatic,
  ) => SourceVariables(
    _span(node),
    isStatic: isStatic,
    type: list.type == null ? null : type(list.type!),
    variables: list.variables.map(
      (variable) => SourceVariable(
        _span(variable),
        variable.name.lexeme,
        variable.initializer == null ? null : expression(variable.initializer!),
      ),
    ),
  );

  SourceExpression expression(AstNode node) {
    final kind = switch (node) {
      IntegerLiteral() || DoubleLiteral() => SourceExpressionKind.number,
      BooleanLiteral() ||
      NullLiteral() ||
      SimpleStringLiteral() => SourceExpressionKind.literal,
      ParenthesizedExpression() => SourceExpressionKind.parenthesized,
      PrefixExpression() => SourceExpressionKind.prefix,
      ListLiteral() => SourceExpressionKind.list,
      SetOrMapLiteral() => SourceExpressionKind.setOrMap,
      MapLiteralEntry() => SourceExpressionKind.mapEntry,
      _ => SourceExpressionKind.other,
    };
    final Iterable<AstNode> children = switch (node) {
      ParenthesizedExpression() => [node.expression],
      PrefixExpression() => [node.operand],
      ListLiteral() => node.elements,
      SetOrMapLiteral() => node.elements,
      MapLiteralEntry() => [node.key, node.value],
      _ => const <AstNode>[],
    };
    return SourceExpression(
      _span(node),
      kind,
      operator: node is PrefixExpression ? node.operator.lexeme : null,
      children: children.map(expression),
    );
  }
}

final class _SyntaxOccurrences extends RecursiveAstVisitor<void> {
  _SyntaxOccurrences(this.extractor);

  final _Extractor extractor;
  final occurrences = <SourceNode>[];

  @override
  void visitNamedType(NamedType node) {
    occurrences.add(extractor.type(node));
    super.visitNamedType(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    occurrences.add(extractor.field(node));
    super.visitFieldDeclaration(node);
  }
}
