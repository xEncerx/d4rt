import 'dart:collection';
import 'dart:convert';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

abstract interface class _Metrics {
  int get serializedBytes;
  int get nodes;
  int get maxContainerDepth;
}

final class _NativeList extends UnmodifiableListView<Object?>
    implements _Metrics {
  _NativeList(super.values);
  @override
  final int serializedBytes = 3;
  @override
  final int nodes = 2;
  @override
  final int maxContainerDepth = 0;
}

final class _NativeMap extends UnmodifiableMapView<String, Object?>
    implements _Metrics {
  _NativeMap(super.values);
  @override
  final int serializedBytes = 10;
  @override
  final int nodes = 2;
  @override
  final int maxContainerDepth = 0;
}

const _classes = '''
import 'dart:collection';
abstract interface class Metrics {
  int get serializedBytes;
  int get nodes;
  int get maxContainerDepth;
}
final class CapturedList extends UnmodifiableListView<Object?> implements Metrics {
  CapturedList(List<Object?> values)
      : serializedBytes = 3, nodes = 2, maxContainerDepth = 0, super(values);
  final int serializedBytes;
  final int nodes;
  final int maxContainerDepth;
  String label() => 'list';
}
final class CapturedMap extends UnmodifiableMapView<String, Object?> implements Metrics {
  CapturedMap(Map<String, Object?> values)
      : serializedBytes = 10, nodes = 2, maxContainerDepth = 0, super(values);
  final int serializedBytes;
  final int nodes;
  final int maxContainerDepth;
  String label() => 'map';
}
Object create(String kind) {
  switch (kind) {
    case 'raw-list': return <Object?>[7];
    case 'view-list': return UnmodifiableListView<Object?>(<Object?>[7]);
    case 'subclass-list': return CapturedList(<Object?>[7]);
    case 'raw-map': return <String, Object?>{'page': 1};
    case 'view-map': return UnmodifiableMapView<String, Object?>(<String, Object?>{'page': 1});
    case 'subclass-map': return CapturedMap(<String, Object?>{'page': 1});
    default: throw ArgumentError(kind);
  }
}
''';

const _superClasses = '''
import 'dart:collection';
class Values<T> extends UnmodifiableListView<T> {
  Values(List<T> super.source);
}
class Child<T> extends Values<T> {
  Child(super.renamed);
}
class Entries<K, V> extends UnmodifiableMapView<K, V> {
  Entries(Map<K, V> super.map);
}
''';

Object _native(String kind) => switch (kind) {
      'raw-list' => <Object?>[7],
      'view-list' => UnmodifiableListView<Object?>(<Object?>[7]),
      'subclass-list' => _NativeList(<Object?>[7]),
      'raw-map' => <String, Object?>{'page': 1},
      'view-map' =>
        UnmodifiableMapView<String, Object?>(<String, Object?>{'page': 1}),
      'subclass-map' => _NativeMap(<String, Object?>{'page': 1}),
      _ => throw ArgumentError(kind),
    };

List<Object?> _description(dynamic value, String kind) => [
      value is List,
      value is List<Object?>,
      value is Map,
      value is Map<String, Object?>,
      kind.endsWith('list') ? value[0] : value['page'],
      value.length,
    ];

class _CountingList extends ListBase<Object?> {
  final backing = <Object?>[7];
  int reads = 0;
  @override
  int get length => backing.length;
  @override
  set length(int value) => backing.length = value;
  @override
  Object? operator [](int index) {
    reads++;
    return backing[index];
  }

  @override
  void operator []=(int index, Object? value) => backing[index] = value;
}

class _CountingMap extends MapBase<String, Object?> {
  final backing = <String, Object?>{'page': 1};
  int reads = 0;
  @override
  Iterable<String> get keys {
    reads++;
    return backing.keys;
  }

  @override
  Object? operator [](Object? key) {
    reads++;
    return backing[key];
  }

  @override
  void operator []=(String key, Object? value) => backing[key] = value;
  @override
  void clear() => backing.clear();
  @override
  Object? remove(Object? key) => backing.remove(key);
}

