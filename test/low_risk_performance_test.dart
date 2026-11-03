import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/module_loader.dart';
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

abstract interface class _Marker {}

class _MarkerValue implements _Marker {}

class _First {}

class _Second {}

class _TypeMetadata implements Type {
  int strings = 0;
  @override
  String toString() {
    strings++;
    return 'HostMetadata';
  }
}

class _MetadataValue {
  _MetadataValue(this.metadata);
  final Type metadata;
  @override
  Type get runtimeType => metadata;
}

class _NameProbeType implements RuntimeType {
  _NameProbeType({required this.throwOnName});
  final bool throwOnName;
  int nameReads = 0;
  int subtypeChecks = 0;
  @override
  String get name {
    nameReads++;
    if (throwOnName) throw StateError('Diagnostic name read');
    return 'External';
  }

  @override
  bool isSubtypeOf(RuntimeType other, {Object? value}) {
    subtypeChecks++;
    return true;
  }
}

class _PathReads {
  int absolute = 0;
}

class _SourceFile implements File {
  _SourceFile(this.path, this.reads, this.present);
  @override
  final String path;
  final _PathReads reads;
  final bool present;
  @override
  File get absolute {
    reads.absolute++;
    return this;
  }

  @override
  Uri get uri => Uri.file(path);
  @override
  bool existsSync() => present;
  @override
  String resolveSymbolicLinksSync() => path;
  @override
  String readAsStringSync({Object? encoding}) => '';
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected file operation: ${invocation.memberName}',
  );
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
        if (mode == 'enabled') {
          expect(
            logs.any((line) => line.contains('[visitSimpleIdentifier]')),
            isTrue,
          );
        }
      },
    );
  }

  test(
    'null bindings shadow outer values, classes and enums through prefixes',
    () {
      final outer = Environment()..define('value', 3);
      outer.defineBridge(BridgedClass(nativeType: _Payload, name: 'Payload'));
      final enumType = BridgedEnumDefinition<LogLevel>(
        name: 'Level',
        values: LogLevel.values,
      ).buildBridgedEnum();
      outer.defineBridgedEnum(enumType);
      final local = Environment(enclosing: outer)
        ..define('value', null)
        ..define('Payload', null)
        ..define('Level', null);
      final child = Environment(enclosing: local);
      expect(child.get('value'), isNull);
      expect(child.get('Payload'), isNull);
      expect(child.get('Level'), isNull);
      expect(child.findDefiningEnvironment('value'), same(local));
      final module = Environment()
        ..define('visible', null)
        ..define('_hidden', 8);
      final visible = module.shallowCopyFiltered(showNames: {'visible'});
      local.definePrefixedImport('p', visible);
      local.define('p', 99);
      expect(child.get('p'), same(visible));
      expect(child.get('p.visible'), isNull);
      expect(() => child.get('p._hidden'), throwsA(isA<RuntimeError>()));
      expect(() => child.get('p.missing'), throwsA(isA<RuntimeError>()));
      expect(() => child.get('p.visible.extra'), throwsA(isA<RuntimeError>()));
      expect(() => child.get('missing'), throwsA(isA<RuntimeError>()));
      expect(outer.get('Payload'), isA<BridgedClass>());
      expect(outer.get('Level'), same(enumType));
    },
  );

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

  test(
    'cascade discovers a native receiver once before invoking its adapter',
    () {
      var probes = 0;
      var calls = 0;
      final runtime = D4rt()
        ..registerBridgedClass(
          BridgedClass(
            nativeType: _Marker,
            name: 'Marker',
            isSubtypeOfFunc: (value) {
              if (value is! _Marker) return false;
              probes++;
              return true;
            },
            methods: {
              'touch': (v, target, args, named) {
                expect(probes, 1);
                calls++;
                return null;
              },
            },
          ),
          'package:host/marker.dart',
        )
        ..registertopLevelFunction('resetProbes', (v, args, named, types) {
          probes = 0;
          return null;
        });
      expect(
        runtime.execute(
          source: '''
import 'package:host/marker.dart';
main(dynamic value) { resetProbes(); value..touch(); return 42; }
''',
          positionalArgs: [_MarkerValue()],
        ),
        42,
      );
      expect(calls, 1);
    },
  );

  test(
    'bridge selection retains exact hits, ordered predicates and live probes',
    () {
      final events = <String>[];
      var firstMatches = true;
      final environment = Environment();
      final first = BridgedClass(
        nativeType: _First,
        name: 'First',
        isSubtypeOfFunc: (value) {
          events.add('first');
          return firstMatches && value is List;
        },
      );
      final second = BridgedClass(
        nativeType: _Second,
        name: 'Second',
        isSubtypeOfFunc: (value) {
          events.add('second');
          return value is List;
        },
      );
      final list = BridgedClass(nativeType: List, name: 'List');
      environment.defineBridge(first);
      environment.defineBridge(second);
      environment.defineBridge(list);
      final values = <int>[1];
      expect(environment.toBridgedClass(values), same(first));
      expect(events, ['first']);
      firstMatches = false;
      events.clear();
      expect(environment.toBridgedClass(values), same(second));
      expect(events, ['first', 'second']);
      events.clear();
      final exact = BridgedClass(
        nativeType: values.runtimeType,
        name: 'ExactList',
      );
      environment.defineBridge(exact);
      expect(environment.toBridgedClass(values), same(exact));
      expect(events, isEmpty);
      expect(
        () => Environment().toBridgedClass(Object()),
        throwsA(isA<RuntimeError>()),
      );
    },
  );

  test(
    'exact and predicate discovery do not stringify native type metadata',
    () {
      final metadata = _TypeMetadata();
      final value = _MetadataValue(metadata);
      final exact = BridgedClass(nativeType: metadata, name: 'Exact');
      final exactScope = Environment()..defineBridge(exact);
      expect(exactScope.toBridgedClass(value), same(exact));
      expect(metadata.strings, 0);
      final predicate = BridgedClass(
        nativeType: _Marker,
        name: 'Predicate',
        isSubtypeOfFunc: (value) => value is _MetadataValue,
      );
      final predicateScope = Environment()..defineBridge(predicate);
      expect(predicateScope.toBridgedClass(value), same(predicate));
      expect(metadata.strings, 0);
    },
  );

  test('runtime type name getters are not diagnostic projections', () {
    for (final mode in ['disabled', 'filtered', 'enabled']) {
      Logger.setDebug(mode != 'disabled');
      Logger.setMinLevel(mode == 'filtered' ? LogLevel.info : LogLevel.debug);
      for (final throwOnName in [false, true]) {
        final logs = <String>[];
        IOOverrides.runZoned(() {
          final declaredType = _NameProbeType(throwOnName: throwOnName);
          final declarationScope = Environment()
            ..define('External', declaredType);
          parseString(
            content: 'External result() => null;',
          ).unit.accept(DeclarationVisitor(declarationScope));
          final function =
              declarationScope.get('result') as InterpretedFunction;
          expect(function.declaredReturnType, same(declaredType));
          expect(declaredType.nameReads, 0);

          for (final globalFallback in [false, true]) {
            for (final named in [false, true]) {
              final target = Object();
              final targetType = _NameProbeType(throwOnName: throwOnName);
              final onType = _NameProbeType(throwOnName: throwOnName);
              final global = Environment();
              final scope = globalFallback ? Environment() : global;
              scope.annotateRuntimeType(target, targetType);
              final member = NativeFunction(
                (visitor, args, named, types) => 42,
                arity: 0,
              );
              final extension = InterpretedExtension(
                name: named ? 'Example' : null,
                onType: onType,
                members: {'marker': member},
              );
              if (named) {
                global.define('Example', extension);
              } else {
                global.addUnnamedExtension(extension);
              }
              final visitor = InterpreterVisitor(
                globalEnvironment: global,
                moduleLoader: ModuleLoader(global, {}, [], []),
              );
              final found = scope.findExtensionMember(
                target,
                'marker',
                visitor: visitor,
              );
              expect(found, same(member));
              expect(found!.call(visitor, []), 42);
              expect(targetType.subtypeChecks, 1);
              expect(targetType.nameReads, 0);
              expect(onType.nameReads, 0);
            }
          }
        }, stdout: () => _OutputCapture(logs));
        if (mode == 'enabled') {
          expect(
            logs.any((line) => line.contains('return annotation: External')),
            isTrue,
          );
        }
      }
    }
  });

  test('enabled diagnostics retain module, syntax and operand context', () async {
    Logger.setDebug(true);
    Logger.setMinLevel(LogLevel.debug);
    const module = 'package:diagnostic/number.dart';
    final logs = <String>[];
    final result = await IOOverrides.runZoned(
      () => D4rt().execute(
        source:
            '''
import '$module' as first;
import '$module' as second;
extension type Token(int value) {}
main() async {
  final result = first.increment(4) + second.increment(5);
  await Future.value(0);
  return result;
}
''',
        sources: {module: 'int increment(int value) => value + 1;'},
      ),
      stdout: () => _OutputCapture(logs),
    );
    expect(result, 11);
    for (final operation in [
      'Loading module',
      'Parsing source',
      'found in cache',
    ]) {
      expect(
        logs.any((line) => line.contains(operation) && line.contains(module)),
        isTrue,
        reason: 'Missing useful module context for $operation',
      );
    }
    expect(
      logs.any(
        (line) =>
            line.contains('[StateMachine]') &&
            line.contains('VariableDeclarationStatement') &&
            line.contains('offset'),
      ),
      isTrue,
    );
    expect(logs.any((line) => line.contains('Left operand type: int')), isTrue);
    expect(
      logs.any((line) => line.contains('Right operand type: int')),
      isTrue,
    );
    expect(
      logs.any((line) => line.contains('Representation type annotation: int')),
      isTrue,
      reason:
          'The representation annotation is int, not the host type-model category.',
    );
  });

  test(
    'filesystem path diagnostics prepare only eligible missing-file reports',
    () {
      final uri = Uri.parse('file:///synthetic/diagnostic.dart');
      for (final exists in [true, false]) {
        for (final mode in ['disabled', 'filtered', 'enabled']) {
          Logger.setDebug(mode != 'disabled');
          Logger.setMinLevel(
            mode == 'filtered' ? LogLevel.info : LogLevel.debug,
          );
          final reads = _PathReads();
          final logs = <String>[];
          IOOverrides.runZoned(
            () {
              final loader = ModuleLoader(
                Environment(),
                {},
                [],
                [],
                allowFileSystemImports: true,
              );
              if (exists) {
                expect(loader.loadModule(uri), isA<LoadedModule>());
              } else {
                expect(
                  () => loader.loadModule(uri),
                  throwsA(isA<SourceCodeException>()),
                );
              }
            },
            createFile: (path) => _SourceFile(path, reads, exists),
            stdout: () => _OutputCapture(logs),
          );
          // Existing files need only canonicalization. Missing files need one
          // semantic error path, plus diagnostic resolution only when eligible.
          expect(reads.absolute, exists || mode != 'enabled' ? 2 : 3);
          expect(
            logs.any((line) => line.contains('no file found')),
            !exists && mode == 'enabled',
          );
        }
      }
    },
  );
}
