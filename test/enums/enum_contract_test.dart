import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

/// Consumer programs shared with the disposable native-oracle runtime proof.
const enumScenarios = <String, ({String source, List<Object?> expected})>{
  'lexical scope and escaping closures': (
    source: r'''
int payload = 99;
int count = 98;
List<String> values = ['outside'];
String label() => 'outside';
enum Scope {
  a(7), b(8);
  const Scope(this.payload);
  final int payload;
  static int count = 2;
  static Scope fromId(int id) {
    for (final value in values) { if (value.index == id) return value; }
    return a;
  }
  String label() => 'member';
  List inspect(int count) {
    final read = label;
    { final payload = 3; if (payload != 3) throw 'shadow'; }
    return [payload, count, read(), values.length, identical(a, Scope.a)];
  }
  Function escaped() => () => [payload, count, label(), fromId(1).index];
  Function asyncEscaped() => () async { await Future.value(0); return [payload, count, label()]; };
}
main() async {
  final closure = Scope.a.escaped();
  final asyncClosure = Scope.b.asyncEscaped();
  Scope.count = 4;
  return [Scope.a.inspect(6), closure(), await asyncClosure(), payload, count, values[0], label()];
}
''',
    expected: [
      [7, 6, 'member', 2, true],
      [7, 4, 'member', 1],
      [8, 4, 'member'],
      99,
      98,
      'outside',
      'outside'
    ],
  ),
  'live state and mutation ordering': (
    source: r'''
List<String> events = [];
enum Counter {
  a;
  static int storage = 1;
  static int get value { events.add('get'); return storage; }
  static set value(int n) { events.add('set:$n'); storage = n; }
  int get shared => value;
  set shared(int n) { value = n; }
  static int? optional;
  static int rhs() { events.add('rhs'); return 3; }
  static List update() {
    value += rhs();
    final before = value++;
    final after = ++value;
    optional ??= rhs();
    optional ??= rhs();
    return [before, after, optional];
  }
}
Counter receiver() { events.add('receiver'); return Counter.a; }
main() {
  final first = Counter.update();
  final postfix = receiver().shared++;
  final prefix = --receiver().shared;
  return [first, postfix, prefix, Counter.storage, events];
}
''',
    expected: [
      [4, 6, 3],
      6,
      6,
      6,
      [
        'get',
        'rhs',
        'set:4',
        'get',
        'set:5',
        'get',
        'set:6',
        'rhs',
        'receiver',
        'get',
        'set:7',
        'receiver',
        'get',
        'set:6'
      ]
    ],
  ),
  'lazy static transitions and retries': (
    source: r'''
int calls = 0;
int touch(int n) { calls++; return n; }
int fail() { calls++; throw 'failure'; }
enum Lazy {
  a;
  static int unused = touch(99);
  static int forward = later + values.length;
  static int later = touch(4);
  static int overwritten = touch(98);
  static int broken = fail();
  static late int lateBroken = fail();
  static late int manual;
  static late final int once;
  static late final int initialized = 9;
  static final int fixed = 5;
  static const int constant = 6;
  static int cycle = cycle;
}
main() {
  final initial = calls;
  Lazy.overwritten = 21;
  final forward = Lazy.forward;
  final same = Lazy.forward;
  Lazy.manual = 2;
  Lazy.once = 3;
  final errors = [];
  try { Lazy.once = 4; } catch (_) { errors.add('once'); }
  for (var i=0;i<2;i++) { try { Lazy.broken; } catch (_) { errors.add('broken'); } }
  for (var i=0;i<2;i++) { try { Lazy.lateBroken; } catch (_) { errors.add('late'); } }
  try { Lazy.cycle; } catch (_) { errors.add('cycle'); }
  return [initial, forward, same, calls, Lazy.overwritten, Lazy.manual, Lazy.once, Lazy.initialized, Lazy.fixed, Lazy.constant, errors];
}
''',
    expected: [
      0,
      5,
      5,
      5,
      21,
      2,
      3,
      9,
      5,
      6,
      ['once', 'broken', 'broken', 'late', 'late', 'cycle']
    ],
  ),
  'constructors factories redirects and tearoffs': (
    source: r'''
enum Constructed {
  a, b.named(5), c(7);
  const Constructed([int n=3]) : this.named(n);
  const Constructed.named(this.n) : assert(n > 0);
  final int n;
  final int offset = 2;
  factory Constructed.pick(int index) => values[index];
  factory Constructed.redirect(int index) = Constructed.pick;
}
enum FactoryDefault {
  a.named();
  const FactoryDefault.named();
  factory FactoryDefault() => a;
}
main() {
  final factory = Constructed.pick;
  final redirected = Constructed.redirect;
  final unnamed = FactoryDefault.new;
  return [Constructed.a.n, Constructed.b.n, Constructed.c.n, Constructed.a.offset,
    identical(factory(1), Constructed.b), identical(redirected(2), Constructed.c),
    identical(FactoryDefault(), FactoryDefault.a), identical(unnamed(), FactoryDefault.a)];
}
''',
    expected: [3, 5, 7, 2, true, true, true, true],
  ),
  'immutable constants and nested collections': (
    source: r'''
enum Frozen {
  a([[1]], {'x': [2]}, {3}), b([[1]], {'x': [2]}, {3});
  const Frozen(this.lists, this.map, this.set);
  final List<List<int>> lists;
  final Map<String,List<int>> map;
  final Set<int> set;
}
main() {
  final failed = [];
  try { Frozen.values.add(Frozen.a); } catch (_) { failed.add(true); }
  try { Frozen.values[0] = Frozen.b; } catch (_) { failed.add(true); }
  try { Frozen.values.length = 0; } catch (_) { failed.add(true); }
  try { Frozen.a.lists[0].add(9); } catch (_) { failed.add(true); }
  try { Frozen.a.map['x']!.add(9); } catch (_) { failed.add(true); }
  try { Frozen.a.set.add(9); } catch (_) { failed.add(true); }
  dynamic value = Frozen.a;
  try { value.lists = []; } catch (_) { failed.add(true); }
  try { value.invented = 1; } catch (_) { failed.add(true); }
  return [failed.length, identical(Frozen.values, Frozen.values), identical(Frozen.a, Frozen.values[0]),
    Frozen.a != Frozen.b, Frozen.a.hashCode == Frozen.a.hashCode, Frozen.values.map((e) => e.index).toList()];
}
''',
    expected: [
      8,
      true,
      true,
      true,
      true,
      [0, 1]
    ],
  ),
  'member overrides and core enum helpers': (
    source: r'''
enum Named {
  zebra, alpha;
  String get name => 'custom';
  String toString() => 'display';
}
enum Plain { first, second }
main() {
  final display = Named.zebra.toString;
  final map = Named.values.asNameMap();
  map['extra'] = Named.alpha;
  var missing = false;
  try { Named.values.byName('custom'); } catch (_) { missing = true; }
  return [Named.zebra.name, EnumName(Named.zebra).name, '${Named.zebra}', display(),
    Plain.first.name, Plain.first.toString(),
    Enum.compareByIndex(Named.zebra, Named.alpha) < 0,
    Enum.compareByName(Named.zebra, Named.alpha) > 0,
    identical(Named.values.byName('alpha'), Named.alpha), map.length, missing];
}
''',
    expected: [
      'custom',
      'zebra',
      'display',
      'display',
      'first',
      'Plain.first',
      true,
      true,
      true,
      3,
      true
    ],
  ),
  'generic types interfaces casts and nullability': (
    source: r'''
abstract interface class Payload<T> { T get value; }
abstract interface class Nested<T> implements Payload<List<T>> {}
enum Box<T extends num> implements Payload<T>, Comparable<Box<T>> {
  integer<int>(1), inferred(2.5);
  const Box(this.value);
  final T value;
  int compareTo(Box<T> other) => index.compareTo(other.index);
}
enum CollectionBox<T> implements Nested<T> {
  ints<int>([1]), strings<String>(['x']);
  const CollectionBox(this.value);
  final List<T> value;
}
enum Other { a }
main() {
  dynamic integer = Box.integer;
  var castFailed = false;
  try { integer as Box<double>; } catch (_) { castFailed = true; }
  var otherFailed = false;
  try { integer as Other; } catch (_) { otherFailed = true; }
  dynamic absent = null;
  return [integer is Box<int>, integer is Box<num>, integer is Box<double>,
    Box.inferred is Box<double>, integer is Enum, integer is Object,
    integer is Payload<int>, integer is Comparable<Box<int>>,
    identical(integer as Box<int>, Box.integer), castFailed, otherFailed,
    absent is Box<int>?, absent is Box<int>, (absent as Box<int>?) == null,
    CollectionBox.ints is Payload<List<int>>, CollectionBox.ints is Payload<List<String>>,
    Box.values is List<Box<num>>, CollectionBox.strings.value[0]];
}
''',
    expected: [
      true,
      true,
      false,
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      true,
      false,
      true,
      true,
      false,
      true,
      'x'
    ],
  ),
  'enum type object and constant patterns': (
    source: r'''
abstract interface class Payload<T> { T get value; }
enum Box<T extends num> implements Payload<T> {
  integer<int>(1), floating<double>(2.5);
  const Box(this.value);
  final T value;
}
enum Other { a }
String match(dynamic value) => switch (value) {
  Box<int>(value: var n) when n == 1 => 'integer',
  Payload<double>(value: var n) => 'double:$n',
  Other.a => 'other',
  Enum(index: 0) => 'zero',
  _ => 'none',
};
String typed(dynamic value) { switch(value) { case Box<int> box: return 'typed:${box.value}'; default: return 'none'; } }
main() => [match(Box.integer), match(Box.floating), match(Other.a), match(3), typed(Box.integer), typed(Box.floating)];
''',
    expected: ['integer', 'double:2.5', 'other', 'none', 'typed:1', 'none'],
  ),
  'generic mixins super and captured receivers': (
    source: r'''
mixin First on Enum {
  String get label => 'first';
  String base() => super.toString();
}
mixin Last<T> on Enum {
  String get label => 'last';
  Function superClosure() => () => super.index;
  T? get optional => null;
}
enum Mixed with First, Last<int> { a, b }
enum Override with First, Last<String> {
  a;
  String get label => 'enum';
}
main() {
  final closure = Mixed.b.superClosure();
  return [Mixed.a.label, Override.a.label, Mixed.a.base(), closure(),
    Mixed.a is First, Mixed.a is Last<int>, Mixed.a is Last<String>, Mixed.a.optional == null];
}
''',
    expected: ['last', 'enum', 'Mixed.a', 1, true, true, false, true],
  ),
  'forward constants and deep implicit const payloads': (
    source: r'''
enum First {
  a(Second.b, Payload(4), shared);
  const First(this.other, this.record, this.payload);
  final Second other;
  final Payload record;
  final List<Object> payload;
}
enum Second { b }
class Payload { const Payload(this.value); final int value; }
const shared = <Object>[[1], {'key': [2]}, {3}];
enum Linked { a(b), b(null); const Linked(this.other); final Linked? other; }
main() {
  var failures = 0;
  try { First.a.payload.add(5); } catch (_) { failures++; }
  try { (First.a.payload[0] as List).add(5); } catch (_) { failures++; }
  try { ((First.a.payload[1] as Map)['key'] as List).add(5); } catch (_) { failures++; }
  try { (First.a.payload[2] as Set).add(5); } catch (_) { failures++; }
  return [identical(First.a.other, Second.b), First.a.record.value,
    identical(First.a, First.values.first), failures,
    identical(Linked.a.other, Linked.b), Linked.b.other == null];
}
''',
    expected: [true, 4, true, 4, true, true],
  ),
  'dependent recursive bounds defaults and nullable arguments': (
    source: r'''
enum Dependent<T extends num, U extends T> {
  a<int, int>(1, 2), b(1, 2);
  const Dependent(this.first, this.second);
  final T first;
  final U second;
}
enum Defaults<T extends num> { a(); const Defaults([this.value]); final T? value; }
enum SelfBound<T extends Comparable<T>> { text<String>('x'); const SelfBound(this.value); final T value; }
enum Nullable<T> { explicit<int?>(null), inferred(null); const Nullable(this.value); final T value; }
enum NullableBound<T extends num> { a(null); const NullableBound(this.value); final T? value; }
main() => [Dependent.b is Dependent<int, int>, Dependent.values is List<Dependent<num, num>>,
  Defaults.a is Defaults<num>, Defaults.a.value == null, SelfBound.text is SelfBound,
  SelfBound.values is List<SelfBound<Comparable<dynamic>>>, Nullable.explicit is Nullable<int?>,
  Nullable.explicit is Nullable<int>, Nullable.inferred is Nullable<int?>, NullableBound.a is NullableBound<num>];
''',
    expected: [true, true, true, true, true, true, true, false, true, true],
  ),
  'mixin lexical statics and extension name fallback': (
    source: r'''
String name = 'global';
int amount = 100;
mixin M on Enum { static int amount = 3; int read() => amount; int bump() => amount++; }
enum E with M { name, b; static int amount = 9; String bare() => name.toString(); }
enum F { a; String bare() => name; }
main() => [E.b.bare(), E.b.name, F.a.bare(), E.b.read(), E.b.bump(), E.amount, M.amount];
''',
    expected: ['E.name', 'b', 'global', 3, 3, 9, 4],
  ),
  'nullable bounds and dynamic argument distinctions': (
    source: r'''
enum N<T extends num?> { a(null); const N(this.value); final T value; }
enum U<T> { broad<dynamic>(1), nullable<int?>(null), nil(null); const U(this.value); final T value; }
main() => [N.a is N<num?>, U.broad is U<Object>, U.broad is U<Object?>,
  U.nil is U<Null>, U.nil is U<int?>, U.nullable is U<int>, {U.nil}.byName('nil').index];
''',
    expected: [true, false, true, true, true, false, 2],
  ),
  'callable members null bindings and throwing getters': (
    source: r'''
int nullable = 77;
int broken = 99;
Function callback = () => 'global';
enum Calls {
  a;
  static int state = 1;
  static int? nullable;
  static Function callback = (int n) => state += n;
  static Function get fromGetter => (int n) => state += n;
  Function get instanceCallback => (int n) => state += n + index;
  static int get broken => throw 'member failure';
  int invokeBare() => callback(5);
  int? readNull() => nullable;
  int readBroken() => broken;
}
main() {
  final field = (Calls.callback);
  final getter = Calls.fromGetter;
  final instance = Calls.a.instanceCallback;
  final first = field(2);
  final second = getter(3);
  final third = instance(4);
  final fourth = Calls.a.invokeBare();
  var failures = 0;
  try { Calls.broken; } catch (_) { failures++; }
  try { Calls.a.readBroken(); } catch (_) { failures++; }
  return [first, second, third, fourth, Calls.a.readNull() == null,
    Calls.state, failures, nullable, callback()];
}
''',
    expected: [3, 6, 10, 15, true, 15, 2, 77, 'global'],
  ),
  'generic factory inference explicit types and tearoffs': (
    source: r'''
enum Chooser<T extends num> {
  integer<int>(1), floating<double>(2.5);
  const Chooser(this.value);
  final T value;
  factory Chooser.choose(T value) => T == int
      ? integer as Chooser<T> : floating as Chooser<T>;
}
enum Pair<T> { both(1, null); const Pair(this.first, this.second); final T first; final T second; }
main() {
  final inferred = Chooser.choose;
  final fixed = Chooser<num>.choose;
  return [identical(Chooser.choose(1), Chooser.integer),
    identical(Chooser.choose(2.5), Chooser.floating),
    identical(inferred(1), Chooser.integer), Chooser.integer.value, Chooser.floating.value,
    Pair.both is Pair<int?>, identical(fixed(1), Chooser.floating),
    Chooser.integer.runtimeType == Chooser<int>,
    Chooser.integer.runtimeType != Chooser<double>,
    Chooser.integer.runtimeType.hashCode == (Chooser<int>).hashCode,
    Chooser.integer.runtimeType.toString()];
}
''',
    expected: [
      true,
      true,
      true,
      1,
      2.5,
      true,
      true,
      true,
      true,
      true,
      'Chooser<int>'
    ],
  ),
};

