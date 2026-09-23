import 'dart:collection';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

const _source = '''
List<Object?> inspect(
  Object? matchingMap,
  Object? wrongMapKey,
  Object? wrongMapValue,
  Object? wrongMapKind,
  Object? matchingList,
  Object? wrongListElement,
  Object? matchingSet,
  Object? wrongSetElement,
) {
  return [
    matchingMap is Map<Object?, Object?>,
    switch (matchingMap) {
      final Map<Object?, Object?> map => map.length,
      _ => -1,
    },
    wrongMapKey is Map<int, Object?>,
    switch (wrongMapKey) {
      final Map<int, Object?> map => map.length,
      _ => -1,
    },
    wrongMapValue is Map<String, int>,
    switch (wrongMapValue) {
      final Map<String, int> map => map.length,
      _ => -1,
    },
    wrongMapKind is Map<Object?, Object?>,
    switch (wrongMapKind) {
      final Map<Object?, Object?> map => map.length,
      _ => -1,
    },
    matchingList is List<num>,
    switch (matchingList) {
      final List<num> list => list.length,
      _ => -1,
    },
    wrongListElement is List<num>,
    switch (wrongListElement) {
      final List<num> list => list.length,
      _ => -1,
    },
    matchingSet is Set<num>,
    switch (matchingSet) {
      final Set<num> set => set.length,
      _ => -1,
    },
    wrongSetElement is Set<num>,
    switch (wrongSetElement) {
      final Set<num> set => set.length,
      _ => -1,
    },
  ];
}
''';

List<Object?> _inspectNatively(List<Object?> values) {
  final matchingMap = values[0];
  final wrongMapKey = values[1];
  final wrongMapValue = values[2];
  final wrongMapKind = values[3];
  final matchingList = values[4];
  final wrongListElement = values[5];
  final matchingSet = values[6];
  final wrongSetElement = values[7];

  return [
    matchingMap is Map<Object?, Object?>,
    switch (matchingMap) {
      final Map<Object?, Object?> map => map.length,
      _ => -1,
    },
    wrongMapKey is Map<int, Object?>,
    switch (wrongMapKey) {
      final Map<int, Object?> map => map.length,
      _ => -1,
    },
    wrongMapValue is Map<String, int>,
    switch (wrongMapValue) {
      final Map<String, int> map => map.length,
      _ => -1,
    },
    wrongMapKind is Map<Object?, Object?>,
    switch (wrongMapKind) {
      final Map<Object?, Object?> map => map.length,
      _ => -1,
    },
    matchingList is List<num>,
    switch (matchingList) {
      final List<num> list => list.length,
      _ => -1,
    },
    wrongListElement is List<num>,
    switch (wrongListElement) {
      final List<num> list => list.length,
      _ => -1,
    },
    matchingSet is Set<num>,
    switch (matchingSet) {
      final Set<num> set => set.length,
      _ => -1,
    },
    wrongSetElement is Set<num>,
    switch (wrongSetElement) {
      final Set<num> set => set.length,
      _ => -1,
    },
  ];
}

const _reifiedSource = '''
List<Object?> inspectReified(
  Object? emptyMap,
  Object? sameKeyMap,
  Object? sameValueMap,
  Object? emptyList,
  Object? sameList,
  Object? emptySet,
  Object? sameSet,
) => [
  emptyMap is Map<String, Object?>,
  switch (emptyMap) {
    final Map<String, Object?> map => map.length,
    _ => -1,
  },
  sameKeyMap is Map<int, Object?>,
  switch (sameKeyMap) {
    final Map<int, Object?> map => map.length,
    _ => -1,
  },
  sameValueMap is Map<String, int>,
  switch (sameValueMap) {
    final Map<String, int> map => map.length,
    _ => -1,
  },
  emptyList is List<int>,
  switch (emptyList) {
    final List<int> list => list.length,
    _ => -1,
  },
  sameList is List<int>,
  switch (sameList) {
    final List<int> list => list.length,
    _ => -1,
  },
  emptySet is Set<int>,
  switch (emptySet) {
    final Set<int> set => set.length,
    _ => -1,
  },
  sameSet is Set<int>,
  switch (sameSet) {
    final Set<int> set => set.length,
    _ => -1,
  },
];
''';

