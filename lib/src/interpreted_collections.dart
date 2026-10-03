part of 'runtime_types.dart';

// These are the interpreted identity itself, not boundary adapters. Native
// consumers can see subclasses at any graph depth without a graph walk.
mixin _CollectionDispatch on InterpretedInstance {
  late InterpreterVisitor _constructionVisitor;
  InterpreterVisitor? _hostVisitor;

  InterpreterVisitor get _dispatchVisitor {
    final current = InterpreterVisitor.currentCollectionVisitor;
    if (current != null) return current;
    final visitor = _constructionVisitor;
    return _hostVisitor ??= InterpreterVisitor(
      globalEnvironment: visitor.globalEnvironment,
      moduleLoader: visitor.moduleLoader,
      initiallibrary: visitor.currentLibrary,
      onPrint: visitor.onPrint,
    );
  }

  Object? _callOverride(InterpretedFunction function, List<Object?> args,
      [Map<String, Object?> named = const {}, List<RuntimeType>? types]) {
    Object? callableArgument(Object? value) => value is Function
        ? NativeFunction(
            (visitor, positional, named, types) => Function.apply(
                value,
                positional,
                named.map((key, value) => MapEntry(Symbol(key), value))),
            arity: 0)
        : value;
    for (var i = 0; i < args.length; i++) {
      args[i] = callableArgument(args[i]);
    }
    try {
      return function.bind(this).call(
          _dispatchVisitor,
          args,
          named.isEmpty
              ? named
              : named
                  .map((key, value) => MapEntry(key, callableArgument(value))),
          types);
    } on ReturnException catch (error) {
      return error.value;
    } on InternalInterpreterException catch (error) {
      throw error.originalThrownValue ?? error;
    }
  }

  Object? _readCollectionProperty(String name, Object? Function() inherited) {
    // Match InterpretedInstance.get: initialized instance fields, including
    // inherited and late fields, take precedence over function-backed getters.
    if (_fields.containsKey(name)) {
      final value = _fields[name];
      return value is LateVariable ? value.value : value;
    }
    final getter = klass.findInstanceGetter(name);
    return getter == null ? inherited() : _callOverride(getter, const []);
  }

  Object? _collectionMethod(
      String name, List<Object?> args, Object? Function() inherited,
      {Map<String, Object?> named = const {}, List<RuntimeType>? types}) {
    final method = klass.findInstanceMethod(name);
    return method == null
        ? inherited()
        : _callOverride(method, args, named, types);
  }

  @override
  int get hashCode =>
      _readCollectionProperty('hashCode', () => super.hashCode) as int;
  @override
  bool operator ==(Object other) {
    final operator = findOperator('==');
    return operator == null
        ? super == other
        : _callOverride(operator, [other]) as bool;
  }
}

// Iterator has no cast API. Adapt only current, never advance it at exposure.
final class _CollectionIterator<T> implements Iterator<T> {
  _CollectionIterator(this.source);
  final Iterator source;
  @override
  T get current => source.current as T;
  @override
  bool moveNext() => source.moveNext();
}

