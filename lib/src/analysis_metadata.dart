import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/d4rt.dart';

/// Collects declaration descriptions without resolving or evaluating expressions.
/// Bindings carry their own metadata through the loader's normal namespace rules.
class AnalysisMetadata {
  static IntrospectionResult buildResult(Environment environment) {
    final functions = <FunctionInfo>[];
    final classes = <ClassInfo>[];
    final variables = <VariableInfo>[];
    final enums = <EnumInfo>[];
    final extensions = <ExtensionInfo>[];
    for (final declaration in environment.values.values) {
      switch (declaration) {
        case FunctionInfo():
          functions.add(declaration);
        case ClassInfo():
          classes.add(declaration);
        case VariableInfo():
          variables.add(declaration);
        case EnumInfo():
          enums.add(declaration);
        case ExtensionInfo():
          extensions.add(declaration);
      }
    }
    return IntrospectionResult(
      functions: functions,
      classes: classes,
      variables: variables,
      enums: enums,
      extensions: extensions,
    );
  }

  static void declare(CompilationUnit unit, Environment environment) {
    for (final declaration in unit.declarations) {
      switch (declaration) {
        case FunctionDeclaration():
          final parameters =
              declaration.functionExpression.parameters?.parameters;
          final body = declaration.functionExpression.body;
          environment.define(
            declaration.name.lexeme,
            FunctionInfo(
              name: declaration.name.lexeme,
              arity:
                  parameters?.where((p) => p.isRequiredPositional).length ?? 0,
              parameterNames: [
                for (final parameter in parameters ?? <FormalParameter>[])
                  if (parameter.isPositional && parameter.name != null)
                    parameter.name!.lexeme,
              ],
              namedParameterNames: [
                for (final parameter in parameters ?? <FormalParameter>[])
                  if (parameter.isNamed && parameter.name != null)
                    parameter.name!.lexeme,
              ],
              returnType: declaration.returnType?.toSource(),
              isAsync: body.isAsynchronous,
              isGenerator: body.isGenerator,
            ),
          );
        case TopLevelVariableDeclaration():
          final list = declaration.variables;
          for (final variable in list.variables) {
            if (variable.name.lexeme == '_') continue;
            environment.define(
              variable.name.lexeme,
              VariableInfo(
                name: variable.name.lexeme,
                declaredType: list.type?.toSource(),
                valueType: 'unavailable',
                isValueAvailable: false,
                isFinal: list.isFinal,
                isConst: list.isConst,
                isLate: list.lateKeyword != null,
              ),
            );
          }
        case ClassDeclaration():
          final interfaces = _types(declaration.implementsClause?.interfaces);
          final mixins = _types(declaration.withClause?.mixinTypes);
          final superclass = declaration.extendsClause?.superclass.toSource();
          final info = _classInfo(
            declaration.namePart.typeName.lexeme,
            declaration.body.members,
            interfaces: interfaces,
            mixins: mixins,
            superTypes: [?superclass, ...interfaces, ...mixins],
            isAbstract: declaration.abstractKeyword != null,
          );
          environment.define(info.name, info);
        case MixinDeclaration():
          final interfaces = _types(declaration.implementsClause?.interfaces);
          final info = _classInfo(
            declaration.name.lexeme,
            declaration.body.members,
            interfaces: interfaces,
            superTypes: [
              ..._types(declaration.onClause?.superclassConstraints),
              ...interfaces,
            ],
          );
          environment.define(info.name, info);
        case EnumDeclaration():
          final name = declaration.namePart.typeName.lexeme;
          environment.define(
            name,
            EnumInfo(
              name: name,
              values: [
                for (final value in declaration.body.constants)
                  value.name.lexeme,
              ],
              methods: _methods(declaration.body.members),
            ),
          );
        case ExtensionDeclaration():
          final onType =
              declaration.onClause?.extendedType.toSource() ?? 'unknown';
          final name =
              declaration.name?.lexeme ?? '<unnamed extension on $onType>';
          // Unnamed extensions are local declarations, never exported names.
          environment.define(
            declaration.name?.lexeme ?? '_<extension at ${declaration.offset}>',
            ExtensionInfo(
              name: name,
              onType: onType,
              methods: _methods(declaration.body.members),
            ),
          );
        case ExtensionTypeDeclaration():
          final name = declaration.namePart.typeName.lexeme;
          final constructor =
              declaration.namePart as PrimaryConstructorDeclaration;
          environment.define(
            name,
            ExtensionInfo(
              name: name,
              onType: constructor.formalParameters.parameters.single.type!
                  .toSource(),
              methods: _methods(declaration.body.members),
            ),
          );
      }
    }
  }

  static List<String> _types(Iterable<NamedType>? types) => [
    for (final type in types ?? <NamedType>[]) type.toSource(),
  ];

  static List<String> _methods(Iterable<ClassMember> members) => {
    for (final member in members)
      if (member is MethodDeclaration) member.name.lexeme,
  }.toList();

  static ClassInfo _classInfo(
    String name,
    Iterable<ClassMember> members, {
    List<String> superTypes = const [],
    List<String> interfaces = const [],
    List<String> mixins = const [],
    bool isAbstract = false,
  }) => ClassInfo(
    name: name,
    superTypes: superTypes,
    interfaces: interfaces,
    mixins: mixins,
    isAbstract: isAbstract,
    methods: _methods(members),
    fields: [
      for (final member in members)
        if (member is FieldDeclaration)
          for (final field in member.fields.variables) field.name.lexeme,
    ],
    constructors: [
      name,
      for (final member in members)
        if (member is ConstructorDeclaration && member.name != null)
          member.name!.lexeme,
    ],
  );

  /// Reads registered descriptions, never native adapters or native values.
  static DeclarationInfo describeBinding(String name, Object? value) {
    if (value is DeclarationInfo) return value;
    if (value is NativeFunction) {
      return FunctionInfo(name: name, arity: value.arity);
    }
    if (value is BridgedClass) {
      return ClassInfo(
        name: name,
        methods: {
          ...value.methods.keys,
          ...value.getters.keys,
          ...value.setters.keys,
          ...value.staticMethods.keys,
        }.toList(),
        constructors: [
          for (final key in value.constructors.keys) key.isEmpty ? name : key,
        ],
      );
    }
    if (value is BridgedEnum) {
      return EnumInfo(
        name: name,
        values: value.values.keys.toList(),
        methods: value.methods.keys.toList(),
      );
    }
    return VariableInfo(
      name: name,
      valueType: 'unavailable',
      isValueAvailable: false,
    );
  }
}
