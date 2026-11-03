import 'package:d4rt/src/source_inspector.dart';

/// Parses one source without resolving imports, types, or executing any code.
///
/// Recovery facts may be present alongside errors; callers requiring valid
/// syntax must check [SourceInspection.hasErrors] before using them.
SourceInspection inspectSource({required String source}) =>
    inspectDartSource(source);

/// A half-open range measured in UTF-16 code units of the original source.
///
/// Parser recovery diagnostics at EOF may extend one code unit beyond input.
final class SourceSpan {
  /// Creates a range, including zero-length recovery ranges at end of input.
  const SourceSpan(this.offset, this.length);

  /// The inclusive start offset.
  final int offset;

  /// The number of code units.
  final int length;

  /// The exclusive end offset.
  int get end => offset + length;
}

/// A source fact with its original syntax range.
abstract class SourceNode {
  /// Creates a source fact.
  const SourceNode(this.span);

  /// The original range, including any attached declaration metadata.
  final SourceSpan span;
}

/// Parser diagnostic severity, independent of the parser implementation.
enum SourceDiagnosticSeverity { error, warning, info }

/// A parser diagnostic; no import or semantic analysis diagnostics are produced.
final class SourceDiagnostic extends SourceNode {
  /// Creates a parser diagnostic.
  const SourceDiagnostic(super.span, this.severity, this.code, this.message);

  /// The parser severity.
  final SourceDiagnosticSeverity severity;

  /// The parser diagnostic identifier.
  final String code;

  /// The parser's message, which may contain source text.
  final String message;
}

/// The immutable, occurrence-preserving inventory of one source.
final class SourceInspection extends SourceNode {
  /// Creates a source inventory.
  SourceInspection(
    super.span,
    Iterable<SourceDirective> directives,
    Iterable<SourceDeclaration> declarations,
    Iterable<SourceDiagnostic> diagnostics,
  ) : directives = List.unmodifiable(directives),
      declarations = List.unmodifiable(declarations),
      diagnostics = List.unmodifiable(diagnostics);

  /// Directives in source order, including non-import directives.
  final List<SourceDirective> directives;

  /// Root declarations in source order, without privacy filtering or deduplication.
  final List<SourceDeclaration> declarations;

  /// Parser diagnostics in parser order.
  final List<SourceDiagnostic> diagnostics;

  /// Whether syntax errors were reported.
  bool get hasErrors =>
      diagnostics.any((d) => d.severity == SourceDiagnosticSeverity.error);
}

/// Directive syntax categories.
enum SourceDirectiveKind { import, export, library, part, partOf }

/// An import, export, or other root directive.
final class SourceDirective extends SourceNode {
  /// Creates directive syntax facts.
  const SourceDirective(
    super.span, {
    required this.kind,
    this.uri,
    this.prefix,
    this.isDeferred = false,
    this.isConditional = false,
    this.hasCombinators = false,
  });

  /// The syntactic directive category.
  final SourceDirectiveKind kind;

  /// The decoded URI, absent for non-URI or nonconstant URI syntax.
  final String? uri;

  /// The declared import prefix.
  final String? prefix;

  /// Whether the import is deferred.
  final bool isDeferred;

  /// Whether conditional configurations are present.
  final bool isConditional;

  /// Whether show or hide combinators are present.
  final bool hasCombinators;
}

/// Declared type syntax, not inferred or resolved types.
enum SourceTypeKind { named, function, record }

/// A type annotation and its generic arguments as written.
final class SourceType extends SourceNode {
  /// Creates type syntax facts.
  SourceType(
    super.span, {
    required this.kind,
    this.name,
    this.prefix,
    this.isNullable = false,
    this.hasTypeArguments = false,
    Iterable<SourceType> arguments = const [],
  }) : arguments = List.unmodifiable(arguments);

  /// The annotation form.
  final SourceTypeKind kind;

  /// The unqualified name for named syntax only.
  final String? name;

  /// The syntactic import prefix, without resolution.
  final String? prefix;

  /// Whether a trailing question mark is present.
  final bool isNullable;

  /// Whether an explicit type argument list is present.
  final bool hasTypeArguments;

  /// Declared generic arguments in source order.
  final List<SourceType> arguments;