List<Object?> _inspectReifiedNatively(List<Object?> values) {
  final emptyMap = values[0];
  final sameKeyMap = values[1];
  final sameValueMap = values[2];
  final emptyList = values[3];
  final sameList = values[4];
  final emptySet = values[5];
  final sameSet = values[6];
  return [
    emptyMap is Map<String, Object?>,
    switch (emptyMap) {
      final Map<String, Object?> map => map.length,
      _ => -1,
    },
    sameKeyMap is Map<int, Object?>,
    switch (sameKeyMap) {
      final Map<int, Object?> map => map.length,
      _ => -1,
    },
    sameValueMap is Map<String, int>,
    switch (sameValueMap) {
      final Map<String, int> map => map.length,
      _ => -1,
    },
    emptyList is List<int>,
    switch (emptyList) {
      final List<int> list => list.length,
      _ => -1,
    },
    sameList is List<int>,
    switch (sameList) {
      final List<int> list => list.length,
      _ => -1,
    },
    emptySet is Set<int>,
    switch (emptySet) {
      final Set<int> set => set.length,
      _ => -1,
    },
    sameSet is Set<int>,
    switch (sameSet) {
      final Set<int> set => set.length,
      _ => -1,
    },
  ];
}

const _castSource = '''
int castList(Object? value) => switch (value) {
  (var list as List<int>) => list.length,
  _ => -1,
};

int castMap(Object? value) => switch (value) {
  (var map as Map<String, Object?>) => map.length,
  _ => -1,
};

int castSet(Object? value) => switch (value) {
  (var set as Set<int>) => set.length,
  _ => -1,
};
''';

int _castListNatively(Object? value) => switch (value) {
      (var list as List<int>) => list.length,
      // A cast pattern either binds or throws; retain the fallback for D4rt parity.
      // ignore: unreachable_switch_case, dead_code
      _ => -1,
    };

int _castMapNatively(Object? value) => switch (value) {
      (var map as Map<String, Object?>) => map.length,
      // A cast pattern either binds or throws; retain the fallback for D4rt parity.
      // ignore: unreachable_switch_case, dead_code
      _ => -1,
    };

int _castSetNatively(Object? value) => switch (value) {
      (var set as Set<int>) => set.length,
      // A cast pattern either binds or throws; retain the fallback for D4rt parity.
      // ignore: unreachable_switch_case, dead_code
      _ => -1,
    };

const _bridgedSource = '''
List<bool> checkBridged(Object? map, Object? list, Object? set) => [
  map is Map<String, Object?>,
  list is List<int>,
  set is Set<int>,
];
''';

