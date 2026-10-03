import 'dart:collection';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

class _ListView<T> extends UnmodifiableListView<T> {
  _ListView(super.source);
}

class _MapView<K, V> extends UnmodifiableMapView<K, V> {
  _MapView(super.source);
}

class _AdjustedMap extends MapView<String, int> {
  _AdjustedMap(super.source);
  @override
  int? operator [](Object? key) => (super[key] ?? 0) + 10;
}

class _VirtualKeys extends MapView<String, int> {
  _VirtualKeys() : super({'backing': 1});
  @override
  Iterable<String> get keys => <String>['virtual'];
}

class _FieldMap extends MapView<String, int> {
  _FieldMap() : super({'backing': 1});
  @override
  final Iterable<String> keys = <String>['virtual'];
  @override
  final Iterable<int> values = <int>[41];
  @override
  final Iterable<MapEntry<String, int>> entries = [MapEntry('virtual', 42)];
  @override
  final int length = 9;
  @override
  final bool isEmpty = true;
  @override
  final bool isNotEmpty = false;
}

class _InheritedFieldMap extends _FieldMap {}

class _FieldList extends UnmodifiableListView<int> {
  _FieldList() : super([1, 2]);
  @override
  final int first = 71;
  @override
  final int last = 72;
  @override
  final int single = 73;
  @override
  final int length = 1;
  @override
  final Iterable<int> reversed = <int>[74];
  @override
  final bool isEmpty = true;
  @override
  final bool isNotEmpty = false;
}

class _InheritedFieldList extends _FieldList {}

class _LateFieldMap extends MapView<String, int> {
  _LateFieldMap() : super({'backing': 1});
  int reads = 0;
  @override
  late final Iterable<String> keys = _createKeys();
  Iterable<String> _createKeys() {
    reads++;
    return <String>['virtual'];
  }
}

List<Object?> _fieldProperties(Object value) {
  if (value is List<int>) {
    return [
      value.first,
      value.last,
      value.single,
      value.length,
      value.reversed.toList(),
      value.isEmpty,
      value.isNotEmpty
    ];
  }
  final map = value as Map<String, int>;
  return [
    map.keys.toList(),
    map.values.toList(),
    map.entries.map((entry) => [entry.key, entry.value]).toList(),
    map.length,
    map.isEmpty,
    map.isNotEmpty
  ];
}

class _VirtualList extends UnmodifiableListView<int> {
  _VirtualList() : super([1, 2]);
  @override
  Iterator<int> get iterator => <int>[91].iterator;
  @override
  int get hashCode => 123;
  @override
  bool operator ==(Object other) => other == 'virtual-list';
  @override
  String join([String separator = '']) => 'virtual$separator';
  @override
  void forEach(void Function(int) action) {
    action(41);
    action(42);
  }

  @override
  Iterable<int> get reversed => [71, 72];
  @override
  int indexWhere(bool Function(int) test, [int start = 0]) =>
      test(99) ? start + 10 : -1;
  @override
  int firstWhere(bool Function(int) test, {int Function()? orElse}) =>
      test(55) ? 55 : orElse!();
  @override
  R fold<R>(R initialValue, R Function(R, int) combine) =>
      combine(initialValue, 30);
  @override
  Iterable<R> map<R>(R Function(int) convert) => [convert(20)];
  @override
  List<int> sublist(int start, [int? end]) => [start + 80, end ?? 90];
  @override
  Iterable<int> getRange(int start, int end) => [start + 60, end + 60];
}

class _VirtualMap extends MapView<String, int> {
  _VirtualMap() : super({'backing': 1});
  @override
  Iterable<MapEntry<String, int>> get entries => [MapEntry('virtual', 77)];
  @override
  void forEach(void Function(String, int) action) {
    action('virtual', 40);
  }

  @override
  bool containsValue(Object? value) => value == 99;
  @override
  Iterable<int> get values => [88];
  @override
  int update(String key, int Function(int) update,
          {int Function()? ifAbsent}) =>
      key == 'virtual' ? update(30) : ifAbsent!();
  @override
  Map<RK, RV> map<RK, RV>(MapEntry<RK, RV> Function(String, int) transform) =>
      Map.fromEntries([transform('virtual', 50)]);
}