  /// Canonical unprefixed, nonnullable named syntax, or null for other shapes.
  ///
  /// This does not resolve aliases, type parameters, or names.
  String? get canonicalName {
    if (kind != SourceTypeKind.named || prefix != null || isNullable) {
      return null;
    }
    if (arguments.isEmpty) return name;
    final names = <String>[];
    for (final argument in arguments) {
      final value = argument.canonicalName;
      if (value == null) return null;
      names.add(value);
    }
    return '$name<${names.join(',')}>';
  }
}

/// Declaration forms, retaining distinctions relevant to source consumers.
enum SourceDeclarationKind {
  classType,
  mixin,
  enumType,
  extension,
  extensionType,
  alias,
  function,
  method,
  constructor,
  variables,
  other,
}

/// Common declaration identity and range.
abstract class SourceDeclaration extends SourceNode {
  /// Creates a declaration fact.
  const SourceDeclaration(super.span, this.kind, this.name);

  /// The declared form.
  final SourceDeclarationKind kind;

  /// The syntactic name, absent for unnamed extensions and variable groups.
  final String? name;
}

/// A class, mixin, enum, extension, or extension type and its declared members.
final class SourceTypeDeclaration extends SourceDeclaration {
  /// Creates a type declaration inventory.
  SourceTypeDeclaration(
    super.span,
    super.kind,
    super.name, {
    Iterable<String> modifiers = const [],
    this.sealedSpan,
    this.superclass,
    Iterable<SourceType> mixins = const [],
    Iterable<SourceType> interfaces = const [],
    Iterable<SourceType> constraints = const [],
    this.hasWithClause = false,
    this.hasImplementsClause = false,
    Iterable<SourceDeclaration> members = const [],
    Iterable<SourceEnumConstant> constants = const [],
    Iterable<SourceNode> syntax = const [],
  }) : modifiers = Set.unmodifiable(modifiers),
       mixins = List.unmodifiable(mixins),
       interfaces = List.unmodifiable(interfaces),
       constraints = List.unmodifiable(constraints),
       members = List.unmodifiable(members),
       constants = List.unmodifiable(constants),
       syntax = List.unmodifiable(syntax);

  /// Explicit declaration modifiers.
  final Set<String> modifiers;

  /// The sealed keyword range, when present.
  final SourceSpan? sealedSpan;

  /// The declared superclass, if any.
  final SourceType? superclass;

  /// Declared with-clause types.
  final List<SourceType> mixins;

  /// Declared implements-clause types.
  final List<SourceType> interfaces;

  /// Declared mixin on-clause constraints.
  final List<SourceType> constraints;

  /// Whether a with clause is present, including recovered empty clauses.
  final bool hasWithClause;

  /// Whether an implements clause is present.
  final bool hasImplementsClause;

  /// Explicit members only, preserving duplicates and order.
  final List<SourceDeclaration> members;

  /// Enum constants in source order.
  final List<SourceEnumConstant> constants;

  /// Named-type and field occurrences in recursive syntax visitation order.
  ///
  /// Includes types inside bodies, annotations, and nested generic syntax.
  /// Field groups precede their descendant types; no executable AST is retained.
  final List<SourceNode> syntax;

  /// Names introduced by members, without deduplication.
  Iterable<String> memberNames({bool instanceOnly = false}) sync* {
    for (final member in members) {
      if (member is SourceCallable) {
        if (member.kind == SourceDeclarationKind.constructor) {
          if (!instanceOnly && member.name != null) yield member.name!;
        } else if (!instanceOnly || !member.isStatic) {
          yield member.name!;
        }
      } else if (member is SourceVariables &&
          (!instanceOnly || !member.isStatic)) {
        yield* member.variables.map((variable) => variable.name);
      }
    }
  }
}

/// Function body syntax categories.
enum SourceBodyKind { empty, block, expression }

/// An explicitly declared function, method, accessor, or constructor.
final class SourceCallable extends SourceDeclaration {
  /// Creates callable syntax facts.
  SourceCallable(
    super.span,
    super.kind,
    super.name, {
    this.returnType,
    Iterable<SourceParameter> parameters = const [],
    this.hasTypeParameters = false,
    this.isStatic = false,
    this.isGetter = false,
    this.isSetter = false,
    this.isExternal = false,
    this.isFactory = false,
    this.isConst = false,
    this.isRedirecting = false,
    this.initializerCount = 0,
    required this.bodyKind,
    required this.bodySpan,
    this.isAsync = false,
    this.isGenerator = false,
  }) : parameters = List.unmodifiable(parameters);

  /// Explicit return annotation; null means no annotation was written.
  final SourceType? returnType;

  /// Explicit parameters in source order.
  final List<SourceParameter> parameters;

