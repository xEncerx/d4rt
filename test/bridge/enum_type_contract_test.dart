import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

/// Native generic interface used by the bridge contract fixture.
abstract interface class HostPayload<T> {
  /// The payload exposed to interpreter consumers.
  T get value;
}

/// Native generic enum with observable factory and setter behavior.
enum HostBox<T extends num> implements HostPayload<T> {
  /// An explicitly instantiated integer constant.
  integer<int>(1),

  /// An inferred floating-point constant.
  inferred(2.5);

  const HostBox(this.value);
  @override

  /// The immutable generic payload.
  final T value;

  /// Shared mutable state observed by setters and static adapters.
  static int state = 0;

  /// Returns an existing constant rather than constructing an enum instance.
  factory HostBox.pick(int index) => values[index] as HostBox<T>;

  /// Reads shared state through an instance getter.
  int get external => state;

  /// Updates shared state through a legal enum instance setter.
  set external(int value) {
    state = value;
  }

  /// Deliberately overrides the declaration-name extension.
  String get name => 'override';
}

/// Native mixin applied through explicit enum bridge metadata.
mixin NativeLabel on Enum {
  /// The native label overridden by later mixins or enum members.
  String get label => 'native';
}

/// Public interpreter source shared by bridge tests and retained smoke proof.
const nativeEnumConsumer = r'''
import 'package:host/enum.dart';
main() {
  HostBox.state = 0;
  final pick = HostBox<int>.pick;
  final returned = pick(0);
  returned.external = 2;
  final before = returned.external++;
  ++returned.external;
  dynamic value = HostBox.integer;
  var failed = false;
  try { value as HostBox<double>; } catch (_) { failed = true; }
  final pattern = switch(returned) { HostPayload<int>(value: var n) => n, _ => -1 };
  return [value is HostBox<int>, value is HostBox<num>, value is HostBox<double>,
    HostBox.inferred is HostBox<double>, value is Enum, value is HostPayload<int>, failed, pattern,
    EnumName(value).name, Enum.compareByIndex(value, HostBox.inferred) < 0,
    HostBox.values.byName('inferred').value, returned.value, returned.name,
    EnumName(returned).name, before, HostBox.state, HostBox.values is List<HostBox<num>>];
}
''';

/// Observable native bridge consumer output.
const nativeEnumExpected = <Object?>[
  true,
  true,
  false,
  true,
  true,
  true,
  true,
  1,
  'integer',
  true,
  2.5,
  1,
  'override',
  'integer',
  2,
  4,
  true
];

/// Source exercising native and interpreted mixin dispatch and nominal types.
const nativeMixinConsumer = r'''
import 'package:host/mixin.dart';
mixin First { String get label => 'first'; static int marker = 7; }
mixin Last { String get label => 'last'; }
enum NativeLast with First, NativeLabel { a }
enum InterpretedLast with NativeLabel, Last { a }
enum Own with First, NativeLabel, Last { a; String get label => 'own'; }
main() => [NativeLast.a.label, InterpretedLast.a.label, Own.a.label,
  NativeLast.a is NativeLabel, NativeLast.a is First];
''';

/// Expected last-mixin and own-member precedence.
const nativeMixinExpected = <Object?>['native', 'last', 'own', true, true];

/// Registers native mixin adapters for real interpreted enum receivers.
D4rt nativeMixinInterpreter() {
  final interpreter = D4rt();
  interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: NativeLabel,
        name: 'NativeLabel',
        canBeUsedAsMixin: true,
        enumMixinMetadata: EnumMixinMetadata(
            typeMetadata: EnumTypeMetadata(), constraints: ['Enum']),
        getters: {
          'label': (visitor, target) {
            if (target is! InterpretedEnumValue) {
              throw StateError('Expected an interpreted enum receiver.');
            }
            return 'native';
          }
        },
      ),
      'package:host/mixin.dart');
  return interpreter;
}

