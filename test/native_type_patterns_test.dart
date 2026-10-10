import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

const _uriSource = '''
String typed(Object? value) => switch (value) {
  final Uri uri => uri.toString(),
  _ => 'no match',
};
String record(Object? value) => switch ((0, value)) {
  (0, final Uri uri) => uri.toString(),
  _ => 'no match',
};
List<bool> inspect(Object? value) => [
  value is Uri,
  switch (value) { final Uri uri => true, _ => false },
  switch ((0, value)) { (0, final Uri uri) => true, _ => false },
  switch (value) { Uri _ => true, _ => false },
  switch (value) { final Uri _ => true, _ => false },
  switch (value) { Uri() => true, _ => false },
];
List<bool> nullable(Object? value) => [
  switch (value) { final Uri? uri => true, _ => false },
  switch (value) { Uri? _ => true, _ => false },
  switch (value) { final Object? object => true, _ => false },
  switch (value) { final dynamic object => true, _ => false },
  switch (value) { final Object object => true, _ => false },
];
Object? bind(Object? value) => switch (value) {
  final Uri uri => uri,
  _ => null,
};
Object? cast(Object? value) => switch (value) {
  var uri as Uri => uri,
};
List<String> main() {
  final values = [
    Uri.https('example.com', '/read'),
    Uri.parse('https://example.com/read'),
    Uri(path: '/read'),
  ];
  return [for (final value in values) typed(value),
          for (final value in values) record(value)];
}
''';

const _erasedCollectionSource = '''
import 'dart:collection';
class OwnedList extends UnmodifiableListView<int> {
  OwnedList(super.source);
}
class OwnedMap extends UnmodifiableMapView<String, int> {
  OwnedMap(super.source);
}
List<bool> inspect(Object? value) => [
  value is List,
  switch (value) { final List list => true, _ => false },
  switch ((value,)) { (final List list,) => true, _ => false },
  switch (value) { List _ => true, _ => false },
  switch (value) { List() => true, _ => false },
  value is Map,
  switch (value) { final Map map => true, _ => false },
  switch ((value,)) { (final Map map,) => true, _ => false },
  switch (value) { Map _ => true, _ => false },
  switch (value) { Map() => true, _ => false },
  value is Set,
  switch (value) { final Set set => true, _ => false },
  switch ((value,)) { (final Set set,) => true, _ => false },
  switch (value) { Set _ => true, _ => false },
  switch (value) { Set() => true, _ => false },
];
int castList(Object? value) => switch (value) { var list as List => list.length };
int castMap(Object? value) => switch (value) { var map as Map => map.length };
int castSet(Object? value) => switch (value) { var set as Set => set.length };
int rejectListAsMap() => castMap(OwnedList([1]));
int rejectMapAsList() => castList(OwnedMap({'key': 1}));
List<Object?> main() {
  final list = OwnedList([1]);
  final map = OwnedMap({'key': 1});
  return [
    inspect(list), inspect(map), castList(list), castMap(map),
    switch (list) { final List<int> list => true, _ => false },
    switch (list) { final List<String> list => true, _ => false },
    switch (map) { final Map<String, int> map => true, _ => false },
    switch (map) { final Map<int, int> map => true, _ => false },
  ];
}
''';

abstract class _NativeReading {
  int get value;
}

class _ReadingImplementation implements _NativeReading {
  @override
  final int value;
  _ReadingImplementation(this.value);
}

// Its name deliberately resembles the interpreted type without implementing it.
class _PretendReading {}

class _NativeBox<T> {}

