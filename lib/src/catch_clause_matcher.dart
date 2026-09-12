import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/src/environment.dart';
import 'package:d4rt/src/exceptions.dart';
import 'package:d4rt/src/runtime_types.dart';
import 'package:d4rt/src/utils/logger/logger.dart';

/// Finds the first catch clause matching an interpreted thrown value.
CatchClause? findMatchingCatchClause(
  Iterable<CatchClause> clauses,
  Object? thrownValue,
  Environment environment,
) {
  for (final clause in clauses) {
    if (catchClauseMatches(clause, thrownValue, environment)) {
      return clause;
    }
  }
  return null;
}

/// Determines whether a catch clause accepts an interpreted thrown value.
bool catchClauseMatches(
  CatchClause clause,
  Object? thrownValue,
  Environment environment,
) {
  final exceptionType = clause.exceptionType;
  if (exceptionType == null) {
    return true;
  }
  if (exceptionType is! NamedType) {
    Logger.warn(
      '[CatchClauseMatcher] Unsupported catch clause type node: '
      '${exceptionType.runtimeType}',
    );
    return false;
  }

  final typeName = exceptionType.name.lexeme;
  final importPrefix = exceptionType.importPrefix?.name.lexeme;
  if (importPrefix == null) {
    switch (typeName) {
      case 'int':
        return thrownValue is int;
      case 'double':
        return thrownValue is double;
      case 'num':
        return thrownValue is num;
      case 'String':
        return thrownValue is String;
      case 'bool':
        return thrownValue is bool;
      case 'List':
        return thrownValue is List;
      case 'Null':
        return thrownValue == null;
      case 'Object':
        return thrownValue != null;
      case 'dynamic':
        return true;
      case 'void':
        return false;
    }
  }

  try {
    late final Environment lookupEnvironment;
    if (importPrefix == null) {
      lookupEnvironment = environment;
    } else {
      final prefixedEnvironment = environment.get(importPrefix);
      if (prefixedEnvironment is! Environment) {
        return false;
      }
      lookupEnvironment = prefixedEnvironment;
    }
    final targetType = lookupEnvironment.get(typeName);
    return targetType is InterpretedClass &&
        thrownValue is InterpretedInstance &&
        thrownValue.klass.isSubtypeOf(targetType);
  } on RuntimeError catch (error) {
    Logger.warn(
      "[CatchClauseMatcher] Error resolving catch clause type "
      "'${importPrefix == null ? typeName : '$importPrefix.$typeName'}': "
      '$error',
    );
    return false;
  }
}