/// Registers native enum adapters shared by regression and disposable smoke.
D4rt nativeEnumInterpreter() {
  final interpreter = D4rt();
  interpreter.registerBridgedClass(
      BridgedClass(
        nativeType: HostPayload,
        name: 'HostPayload',
        typeParameterCount: 1,
        getters: {'value': (visitor, target) => (target as HostPayload).value},
      ),
      'package:host/enum.dart');
  interpreter.registerBridgedEnum(
      BridgedEnumDefinition<HostBox>(
        name: 'HostBox',
        values: HostBox.values,
        typeMetadata: EnumTypeMetadata(
            typeParameters: ['T'],
            typeBounds: {'T': 'num'},
            supertypes: ['HostPayload<T>']),
        getters: {
          'value': (visitor, target) => (target as HostBox).value,
          'name': (visitor, target) => (target as HostBox).name,
          'external': (visitor, target) => (target as HostBox).external,
        },
        setters: {
          'external': (visitor, target, value) =>
              (target as HostBox).external = value as int
        },
        staticGetters: {'state': (visitor) => HostBox.state},
        staticSetters: {
          'state': (visitor, value) => HostBox.state = value as int
        },
        factories: {
          'pick': BridgedEnumFactory(
            signature: EnumSignature(
                [const EnumFormalParameter('index', NamedRuntimeType('int'))]),
            specializations: [
              BridgedEnumFactorySpecialization(
                  [const NamedRuntimeType('num')],
                  (visitor, arguments, named, types) =>
                      HostBox<num>.pick(arguments.single as int)),
              BridgedEnumFactorySpecialization(
                  [const NamedRuntimeType('int')],
                  (visitor, arguments, named, types) =>
                      HostBox<int>.pick(arguments.single as int)),
              BridgedEnumFactorySpecialization(
                  [const NamedRuntimeType('double')],
                  (visitor, arguments, named, types) =>
                      HostBox<double>.pick(arguments.single as int)),
            ],
          )
        },
      ),
      'package:host/enum.dart');
  return interpreter;
}

void main() {
  test('enum type keys have symmetric nominal equality and coherent hashes',
      () {
    const source = "import 'package:host/enum.dart'; main()=>HostBox<int>;";
    final first =
        nativeEnumInterpreter().execute(source: source) as AppliedRuntimeType;
    final second =
        nativeEnumInterpreter().execute(source: source) as AppliedRuntimeType;
    final plain = AppliedRuntimeType(first.baseType, first.typeArguments);
    for (final pair in [(first, second), (first, plain), (second, plain)]) {
      expect(pair.$1 == pair.$2, isTrue);
      expect(pair.$2 == pair.$1, isTrue);
      expect(pair.$1.hashCode, pair.$2.hashCode);
    }
    expect({first, second, plain}.length, 1);
    final different = nativeEnumInterpreter().execute(
        source: "import 'package:host/enum.dart'; main()=>HostBox<double>;");
    expect(first == different, isFalse);
    expect(D4rt().execute(source: '''
      enum E<T extends num> {a<int>(1);const E(this.n);final T n;}
      main() => [E<int> == E<int>, E<int> == E<double>,
        {E<int>, E<int>, E<double>}.length];
    '''), [true, false, 2]);
  });
  test(
      'native generic constants retain type arguments, interfaces and native results',
      () {
    final interpreter = nativeEnumInterpreter();
    const source = nativeEnumConsumer;
    const expected = nativeEnumExpected;
    expect(interpreter.execute(source: source), expected);
    expect(interpreter.executeCompiled(interpreter.compile(source: source)),
        expected);
    expect(
        interpreter.execute(
            source:
                "import 'package:host/enum.dart'; main()=>HostBox.integer;"),
        same(HostBox.integer));
    expect(
        interpreter.execute(
            source:
                "import 'package:host/enum.dart'; main()=>HostBox.pick(0);"),
        same(HostBox.integer));
  });

  test(
      'native and interpreted mixins preserve application order and receiver adapters',
      () {
    final interpreter = nativeMixinInterpreter();
    expect(
        interpreter.execute(source: nativeMixinConsumer), nativeMixinExpected);
    expect(
        interpreter
            .executeCompiled(interpreter.compile(source: nativeMixinConsumer)),
        nativeMixinExpected);
    expect(() => interpreter.execute(source: r'''
import 'package:host/mixin.dart';
mixin First { static int marker = 7; }
enum E with First { a }
main() => E.marker;
'''), throwsA(anything));
  });

  test('native mixin metadata enforces enum construction constraints', () {
    final interpreter = D4rt();
    interpreter.registerBridgedClass(
        BridgedClass(
          nativeType: NativeLabel,
          name: 'NativeLabel',
          canBeUsedAsMixin: true,
          enumMixinMetadata: EnumMixinMetadata(
              typeMetadata: EnumTypeMetadata(), constraints: ['String']),
        ),
        'package:host/mixin.dart');
    expect(
        () => interpreter.execute(
            source:
                "import 'package:host/mixin.dart'; enum E with NativeLabel { a } main()=>E.a;"),
        throwsA(anything));
  });
}