final class _InterpretedList<T> extends InterpretedInstance
    with _CollectionDispatch, ListMixin<T> {
  _InterpretedList(super.klass, InterpreterVisitor visitor,
      {super.typeArguments}) {
    _constructionVisitor = visitor;
  }
  List get _source => bridgedSuperObject as List;
  @override
  int get length =>
      _readCollectionProperty('length', () => _source.length) as int;

  @override
  set length(int value) {
    final setter = klass.findInstanceSetter('length');
    if (setter != null) {
      _callOverride(setter, [value]);
    } else {
      _source.length = value;
    }
  }

  @override
  T operator [](int index) {
    final operator = findOperator('[]');
    return (operator == null
        ? _source[index]
        : _callOverride(operator, [index])) as T;
  }

  @override
  void operator []=(int index, T value) {
    final operator = findOperator('[]=');
    if (operator == null) {
      _source[index] = value;
    } else {
      _callOverride(operator, [index, value]);
    }
  }

  @override
  void add(T value) =>
      _collectionMethod('add', [value], () => _source.add(value));
  @override
  void addAll(Iterable<T> values) =>
      _collectionMethod('addAll', [values], () => _source.addAll(values));
  @override
  void clear() => _collectionMethod('clear', [], () => _source.clear());
  @override
  bool remove(Object? value) =>
      _collectionMethod('remove', [value], () => _source.remove(value)) as bool;
  @override
  T removeAt(int index) =>
      _collectionMethod('removeAt', [index], () => _source.removeAt(index))
          as T;
  @override
  T removeLast() =>
      _collectionMethod('removeLast', [], () => _source.removeLast()) as T;
  @override
  void insert(int index, T value) => _collectionMethod(
      'insert', [index, value], () => _source.insert(index, value));
  @override
  void insertAll(int index, Iterable<T> values) => _collectionMethod(
      'insertAll', [index, values], () => _source.insertAll(index, values));
  @override
  void removeRange(int start, int end) => _collectionMethod(
      'removeRange', [start, end], () => _source.removeRange(start, end));
  @override
  void removeWhere(bool Function(T) test) => _collectionMethod('removeWhere',
      [test], () => _source.removeWhere((value) => test(value as T)));
  @override
  void retainWhere(bool Function(T) test) => _collectionMethod('retainWhere',
      [test], () => _source.retainWhere((value) => test(value as T)));
  @override
  void sort([int Function(T, T)? compare]) => _collectionMethod(
      'sort',
      [compare],
      () => _source
          .sort(compare == null ? null : (a, b) => compare(a as T, b as T)));
  @override
  void shuffle([Random? random]) =>
      _collectionMethod('shuffle', [random], () => _source.shuffle(random));
  @override
  void setAll(int index, Iterable<T> values) => _collectionMethod(
      'setAll', [index, values], () => _source.setAll(index, values));
  @override
  void setRange(int start, int end, Iterable<T> values, [int skipCount = 0]) =>
      _collectionMethod('setRange', [start, end, values, skipCount],
          () => _source.setRange(start, end, values, skipCount));
  @override
  void fillRange(int start, int end, [T? value]) => _collectionMethod(
      'fillRange',
      [start, end, value],
      () => _source.fillRange(start, end, value));
  @override
  void replaceRange(int start, int end, Iterable<T> values) =>
      _collectionMethod('replaceRange', [start, end, values],
          () => _source.replaceRange(start, end, values));
  @override
  T get first => _readCollectionProperty('first', () => super.first) as T;
  @override
  set first(T value) {
    final setter = klass.findInstanceSetter('first');
    if (setter != null) {
      _callOverride(setter, [value]);
    } else {
      _source.first = value;
    }
  }

  @override
  T get last => _readCollectionProperty('last', () => super.last) as T;
  @override
  set last(T value) {
    final setter = klass.findInstanceSetter('last');
    if (setter != null) {
      _callOverride(setter, [value]);
    } else {
      _source.last = value;
    }
  }

  @override
  T get single => _readCollectionProperty('single', () => super.single) as T;
  @override
  bool get isEmpty =>
      _readCollectionProperty('isEmpty', () => super.isEmpty) as bool;
  @override
  bool get isNotEmpty =>
      _readCollectionProperty('isNotEmpty', () => super.isNotEmpty) as bool;
  @override
  bool contains(Object? value) =>
      _collectionMethod('contains', [value], () => super.contains(value))
          as bool;
  @override
  T elementAt(int index) =>
      _collectionMethod('elementAt', [index], () => super.elementAt(index))
          as T;

  // UnmodifiableListView inherits ListBase's read algorithms on the receiver.
  // Its cast and all writes instead delegate to the actual native superclass.
  @override
  Iterator<T> get iterator {
    final value = _readCollectionProperty('iterator', () => super.iterator);
    final native = value is BridgedInstance ? value.nativeObject : value;
    return native is Iterator<T>
        ? native
        : _CollectionIterator<T>(native as Iterator);
  }

  @override
  Iterable<T> get reversed =>
      (_readCollectionProperty('reversed', () => super.reversed) as Iterable)
          .cast<T>();
  @override
  List<R> cast<R>() => (_collectionMethod('cast', [], () => _source.cast<R>(),
          types: [NamedRuntimeType('$R')]) as List)
      .cast<R>();
  @override
  String join([String separator = '']) =>
      _collectionMethod('join', [separator], () => super.join(separator))
          as String;
  @override
  void forEach(void Function(T) action) =>
      _collectionMethod('forEach', [action], () => super.forEach(action));
  @override
  bool any(bool Function(T) test) =>
      _collectionMethod('any', [test], () => super.any(test)) as bool;
  @override
  bool every(bool Function(T) test) =>
      _collectionMethod('every', [test], () => super.every(test)) as bool;
  @override
  Iterable<T> followedBy(Iterable<T> other) =>
      (_collectionMethod('followedBy', [other], () => super.followedBy(other))
              as Iterable)
          .cast<T>();
  @override
  Iterable<R> map<R>(R Function(T) convert) =>
      (_collectionMethod('map', [convert], () => super.map<R>(convert),
              types: [NamedRuntimeType('$R')]) as Iterable)
          .cast<R>();
  @override
  Iterable<R> expand<R>(Iterable<R> Function(T) convert) =>
      (_collectionMethod('expand', [convert], () => super.expand<R>(convert),
              types: [NamedRuntimeType('$R')]) as Iterable)
          .cast<R>();
  @override
  Iterable<T> where(bool Function(T) test) =>
      (_collectionMethod('where', [test], () => super.where(test)) as Iterable)
          .cast<T>();
  @override
  Iterable<R> whereType<R>() =>
      (_collectionMethod('whereType', [], () => super.whereType<R>(),
              types: [NamedRuntimeType('$R')]) as Iterable)
          .cast<R>();
  @override
  T reduce(T Function(T, T) combine) =>
      _collectionMethod('reduce', [combine], () => super.reduce(combine)) as T;
  @override
  R fold<R>(R initialValue, R Function(R, T) combine) => _collectionMethod(
      'fold',
      [initialValue, combine],
      () => super.fold<R>(initialValue, combine),
      types: [NamedRuntimeType('$R')]) as R;
  @override
  T firstWhere(bool Function(T) test, {T Function()? orElse}) =>
      _collectionMethod(
          'firstWhere', [test], () => super.firstWhere(test, orElse: orElse),
          named: {if (orElse != null) 'orElse': orElse}) as T;
  @override
  T lastWhere(bool Function(T) test, {T Function()? orElse}) =>
      _collectionMethod(
          'lastWhere', [test], () => super.lastWhere(test, orElse: orElse),
          named: {if (orElse != null) 'orElse': orElse}) as T;
  @override
  T singleWhere(bool Function(T) test,
          {T Function()? orElse}) =>
      _collectionMethod(
          'singleWhere', [test], () => super.singleWhere(test, orElse: orElse),
          named: {if (orElse != null) 'orElse': orElse}) as T;
  @override
  Iterable<T> skip(int count) =>
      (_collectionMethod('skip', [count], () => super.skip(count)) as Iterable)
          .cast<T>();
  @override
  Iterable<T> take(int count) =>
      (_collectionMethod('take', [count], () => super.take(count)) as Iterable)
          .cast<T>();
  @override
  Iterable<T> skipWhile(bool Function(T) test) =>
      (_collectionMethod('skipWhile', [test], () => super.skipWhile(test))
              as Iterable)
          .cast<T>();
  @override
  Iterable<T> takeWhile(bool Function(T) test) =>
      (_collectionMethod('takeWhile', [test], () => super.takeWhile(test))
              as Iterable)
          .cast<T>();
  @override
  List<T> toList({bool growable = true}) =>
      (_collectionMethod('toList', [], () => super.toList(growable: growable),
              named: {'growable': growable}) as List)
          .cast<T>();
  @override
  Set<T> toSet() =>
      (_collectionMethod('toSet', [], () => super.toSet()) as Set).cast<T>();
  @override
  int indexOf(Object? element, [int start = 0]) => _collectionMethod(
      'indexOf', [element, start], () => super.indexOf(element, start)) as int;
  @override
  int lastIndexOf(Object? element, [int? start]) => _collectionMethod(
      'lastIndexOf',
      [element, start],
      () => super.lastIndexOf(element, start)) as int;
  @override
  int indexWhere(bool Function(T) test, [int start = 0]) => _collectionMethod(
      'indexWhere', [test, start], () => super.indexWhere(test, start)) as int;
  @override
  int lastIndexWhere(bool Function(T) test, [int? start]) => _collectionMethod(
      'lastIndexWhere',
      [test, start],
      () => super.lastIndexWhere(test, start)) as int;
  @override
  List<T> sublist(int start, [int? end]) => (_collectionMethod(
          'sublist', [start, end], () => super.sublist(start, end)) as List)
      .cast<T>();
  @override
  Iterable<T> getRange(int start, int end) => (_collectionMethod(
              'getRange', [start, end], () => super.getRange(start, end))
          as Iterable)
      .cast<T>();
  @override
  String toString() =>
      _collectionMethod('toString', [], () => super.toString()) as String;
}