void main() {
  test('six collection cases agree with native types and inherited reads', () {
    for (final kind in [
      'raw-list',
      'view-list',
      'subclass-list',
      'raw-map',
      'view-map',
      'subclass-map'
    ]) {
      final interpreter = D4rt();
      final observed = interpreter.execute(source: '''
$_classes
main() {
  dynamic value = create('$kind');
  return [value is List, value is List<Object?>, value is Map,
    value is Map<String, Object?>,
    '$kind'.endsWith('list') ? value[0] : value['page'], value.length];
}
''');
      expect(observed, _description(_native(kind), kind), reason: kind);
    }
  });

  test('implicit super formals create lazy live immutable list and map views',
      () {
    final list = _CountingList();
    final map = _CountingMap();
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'sources', (visitor, args, named, types) => [list, map]);
    final result = interpreter.execute(source: '''
$_superClasses
main() {
  final source = sources();
  return [Child<Object?>(source[0]), Entries<String, Object?>(source[1])];
}
''') as List;
    expect(list.reads, 0);
    expect(map.reads, 0);
    final values = result[0] as List<Object?>;
    final entries = result[1] as Map<String, Object?>;
    expect(values, isA<InterpretedInstance>());
    expect(entries, isA<InterpretedInstance>());
    expect(values.length, 1);
    expect(entries.length, 1);
    expect(list.reads, 0);
    list.backing[0] = 8;
    map.backing['page'] = 2;
    expect(values[0], 8);
    expect(entries['page'], 2);
    expect(() => values[0] = 9, throwsUnsupportedError);
    expect(() => entries['page'] = 3, throwsUnsupportedError);
    expect(values.clear, throwsUnsupportedError);
    expect(entries.clear, throwsUnsupportedError);
  });

  test('implicit immutable views retain interpreted typed native catches', () {
    final list = <Object?>[1];
    final map = <String, Object?>{'a': 1};
    final additions = <String, Object?>{'blocked': 3};
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'sources', (visitor, args, named, types) => [list, map, additions]);
    expect(interpreter.execute(source: '''
$_superClasses
main() {
  final source = sources();
  final values = Child<Object?>(source[0]);
  final entries = Entries<String, Object?>(source[1]);
  final caught = <String>[];
  int postFailure = 0;
  try { values.add(2); postFailure++; }
  on UnsupportedError { caught.add('list-add'); }
  try { values.clear(); postFailure++; }
  on UnsupportedError { caught.add('list-clear'); }
  try { entries.addAll(source[2]); postFailure++; }
  on UnsupportedError { caught.add('map-addAll'); }
  try { entries.clear(); postFailure++; }
  on UnsupportedError { caught.add('map-clear'); }
  return [caught, postFailure, values.length, entries.length];
}
'''), [
      ['list-add', 'list-clear', 'map-addAll', 'map-clear'],
      0,
      1,
      1,
    ]);
    expect(list, [1]);
    expect(map, {'a': 1});
    expect(additions, {'blocked': 3});
  });

  test('implicit generic super views retain substituted type contracts', () {
    expect(D4rt().execute(source: '''
$_superClasses
class Element {}
main() {
  final values = Child<int>(<int>[1]);
  final nullable = Values<int?>(<int?>[null]);
  final entries = Entries<String, Object?>(<String, Object?>{'a': 1});
  final bottom = Values<Never>(<Never>[]);
  final nested = Values<List<int>>(<List<int>>[<int>[2]]);
  final elements = Values<Element>(<Element>[]);
  return [values.length, entries.length,
    values is List<int>, values is List<num>, values is List<String>,
    nullable is List<int?>, nullable is List<int>, nullable[0],
    entries is Map<String, Object?>, entries is Map<int, Object?>,
    bottom is List<Never>, bottom.length,
    nested is List<List<int>>, nested is List<List<String>>, nested[0][0],
    elements is List<Element>, elements.length];
}
'''), [
      1,
      1,
      true,
      true,
      false,
      true,
      false,
      null,
      true,
      false,
      true,
      0,
      true,
      false,
      2,
      true,
      0
    ]);
  });

  test('explicit child collection defaults are forwarded', () {
    expect(D4rt().execute(source: '''
import 'dart:collection';
class Values extends UnmodifiableListView<int> {
  Values([List<int> super.source = const <int>[1]]);
}
main() => Values().length;
'''), 1);
  });

  test('implicit view forwarding preserves ordinary argument errors', () {
    for (final expression in [
      'Values<int>()',
      'Values<int>(<int>[1], <int>[2])',
      'Values<int>(<int>[1], unknown: 2)',
      'Values<int>(<String>[])',
      'Values<int>(null)',
      'Entries<String, int>(<String, String>{})',
      'Entries<String, int>(<int, int>{})',
    ]) {
      expect(() => D4rt().execute(source: '''
$_superClasses
main() => $expression;
'''), throwsA(isA<RuntimeError>()), reason: expression);
    }
    for (final constructor in [
      'UnmodifiableListView<int>(<int>[1], unknown: 2)',
      'UnmodifiableMapView<String, int>(<String, int>{}, unknown: 2)',
      'MapView<String, int>(<String, int>{}, unknown: 2)',
    ]) {
      expect(
          () => D4rt().execute(
              source: "import 'dart:collection'; main() => $constructor;"),
          throwsA(isA<RuntimeError>()),
          reason: constructor);
    }
    expect(() => D4rt().execute(source: '''
import 'dart:collection';
class Values extends UnmodifiableListView<int> {
  Values(super.source, {super.unknown});
}
main() => Values(<int>[1], unknown: 2);
'''), throwsA(isA<RuntimeError>()));
  });

  test('final fields implement getters without erasing subclass identity', () {
    final interpreter = D4rt();
    expect(interpreter.execute(source: '''
$_classes
main() {
  final list = CapturedList(<Object?>[7]);
  final map = CapturedMap(<String, Object?>{'page': 1});
  return [list is CapturedList, map is CapturedMap,
    list.serializedBytes, list.nodes, list.maxContainerDepth, list.label(),
    map.serializedBytes, map.nodes, map.maxContainerDepth, map.label()];
}
'''), [true, true, 3, 2, 0, 'list', 10, 2, 0, 'map']);
    expect(D4rt().execute(source: '''
abstract class Metrics { int get count; set count(int value); }
class Fields { int count = 2; }
class Value extends Fields implements Metrics {}
main() => Value().count;
'''), 2);
    for (final declaration in [
      'class Value implements Metrics { final int count = 1; }',
      'class Value implements Metrics { static int count = 1; }',
      'class Value implements Metrics { int count() => 1; }',
      'class Value implements Metrics { set count(int value) {} }',
    ]) {
      expect(() => D4rt().execute(source: '''
abstract class Metrics { int get count; set count(int value); }
$declaration
main() => Value();
'''), throwsA(isA<RuntimeError>()));
    }
    expect(() => D4rt().execute(source: '''
abstract class Parent { void count(); }
class Value extends Parent { int count = 1; }
main() => Value();
'''), throwsA(isA<RuntimeError>()));
  });

  test('nested sync async and callback results retain identity and aliases',
      () async {
    final interpreter = D4rt();
    final list = <Object?>[7];
    final map = <String, Object?>{'page': 1};
    interpreter.registertopLevelFunction(
        'sources', (v, args, named, types) => [list, map]);
    Object? callbackList;
    Object? callbackMap;
    interpreter.registertopLevelFunction('admit', (v, args, named, types) {
      final payload = args.single as Map;
      final values = payload['next'] as List;
      callbackList = values[0];
      callbackMap = values[1];
      expect(callbackList, isA<InterpretedInstance>());
      expect(callbackMap, isA<InterpretedInstance>());
      expect(jsonEncode(payload), '{"next":[[7],{"page":1}]}');
      return payload;
    });
    for (final async in [false, true]) {
      final result = await interpreter.execute(source: '''
$_classes
${async ? 'Future<Object> main() async' : 'Object main()'} {
  final input = sources();
  final list = CapturedList(input[0]);
  final map = CapturedMap(input[1]);
  return admit({'next': [list, map]});
}
''') as Map;
      final values = result['next'] as List;
      expect(values[0], same(callbackList));
      expect(values[1], same(callbackMap));
      list[0] = 9;
      map['page'] = 4;
      expect((values[0] as List)[0], 9);
      expect((values[1] as Map)['page'], 4);
      expect((values[1] as Map)['missing'], isNull);
      expect(() => (values[0] as List).add(1), throwsUnsupportedError);
      expect(() => (values[0] as List)[0] = 1, throwsUnsupportedError);
      expect(() => (values[1] as Map)['page'] = 1, throwsUnsupportedError);
      expect(() => (values[1] as Map).clear(), throwsUnsupportedError);
      expect(() => (values[0] as List)[-1], throwsRangeError);
      list[0] = 7;
      map['page'] = 1;
      interpreter.execute(source: 'main() => 42;');
      expect(jsonEncode(result), '{"next":[[7],{"page":1}]}');
    }
  });

  test('construction and native bridges do not visit backing contents', () {
    final list = _CountingList();
    final map = _CountingMap();
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'sources', (v, args, named, types) => [list, map]);
    interpreter.registertopLevelFunction('retain', (v, args, named, types) {
      expect(list.reads, 0);
      expect(map.reads, 0);
      return args.single;
    });
    final result = interpreter.execute(source: '''
$_classes
main() {
  final input = sources();
  return retain({'next': [CapturedList(input[0]), CapturedMap(input[1])]});
}
''') as Map;
    expect(list.reads, 0);
    expect(map.reads, 0);
    expect(jsonEncode(result), '{"next":[[7],{"page":1}]}');
    expect(list.reads, greaterThan(0));
    expect(map.reads, greaterThan(0));
  });

  test('native collection overrides use original fields after later execution',
      () {
    final interpreter = D4rt();
    const source = '''
import 'dart:collection';
int offset = 10;
class Adjusted extends MapView<String, int> {
  Adjusted(Map<String, int> values) : super(values);
  int writes = 0;
  int? operator [](Object? key) => super[key] + offset;
  void operator []=(String key, int value) {
    writes++;
    super[key] = value - offset;
  }
  int get length => super.length + 1;
  bool containsKey(Object? key) => key == 'virtual';
  int increment() => ++super['n'];
}
main() {
  final value = Adjusted(<String, int>{'n': 1});
  value['n'] += 2;
  ++value['n'];
  value['n']++;
  return [value, value.writes, value['n'], value.length,
    value.containsKey('virtual'), value.increment()];
}
''';
    final result = interpreter.execute(source: source) as List;
    expect(result.sublist(1), [3, 15, 2, true, 6]);
    final value = result[0] as Map<String, int>;
    expect(value, isA<InterpretedInstance>());
    expect(value['n'], 16);
    interpreter.execute(source: 'int offset = 100; main() => offset;');
    expect(value['n'], 16);
    expect(value.length, 2);
    expect(value.containsKey('virtual'), isTrue);
    value['n'] = 20;
    expect(value['n'], 20);
    expect((value as InterpretedInstance).get('writes'), 4);
    expect(((value as InterpretedInstance).bridgedSuperObject as Map)['n'], 10);
    expect(D4rt().execute(source: '''
import 'dart:collection';
class Adjusted extends UnmodifiableListView<int> {
  Adjusted(List<int> source) : super(source);
  int operator [](int index) => super[index] + 10;
}
main() { final value = Adjusted(<int>[7]); return [value[0], value.toList(), value]; }
'''), [
      17,
      [17],
      [17]
    ]);
  });

  test(
      'empty direct and inherited generic views preserve wrong types and nullability',
      () {
    expect(D4rt().execute(source: '''
import 'dart:collection';
class Values<T> extends UnmodifiableListView<T> { Values(List<T> source) : super(source); }
class Child<T> extends Values<T> { Child(List<T> source) : super(source); }
class Entries<K, V> extends UnmodifiableMapView<K, V> {
  Entries(Map<K, V> source) : super(source);
}
main() {
  final numbers = Child<int>(<int>[]);
  final nullable = Values<int?>(<int?>[null]);
  final map = Entries<String, int?>(<String, int?>{});
  final direct = UnmodifiableMapView<String, int>(<String, int>{'n': 1});
  return [numbers is List<int>, numbers is List<num>, numbers is List<String>,
    numbers is Map, nullable is List<int?>, nullable is List<int>,
    nullable[0], map is Map<String, int?>, map is Map<String, int>,
    map is Map<int, int?>, direct is Map<String, int>, direct is Map<int, int>,
    switch (direct) { Map<String, int> value => value['n'], _ => 0 },
    switch (numbers) { List<int> value => value.length, _ => -1 }];
}
'''), [
      true,
      true,
      false,
      false,
      true,
      false,
      null,
      true,
      false,
      false,
      true,
      false,
      1,
      0
    ]);
    for (final source in ['<String>[]', "<String>['same']", '<int?>[]']) {
      expect(() => D4rt().execute(source: '''
import 'dart:collection';
main() => UnmodifiableListView<int>($source);
'''), throwsA(isA<RuntimeError>()));
    }
    for (final source in [
      '<int, int>{}',
      '<String, String>{}',
      '<String, int?>{}'
    ]) {
      expect(() => D4rt().execute(source: '''
import 'dart:collection';
main() => UnmodifiableMapView<String, int>($source);
'''), throwsA(isA<RuntimeError>()));
    }
  });

  test(
      'mutable subclasses write through while immutable empty views reject clear',
      () {
    final source = <String, int>{'n': 1};
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'source', (v, args, named, types) => source);
    final value = interpreter.execute(source: '''
import 'dart:collection';
class Values extends MapView<String, int> { Values(Map<String, int> values) : super(values); }
main() { final value = Values(source()); value['n']++; return value; }
''') as Map<String, int>;
    expect(source['n'], 2);
    value['n'] = 3;
    expect(source['n'], 3);
    for (final script in [
      "class Value extends UnmodifiableListView<int> { Value() : super(<int>[]); }",
      "class Value extends UnmodifiableMapView<String, int> { Value() : super(<String, int>{}); }",
    ]) {
      final empty = D4rt().execute(
          source: "import 'dart:collection'; $script main() => Value();");
      expect(() => (empty as dynamic).clear(), throwsUnsupportedError);
    }
  });

  test(
      'nested unsupported objects and cycles are not normalized at native exits',
      () {
    final interpreter = D4rt();
    final cycle = <Object?>[];
    cycle.add(cycle);
    interpreter.registertopLevelFunction(
        'source', (v, args, named, types) => cycle);
    final result = interpreter.execute(source: '''
$_classes
main() => {'next': CapturedList(source())};
''') as Map;
    final view = result['next'] as List;
    expect(view[0], same(cycle));
    expect(cycle[0], same(cycle));
    expect(
        () => jsonEncode(result), throwsA(isA<JsonUnsupportedObjectError>()));
    final unsupported = interpreter.execute(source: '''
$_classes
class Unsupported {}
main() => {'next': CapturedList(<Object?>[Unsupported()])};
''');
    expect(() => jsonEncode(unsupported),
        throwsA(isA<JsonUnsupportedObjectError>()));
  });

  test('native override calls share the active execution step limit', () {
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'read', (v, args, named, types) => (args.single as List)[0]);
    expect(() => interpreter.execute(maxSteps: 150, source: '''
import 'dart:collection';
class Slow extends UnmodifiableListView<int> {
  Slow() : super(<int>[1]);
  int operator [](int index) {
    int count = 0;
    while (count < 1000) { count++; }
    return 1;
  }
}
main() => read(Slow());
'''), throwsA(isA<RuntimeError>()));
  });

  test('host source reification is checked without consulting contents', () {
    for (final source in <Object>[
      <String>[],
      <String>['1'],
      <Object>[1],
      <int?>[],
      <int, int>{},
      <String, String>{},
      <String, int?>{},
    ]) {
      final interpreter = D4rt();
      interpreter.registertopLevelFunction(
          'source', (v, args, named, types) => source);
      final view = source is List
          ? 'UnmodifiableListView<int>'
          : 'UnmodifiableMapView<String, int>';
      expect(() => interpreter.execute(source: """
import 'dart:collection';
main() => $view(source());
"""), throwsA(isA<RuntimeError>()));
    }
  });

  test('collection casts and typed returns retain subclass generic contracts',
      () {
    const definitions = '''
import 'dart:collection';
class Values extends UnmodifiableListView<int> {
  Values() : super(<int>[7]);
}
class Entries extends UnmodifiableMapView<String, int> {
  Entries() : super(<String, int>{'n': 1});
}
List<int> list() { return Values(); }
Map<String, int> map() { return Entries(); }
''';
    expect(D4rt().execute(source: '''
$definitions
main() => [(list() as List<int>)[0], (map() as Map<String, int>)['n']];
'''), [7, 1]);
    for (final expression in [
      'list() as List<String>',
      'map() as Map<int, int>',
      'list() as Map',
      'map() as List',
    ]) {
      expect(
          () => D4rt().execute(source: '$definitions main() => $expression;'),
          throwsA(isA<RuntimeError>()));
    }
  });
}
