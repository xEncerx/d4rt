import 'dart:convert';
import 'dart:io';
import 'package:d4rt/src/generator/code_emitter.dart';
import 'package:d4rt/src/generator/generator_config.dart';
import 'package:d4rt/src/generator/metadata_collector.dart';
import 'package:d4rt/src/generator/transform_pipeline.dart';
import 'package:test/test.dart';

/// Native source exercising generated enum fields, setters, factories and types.
const generatedEnumNativeSource = r'''
abstract interface class HostPayload<T> { T get value; }
abstract interface class HostReadable<T> implements HostPayload<T> {}
class NativeRecord { const NativeRecord(this.value); final int value; }
class NativeBase { const NativeBase(); }
abstract interface class NativeParent<T> {}
class NativeChild extends NativeBase implements NativeParent<List<String>> {
  const NativeChild();
}
class NativeWrong { const NativeWrong(); }
enum CustomBound<T extends NativeBase> {
  child<NativeChild>();
  const CustomBound();
  static int calls = 0;
  factory CustomBound.choose() { calls++; return child as CustomBound<T>; }
}
enum NestedBound<T extends NativeParent<List<String>>> {
  child<NativeChild>();
  const NestedBound();
  factory NestedBound.choose() => child as NestedBound<T>;
}
enum Wired<T extends num> implements HostReadable<T> {
  integer<int>(1), floating(2.5);
  const Wired(this.value);
  @override
  final T value;
  static int state = 0;
  factory Wired.pick(int index) => values[index] as Wired<T>;
  int get current => state;
  set current(int value) { state = value; }
  String get name => 'custom';
  @override
  String toString() => 'wired:$value';
}
enum Pick<T extends num> {
  low<int>(1), high<int>(2);
  const Pick(this.value);
  final T value;
  static int calls = 0;
  factory Pick.choose() {
    calls++;
    return (T == int ? high : low) as Pick<T>;
  }
  factory Pick.from(T value, {T? other}) => Pick<T>.choose();
  factory Pick.nested(List<T> values) => Pick<T>.choose();
  factory Pick.redirect() = Pick<T>.choose;
  factory Pick.optional([T? value]) => Pick<T>.choose();
  factory Pick.concrete(int Function() make) {
    final value = make();
    return (value == 1 ? high : low) as Pick<T>;
  }
  factory Pick.callback(T Function() make) => Pick<T>.from(make());
  static Pick<int> ordinary() => high;
}
enum Pair<A extends num, B extends Object?> {
  first<int, String>(1, 'one'), second<double, bool>(2.0, true);
  const Pair(this.left, this.right);
  final A left;
  final B right;
  static int calls = 0;
  factory Pair.choose(A left, B right) {
    calls++;
    return (A == int && B == String ? first : second) as Pair<A, B>;
  }
  factory Pair.defaults([A? left, B? right]) =>
      (A == int && B == String ? first : second) as Pair<A, B>;
}
enum NativeChoice<T extends num> {
  integer<int>.constant(1), floating<double>.constant(2.0);
  const NativeChoice.constant(this.value);
  final T value;
  factory NativeChoice() =>
      (T == int ? integer : floating) as NativeChoice<T>;
}
enum NullablePick<T extends Object?> {
  none<Null>(null), text<String>('text');
  const NullablePick(this.value);
  final T value;
  static int calls = 0;
  factory NullablePick.choose(T value) {
    calls++;
    return (T == String ? text : none) as NullablePick<T>;
  }
}
class NativeDriver {
  static int twice(int Function() callback) => callback() + callback();
  static List<int> list() => <int>[1, 2];
}
enum Plain { a; factory Plain.pick() => a; static Plain ordinary() => a; }
enum NativeKey { first }
enum EnumBound<T extends Enum> {
  first<NativeKey>();
  const EnumBound();
  factory EnumBound.choose() => first as EnumBound<T>;
}
enum Retained {
  ready;
  static int Function(int?)? _callback;
  static Future<int> Function()? _asyncCallback;
  static void retainOrdinary(int Function(int?) callback) {
    _callback = callback;
  }
  factory Retained.retain(int Function(int?) callback) {
    _callback = callback;
    return ready;
  }
  factory Retained.retainAsync(Future<int> Function() callback) {
    _asyncCallback = callback;
    return ready;
  }
  static int invoke(int? value) => _callback!(value);
  static Future<int> invokeAsync() => _asyncCallback!();
}
''';

