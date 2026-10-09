import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

enum Choice<T extends num> {
  low<int>(1),
  high<int>(2);

  const Choice(this.value);
  final T value;
  factory Choice.choose() => (T == int ? high : low) as Choice<T>;
}

D4rt factoryInterpreter(List<List<RuntimeType>> observations,
    {bool slow = false}) {
  final interpreter = D4rt();
  Object? invoke(List<RuntimeType> types, bool integer) {
    observations.add(types);
    if (slow) {
      final clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(milliseconds: 150)) {}
    }
    return integer ? Choice<int>.choose() : Choice<num>.choose();
  }

  interpreter.registerBridgedEnum(
      BridgedEnumDefinition<Choice>(
          name: 'Choice',
          values: Choice.values,
          typeMetadata:
              EnumTypeMetadata(typeParameters: ['T'], typeBounds: {'T': 'num'}),
          factories: {
            'choose': BridgedEnumFactory(
                signature: EnumSignature([]),
                specializations: [
                  BridgedEnumFactorySpecialization(
                      [const NamedRuntimeType('num')],
                      (visitor, positional, named, types) =>
                          invoke(types, false)),
                  BridgedEnumFactorySpecialization(
                      [const NamedRuntimeType('int')],
                      (visitor, positional, named, types) =>
                          invoke(types, true)),
                ])
          }),
      'package:host/choice.dart');
  return interpreter;
}

/// Exercises immutable vector ownership through the public bind/invoke APIs.
List<Object?> runEnumVectorOwnershipCorrection() {
  final observations = <List<RuntimeType>>[];
  final immutable = <bool>[];
  final registration = BridgedEnumDefinition<Choice>(
    name: 'Choice',
    values: Choice.values,
    typeMetadata:
        EnumTypeMetadata(typeParameters: ['T'], typeBounds: {'T': 'num'}),
    factories: {
      'choose':
          BridgedEnumFactory(signature: EnumSignature([]), specializations: [
        BridgedEnumFactorySpecialization([const NamedRuntimeType('int')],
            (visitor, positional, named, types) {
          observations.add(types);
          try {
            types[0] = const NamedRuntimeType('num');
            immutable.add(false);
          } on UnsupportedError {
            immutable.add(true);
          }
          return Choice.high;
        }),
      ]),
    },
  );
  final owner = registration.buildBridgedEnum();
  final input = <RuntimeType>[const NamedRuntimeType('int')];
  final bound = owner.factories['choose']!.bind(owner, 'choose', input);
  input[0] = const NamedRuntimeType('num');
  final interpreter = D4rt()
    ..registerBridgedEnum(registration, 'package:host/choice.dart')
    ..registertopLevelFunction(
        'bound', (visitor, args, named, types) => bound.call(visitor, []))
    ..registertopLevelFunction(
        'explicit',
        (visitor, args, named, types) => owner.factories['choose']!
            .bind(owner, 'choose')
            .call(
                visitor, [], {}, <RuntimeType>[const NamedRuntimeType('int')]));
  final values = interpreter.execute(
      source:
          "import 'package:host/choice.dart'; main()=>[bound().index,bound().index,explicit().index];");
  return [
    values,
    observations.map((types) => types.single.name).toList(),
    immutable,
    identical(observations[0], observations[1])
  ];
}

void main() {
  test('external factory vectors stay immutable across prebound invocations',
      () {
    expect(runEnumVectorOwnershipCorrection(), [
      [1, 1, 1],
      ['int', 'int', 'int'],
      [true, true, true],
      true
    ]);
  });
  test('native factory gets the exact vector through bound escaping callbacks',
      () {
    final observations = <List<RuntimeType>>[];
    final interpreter = factoryInterpreter(observations);
    const source =
        "import 'package:host/choice.dart'; main() { final f = Choice<int>.choose; return () => [f().index, f().index, Choice.choose().index]; }";
    final callback = interpreter.execute(source: source);
    interpreter.registertopLevelFunction('host',
        (visitor, arguments, named, types) {
      return (callback as Callable).call(visitor, []);
    });
    expect(interpreter.execute(source: 'main() => host();'), [1, 1, 0]);
    expect(
        observations.map((types) => types.single.name), ['int', 'int', 'num']);
    expect(identical(observations[0], observations[1]), isTrue,
        reason:
            'Repeated bound calls carry the same resolved immutable vector.');
  });

  test('unsupported and invalid native tuples never enter the body', () {
    final observations = <List<RuntimeType>>[];
    final interpreter = factoryInterpreter(observations);
    for (final request in ['double', 'String', 'Local']) {
      expect(
          () => interpreter.execute(
              source:
                  "import 'package:host/choice.dart'; class Local {} main()=>Choice<$request>.choose();"),
          throwsA(anything));
    }
    expect(observations, isEmpty);
    expect(
        interpreter.execute(
            source:
                "import 'package:host/choice.dart'; main()=>Choice<int>.choose();"),
        same(Choice.high));
  });

  test('native factory deadline is terminal after synchronous native work', () {
    for (final compiled in [false, true]) {
      final observations = <List<RuntimeType>>[];
      final events = <String>[];
      final interpreter = factoryInterpreter(observations, slow: true)
        ..registertopLevelFunction('mark', (visitor, arguments, named, types) {
          events.add('after');
          return null;
        });
      const source =
          "import 'package:host/choice.dart'; main() { try { Choice<int>.choose(); } catch (_) { mark(); } finally { mark(); } mark(); }";
      expect(
          () => compiled
              ? interpreter.executeCompiled(interpreter.compile(source: source),
                  timeout: const Duration(milliseconds: 100))
              : interpreter.execute(
                  source: source, timeout: const Duration(milliseconds: 100)),
          throwsA(isA<ExecutionTimeoutException>()));
      expect(observations, hasLength(1));
      expect(events, isEmpty);
    }
  });

  test('factory rejects a native result from another enum', () {
    final interpreter = D4rt();
    interpreter.registerBridgedEnum(
        BridgedEnumDefinition<Choice>(
            name: 'Choice',
            values: Choice.values,
            typeMetadata: EnumTypeMetadata(
                typeParameters: ['T'], typeBounds: {'T': 'num'}),
            factories: {
              'choose': BridgedEnumFactory(
                  signature: EnumSignature([]),
                  specializations: [
                    BridgedEnumFactorySpecialization(
                        [const NamedRuntimeType('num')],
                        (visitor, arguments, named, types) => Other.low)
                  ])
            }),
        'package:host/choice.dart');
    expect(
        () => interpreter.execute(
            source:
                "import 'package:host/choice.dart'; main()=>Choice.choose();"),
        throwsA(isA<RuntimeError>()));
  });
}

enum Other { low }