void main() {
  test('inferred collection subclasses retain erased and generic interfaces',
      () {
    expect(D4rt().execute(source: _erasedCollectionSource), [
      [...List.filled(5, true), ...List.filled(10, false)],
      [
        ...List.filled(5, false),
        ...List.filled(5, true),
        ...List.filled(5, false)
      ],
      1,
      1,
      true,
      false,
      true,
      false,
    ]);
    for (final name in ['rejectListAsMap', 'rejectMapAsList']) {
      expect(() => D4rt().execute(source: _erasedCollectionSource, name: name),
          throwsA(isA<RuntimeError>()));
    }
  });

  test('raw and wrapped erased collection checks reject unrelated kinds', () {
    final core = Environment();
    Stdlib(core).register();
    final values = <Object?>[
      <int>[1],
      <String, int>{'key': 1},
      <int>{1},
      Uri(path: '/read'),
      null
    ];
    for (final native in values) {
      final wrapped = native == null || native is Uri
          ? native
          : BridgedInstance(core.toBridgedClass(native), native);
      for (final value in [native, wrapped]) {
        expect(
            D4rt().execute(
                source: _erasedCollectionSource,
                name: 'inspect',
                positionalArgs: [value]),
            [
              ...List.filled(5, native is List),
              ...List.filled(5, native is Map),
              ...List.filled(5, native is Set),
            ]);
        for (final (name, matches) in [
          ('castList', native is List),
          ('castMap', native is Map),
          ('castSet', native is Set),
        ]) {
          if (matches) {
            expect(
                D4rt().execute(
                    source: _erasedCollectionSource,
                    name: name,
                    positionalArgs: [value]),
                1);
          } else {
            expect(
                () => D4rt().execute(
                    source: _erasedCollectionSource,
                    name: name,
                    positionalArgs: [value]),
                throwsA(isA<RuntimeError>()));
          }
        }
      }
    }
  });

  test('collection namesakes do not acquire native core interfaces', () {
    const source = '''
class List {}
class Map {}
class Set {}
inspect(Object? value) => [
  value is List,
  switch (value) { final List list => true, _ => false },
  switch (value) { List _ => true, _ => false },
  switch (value) { List() => true, _ => false },
  value is Map,
  switch (value) { final Map map => true, _ => false },
  value is Set,
  switch (value) { final Set set => true, _ => false },
];
''';
    for (final value in [
      <int>[1],
      <String, int>{'key': 1},
      <int>{1}
    ]) {
      expect(
          D4rt().execute(
              source: source, name: 'inspect', positionalArgs: [value]),
          List.filled(8, false));
    }
  });

  test('Uri constructors bind usable values in plain and record patterns', () {
    expect(D4rt().execute(source: _uriSource), [
      'https://example.com/read',
      'https://example.com/read',
      '/read',
      'https://example.com/read',
      'https://example.com/read',
      '/read',
    ]);
  });

  test('raw and wrapped native values share genuine pattern type checks', () {
    final core = Environment();
    Stdlib(core).register();
    final uri = Uri.https('example.com', '/host');
    final wrapped = BridgedInstance(core.toBridgedClass(uri), uri);
    for (final value in [uri, wrapped]) {
      expect(
        D4rt().execute(
            source: _uriSource, name: 'inspect', positionalArgs: [value]),
        List.filled(6, true),
      );
      expect(
        D4rt()
            .execute(source: _uriSource, name: 'bind', positionalArgs: [value]),
        same(uri),
      );
      expect(
        D4rt()
            .execute(source: _uriSource, name: 'cast', positionalArgs: [value]),
        same(uri),
      );
    }
    for (final value in ['https://example.com/host', null, DateTime(2026)]) {
      expect(
        D4rt().execute(
            source: _uriSource, name: 'inspect', positionalArgs: [value]),
        List.filled(6, false),
      );
      expect(
        () => D4rt()
            .execute(source: _uriSource, name: 'cast', positionalArgs: [value]),
        throwsA(isA<RuntimeError>()),
      );
    }
  });

  test('nullable native patterns and top types preserve null handling', () {
    for (final value in [null, Uri(path: '/read')]) {
      expect(
        D4rt().execute(
            source: _uriSource, name: 'nullable', positionalArgs: [value]),
        [true, true, true, true, value != null],
      );
    }
    expect(
      D4rt().execute(
          source: _uriSource, name: 'nullable', positionalArgs: ['not a Uri']),
      [false, false, true, true, true],
    );
  });

  test('another core bridge matches without admitting unrelated native values',
      () {
    const source = '''
List<bool> inspect(Object? value) => [
  value is DateTime,
  switch (value) { final DateTime date => date.year == 2026, _ => false },
  switch ((value,)) { (final DateTime date,) => true, _ => false },
  switch (value) { DateTime _ => true, _ => false },
  switch (value) { DateTime() => true, _ => false },
];
''';
    for (final value in [DateTime(2026), Uri(path: '/read'), 'date']) {
      expect(
        D4rt()
            .execute(source: source, name: 'inspect', positionalArgs: [value]),
        List.filled(5, value is DateTime),
      );
    }
  });

  test('registered native interface checker recognizes a real implementation',
      () {
    final d4rt = D4rt();
    d4rt.registerBridgedClass(
      BridgedClass(
        nativeType: _NativeReading,
        name: 'Reading',
        isSubtypeOfFunc: (value) => value is _NativeReading,
        getters: {
          'value': (visitor, target) => (target as _NativeReading).value
        },
      ),
      'package:native/reading.dart',
    );
    d4rt.registerBridgedClass(
      BridgedClass(nativeType: _PretendReading, name: 'PretendReading'),
      'package:native/reading.dart',
    );
    const source = '''
import 'package:native/reading.dart';
List<bool> inspect(Object? value) => [
  value is Reading,
  switch (value) { final Reading reading => reading.value == 7, _ => false },
  switch ((value,)) { (final Reading reading,) => true, _ => false },
  switch (value) { Reading _ => true, _ => false },
  switch (value) { Reading() => true, _ => false },
];
''';
    for (final value in [_ReadingImplementation(7), _PretendReading(), null]) {
      expect(
          d4rt.execute(
              source: source, name: 'inspect', positionalArgs: [value]),
          List.filled(5, value is _NativeReading));
    }
  });

  test('generic bridged patterns retain wrapper arguments and reject erasure',
      () {
    final boxType = BridgedClass(
      nativeType: _NativeBox,
      name: 'Box',
      typeParameterCount: 1,
      isSubtypeOfFunc: (value) => value is _NativeBox,
    );
    final d4rt = D4rt()
      ..registerBridgedClass(boxType, 'package:native/box.dart');
    const source = '''
import 'package:native/box.dart';
List<bool> inspect(Object? value) => [
  switch (value) { final Box<int> box => true, _ => false },
  switch (value) { Box<int> _ => true, _ => false },
  switch (value) { Box<int>() => true, _ => false },
  switch (value) { final Box<String> box => true, _ => false },
];
''';
    final native = _NativeBox<int>();
    final wrapped = BridgedInstance(boxType, native,
        typeArguments: [BridgedClass(nativeType: int, name: 'int')]);
    expect(
        d4rt.execute(
            source: source, name: 'inspect', positionalArgs: [wrapped]),
        [true, true, true, false]);
    expect(
        d4rt.execute(source: source, name: 'inspect', positionalArgs: [native]),
        [false, false, false, false]);
  });

  test(
      'interpreted hierarchy, generic arguments and enum identities remain sound',
      () {
    const source = '''
class Base {}
class Child extends Base {}
abstract class Marker {}
class Tagged implements Marker {}
class Box<T> {}
enum Color { red, blue }
enum OtherColor { red }
List<bool> main() {
  final child = Child();
  final tagged = Tagged();
  final box = Box<int>();
  return [
    switch (child) { final Base base => true, _ => false },
    switch (child) { Base() => true, _ => false },
    switch (tagged) { final Marker marker => true, _ => false },
    switch (tagged) { Marker() => true, _ => false },
    switch (box) { final Box<num> box => true, _ => false },
    switch (box) { Box<String>() => true, _ => false },
    switch (Color.red) { final Color color => true, _ => false },
    switch (OtherColor.red) { Color _ => true, _ => false },
    switch (1) { num _ => true, _ => false },
  ];
}
''';
    expect(D4rt().execute(source: source),
        [true, true, true, true, true, false, true, false, true]);
  });
}