/// Interpreter consumer run against the real generated native enum adapters.
const generatedEnumConsumer = r'''
import 'package:generated/enums.dart';
enum ImportedPayload { a(NativeRecord(4)); const ImportedPayload(this.record); final NativeRecord record; }
main() {
  Wired.state = 1;
  final pick = Wired<int>.pick;
  final value = pick(0);
  value.current += 2;
  final before = value.current++;
  final pattern = switch (value) { HostPayload<int>(value: var n) => n, _ => -1 };
  return [value.value, value.name, EnumName(value).name, value.toString(), before,
    Wired.state, value is Wired<int>, value is Wired<double>, value is HostReadable<int>,
    value is HostPayload<int>, Wired.floating is Wired<double>, pattern,
    Wired.values.byName('integer').value, Wired.values is List<Wired<num>>,
    ImportedPayload.a.record.value, value.runtimeType == Wired<int>];
}
''';

/// Observable expected output, independent of generator implementation details.
const generatedEnumExpected = <Object?>[
  1,
  'custom',
  'integer',
  'wired:1',
  3,
  4,
  true,
  false,
  true,
  true,
  true,
  1,
  1,
  true,
  4,
  true,
];

/// T-sensitive consumer, including correlated tuples and native callback use.
const generatedFactoryConsumer = r'''
import 'package:generated/enums.dart' as host;
class NativeRecord {}
main() {
  int make() => 1;
  host.Pick.calls = 0;
  host.Pair.calls = 0;
  final fixed = host.Pick<int>.choose;
  final callbackFactory = host.Pick<int>.callback;
  final nested = host.Pick<int>.nested;
  host.Pick<int> Function() contextual = host.Pick.choose;
  final explicitReference = host.Pick.choose<int>;
  late host.Pick<int> Function() lateContextual = host.Pick.choose;
  final escaped = () => fixed().index;
  final inferred = host.Pick.from;
  final callback = host.NativeDriver.twice(() => escaped());
  final picks = [host.Pick<int>.choose().index, host.Pick.choose().index,
    fixed().index, fixed().index, inferred(1).index,
    host.Pick.from(1, other: 2).index, host.Pick.from(1, other: 2.0).index,
    host.Pick.nested(<int>[1]).index, host.Pick<int>.redirect().index,
    host.Pick.ordinary().index, callback, contextual().index,
    explicitReference().index, lateContextual().index,
    host.Pick.optional().index, host.Pick.optional(1).index,
    nested(<int>[1]).index, nested(<int>[2]).index,
    host.Pick<int>.concrete(make).index, host.Pick.callback(make).index,
    callbackFactory(make).index];
  final pairs = [host.Pair<int, String>.choose(1, 'one').index,
    host.Pair.choose(2.0, true).index, host.Pair<num, Object?>.choose(1, null).index,
    host.Pair.defaults().index];
  final nullable = [host.NullablePick.choose(null).index,
    host.NullablePick.choose('value').index];
  final sourceKnown = host.NullablePick<host.NativeRecord?>.choose(null).index;
  final nullableBefore = host.NullablePick.calls;
  var interpreterOnlyFailed = false;
  try { host.NullablePick<NativeRecord?>.choose(null); }
  catch (_) { interpreterOnlyFailed = true; }
  final choices = [host.NativeChoice<int>().index, host.NativeChoice().index];
  final custom = [host.CustomBound<host.NativeChild>.choose().index,
    host.CustomBound.choose().index, host.CustomBound.child is host.CustomBound<host.NativeBase>,
    host.NestedBound<host.NativeChild>.choose().index, host.NestedBound.choose().index];
  final customBefore = host.CustomBound.calls;
  var customFailed = false;
  try { host.CustomBound<host.NativeWrong>.choose(); } catch (_) { customFailed = true; }
  final before = host.Pick.calls;
  final pairBefore = host.Pair.calls;
  var evaluated = 0;
  var failure = false;
  int argument() { evaluated++; return 1; }
  var typeFailed = false;
  try { host.Pick<int>.optional('bad'); } catch (_) { typeFailed = true; }
  try { host.Pick<double>.from(argument()); } catch (_) { failure = true; }
  var pairFailed = false;
  try { host.Pair<int, bool>.choose(1, true); } catch (_) { pairFailed = true; }
  var staticFailed = false;
  try { final bad = host.Pick<int>.ordinary; } catch (_) { staticFailed = true; }
  var boundsFailed = false;
  try { host.Pick<String>.choose(); } catch (_) { boundsFailed = true; }
  var shapeFailed = false;
  try { host.Pick.from(1, extra: 2); } catch (_) { shapeFailed = true; }
  var callbackRejected = false;
  try { host.Pick.callback(() {host.Pick.calls++;return 1;}); }
  catch (_) { callbackRejected = true; }
  return [picks, pairs, nullable, choices, host.Pick.calls == before,
    host.Pair.calls == pairBefore, evaluated,
    failure, pairFailed,
    staticFailed, boundsFailed, shapeFailed, host.NativeDriver.list() is List<int>,
    typeFailed, host.Plain.pick().index, host.Plain.ordinary().index,
    host.Wired<double>.pick(1).index, sourceKnown, interpreterOnlyFailed,
    host.NullablePick.calls == nullableBefore, custom, customFailed,
    host.CustomBound.calls == customBefore, callbackRejected];
}
''';

