import 'package:d4rt/src/generator/generator_config.dart';
import 'package:d4rt/src/generator/metadata_collector.dart';
import 'package:test/test.dart';

void main() {
  test('collects metadata from analyzer 13 compositional AST nodes', () {
    const source = '''
class Marker {
  const Marker({required this.tag});

  final String tag;
}

@Marker(tag: 'model')
class Box<T extends num> {
  Box({this.value = 1});

  final int value;

  void transform(void callback(), {int count = 2}) {}
}

enum Status {
  ready,
  done;

  bool get complete => this == done;
}
''';
    const config = GeneratorConfig(inputPaths: [], outputPath: 'generated');

    final metadata =
        MetadataCollector(config: config).collectFromSource(source);

    expect(metadata.warnings, isEmpty);
    final box = metadata.classes.singleWhere((item) => item.name == 'Box');
    expect(box.typeParameters.single.name, 'T');
    expect(box.typeParameters.single.bound?.name, 'num');
    expect(box.annotations.single.namedArguments, {'tag': "'model'"});
    expect(box.constructors.single.parameters.single.name, 'value');
    expect(box.constructors.single.parameters.single.defaultValue, '1');

    final transform =
        box.methods.singleWhere((item) => item.name == 'transform');
    expect(transform.parameters.first.name, 'callback');
    expect(transform.parameters.first.type.name, 'Function');
    expect(transform.parameters.last.name, 'count');
    expect(transform.parameters.last.isNamed, isTrue);
    expect(transform.parameters.last.defaultValue, '2');

    final status = metadata.enums.single;
    expect(status.name, 'Status');
    expect(status.values.map((item) => item.name), ['ready', 'done']);
    expect(status.getters.single.name, 'complete');
  });

  test('preserves analyzer 8 parameter category metadata behavior', () {
    const source = '''
class Base {
  Base(this.inherited, [this.optionalInherited = 1]);

  final int inherited;
  final int optionalInherited;
}

class ParameterKinds extends Base {
  ParameterKinds(
    this.value,
    void this.callback(),
    super.inherited, [
    super.optionalInherited,
  ]);

  final int value;
  final void Function() callback;

  void requiredOrdinary(value) {}
  void optionalOrdinary([value]) {}
  void namedOrdinary({value}) {}
  void requiredNamedOrdinary({required value}) {}
  void functionTyped(void callback()) {}
  void optionalFunctionTyped([void callback()]) {}
  void namedFunctionTyped({void callback()}) {}
}

class NamedBase {
  NamedBase({
    required this.requiredNamedInherited,
    this.namedInherited = 2,
  });

  final int requiredNamedInherited;
  final int namedInherited;
}

class NamedSuperParameterKinds extends NamedBase {
  NamedSuperParameterKinds({
    required super.requiredNamedInherited,
    super.namedInherited,
  });
}

class OptionalFieldKinds {
  OptionalFieldKinds([this.value = 1]);

  final int value;
}

class NamedFieldKinds {
  NamedFieldKinds({this.value = 1});

  final int value;
}
''';
    const config = GeneratorConfig(inputPaths: [], outputPath: 'generated');

    final metadata =
        MetadataCollector(config: config).collectFromSource(source);

    expect(metadata.warnings, isEmpty);
    final parameterKinds =
        metadata.classes.singleWhere((item) => item.name == 'ParameterKinds');
    final constructorParameters = parameterKinds.constructors.single.parameters;
    expect(constructorParameters[0].type.name, 'int');
    expect(constructorParameters[1].type.name, 'void');
    expect(constructorParameters[2].type.name, 'int');
    expect(constructorParameters[3].type.name, 'int');

    final namedSuperParameterKinds = metadata.classes
        .singleWhere((item) => item.name == 'NamedSuperParameterKinds');
    final namedSuperParameters =
        namedSuperParameterKinds.constructors.single.parameters;
    expect(namedSuperParameters[0].type.name, 'int');
    expect(namedSuperParameters[1].type.name, 'int');

    final requiredOrdinary = parameterKinds.methods
        .singleWhere((item) => item.name == 'requiredOrdinary');
    expect(requiredOrdinary.parameters.single.type.name, 'dynamic');

    final optionalOrdinary = parameterKinds.methods
        .singleWhere((item) => item.name == 'optionalOrdinary');
    expect(optionalOrdinary.parameters.single.type.name, 'int');

    final namedOrdinary = parameterKinds.methods
        .singleWhere((item) => item.name == 'namedOrdinary');
    expect(namedOrdinary.parameters.single.type.name, 'int');

    final requiredNamedOrdinary = parameterKinds.methods
        .singleWhere((item) => item.name == 'requiredNamedOrdinary');
    expect(requiredNamedOrdinary.parameters.single.type.name, 'int');

    final functionTyped = parameterKinds.methods
        .singleWhere((item) => item.name == 'functionTyped');
    expect(functionTyped.parameters.single.type.name, 'Function');

    final optionalFunctionTyped = parameterKinds.methods
        .singleWhere((item) => item.name == 'optionalFunctionTyped');
    expect(optionalFunctionTyped.parameters.single.type.name, 'Function');

    final namedFunctionTyped = parameterKinds.methods
        .singleWhere((item) => item.name == 'namedFunctionTyped');
    expect(namedFunctionTyped.parameters.single.type.name, 'Function');

    final optionalFieldKinds = metadata.classes
        .singleWhere((item) => item.name == 'OptionalFieldKinds');
    expect(
      optionalFieldKinds.constructors.single.parameters.single.type.name,
      'int',
    );

    final namedFieldKinds =
        metadata.classes.singleWhere((item) => item.name == 'NamedFieldKinds');
    expect(
      namedFieldKinds.constructors.single.parameters.single.type.name,
      'int',
    );
  });
}