  /// Whether a type parameter list was written.
  final bool hasTypeParameters;

  /// Whether static was written.
  final bool isStatic;

  /// Whether this is getter syntax.
  final bool isGetter;

  /// Whether this is setter syntax.
  final bool isSetter;

  /// Whether external was written.
  final bool isExternal;

  /// Whether factory was written.
  final bool isFactory;

  /// Whether const was written.
  final bool isConst;

  /// Whether a constructor has redirect syntax.
  final bool isRedirecting;

  /// The number of explicit constructor initializers.
  final int initializerCount;

  /// The body form.
  final SourceBodyKind bodyKind;

  /// The complete body range, including async/generator keywords.
  final SourceSpan bodySpan;

  /// Whether the body is async.
  final bool isAsync;

  /// Whether the body has a generator star.
  final bool isGenerator;
}

/// Formal parameter syntax form.
enum SourceParameterForm { regular, field, superFormal }

/// Formal parameter optionality and calling convention.
enum SourceParameterKind {
  requiredPositional,
  optionalPositional,
  requiredNamed,
  optionalNamed,
}

/// A formal parameter, without inference from fields or super constructors.
final class SourceParameter extends SourceNode {
  /// Creates formal parameter facts.
  const SourceParameter(
    super.span, {
    this.name,
    this.type,
    required this.form,
    required this.kind,
    this.hasModifier = false,
    this.isCovariant = false,
    this.isFunctionTyped = false,
    this.defaultValue,
  });

  /// The declared name, if present.
  final String? name;

  /// The explicitly written type.
  final SourceType? type;

  /// The formal parameter syntax form.
  final SourceParameterForm form;

  /// The calling convention.
  final SourceParameterKind kind;

  /// Whether const, final, or var was written.
  final bool hasModifier;

  /// Whether covariant was written.
  final bool isCovariant;

  /// Whether an old-style function-typed suffix is present.
  final bool isFunctionTyped;

  /// The default syntax, not its evaluated value.
  final SourceExpression? defaultValue;
}

/// A field or root variable declaration group.
final class SourceVariables extends SourceDeclaration {
  /// Creates a variable group.
  SourceVariables(
    SourceSpan span, {
    required this.isStatic,
    this.type,
    required Iterable<SourceVariable> variables,
  }) : variables = List.unmodifiable(variables),
       super(span, SourceDeclarationKind.variables, null);

  /// Whether this is an explicitly static field.
  final bool isStatic;

  /// The group's explicit type annotation.
  final SourceType? type;

  /// Individual variables, including wildcard names.
  final List<SourceVariable> variables;
}

/// One explicitly declared variable.
final class SourceVariable extends SourceNode {
  /// Creates a variable syntax fact.
  const SourceVariable(super.span, this.name, this.initializer);

  /// The declared name.
  final String name;

  /// The initializer syntax, if written.
  final SourceExpression? initializer;
}

/// An enum constant's arguments, without invoking its constructor.
final class SourceEnumConstant extends SourceNode {
  /// Creates an enum constant fact.
  SourceEnumConstant(
    super.span,
    this.name,
    Iterable<SourceExpression> arguments,
  ) : arguments = List.unmodifiable(arguments);

  /// The constant name.
  final String name;

  /// Argument expressions in source order, with named argument labels removed.
  final List<SourceExpression> arguments;
}

/// Initializer shapes; unlisted syntax remains explicitly [other].
enum SourceExpressionKind {
  number,
  literal,
  parenthesized,
  prefix,
  list,
  setOrMap,
  mapEntry,
  other,
}

/// A compact initializer syntax summary, not an executable expression tree.
final class SourceExpression extends SourceNode {
  /// Creates an initializer syntax summary.
  SourceExpression(
    super.span,
    this.kind, {
    this.operator,
    Iterable<SourceExpression> children = const [],
  }) : children = List.unmodifiable(children);

  /// The syntactic shape.
  final SourceExpressionKind kind;

  /// The unary operator for prefix syntax.
  final String? operator;

  /// Operands, collection elements, or map key/value pairs in source order.
  ///
  /// Unsupported collection elements are represented by [SourceExpressionKind.other].
  final List<SourceExpression> children;
}

/// A named alias or unsupported declaration, preserving its occurrence.
final class SourceOtherDeclaration extends SourceDeclaration {
  /// Creates a declaration identity fact.
  const SourceOtherDeclaration(super.span, super.kind, super.name);
}