const _genericClasses = '''
import 'dart:collection';
class Values<T> extends UnmodifiableListView<T> { Values(List<T> source) : super(source); }
class Entries<K,V> extends UnmodifiableMapView<K,V> { Entries(Map<K,V> source) : super(source); }
''';

List<Object?> _readVirtualList(List<int> list) {
  final trace = <int>[];
  list.forEach(trace.add);
  return [
    list.join('|'),
    trace,
    list.reversed.toList(),
    list.indexWhere((value) => value == 99, 2),
    list.firstWhere((value) => false, orElse: () => 66),
    list.fold<int>(5, (a, b) => a + b),
    list.map<int>((value) => value + 1).toList(),
    list.sublist(1, 2),
    list.toList(),
    list.iterator.moveNext(),
    list.hashCode,
    _equalsObject(list, 'virtual-list'),
    list.getRange(0, 1).toList()
  ];
}

List<Object?> _readVirtualMap(Map<String, int> map) {
  final trace = <Object?>[];
  map.forEach((key, value) => trace.add([key, value]));
  return [
    trace,
    map.containsValue(99),
    map.values.toList(),
    map.update('virtual', (value) => value + 2),
    map.update('missing', (value) => value, ifAbsent: () => 70),
    map.entries.map((entry) => [entry.key, entry.value]).toList(),
    map.map<String, int>((key, value) => MapEntry(key, value + 1))
  ];
}

bool _equalsObject(Object value, Object other) => value == other;

bool _isNullableIntList(Object value) => value is List<int?>;
bool _isNullableIntMap(Object value) => value is Map<String, int?>;