final class _InterpretedMap<K, V> extends InterpretedInstance
    with _CollectionDispatch, MapMixin<K, V> {
  _InterpretedMap(super.klass, InterpreterVisitor visitor,
      {super.typeArguments}) {
    _constructionVisitor = visitor;
  }
  Map get _source => bridgedSuperObject as Map;
  @override
  int get length =>
      _readCollectionProperty('length', () => _source.length) as int;

  @override
  Iterable<K> get keys =>
      (_readCollectionProperty('keys', () => _source.keys) as Iterable)
          .cast<K>();

  @override
  V? operator [](Object? key) {
    final operator = findOperator('[]');
    return (operator == null ? _source[key] : _callOverride(operator, [key]))
        as V?;
  }

  @override
  void operator []=(K key, V value) {
    final operator = findOperator('[]=');
    if (operator == null) {
      _source[key] = value;
    } else {
      _callOverride(operator, [key, value]);
    }
  }

  @override
  void clear() => _collectionMethod('clear', [], () => _source.clear());
  @override
  V? remove(Object? key) =>
      _collectionMethod('remove', [key], () => _source.remove(key)) as V?;
  @override
  bool containsKey(Object? key) =>
      _collectionMethod('containsKey', [key], () => _source.containsKey(key))
          as bool;
  @override
  void addAll(Map<K, V> other) =>
      _collectionMethod('addAll', [other], () => _source.addAll(other));
  @override
  void addEntries(Iterable<MapEntry<K, V>> entries) => _collectionMethod(
      'addEntries', [entries], () => _source.addEntries(entries));
  @override
  V putIfAbsent(K key, V Function() ifAbsent) => _collectionMethod(
      'putIfAbsent',
      [key, ifAbsent],
      () => _source.putIfAbsent(key, ifAbsent)) as V;
  @override
  V update(K key, V Function(V) update, {V Function()? ifAbsent}) {
    final method = klass.findInstanceMethod('update');
    if (method != null) {
      return _callOverride(method, [key, update],
          {if (ifAbsent != null) 'ifAbsent': ifAbsent}) as V;
    }
    return _source.update(key, (value) => update(value as V),
        ifAbsent: ifAbsent) as V;
  }

  @override
  void updateAll(V Function(K, V) update) => _collectionMethod(
      'updateAll',
      [update],
      () => _source.updateAll((key, value) => update(key as K, value as V)));
  @override
  void removeWhere(bool Function(K, V) test) => _collectionMethod(
      'removeWhere',
      [test],
      () => _source.removeWhere((key, value) => test(key as K, value as V)));
  @override
  bool containsValue(Object? value) => _collectionMethod(
      'containsValue', [value], () => _source.containsValue(value)) as bool;
  @override
  bool get isEmpty =>
      _readCollectionProperty('isEmpty', () => _source.isEmpty) as bool;
  @override
  bool get isNotEmpty =>
      _readCollectionProperty('isNotEmpty', () => _source.isNotEmpty) as bool;
  @override
  Iterable<V> get values =>
      (_readCollectionProperty('values', () => _source.values) as Iterable)
          .cast<V>();
  @override
  Iterable<MapEntry<K, V>> get entries {
    final value = _readCollectionProperty('entries', () => _source.entries);
    if (value is Iterable<MapEntry<K, V>>) return value;
    return (value as Iterable).map((entry) {
      final native = entry is BridgedInstance ? entry.nativeObject : entry;
      final pair = native as MapEntry;
      return MapEntry<K, V>(pair.key as K, pair.value as V);
    });
  }

  @override
  void forEach(void Function(K, V) action) => _collectionMethod(
      'forEach',
      [action],
      () => _source.forEach((key, value) => action(key as K, value as V)));
  @override
  Map<RK, RV> cast<RK, RV>() =>
      (_collectionMethod('cast', [], () => _source.cast<RK, RV>(),
              types: [NamedRuntimeType('$RK'), NamedRuntimeType('$RV')]) as Map)
          .cast<RK, RV>();
  @override
  Map<RK, RV> map<RK, RV>(MapEntry<RK, RV> Function(K, V) transform) =>
      (_collectionMethod(
              'map',
              [transform],
              () => _source
                  .map<RK, RV>((key, value) => transform(key as K, value as V)),
              types: [NamedRuntimeType('$RK'), NamedRuntimeType('$RV')]) as Map)
          .cast<RK, RV>();
  @override
  String toString() =>
      _collectionMethod('toString', [], () => _source.toString()) as String;
}
