import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/module_loader.dart';
import 'package:test/test.dart';

void main() {
  test('failed population can be corrected and retried on the same loader', () {
    final sources = <String, String>{
      'package:retry/retry.dart': '''
class RetryChild extends MissingBase {
  staleMethod() => 'stale';
}
''',
    };
    final loader = ModuleLoader(Environment(), sources, [], []);
    final uri = Uri.parse('package:retry/retry.dart');

    expect(
      () => loader.loadModule(uri),
      throwsA(
        isA<RuntimeError>().having(
          (error) => error.message,
          'message',
          contains("Superclass 'MissingBase' not found for class 'RetryChild'"),
        ),
      ),
    );

    sources[uri.toString()] = '''
class RetryChild {
  recoveredMethod() => 'recovered';
}

main() => RetryChild().recoveredMethod();
''';

    final loadedModule = loader.loadModule(uri);
    final retryClass = loadedModule.environment.get('RetryChild');
    final mainFunction = loadedModule.environment.get('main');

    expect(retryClass, isA<InterpretedClass>());
    expect(
      (retryClass as InterpretedClass).methods.keys,
      contains('recoveredMethod'),
    );
    expect(retryClass.methods.keys, isNot(contains('staleMethod')));
    expect(
      identical(
        retryClass,
        loadedModule.exportedEnvironment.get('RetryChild'),
      ),
      isTrue,
    );
    expect(mainFunction, isA<Callable>());
    expect(
      (mainFunction as Callable).call(
        loadedModule.interpreter,
        const [],
        const {},
      ),
      equals('recovered'),
    );
  });

  test('extension declaration visitation retains its null return contract', () {
    final d4rt = D4rt();
    d4rt.execute(source: 'void main() {}');
    final extension = parseString(
      content: '''
extension CompatibilityExtension on String {
  String decorated() => this + ':decorated';
}
''',
    ).unit.declarations.single as ExtensionDeclaration;

    final result = extension.accept<Object?>(d4rt.visitor!);

    expect(result, isNull);
    expect(d4rt.eval("'value'.decorated()"), equals('value:decorated'));
  });
}