/// Expected body selection, failure ordering and unchanged general bridging.
const generatedFactoryExpected = <Object?>[
  [1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 2, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1],
  [0, 1, 1, 1],
  [0, 1],
  [0, 1],
  true,
  true,
  1,
  true,
  true,
  true,
  true,
  true,
  true,
  true,
  0,
  0,
  1,
  0,
  true,
  true,
  [0, 0, true, 0, 0],
  true,
  true,
  true
];

/// Generates, loads and executes native adapters through public D4rt entry points.
///
/// Passing [retainedDirectory] retains fixtures for the independent runtime gate.
Future<Map<String, dynamic>> runGeneratedEnumProof(
    {Directory? retainedDirectory}) async {
  final directory = retainedDirectory ??
      await Directory.systemTemp.createTemp('d4rt-generated-enum-');
  await directory.create(recursive: true);
  try {
    final packageFile =
        File('${Directory.current.path}/.dart_tool/package_config.json');
    final configuration =
        jsonDecode(await packageFile.readAsString()) as Map<String, dynamic>;
    final packages = configuration['packages'] as List<dynamic>;
    for (final raw in packages) {
      final item = raw as Map<String, dynamic>;
      item['rootUri'] = packageFile.absolute.uri
          .resolve(item['rootUri'] as String)
          .toString();
    }
    packages.add({
      'name': 'enum_generated',
      'rootUri': directory.absolute.uri.toString(),
      'packageUri': './',
      'languageVersion': '3.0'
    });
    final temporaryPackages = File('${directory.path}/package_config.json');
    await temporaryPackages.writeAsString(jsonEncode(configuration));
    await File('${directory.path}/native.dart')
        .writeAsString(generatedEnumNativeSource);
    const config = GeneratorConfig(
        inputPaths: [],
        outputPath: '',
        includeAbstractClasses: true,
        enumFactoryTypeArguments: {
          'Wired': [
            ['double']
          ],
          'NullablePick': [
            ['NativeRecord?']
          ],
        },
        additionalImports: ['package:enum_generated/native.dart']);
    await File('${directory.path}/generator_config.json')
        .writeAsString(jsonEncode(config.toJson()));
    final metadata = MetadataCollector(config: config)
        .collectFromSource(generatedEnumNativeSource);
    final transformed = TransformPipeline(config: config).transform(metadata);
    final emitter = CodeEmitter(config: config);
    final imports = <String>[];
    final registrations = <String>[];
    for (final type in transformed.classes) {
      final file = '${type.name.toLowerCase()}_bridge.dart';
      await File('${directory.path}/$file')
          .writeAsString(emitter.emitSingleClass(type));
      imports.add("import 'package:enum_generated/$file';");
      final variable =
          '${type.name[0].toLowerCase()}${type.name.substring(1)}Bridge';
      registrations.add(
          "interpreter.registerBridgedClass($variable, 'package:generated/enums.dart');");
    }
    for (final type in transformed.enums) {
      final file = '${type.name.toLowerCase()}_bridge.dart';
      await File('${directory.path}/$file')
          .writeAsString(emitter.emitSingleEnum(type));
      imports.add("import 'package:enum_generated/$file';");
      final variable =
          '${type.name[0].toLowerCase()}${type.name.substring(1)}Bridge';
      registrations.add(
          "interpreter.registerBridgedEnum($variable, 'package:generated/enums.dart');");
    }
    imports.sort();
    final mainFile = File('${directory.path}/main.dart');
    await mainFile.writeAsString('''
import 'dart:convert';
import 'dart:io';
import 'package:d4rt/d4rt.dart';
import 'package:enum_generated/native.dart';
${imports.join('\n')}
Future<void> main() async {
  final interpreter = D4rt();
  ${registrations.join('\n  ')}
  const source = ${jsonEncode(generatedEnumConsumer)};
  final direct = await interpreter.execute(source: source);
  final compiled = await interpreter.executeCompiled(interpreter.compile(source: source));
  final identity = identical(interpreter.execute(source: "import 'package:generated/enums.dart'; main()=>Wired.pick(0);"), Wired.integer);
  const factorySource = ${jsonEncode(generatedFactoryConsumer)};
  final factoryModes = <String, Object?>{};
  for (final mode in ['direct', 'compiled', 'imported', 'compiledImported']) {
    final imported = mode == 'imported' || mode == 'compiledImported';
    final program = imported
        ? "import 'package:generated/consumer.dart' as consumer; main() => consumer.main();"
        : factorySource;
    final sources = {'package:generated/consumer.dart': factorySource};
    factoryModes[mode] = mode == 'compiled' || mode == 'compiledImported'
        ? await interpreter.executeCompiled(interpreter.compile(source: program), sources: sources)
        : await interpreter.execute(source: program, sources: sources);
  }
  final factoryIdentity = identical(interpreter.execute(
      source: "import 'package:generated/enums.dart'; main()=>Pick<int>.choose();"), Pick.high);
  final nativeSelection = [Pick<int>.choose().index, Pick<num>.choose().index,
    NativeChoice<int>().index, NativeChoice<num>().index];
  final collision = interpreter.execute(source: """
import 'package:generated/enums.dart' as host;
class NativeRecord {}
main() {
  final before = host.NullablePick.calls;
  var rejected = false;
  try { host.NullablePick<NativeRecord?>.choose(null); }
  catch (_) { rejected = true; }
  return [rejected, host.NullablePick.calls == before];
}
""");
  const retainedSource = """
import 'package:generated/enums.dart' as host;
int work(int? n) {if(n==-1)pause();var count=0;while(count<1000){count++;}return count+(n??0);}
Future<int> asyncWork() async {await Future.value(0);return work(null);}
main() {
  host.Retained.retain(work);
  host.Retained.retainAsync(asyncWork);
  return host.Retained.invoke(3);
}
""";
  var pauses = 0;
  interpreter.registertopLevelFunction('pause', (visitor, args, named, types) {
    pauses++;
    sleep(const Duration(milliseconds: 200));
    return null;
  });
  final retainedInitial = await interpreter.execute(
      source: retainedSource, timeout: const Duration(seconds: 1));
  final retainedLimits = <bool>[];
  for (final call in ['invoke(null)', 'invokeAsync()']) {
    try {
      await interpreter.execute(
          source: "import 'package:generated/enums.dart' as host;main()=>host.Retained.\$call;",
          maxSteps: 100);
      retainedLimits.add(false);
    } on ExecutionLimitException {
      retainedLimits.add(true);
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  final retainedFresh = await interpreter.execute(
      source: "import 'package:generated/enums.dart' as host;main() async=>[host.Retained.invoke(null),await host.Retained.invokeAsync()];",
      maxSteps: 20000, timeout: const Duration(seconds: 5));
  var retainedTimeout = false;
  try {
    await interpreter.execute(
        source: "import 'package:generated/enums.dart' as host;main()=>host.Retained.invoke(-1);",
        timeout: const Duration(milliseconds: 100));
  } on ExecutionTimeoutException {
    retainedTimeout = true;
  }
  final ordinaryInitial = await interpreter.execute(
      source: "import 'package:generated/enums.dart' as host;main(){host.Retained.retainOrdinary((int? n)=>n??9);return host.Retained.invoke(null);}");
  final ordinaryFresh = await interpreter.execute(
      source: "import 'package:generated/enums.dart' as host;main()=>host.Retained.invoke(4);");
  var outsideRejected = false;
  try { Retained.invoke(null); } on RuntimeError { outsideRejected = true; }
  final enumBound = await interpreter.execute(
      source: "import 'package:generated/enums.dart' as host;main()=>[host.EnumBound<host.NativeKey>.choose().index,host.EnumBound.choose().index,host.NativeKey.first is Enum];");
  final nativeEnumBound = [EnumBound<NativeKey>.choose().index,
      EnumBound<Enum>.choose().index, NativeKey.first is Enum];
  print(jsonEncode({'direct': direct, 'compiled': compiled, 'nativeIdentity': identity,
    'factoryModes': factoryModes, 'factoryIdentity': factoryIdentity,
    'nativeSelection': nativeSelection, 'interpreterNominalCollision': collision,
    'retained': [retainedInitial, retainedLimits, retainedFresh, retainedTimeout, pauses, ordinaryInitial, ordinaryFresh, outsideRejected],
    'enumBound': enumBound, 'nativeEnumBound': nativeEnumBound}));
}
''');
    final formatted = await Process.run(
        Platform.resolvedExecutable, ['format', directory.path]);
    if (formatted.exitCode != 0) {
      throw StateError('Generated enum formatting failed: ${formatted.stderr}');
    }
    final process = await Process.run(Platform.resolvedExecutable,
        ['--packages=${temporaryPackages.path}', mainFile.path],
        workingDirectory: Directory.current.path);
    if (process.exitCode != 0) {
      throw StateError(
          'Generated enum runtime failed (${process.exitCode}): ${process.stderr}\n${process.stdout}');
    }
    final result =
        jsonDecode((process.stdout as String).trim()) as Map<String, dynamic>;
    if (jsonEncode(result['direct']) != jsonEncode(generatedEnumExpected) ||
        jsonEncode(result['compiled']) != jsonEncode(generatedEnumExpected) ||
        result['nativeIdentity'] != true) {
      throw StateError('Generated enum consumer mismatch: $result');
    }
    final modes = result['factoryModes'] as Map<String, dynamic>;
    if (modes.length != 4 ||
        modes.values.any((value) =>
            jsonEncode(value) != jsonEncode(generatedFactoryExpected)) ||
        result['factoryIdentity'] != true ||
        jsonEncode(result['nativeSelection']) != '[1,0,0,1]' ||
        jsonEncode(result['interpreterNominalCollision']) != '[true,true]') {
      throw StateError('Generated factory mismatch: $result');
    }
    if (jsonEncode(result['retained']) !=
            '[1003,[true,true],[1000,1000],true,1,9,4,true]' ||
        jsonEncode(result['enumBound']) != '[0,0,true]' ||
        jsonEncode(result['nativeEnumBound']) != '[0,0,true]') {
      throw StateError(
          'Retained callback or native enum bound mismatch: $result');
    }
    return result;
  } finally {
    if (retainedDirectory == null) await directory.delete(recursive: true);
  }
}