void main() {
  for (final scenario in enumScenarios.entries) {
    test(scenario.key, () async {
      final interpreter = D4rt();
      expect(await interpreter.execute(source: scenario.value.source),
          scenario.value.expected);
      final compiled = interpreter.compile(source: scenario.value.source);
      expect(
          await interpreter.executeCompiled(compiled), scenario.value.expected);
    });
  }

  test('qualified imports and live enum module scope', () {
    const library = r'''
const selected = Method.second;
enum Method {
  first, second;
  static int state = 0;
  factory Method.pick([int index = 1]) => values[index];
  static Method? fromId(int id) { for (final item in values) { if (item.index == id) return item; } return null; }
  Function closure() => () => ++state;
}
''';
    const source = r'''
import 'package:enum_fixture/model.dart' as model;
enum Imported {
  a(model.selected);
  const Imported(this.value);
  final model.Method value;
}
main() {
  final closure = model.Method.first.closure();
  final pick = model.Method.pick;
  model.Method.state = 3;
  return [model.Method.fromId(1)!.index, closure(), model.Method.state, model.Method.fromId(9) == null,
    pick().index == 1, identical(Imported.a.value, model.Method.second)];
}
''';
    final interpreter = D4rt();
    const sources = {'package:enum_fixture/model.dart': library};
    expect(interpreter.execute(source: source, sources: sources),
        [1, 4, 4, true, true, true]);
    expect(
        interpreter.executeCompiled(interpreter.compile(source: source),
            sources: sources),
        [1, 4, 4, true, true, true]);
  });

  test('host handles cannot construct replacements or reinitialize constants',
      () {
    final value = D4rt().execute(source: r'''
enum E { a(1); const E(this.payload); final int payload; }
main()=>E.a;
''') as InterpretedEnumValue;
    expect(
        () => InterpretedEnumValue(value.parentEnum, value.name, value.index),
        throwsA(anything));
    expect(() => value.set('payload', 8), throwsA(anything));
    expect(() => value.finishInitialization(), throwsA(anything));
  });

  test('throwing found getter never falls back to an outer binding', () {
    expect(() => D4rt().execute(source: r'''
int broken = 99;
enum E { a; int get broken => throw 'member failure'; int read() => broken; }
main() => E.a.read();
'''), throwsA(anything));
  });

  for (final source in <String>[
    'enum E { ; } main() => 0;',
    'enum E { a; int value = 1; } main() => 0;',
    'enum E { a; int get index => 4; } main() => 0;',
    'enum E { a; int get hashCode => 4; } main() => 0;',
    'enum E { a; bool operator ==(Object x) => true; } main() => 0;',
    'enum E { a; static int values = 0; } main() => 0;',
    'mixin M { final int x = 1; } enum E with M { a } main() => 0;',
    'mixin M { int get index => 1; } enum E with M { a } main() => 0;',
    'mixin M on String {} enum E with M { a } main() => 0;',
    'abstract interface class I { void missing(); } enum E implements I { a } main() => 0;',
    'mixin M { void missing(); } enum E with M { a } main() => 0;',
    'abstract interface class I { set x(int value); } enum E implements I { a; final int x=1; } main() => 0;',
    'enum E { a; } class C extends E {} main() => 0;',
    'enum E { a; } class C implements E {} main() => 0;',
    'class C implements Enum { int get index => 0; } main() => 0;',
    'enum E { a; const E(); } main() => E();',
    'enum E { a; const E(); } main() => E.new;',
    'enum E { a.make(); const E(); factory E.make() => a; } main() => 0;',
    'int value=1; enum E { a(value); const E(this.x); final int x; } main() => 0;',
    'int f()=>1; enum E { a(f()); const E(this.x); final int x; } main() => 0;',
    'enum E<T extends num> { a<String>("x"); const E(this.value); final T value; } main() => 0;',
    'enum E<T> { a<int,String>(1); const E(this.value); final T value; } main() => 0;',
    'enum E { a(0); const E(this.value):assert(value>0); final int value; } main() => 0;',
    'enum E { a; const E(); factory E.bad()=>null; } main()=>E.bad();',
    'enum E { a; static late final int initialized=1; } main(){E.initialized=2;}',
    'enum E { a; static final int fixed=1; } main(){E.fixed=2;}',
    'enum E { a; static const int fixed=1; } main(){E.fixed=2;}',
    'enum E { a; } main(){E.values=[];}',
    'enum E { a; } main(){E.a=E.a;}',
    'enum E { a; E(); } main()=>0;',
    'enum E { index } main()=>0;',
    'enum E { a; static int index=1; } main()=>0;',
    'enum E { a; static int hashCode=1; } main()=>0;',
    'abstract interface class I { String get label; } mixin M on I {} enum E with M implements I { a; String get label=>"a"; } main()=>0;',
    'enum E { a(b), b(a); const E(this.other); final E other; } main()=>0;',
    'class P { P(); } enum E { a(P()); const E(this.value); final P value; } main()=>0;',
    'int setterOnly=99; enum E { a; static set setterOnly(int n) {} int read()=>setterOnly; } main()=>E.a.read();',
    'enum E { a; } main()=>a;',
    'enum E { a; static int state=1; } main(){dynamic x="bad"; E.state=x;}',
    'enum E<T extends num> { a<dynamic>(1); const E(this.value); final T value; } main()=>E.a;',
  ]) {
    test('rejects invalid enum contract: $source', () {
      expect(() => D4rt().execute(source: source), throwsA(anything));
    });
  }
}
