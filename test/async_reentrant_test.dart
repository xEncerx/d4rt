import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

Future<Object?> _execute(String source,
    {String name = 'main', List<Object?> args = const []}) async {
  return await D4rt().execute(
    source: source,
    name: name,
    positionalArgs: args,
    maxSteps: 100000,
    timeout: const Duration(seconds: 5),
  );
}

const _nodeSource = '''
class Node {
  Node(this.child);
  final Node? child;

  int count() {
    final next = child;
    return next == null ? 1 : 1 + next.count();
  }
}

int syncScenario() => Node(Node(Node(null))).count();
Future<int> asyncScenario() async => syncScenario();
''';

const _builderSource = '''
class Builder {
  Builder(this.fields, this.children);
  final Map<String, Object?> fields;
  final Map<String, Builder> children;

  Map<String, Object?> finish() {
    final result = <String, Object?>{};
    for (final key in fields.keys) {
      result[key] = fields[key];
    }
    for (final key in children.keys) {
      final value = children[key]!;
      result[key] = value._finish();
    }
    return result;
  }

  Map<String, Object?> _finish() => finish();
}

Object syncScenario() {
  final leaf = Builder({'kind': 'text', 'value': 'a'}, {});
  final values = Builder({}, {'f0': leaf});
  return Builder({}, {'values': values}).finish();
}

Future<Object> asyncScenario() async => syncScenario();
''';

const _recursiveSource = '''
int sum(int n) => n == 0 ? 0 : n + sum(n - 1);

class Counter {
  int implicit(int n) => n == 0 ? 0 : n + implicit(n - 1);
  int explicit(int n) => n == 0 ? 0 : n + this.explicit(n - 1);
}

Future<Object> main() async {
  final counter = Counter();
  final before = [sum(4), counter.implicit(4), counter.explicit(4)];
  await Future.delayed(Duration(milliseconds: 1));
  return [before, [sum(4), counter.implicit(4), counter.explicit(4)]];
}
''';

const _suspensionSource = '''
List<String> events = [];
int calls = 0;

int sum(int n) {
  calls++;
  return n == 0 ? 0 : n + sum(n - 1);
}

int prefix(String label) {
  events.add(label);
  return sum(2);
}

class Box {
  Box(this.offset);
  final int offset;
  int combine(int first, int second, {required int tail}) =>
      offset + first + second + tail;
}

Future<Box> receiver() async {
  events.add('receiver:start');
  final offset = sum(2);
  await Future.delayed(Duration(milliseconds: 1));
  events.add('receiver:end');
  return Box(offset);
}

Future<int> delayed(String label, int value) async {
  events.add(label + ':start');
  await Future.delayed(Duration(milliseconds: 1));
  events.add(label + ':end');
  return value;
}

Future<Object> main() async {
  final invocation = (await receiver()).combine(
    prefix('positional'),
    await delayed('argument', 4),
    tail: await delayed('named', 5),
  );
  final binary = prefix('left') + await delayed('right', 6);
  return {'invocation': invocation, 'binary': binary,
          'calls': calls, 'events': events};
}
''';

const _errorSource = '''
List<String> events = [];
int calls = 0;

int sum(int n, bool fail) {
  calls++;
  if (n == 0) {
    if (fail) throw 'sync';
    return 0;
  }
  return n + sum(n - 1, fail);
}

int prefix(bool fail) {
  events.add('prefix');
  return sum(2, fail);
}

int tail() {
  events.add('tail');
  return 5;
}

int combine(int first, int second, {required int last}) => first + second + last;

Future<int> delayed(bool fail) async {
  events.add('await:start');
  await Future.delayed(Duration(milliseconds: 1));
  events.add('await:end');
  if (fail) throw 'async';
  return 4;
}

Future<Object> main(bool failSync, bool failAwait) async {
  try {
    combine(prefix(failSync), await delayed(failAwait), last: tail());
  } catch (error) {
    events.add('catch:' + error.toString());
  } finally {
    events.add('finally');
  }
  final recovered = combine(prefix(false), await delayed(false), last: tail());
  return {'value': recovered, 'calls': calls, 'events': events};
}
''';