void main() {
  test(
      'interpreter-derived collections keep compatibility without retyping host inputs',
      () {
    final interpreter = D4rt();
    final host = <String>['10', '20', '30'];
    interpreter.registertopLevelFunction('source', (v, a, n, t) => host);
    interpreter.registertopLevelFunction('retain', (v, a, n, t) {
      expect(v.environment.get('calls'), 0);
      return a.single;
    });
    final observed = interpreter.execute(source: '''
$_genericClasses
int calls=0;
List<int> parsed() {
  final transform=source().map;
  final lazy=retain(transform((s) { calls++; return int.parse(s); }));
  final values=lazy.where((n) => n > 0).skip(0).take(3).toList();
  return values;
}
Set<int> parsedSet() { return source().map((s) => int.parse(s)).toSet(); }
Map<int,int> parsedMap() {
  return source().map((s) => int.parse(s)).toList().asMap();
}
List<int> fromSet() { return source().map((s) => int.parse(s)).toSet().toList(); }
List<int> fromMap() { return parsedMap().values.toList(); }
main() {
  final list=parsed();
  final direct=UnmodifiableListView<int>(list);
  final child=Values<int>(list);
  return [list,direct[0],child[1],list is List<int>,list is List<String>,calls,
    parsedSet().toList(),parsedMap(),fromSet(),fromMap()];
}
''');
    final oracle = host.map(int.parse).toList();
    expect(observed, [
      oracle,
      oracle[0],
      oracle[1],
      true,
      false,
      host.length,
      host.map(int.parse).toSet().toList(),
      oracle.asMap(),
      host.map(int.parse).toSet().toList(),
      oracle
    ]);
    expect(host, ['10', '20', '30']);

    for (final input in <Object>[
      <String>[],
      <String>['10'],
      <int?>[]
    ]) {
      final owner = D4rt();
      owner.registertopLevelFunction('source', (v, a, n, t) => input);
      for (final expression in [
        'source()',
        'source().where((v) => true).toList()'
      ]) {
        expect(() => owner.execute(source: '''
List<int> read() { return $expression; }
main() => read();
'''), throwsA(isA<RuntimeError>()));
      }
    }
  });
  test(
      'empty derived collections keep compatibility while declared wrong empties fail',
      () {
    expect(D4rt().execute(source: '''
import 'dart:collection';
main() {
  final derived=<String>[].map((s) => int.parse(s)).toList();
  final view=UnmodifiableListView<int>(derived);
  return [derived is List<int>,(derived as List<int>).length,view.length];
}
'''), [true, 0, 0]);
    expect(() => D4rt().execute(source: '''
List<int> read() { return <String>[].where((s) => true).toList(); }
main() => read();
'''), throwsA(isA<RuntimeError>()));
  });

  test(
      'field-backed collection getters keep state across interpreted and native access',
      () {
    const declarations = '''
import 'dart:collection';
class FieldMap extends MapView<String,int> {
  FieldMap() : super(<String,int>{'backing':1});
  final Iterable<String> keys = <String>['virtual'];
  final Iterable<int> values = <int>[41];
  final Iterable<MapEntry<String,int>> entries = <MapEntry<String,int>>[MapEntry<String,int>('virtual',42)];
  final int length = 9;
  final bool isEmpty = true;
  final bool isNotEmpty = false;
}
class InheritedFieldMap extends FieldMap {}
class FieldList extends UnmodifiableListView<int> {
  FieldList() : super(<int>[1,2]);
  final int first = 71;
  final int last = 72;
  final int single = 73;
  final int length = 1;
  final Iterable<int> reversed = <int>[74];
  final bool isEmpty = true;
  final bool isNotEmpty = false;
}
class InheritedFieldList extends FieldList {}
main(String kind) {
  final value = kind == 'map' ? FieldMap() : kind == 'inherited-map' ? InheritedFieldMap() :
      kind == 'list' ? FieldList() : InheritedFieldList();
  final properties = value is List
      ? [value.first,value.last,value.single,value.length,value.reversed.toList(),value.isEmpty,value.isNotEmpty]
      : [value.keys.toList(),value.values.toList(),
          value.entries.map((entry) => [entry.key,entry.value]).toList(),value.length,value.isEmpty,value.isNotEmpty];
  return [properties,observe(value),value];
}
''';
    final cases = <String, Object>{
      'map': _FieldMap(),
      'inherited-map': _InheritedFieldMap(),
      'list': _FieldList(),
      'inherited-list': _InheritedFieldList(),
    };
    for (final entry in cases.entries) {
      final interpreter = D4rt();
      Object? callbackReceiver;
      interpreter.registertopLevelFunction('observe', (v, a, n, t) {
        callbackReceiver = a.single;
        return _fieldProperties(a.single!);
      });
      final result = interpreter
          .execute(source: declarations, positionalArgs: [entry.key]) as List;
      final oracle = _fieldProperties(entry.value);
      expect(result[0], oracle, reason: 'interpreted ${entry.key}');
      expect(result[1], oracle, reason: 'registered callback ${entry.key}');
      expect(result[2], same(callbackReceiver));
      expect(_fieldProperties(result[2]), oracle,
          reason: 'execute return ${entry.key}');
    }
  });

  test('late field-backed native getter initializes once only on access', () {
    const declarations = '''
import 'dart:collection';
class LazyKeys extends MapView<String,int> {
  LazyKeys() : super(<String,int>{'backing':1});
  int reads = 0;
  late final Iterable<String> keys = createKeys();
  Iterable<String> createKeys() { reads++; return <String>['virtual']; }
}
main() => retain(LazyKeys());
''';
    final interpreter = D4rt();
    Object? callbackReceiver;
    final oracle = _LateFieldMap();
    interpreter.registertopLevelFunction('retain', (v, a, n, t) {
      callbackReceiver = a.single;
      expect((a.single as InterpretedInstance).get('reads'), oracle.reads);
      expect(oracle.reads, 0);
      return a.single;
    });
    final returned =
        interpreter.execute(source: declarations) as Map<String, int>;
    expect(returned, same(callbackReceiver));
    expect((returned as InterpretedInstance).get('reads'), oracle.reads);
    expect(returned.keys.toList(), oracle.keys.toList());
    expect((returned as InterpretedInstance).get('reads'), oracle.reads);
    expect(oracle.reads, 1);
    expect(returned.keys.toList(), oracle.keys.toList());
    expect(
        (returned as InterpretedInstance)
            .get('keys', visitor: interpreter.visitor!),
        ['virtual']);
    expect((returned as InterpretedInstance).get('reads'), oracle.reads);
  });

  test('nested generic direct and subclass views retain declarations and casts',
      () {
    final nativeList = UnmodifiableListView<List<int>>(<List<int>>[
      [7]
    ]);
    final nativeChild = _ListView<List<int>>(<List<int>>[
      [7]
    ]);
    final nativeMap = UnmodifiableMapView<String, List<int>>({
      'n': [7]
    });
    final nativeMapChild = _MapView<String, List<int>>({
      'n': [7]
    });
    final oracle = [
      for (final list in <Object>[nativeList, nativeChild])
        [
          list is List<List<int>>,
          list is List<List<String>>,
          (list as List<List<int>>)[0][0]
        ],
      for (final map in <Object>[nativeMap, nativeMapChild])
        [
          map is Map<String, List<int>>,
          map is Map<String, List<String>>,
          (map as Map<String, List<int>>)['n']![0]
        ]
    ];
    expect(D4rt().execute(source: '''
$_genericClasses
main() {
  final a = UnmodifiableListView<List<int>>(<List<int>>[<int>[7]]);
  final b = Values<List<int>>(<List<int>>[<int>[7]]);
  final c = UnmodifiableMapView<String,List<int>>(<String,List<int>>{'n': <int>[7]});
  final d = Entries<String,List<int>>(<String,List<int>>{'n': <int>[7]});
  return [for (final list in [a,b])
    [list is List<List<int>>, list is List<List<String>>, (list as List<List<int>>)[0][0]],
    for (final map in [c,d])
    [map is Map<String,List<int>>, map is Map<String,List<String>>, (map as Map<String,List<int>>)['n'][0]]];
}
'''), oracle);
    for (final expression in [
      'a as List<List<String>>',
      'c as Map<String,List<String>>'
    ]) {
      expect(() => D4rt().execute(source: '''
$_genericClasses
main() {
  final a = Values<List<int>>(<List<int>>[<int>[7]]);
  final c = Entries<String,List<int>>(<String,List<int>>{'n': <int>[7]});
  return $expression;
}
'''), throwsA(isA<RuntimeError>()));
    }
  });

  test(
      'noncore host collections keep existing direct subclass and cast operations',
      () {
    final date = DateTime.utc(2025);
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'sources',
        (v, a, n, t) => [
              <DateTime>[date],
              <String, DateTime>{'n': date}
            ]);
    final observed = interpreter.execute(source: '''
$_genericClasses
main() {
  final input = sources();
  final a = UnmodifiableListView<DateTime>(input[0]);
  final b = Values<DateTime>(input[0]);
  final c = UnmodifiableMapView<String,DateTime>(input[1]);
  final d = Entries<String,DateTime>(input[1]);
  return [for (final value in [a,b,input[0]])
    [value is List<DateTime>, value is List<Duration>, (value as List<DateTime>)[0]],
    for (final value in [c,d,input[1]])
    [value is Map<String,DateTime>, value is Map<String,Duration>, (value as Map<String,DateTime>)['n']]];
}
''');
    expect(observed, [
      for (final value in <Object>[
        UnmodifiableListView<DateTime>([date]),
        _ListView<DateTime>([date]),
        [date]
      ])
        [
          value is List<DateTime>,
          value is List<Duration>,
          (value as List<DateTime>)[0]
        ],
      for (final value in <Object>[
        UnmodifiableMapView<String, DateTime>({'n': date}),
        _MapView<String, DateTime>({'n': date}),
        {'n': date}
      ])
        [
          value is Map<String, DateTime>,
          value is Map<String, Duration>,
          (value as Map<String, DateTime>)['n']
        ]
    ]);
    expect(
        () => interpreter.execute(
            source: 'main() => sources()[0] as List<Duration>;'),
        throwsA(isA<RuntimeError>()));
  });

  test(
      'interpreted generic instances stay interpreted rather than fake native types',
      () {
    expect(D4rt().execute(source: '''
$_genericClasses
class Box<T> { Box(this.value); final T value; }
main() {
  final box = Box<int>(7);
  final a = UnmodifiableListView<Box<int>>(<Box<int>>[box]);
  final b = Values<Box<int>>(<Box<int>>[box]);
  final c = UnmodifiableMapView<String,Box<int>>(<String,Box<int>>{'n':box});
  final d = Entries<String,Box<int>>(<String,Box<int>>{'n':box});
  return [a[0].value, (b as List<Box<int>>)[0].value,
    (c as Map<String,Box<int>>)['n'].value, d['n'].value,
    identical(a[0], b[0]), b is List<Box<int>>, b is List<Box<String>>];
}
'''), [7, 7, 7, 7, true, true, false]);
  });

  test(
      'Null and Never source subtyping agrees with native direct and subclass views',
      () {
    final native = [
      UnmodifiableListView<Null>(<Null>[null]),
      _ListView<Null>(<Null>[null]),
      UnmodifiableListView<int>(<Never>[]),
      _ListView<int>(<Never>[]),
      UnmodifiableListView<int?>(<Null>[null]),
      _ListView<int?>(<Null>[null])
    ];
    expect(D4rt().execute(source: '''
$_genericClasses
main() => [
  for(final value in [UnmodifiableListView<Null>(<Null>[null]), Values<Null>(<Null>[null]),
    UnmodifiableListView<int>(<Never>[]), Values<int>(<Never>[]),
    UnmodifiableListView<int?>(<Null>[null]), Values<int?>(<Null>[null])])
  [value.length, value is List<Null>, value is List<int>, value is List<int?>]];
'''), [
      for (final value in native)
        [
          value.length,
          value is List<Null>,
          value is List<int>,
          _isNullableIntList(value)
        ]
    ]);
    final nativeMaps = [
      UnmodifiableMapView<String, Null>(<String, Null>{'n': null}),
      _MapView<String, Null>(<String, Null>{'n': null}),
      UnmodifiableMapView<String, int>(<Never, Never>{}),
      _MapView<String, int>(<Never, Never>{})
    ];
    expect(D4rt().execute(source: '''
$_genericClasses
main() => [for(final value in [UnmodifiableMapView<String,Null>(<String,Null>{'n':null}), Entries<String,Null>(<String,Null>{'n':null}),
  UnmodifiableMapView<String,int>(<Never,Never>{}), Entries<String,int>(<Never,Never>{})])
  [value.length, value is Map<String,Null>, value is Map<String,int>, value is Map<String,int?>]];
'''), [
      for (final value in nativeMaps)
        [
          value.length,
          value is Map<String, Null>,
          value is Map<String, int>,
          _isNullableIntMap(value)
        ]
    ]);
    for (final constructor in ['UnmodifiableListView<int>', 'Values<int>']) {
      expect(
          () => D4rt().execute(
              source: '$_genericClasses main() => $constructor(<Null>[]);'),
          throwsA(isA<RuntimeError>()));
    }
  });

  test(
      'host bottom and nullable sources preserve direct and subclass contracts',
      () {
    for (final input in <Object>[
      <Never>[],
      <Null>[null],
      <int?>[],
      <String>[],
      <String>['1'],
      <Never, Never>{},
      <String, Null>{'n': null},
      <String, int?>{},
      <int, int>{},
      <String, String>{},
    ]) {
      final interpreter = D4rt();
      interpreter.registertopLevelFunction('source', (v, a, n, t) => input);
      final list = input is List;
      for (final subclass in [false, true]) {
        final core = list
            ? (subclass ? 'Values<int>' : 'UnmodifiableListView<int>')
            : (subclass
                ? 'Entries<String,int>'
                : 'UnmodifiableMapView<String,int>');
        final nullable = list
            ? (subclass ? 'Values<int?>' : 'UnmodifiableListView<int?>')
            : (subclass
                ? 'Entries<String,int?>'
                : 'UnmodifiableMapView<String,int?>');
        if (list ? input is List<int> : input is Map<String, int>) {
          final value = interpreter.execute(
              source: '$_genericClasses main() => $core(source());');
          expect(list ? value is List<int> : value is Map<String, int>, isTrue);
        } else {
          expect(
              () => interpreter.execute(
                  source: '$_genericClasses main() => $core(source());'),
              throwsA(isA<RuntimeError>()));
        }
        if (list ? input is List<int?> : input is Map<String, int?>) {
          final value = interpreter.execute(
              source: '$_genericClasses main() => $nullable(source());');
          expect(
              list ? value is List<int?> : value is Map<String, int?>, isTrue);
          expect(
              list ? value is List<int> : value is Map<String, int>, isFalse);
        }
      }
    }
  });

  test('MapView inherited operations use backing map despite index override',
      () {
    List<Object?> read(Map<String, int> value) {
      final trace = <Object?>[];
      value.forEach((key, item) => trace.add([key, item]));
      return [
        value['n'],
        value.containsValue(1),
        value.containsValue(11),
        value.values.toList(),
        value.entries.map((entry) => [entry.key, entry.value]).toList(),
        trace,
        value.map((key, item) => MapEntry(key, item + 1)),
        value.cast<String, int>()['n'],
        value.toString()
      ];
    }

    const source = '''
import 'dart:collection';
class Adjusted extends MapView<String,int> {
  Adjusted() : super(<String,int>{'n':1});
  int? operator [](Object? key) => (super[key] ?? 0) + 10;
}
main() => Adjusted();
''';
    final returned = D4rt().execute(source: source) as Map<String, int>;
    expect(read(returned), read(_AdjustedMap({'n': 1})));
    expect(D4rt().execute(source: '''
import 'dart:collection';
class Adjusted extends MapView<String,int> {
  Adjusted() : super(<String,int>{'n':1});
  int? operator [](Object? key) => (super[key] ?? 0) + 10;
}
main() { final value = Adjusted(); return [value['n'], value.containsValue(1), value.containsValue(11), value.values.toList()]; }
'''), [
      11,
      true,
      false,
      [1]
    ]);
  });

  test('native List virtual calls include callbacks generic and named paths',
      () {
    final interpreter = D4rt();
    interpreter.registertopLevelFunction(
        'inspect', (v, a, n, t) => _readVirtualList(a.single as List<int>));
    const declarations = '''
import 'dart:collection';
class Virtual extends UnmodifiableListView<int> {
  Virtual() : super(<int>[1,2]);
  Iterator<int> get iterator => <int>[91].iterator;
  int get hashCode => 123;
  bool operator ==(Object other) => other == 'virtual-list';
  String join([String separator = '']) => 'virtual' + separator;
  void forEach(void Function(int) action) { action(41); action(42); }
  Iterable<int> get reversed => <int>[71,72];
  int indexWhere(bool Function(int) test, [int start = 0]) => test(99) ? start + 10 : -1;
  int firstWhere(bool Function(int) test, {int Function()? orElse}) => test(55) ? 55 : orElse();
  R fold<R>(R initialValue, R Function(R,int) combine) => combine(initialValue,30);
  Iterable<R> map<R>(R Function(int) convert) => <R>[convert(20)];
  List<int> sublist(int start, [int? end]) => <int>[start+80,end ?? 90];
  Iterable<int> getRange(int start,int end) => <int>[start+60,end+60];
}
''';
    final oracle = _readVirtualList(_VirtualList());
    expect(
        interpreter.execute(
            source: '$declarations main() => inspect(Virtual());'),
        oracle);
    final value = interpreter.execute(
        source: '$declarations main() => Virtual();') as List<int>;
    expect(_readVirtualList(value), oracle);
    void failCallback(int _) => throw StateError('callback');
    expect(() => value.forEach(failCallback), throwsStateError);
  });

  test(
      'native Map virtual callbacks and typed interpreted keys match native subclasses',
      () {
    final interpreter = D4rt();
    const declarations = '''
import 'dart:collection';
class Virtual extends MapView<String,int> {
  Virtual() : super(<String,int>{'backing':1});
  Iterable<MapEntry<String,int>> get entries => <MapEntry<String,int>>[MapEntry<String,int>('virtual',77)];
  void forEach(void Function(String,int) action) { action('virtual',40); }
  bool containsValue(Object? value) => value == 99;
  Iterable<int> get values => <int>[88];
  int update(String key,int Function(int) update,{int Function()? ifAbsent}) => key == 'virtual' ? update(30) : ifAbsent();
  Map<RK,RV> map<RK,RV>(MapEntry<RK,RV> Function(String,int) transform) => Map.fromEntries([transform('virtual',50)]);
}
class Keys extends MapView<String,int> {
  Keys() : super(<String,int>{'backing':1});
  Iterable<String> get keys => <String>['virtual'];
}
''';
    interpreter.registertopLevelFunction('inspect',
        (v, a, n, t) => _readVirtualMap(a.single as Map<String, int>));
    expect(
        interpreter.execute(
            source: '$declarations main() => inspect(Virtual());'),
        _readVirtualMap(_VirtualMap()));
    final keys = interpreter.execute(source: '$declarations main() => Keys();')
        as Map<String, int>;
    expect(keys.keys.toList(), _VirtualKeys().keys.toList());
    expect(
        interpreter.execute(
            source: '$declarations main() => Keys().keys.toList();'),
        _VirtualKeys().keys.toList());
  });
}
