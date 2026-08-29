import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  group('analyzer parameter compatibility', () {
    test('positional super formal stays dynamic and unnamed', () {
      final environment = Environment()
        ..define('int', const NamedRuntimeType('int'));
      final function = InterpretedFunction.constructor(
        _constructorFrom('''
class Base {
  Base(int value);
}

class Child extends Base {
  Child(int super.value);
}
'''),
        environment,
        null,
      );
      environment.define('constructor', function);

      final runtimeType = function.callableRuntimeType as FunctionRuntimeType;
      final introspection = IntrospectionBuilder.buildFromEnvironment(
        environment,
      ).functions.single;

      expect(runtimeType.name, 'dynamic Function(dynamic)');
      expect(runtimeType.positionalParameterTypes.single.name, 'dynamic');
      expect(runtimeType.requiredPositionalParameterCount, 1);
      expect(function.positionalParameterNames, isEmpty);
      expect(introspection.arity, 1);
      expect(introspection.parameterNames, isEmpty);
    });

    test('named super formal stays absent from runtime and introspection', () {
      final environment = Environment()
        ..define('int', const NamedRuntimeType('int'));
      final function = InterpretedFunction.constructor(
        _constructorFrom('''
class Base {
  Base({required int value});
}

class Child extends Base {
  Child({required int super.value});
}
'''),
        environment,
        null,
      );
      environment.define('constructor', function);

      final runtimeType = function.callableRuntimeType as FunctionRuntimeType;
      final introspection = IntrospectionBuilder.buildFromEnvironment(
        environment,
      ).functions.single;

      expect(runtimeType.name, 'Function');
      expect(runtimeType.namedParameterTypes, isEmpty);
      expect(runtimeType.requiredNamedParameters, isEmpty);
      expect(function.namedParameterNames, isEmpty);
      expect(introspection.namedParameterNames, isEmpty);
    });

    test('function-typed field formal keeps its declared return type', () {
      final function = InterpretedFunction.constructor(
        _constructorFrom('''
class CallbackHolder {
  CallbackHolder(void this.callback());

  final void Function() callback;
}
'''),
        Environment(),
        null,
      );

      final runtimeType = function.callableRuntimeType as FunctionRuntimeType;

      expect(runtimeType.positionalParameterTypes.single.name, 'void');
      expect(function.positionalParameterNames, ['callback']);
    });
  });
}

ConstructorDeclaration _constructorFrom(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: true).unit;
  final declaration = unit.declarations.whereType<ClassDeclaration>().last;
  return declaration.body.members.whereType<ConstructorDeclaration>().single;
}