void main() {
  group('async dynamic invocation ownership', () {
    test('recursive receivers agree for sync and async entries', () async {
      for (final name in ['syncScenario', 'asyncScenario']) {
        expect(await _execute(_nodeSource, name: name), 3);
      }
    });

    test('nested builders finish the current child at every depth', () async {
      for (final name in ['syncScenario', 'asyncScenario']) {
        expect(await _execute(_builderSource, name: name), {
          'values': {
            'f0': {'kind': 'text', 'value': 'a'},
          },
        });
      }
    });

    test('recursive functions and implicit and explicit methods survive await',
        () async {
      expect(await _execute(_recursiveSource), [
        [10, 10, 10],
        [10, 10, 10],
      ]);
    });

    test('recursive prefixes and awaited receiver and arguments run once',
        () async {
      expect(await _execute(_suspensionSource), {
        'invocation': 15,
        'binary': 9,
        'calls': 9,
        'events': [
          'receiver:start',
          'receiver:end',
          'positional',
          'argument:start',
          'argument:end',
          'named:start',
          'named:end',
          'left',
          'right:start',
          'right:end',
        ],
      });
    });

    test('synchronous recursive errors restore the suspended caller', () async {
      expect(await _execute(_errorSource, args: [true, false]), {
        'value': 12,
        'calls': 6,
        'events': [
          'prefix',
          'catch:sync',
          'finally',
          'prefix',
          'await:start',
          'await:end',
          'tail',
        ],
      });
    });

    test('await failures discard prefixes and run catch and finally once',
        () async {
      expect(await _execute(_errorSource, args: [false, true]), {
        'value': 12,
        'calls': 6,
        'events': [
          'prefix',
          'await:start',
          'await:end',
          'catch:async',
          'finally',
          'prefix',
          'await:start',
          'await:end',
          'tail',
        ],
      });
    });

    test('loop iterations do not reuse recursive operands', () async {
      const source = '''
int calls = 0;
int sum(int n) {
  calls++;
  return n == 0 ? 0 : n + sum(n - 1);
}
Future<int> delayed(int n) async {
  await Future.delayed(Duration(milliseconds: 1));
  return n;
}
Future<Object> main() async {
  final values = <int>[];
  for (int i = 1; i <= 2; i++) {
    values.add(sum(i) + await delayed(i));
  }
  return {'values': values, 'calls': calls};
}
''';
      expect(await _execute(source), {
        'values': [2, 5],
        'calls': 5,
      });
    });

    test('deferred recursive sync generators own their collection evaluation',
        () async {
      const source = '''
List<String> events = [];
Iterable<Object?> values(int n) sync* {
  events.add('enter:' + n.toString());
  yield [n, if (n > 0) ...values(n - 1)];
  events.add('exit:' + n.toString());
}
Future<Object> main() async {
  final before = values(2).toList();
  await Future.delayed(Duration(milliseconds: 1));
  final after = values(1).toList();
  return {'before': before, 'after': after, 'events': events};
}
''';
      expect(await _execute(source), {
        'before': [
          [
            2,
            [
              1,
              [0],
            ],
          ],
        ],
        'after': [
          [
            1,
            [0],
          ],
        ],
        'events': [
          'enter:2',
          'enter:1',
          'enter:0',
          'exit:0',
          'exit:1',
          'exit:2',
          'enter:1',
          'enter:0',
          'exit:0',
          'exit:1',
        ],
      });
    });

    test('recursive yield delegation evaluates each generator body once',
        () async {
      const source = '''
final effects = <int>[];
class Node {
  Node(this.value, this.child);
  final int value;
  final Node? child;

  Iterable<int> values() sync* {
    effects.add(value);
    yield value;
    final next = child;
    if (next != null) {
      yield* next.values();
    }
  }
}

Node root() => Node(1, Node(2, Node(3, null)));
Object syncScenario() => [root().values().toList(), effects];
Future<Object> asyncScenario() async {
  final values = root().values().toList();
  await Future.value(0);
  return [values, effects];
}
''';
      for (final name in ['syncScenario', 'asyncScenario']) {
        expect(await _execute(source, name: name), [
          [1, 2, 3],
          [1, 2, 3],
        ]);
      }
    });

    test('imported recursive helpers retain their dynamic receivers', () async {
      final result = await D4rt().execute(
        library: 'package:example/entry.dart',
        sources: {
          'package:example/nodes.dart': _nodeSource,
          'package:example/entry.dart': '''
import 'package:example/nodes.dart';
Future<int> main() async {
  final first = syncScenario();
  await Future.delayed(Duration(milliseconds: 1));
  return first + syncScenario();
}
''',
        },
        allowFileSystemImports: false,
        maxSteps: 100000,
        timeout: const Duration(seconds: 5),
      );
      expect(result, 6);
    });
  });
}
