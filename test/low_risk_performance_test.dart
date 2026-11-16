import 'dart:collection';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

// The native logger writes to stdout directly, rather than Zone.print.
class _OutputCapture implements Stdout {
  _OutputCapture(this.lines);
  final List<String> lines;
  @override
  void writeln([Object? object = '']) => lines.add(object.toString());
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected stdout operation: ${invocation.memberName}',
  );
}

class _Payload {
  int strings = 0;
  int hashes = 0;
  @override
  String toString() {
    strings++;
    return 'payload';
  }

  @override
  int get hashCode {
    hashes++;
    return 7;
  }

  @override
  bool operator ==(Object other) => identical(this, other);
}

class _Backing extends ListBase<Object?> {
  final values = <Object?>[7];
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => values.length = value;
  @override
  Object? operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, Object? value) => values[index] = value;
}

class _CustomType implements RuntimeType {
  @override
  String get name => 'dynamic';
  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) => true;
}

class _CustomValue implements RuntimeValue {
  @override
  RuntimeType get valueType => const NamedRuntimeType('dynamic');
  @override
  Object? get(String name) => throw StateError('Bridge owns member access');
  @override
  void set(String name, Object? value) =>
      throw StateError('Bridge owns member access');
}

class _CustomCallable extends Callable {
  @override
  int get arity => 0;
  @override
  Object? call(
    InterpreterVisitor visitor,
    List<Object?> positionalArguments, [
    Map<String, Object?> namedArguments = const {},
    List<RuntimeType>? typeArguments,
  ]) => 42;
}

void main() {
  final initialDebug = Logger.debugEnabled;
  final initialLevel = Logger.minLevel;
  tearDown(() {
    Logger.setDebug(initialDebug);
    Logger.setMinLevel(initialLevel);
  });

  for (final mode in ['disabled', 'filtered', 'enabled']) {
    test(
      '$mode diagnostics preserve lazy/getter/enum/live collection effects',
      () async {
        Logger.setDebug(mode != 'disabled');
        Logger.setMinLevel(mode == 'filtered' ? LogLevel.info : LogLevel.debug);
        final payload = _Payload();
        final backing = _Backing();
        final events = <String>[];
        final logs = <String>[];
        final runtime = D4rt()
          ..registertopLevelFunction('mark', (v, args, named, types) {
            events.add(args.single as String);
            return 9;
          });
        const source = '''
import 'dart:collection';
class Probe {
  late final int initialized = mark('late');
  int get field { mark('getter'); return initialized; }
}
class View extends UnmodifiableListView<Object?> {
  View(super.source);
  int get hashCode { mark('hash'); return 17; }
  String toString() { mark('string'); return 'view'; }
}
enum Token {
  one;
  static int get x { mark('enum'); return 7; }
  int read() { { final local = 0; if (local == 0) { return x; } } return 0; }
}
main(dynamic value, List<Object?> backing) async {
  late final saved = value;
  final probe = Probe();
  final view = View(backing);
  final same = saved == value;
  bool caught = false;
  try { throw saved; } catch (error) { caught = identical(error, saved); }
  await Future.value(0);
  final read = probe.field;
  return [same && caught, identical(saved, value), read, probe.field, Token.one.read(), view];
}
''';
        final result =
            await IOOverrides.runZoned(
                  () => runtime.executeCompiled(
                    runtime.compile(source: source),
                    positionalArgs: [payload, backing],
                  ),
                  stdout: () => _OutputCapture(logs),
                )
                as List;
        expect(result.take(5), [true, true, 9, 9, 7]);
        expect(payload.strings, 0);
        expect(payload.hashes, 0);
        expect(events, ['getter', 'late', 'getter', 'enum']);
        expect(backing.reads, 0);
        final view = result[5] as List<Object?>;
        expect(view, isA<InterpretedInstance>());
        backing.values[0] = 8;
        expect(view[0], 8);
        expect(() => view[0] = 10, throwsUnsupportedError);
        expect(logs.any((line) => line.contains('[DEBUG]')), mode == 'enabled');
      },
    );
  }

  test('registered public runtime implementations retain native discovery', () {
    final runtime = D4rt();
    for (final entry in <(Type, String, bool Function(Object?))>[
      (RuntimeType, 'CustomType', (value) => value is _CustomType),
      (RuntimeValue, 'CustomValue', (value) => value is _CustomValue),
      (Callable, 'CustomCallable', (value) => value is _CustomCallable),
      (Environment, 'CustomEnvironment', (value) => value is Environment),
    ]) {
      runtime.registerBridgedClass(
        BridgedClass(
          nativeType: entry.$1,
          name: entry.$2,
          isSubtypeOfFunc: entry.$3,
          getters: {'marker': (v, target) => entry.$2},
        ),
        'package:host/contracts.dart',
      );
    }
    final compiled = runtime.compile(
      source: '''
import 'package:host/contracts.dart';
main(dynamic value) => (value).marker;
''',
    );
    final values = [
      _CustomType(),
      _CustomValue(),
      _CustomCallable(),
      Environment(),
    ];
    for (var i = 0; i < values.length; i++) {
      expect(
        runtime.executeCompiled(compiled, positionalArgs: [values[i]]),
        ['CustomType', 'CustomValue', 'CustomCallable', 'CustomEnvironment'][i],
      );
    }
  });
}