void main() {
  test('host generic collections use native type-pattern semantics', () {
    final values = <Object?>[
      UnmodifiableMapView<String, Object?>({'key': null}),
      UnmodifiableMapView<String, Object?>({'key': null}),
      UnmodifiableMapView<String, String>({'key': 'not an int'}),
      UnmodifiableListView<String>(['not a map']),
      UnmodifiableListView<int>([1]),
      UnmodifiableListView<String>(['not a num']),
      UnmodifiableSetView<int>({1}),
      UnmodifiableSetView<String>({'not a num'}),
    ];

    final nativeOutcome = _inspectNatively(values);
    final d4rtOutcome = D4rt().execute(
      source: _source,
      name: 'inspect',
      positionalArgs: values,
    );

    expect(
        nativeOutcome,
        equals([
          true,
          1,
          false,
          -1,
          false,
          -1,
          false,
          -1,
          true,
          1,
          false,
          -1,
          true,
          1,
          false,
          -1
        ]));
    expect(d4rtOutcome, equals(nativeOutcome));
  });

  test('host const empty collections use reified is and switch patterns', () {
    final values = <Object?>[
      const <String, Object?>{},
      const <String, Object?>{},
      const <String, Object?>{},
      const <Object?>[],
      const <int>[],
      const <String>[],
      const <int>{},
      const <String>{},
    ];
    final nativeOutcome = _inspectNatively(values);
    expect(
      nativeOutcome,
      equals([
        true,
        0,
        false,
        -1,
        false,
        -1,
        false,
        -1,
        true,
        0,
        false,
        -1,
        true,
        0,
        false,
        -1,
      ]),
    );
    expect(
      D4rt().execute(source: _source, name: 'inspect', positionalArgs: values),
      equals(nativeOutcome),
    );
  });

  test('reified arguments reject empty and same-content collections', () {
    final values = <Object?>[
      UnmodifiableMapView<int, Object?>(<int, Object?>{}),
      UnmodifiableMapView<String, Object?>({'key': null}),
      <String, Object?>{'key': 1},
      <Object>[],
      <Object>[1],
      <Object>{},
      <Object>{1},
    ];

    final nativeOutcome = _inspectReifiedNatively(values);
    expect(
        nativeOutcome,
        equals([
          false,
          -1,
          false,
          -1,
          false,
          -1,
          false,
          -1,
          false,
          -1,
          false,
          -1,
          false,
          -1
        ]));
    final d4rtOutcome = D4rt().execute(
      source: _reifiedSource,
      name: 'inspectReified',
      positionalArgs: values,
    );
    expect(d4rtOutcome, equals(nativeOutcome));
  });

  test('matching reified arguments also match empty and populated collections',
      () {
    final values = <Object?>[
      UnmodifiableMapView<String, Object?>(<String, Object?>{}),
      <int, Object?>{1: null},
      <String, int>{'key': 1},
      <int>[],
      <int>[1],
      <int>{},
      <int>{1},
    ];
    final nativeOutcome = _inspectReifiedNatively(values);
    expect(
        nativeOutcome,
        equals(
            [true, 0, true, 1, true, 1, true, 0, true, 1, true, 0, true, 1]));
    expect(
      D4rt().execute(
        source: _reifiedSource,
        name: 'inspectReified',
        positionalArgs: values,
      ),
      equals(nativeOutcome),
    );
  });

  test('bridged native collections retain their reified arguments', () {
    final nativeMap = UnmodifiableMapView<String, Object?>({'key': null});
    final nativeList = <Object>[1];
    final nativeSet = <int>{1};
    final wrapped = <Object?>[
      BridgedInstance(BridgedClass(nativeType: Map, name: 'Map'), nativeMap),
      BridgedInstance(BridgedClass(nativeType: List, name: 'List'), nativeList),
      BridgedInstance(BridgedClass(nativeType: Set, name: 'Set'), nativeSet),
    ];
    final nativeOutcome = <bool>[
      // ignore: unnecessary_type_check
      nativeMap is Map<String, Object?>,
      nativeList is List<int>,
      // ignore: unnecessary_type_check
      nativeSet is Set<int>,
    ];
    expect(nativeOutcome, equals([true, false, true]));
    expect(
      D4rt().execute(
        source: _bridgedSource,
        name: 'checkBridged',
        positionalArgs: wrapped,
      ),
      equals(nativeOutcome),
    );
  });

  test('cast patterns use the same reified collection arguments', () {
    final cases = <(String, Object?, int Function(Object?))>[
      ('castList', <int>[1], _castListNatively),
      (
        'castMap',
        UnmodifiableMapView<String, Object?>({'key': null}),
        _castMapNatively
      ),
      ('castSet', <int>{1}, _castSetNatively),
    ];
    for (final (name, value, nativeCast) in cases) {
      expect(
        D4rt()
            .execute(source: _castSource, name: name, positionalArgs: [value]),
        nativeCast(value),
      );
    }
    final mismatches = <(String, Object?, int Function(Object?))>[
      ('castList', <Object>[1], _castListNatively),
      (
        'castMap',
        UnmodifiableMapView<int, Object?>(<int, Object?>{}),
        _castMapNatively
      ),
      ('castSet', <Object>{1}, _castSetNatively),
    ];
    for (final (name, value, nativeCast) in mismatches) {
      expect(() => nativeCast(value), throwsA(isA<TypeError>()));
      expect(
        () => D4rt().execute(
          source: _castSource,
          name: name,
          positionalArgs: [value],
        ),
        throwsA(isA<RuntimeError>()),
      );
    }
  });
}