void main() {
  test(
      'generated enum bridge executes fields setters factories and transitive generic interfaces',
      () async {
    final result = await runGeneratedEnumProof();
    expect(result['direct'], generatedEnumExpected);
    expect(result['compiled'], generatedEnumExpected);
    expect(result['nativeIdentity'], isTrue);
    expect((result['factoryModes'] as Map).values,
        everyElement(generatedFactoryExpected));
  });
  test('invalid compiled tuple configuration fails instead of guessing', () {
    for (final tuples in [
      [
        ['int', 'String']
      ],
      [
        ['String']
      ],
      [
        ['int'],
        ['int']
      ],
      [
        ['Missing']
      ],
      [
        ['Alias']
      ],
      [
        ['List']
      ],
      [
        ['int>ignored']
      ],
    ]) {
      final config = GeneratorConfig(
          inputPaths: [],
          outputPath: '',
          enumFactoryTypeArguments: {'Pick': tuples});
      final metadata = MetadataCollector(config: config)
          .collectFromSource(generatedEnumNativeSource);
      expect(() => TransformPipeline(config: config).transform(metadata),
          throwsA(anything),
          reason:
              'Invalid exact capability $tuples must not compile a fallback.');
    }
  });
  test('custom native source bounds reject invalid compiled tuples', () {
    const config = GeneratorConfig(
        inputPaths: [],
        outputPath: '',
        enumFactoryTypeArguments: {
          'CustomBound': [
            ['NativeWrong']
          ]
        });
    final metadata = MetadataCollector(config: config)
        .collectFromSource(generatedEnumNativeSource);
    expect(() => TransformPipeline(config: config).transform(metadata),
        throwsA(anything));
  });
}
