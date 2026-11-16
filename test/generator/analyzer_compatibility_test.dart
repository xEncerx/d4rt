import 'package:d4rt/src/generator/generator_config.dart';
import 'package:d4rt/src/generator/metadata_collector.dart';
import 'package:d4rt/src/generator/transform_pipeline.dart';
import 'package:test/test.dart';

void main() {
  test('collects generic class and enum metadata from source', () {
    const source = '''
class Marker { const Marker({required this.tag}); final String tag; }
@Marker(tag: 'model')
class Box<T extends num> {
  Box({this.value = 1});
  final int value;
  void transform(void callback(), {int count = 2}) {}
}
enum Status { ready, done; bool get complete => this == done; }
''';
    const config = GeneratorConfig(inputPaths: [], outputPath: '');
    final metadata = MetadataCollector(
      config: config,
    ).collectFromSource(source);
    expect(metadata.warnings, isEmpty);
    final box = metadata.classes.singleWhere((item) => item.name == 'Box');
    expect(box.typeParameters.single.name, 'T');
    expect(box.typeParameters.single.bound?.name, 'num');
    expect(box.annotations.single.namedArguments, {'tag': "'model'"});
    expect(box.constructors.single.parameters.single.name, 'value');
    expect(box.constructors.single.parameters.single.defaultValue, '1');
    final method = box.methods.singleWhere((item) => item.name == 'transform');
    expect(method.parameters.map((p) => p.name), ['callback', 'count']);
    expect(method.parameters.first.type.name, 'Function');
    expect(method.parameters.last.isNamed, isTrue);
    expect(method.parameters.last.defaultValue, '2');
    final status = metadata.enums.single;
    expect(status.values.map((item) => item.name), ['ready', 'done']);
    expect(status.getters.single.name, 'complete');
  });
  test('collects constructor and method parameter categories', () {
    const source = '''
class Base {
  Base(this.inherited, [this.optionalInherited = 1]);
  final int inherited;
  final int optionalInherited;
}
class ParameterKinds extends Base {
  ParameterKinds(this.value, void this.callback(), super.inherited,
      [super.optionalInherited]);
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
  NamedBase({required this.requiredNamedInherited, this.namedInherited = 2});
  final int requiredNamedInherited;
  final int namedInherited;
}
class NamedSuperParameterKinds extends NamedBase {
  NamedSuperParameterKinds({required super.requiredNamedInherited, super.namedInherited});
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
    const config = GeneratorConfig(inputPaths: [], outputPath: '');
    final metadata = MetadataCollector(
      config: config,
    ).collectFromSource(source);
    expect(metadata.warnings, isEmpty);
    final kind = metadata.classes.singleWhere(
      (item) => item.name == 'ParameterKinds',
    );
    expect(kind.constructors.single.parameters.map((p) => p.name), [
      'value',
      'callback',
      'inherited',
      'optionalInherited',
    ]);
    expect(kind.constructors.single.parameters.map((p) => p.type.name), [
      'int',
      'void',
      'int',
      'int',
    ]);
    for (final entry in {
      'requiredOrdinary': 'dynamic',
      'optionalOrdinary': 'int',
      'namedOrdinary': 'int',
      'requiredNamedOrdinary': 'int',
      'functionTyped': 'Function',
      'optionalFunctionTyped': 'Function',
      'namedFunctionTyped': 'Function',
    }.entries) {
      expect(
        kind.methods
            .singleWhere((m) => m.name == entry.key)
            .parameters
            .single
            .name,
        entry.key.contains('FunctionTyped') || entry.key == 'functionTyped'
            ? 'callback'
            : 'value',
      );
      expect(
        kind.methods
            .singleWhere((m) => m.name == entry.key)
            .parameters
            .single
            .type
            .name,
        entry.value,
      );
    }
    final namedSuper = metadata.classes
        .singleWhere((item) => item.name == 'NamedSuperParameterKinds')
        .constructors
        .single
        .parameters;
    expect(namedSuper.map((p) => p.name), [
      'requiredNamedInherited',
      'namedInherited',
    ]);
    expect(namedSuper.map((p) => p.type.name), ['int', 'int']);
    expect(namedSuper.map((p) => p.isNamed), [true, true]);
    expect(namedSuper.map((p) => p.isRequired), [true, false]);
    for (final entry in {
      'OptionalFieldKinds': false,
      'NamedFieldKinds': true,
    }.entries) {
      final parameter = metadata.classes
          .singleWhere((item) => item.name == entry.key)
          .constructors
          .single
          .parameters
          .single;
      expect(parameter.name, 'value');
      expect(parameter.type.name, 'int');
      expect(parameter.isNamed, entry.value);
      expect(parameter.isRequired, isFalse);
      expect(parameter.defaultValue, '1');
    }
    for (final entry in {
      'requiredOrdinary': [false, true],
      'optionalOrdinary': [false, false],
      'namedOrdinary': [true, false],
      'requiredNamedOrdinary': [true, true],
      'functionTyped': [false, true],
      'optionalFunctionTyped': [false, false],
      'namedFunctionTyped': [true, false],
    }.entries) {
      final parameter = kind.methods
          .singleWhere((m) => m.name == entry.key)
          .parameters
          .single;
      expect([parameter.isNamed, parameter.isRequired], entry.value);
    }
  });

  const source = '''
class NativeBase { const NativeBase(); }
class NativeChild extends NativeBase { const NativeChild(); }
class NativeWrong { const NativeWrong(); }
enum Pick<T extends num> {
  low<int>(1), high<int>(2);
  const Pick(this.value);
  final T value;
  factory Pick.choose() => low as Pick<T>;
}
enum CustomBound<T extends NativeBase> {
  child<NativeChild>();
  const CustomBound();
  factory CustomBound.choose() => child as CustomBound<T>;
}
''';

  test('invalid enum factory type tuples are rejected', () {
    for (final tuples in [
      [
        ['int', 'String'],
      ],
      [
        ['String'],
      ],
      [
        ['int'],
        ['int'],
      ],
      [
        ['Missing'],
      ],
      [
        ['Alias'],
      ],
      [
        ['List'],
      ],
      [
        ['int>ignored'],
      ],
    ]) {
      final config = GeneratorConfig(
        inputPaths: [],
        outputPath: '',
        enumFactoryTypeArguments: {'Pick': tuples},
      );
      final metadata = MetadataCollector(
        config: config,
      ).collectFromSource(source);
      expect(
        () => TransformPipeline(config: config).transform(metadata),
        throwsA(anything),
        reason: 'Invalid tuple $tuples',
      );
    }
  });

  test('native bounds reject unrelated configured types', () {
    const config = GeneratorConfig(
      inputPaths: [],
      outputPath: '',
      enumFactoryTypeArguments: {
        'CustomBound': [
          ['NativeWrong'],
        ],
      },
    );
    final metadata = MetadataCollector(
      config: config,
    ).collectFromSource(source);
    expect(
      () => TransformPipeline(config: config).transform(metadata),
      throwsA(anything),
    );
  });
}
