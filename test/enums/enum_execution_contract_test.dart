import 'dart:async';
import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

/// Consumer programs exercising enum scope, construction and execution.
const enumCorrectionScenarios =
    <String, ({String source, Object? expected, Map<String, String> sources})>{
  'recursive and reentrant factories return canonical constants': (
    source:
        '''enum E { a; const E(); factory E.pick(int n)=>n==0?a:E.pick(n-1); factory E.redirect(int n)=E.pick; factory E.reenter(int n)=>n==0?a:E.redirect(n-1); } main()=>[E.pick(3).index,E.reenter(3).index,identical(E.redirect(2),E.a)];''',
    expected: [0, 0, true],
    sources: {}
  ),
  'inherited setters preserve ordering across every write form': (
    source:
        r'''List<String> events=[]; int state=0;int? optional; int rhs(){events.add('rhs');return 2;} mixin First {int get n {events.add('get');return state;} set n(int value){events.add('set:$value');state=value;} int? get maybe {events.add('getMaybe');return optional;} set maybe(int? value){events.add('setMaybe:$value');optional=value;}} mixin Last on First {List act(){super.n=rhs();final a=super.n+=rhs();final b=super.n++;final c=++super.n;final d=super.n--;final e=--super.n;super.maybe??=rhs();super.maybe??=rhs();return [a,b,c,d,e,state,optional];}} enum E with First,Last {a} main()=>[E.a.act(),events];''',
    expected: [
      [4, 4, 6, 6, 4, 4, 2],
      [
        'rhs',
        'set:2',
        'get',
        'rhs',
        'set:4',
        'get',
        'set:5',
        'get',
        'set:6',
        'get',
        'set:5',
        'get',
        'set:4',
        'getMaybe',
        'rhs',
        'setMaybe:2',
        'getMaybe'
      ]
    ],
    sources: {}
  ),
  'const payloads accept declared function tearoffs and core identical': (
    source:
        '''import 'package:payload/p.dart' as p; int top()=>1; class C {static int make()=>2;} enum E {a(top),b(C.make),c(p.top),d(p.C.make),e();const E([this.make=top]);final int Function() make; static int own()=>5;} enum F {a(E.own),b(print);const F(this.f);final dynamic f;} enum Truth {a(identical(1,1));const Truth(this.value);final bool value;} main()=>[E.a.make(),E.b.make(),E.c.make(),E.d.make(),E.e.make(),F.a.f(),Truth.a.value];''',
    expected: [1, 2, 3, 4, 1, 5, true],
    sources: {
      'package:payload/p.dart': 'int top()=>3; class C {static int make()=>4;}'
    }
  ),
  'casts and patterns distinguish nominal library and core identity': (
    source:
        '''import 'package:a/a.dart' as a; import 'package:b/b.dart' as b; class Enum {} main(){var failed=false;try{a.E.a as b.I;}catch(_){failed=true;}return [a.E.a is a.I,a.E.a is b.I,a.E.a is Enum,switch(a.E.a){b.I()=>1,_=>0},switch(a.E.a){a.I()=>1,_=>0},failed];}''',
    expected: [true, false, false, 0, 1, true],
    sources: {
      'package:a/a.dart':
          'abstract interface class I {} enum E implements I {a}',
      'package:b/b.dart': 'abstract interface class I {}'
    }
  ),
  'projected inference preserves nested substituted bounds': (
    source:
        '''abstract interface class Parent<T> {} class Child implements Parent<int> {const Child();} class Nested<U> implements Parent<List<U>> {const Nested();} enum E<T> {a(Child());const E(this.value);final Parent<T> value;factory E.pick(Parent<T> value)=>a as E<T>;} enum Bound<T extends Parent<List<String>>> {a<Nested<String>>(Nested<String>());const Bound(this.value);final T value;factory Bound.pick(T value)=>a as Bound<T>;} main()=>[E.a is E<int>,E.pick(Child()) is E<int>,Bound.a.index,Bound.pick(Nested<String>()).index,Bound.a.value is Parent<List<String>>,Bound.a.value is Parent<List<int>>];''',
    expected: [true, true, 0, 0, true, false],
    sources: {}
  ),
  'imported const payloads preserve owning identity and forward cache': (
    source:
        '''import 'package:payload/p.dart' as p; import 'package:payload/p.dart' show shared; enum E {a(p.shared),b(p.forward),c(shared);const E(this.value);final p.P value;} main()=>[identical(E.a.value,E.b.value),identical(E.a.value,E.c.value),E.a.value.n];''',
    expected: [true, true, 7],
    sources: {
      'package:payload/p.dart':
          'class P {const P(this.n);final int n;} const forward=shared; const shared=P(7);'
    }
  ),
  'callable inference and bound tearoffs preserve structural signatures': (
    source:
        '''enum E<T extends num>{low<int>(1),high<int>(2);const E(this.value);final T value;factory E.choose(T Function() make)=>(T==int?high:low) as E<T>;factory E.input(void Function(T) accept)=>(T==int?high:low) as E<T>;} int make()=>1; void accept(int value){} main(){final bound=E<int>.choose;return [E.choose(make).index,bound(make).index,E.input(accept).index,bound is E<int> Function(int Function())];}''',
    expected: [1, 1, 1, true],
    sources: {}
  ),
  'const type literals and factory tearoffs retain canonical identity': (
    source:
        '''class P {const P();} enum E {a(int),b(P);const E(this.type);final Type type;factory E.pick()=>a;} enum F {a(E.pick),b(P.new),c(P.new),d(E.pick);const F(this.make);final dynamic make;} main()=>[E.a.type==int,E.b.type==P,identical(F.a.make(),E.a),F.b.make() is P,identical(F.b.make,F.c.make),identical(F.a.make,F.d.make)];''',
    expected: [true, true, true, true, true, true],
    sources: {}
  ),
  'const function payloads retain typed enum factory references': (
    source:
        '''enum E<T extends num>{a<int>(1);const E(this.value);final T value;factory E.pick()=>a as E<T>;} enum F {a(E<int>.pick);const F(this.make);final E<int> Function() make;} main()=>[F.a.make().index,F.a.make() is E<int>];''',
    expected: [0, true],
    sources: {}
  ),
  'qualified core identities survive local namesakes': (
    source:
        '''import 'dart:core';import 'dart:core' as core;class Enum {} bool identical(Object? a,Object? b)=>false;enum E {a(core.identical(1,1));const E(this.value);final bool value;} main()=>[E.a.value,E.a is core.Enum,E.a is Enum];''',
    expected: [true, true, false],
    sources: {}
  ),
  'class static const payloads and defaults retain declaration provenance': (
    source:
        '''import 'package:payload/constants.dart' as p; enum E {a(Limits.size),b(p.Limits.size),c();const E([this.n=Limits.size]);final int n;} class Limits {static const size=next;static const next=3;} main()=>[E.a.n,E.b.n,E.c.n];''',
    expected: [3, 7, 3],
    sources: {
      'package:payload/constants.dart': 'class Limits {static const size=7;}'
    }
  ),
  'nullable callback parameters and nullable return contexts retain owner types':
      (
    source:
        '''enum E<T extends num> {a<int>(1),b<int>(2);const E(this.n);final T n;factory E.pick(int Function(T?) read)=>(read(null)==3 && T==int?b:a) as E<T>;factory E.choose()=>(T==int?b:a) as E<T>;} int read(int? value)=>3; main(){E<int>? Function() make=E.choose;return [E<int>.pick(read).index,E.pick(read).index,make()!.index];}''',
    expected: [1, 1, 1],
    sources: {}
  ),
  'ordinary lambdas retain explicit owner specialization': (
    source:
        '''enum E<T extends num>{a<int>(1);const E(this.n);final T n;factory E.pick(T Function() make)=>make()==1?a as E<T>:throw 'bad';}main()=>[E<int>.pick(()=>1).index,(() => 4)()];''',
    expected: [0, 4],
    sources: {}
  ),
  'core Type discovery survives a lexical Type namesake': (
    source:
        '''import 'dart:core';import 'dart:core' as core;class Type {}enum E {a(int);const E(this.type);final core.Type type;}main()=>[E.a.type is core.Type,E.a.type is Type];''',
    expected: [true, false],
    sources: {}
  ),
  'constructor parameters retain field initializer and assertion permissions': (
    source:
        'const alias=3;enum E{a(2),b(4,dummy:2);const E(this.value,{int dummy=1}):sum=alias+dummy,assert(dummy>0),assert(alias+dummy>0);final int value;final int sum;}main()=>[E.a.value,E.a.sum,E.b.value,E.b.sum];',
    expected: [2, 4, 4, 5],
    sources: {}
  ),
};

/// Invalid consumer programs defend const, redirect, hierarchy and type boundaries.
const enumCorrectionInvalidSources = <String, String>{
  'factory redirect cycles reject execution':
      'enum E {a;const E();factory E.one()=E.two;factory E.two()=E.one;} main()=>E.one();',
  'immutable super members reject writes':
      'mixin First {int get n=>1;} mixin Last {void act(){super.n=2;}} enum E with First,Last {a} main()=>E.a.act();',
  'implicit enum constructors reject positional arguments':
      'enum E {a(1)} main()=>0;',
  'implicit enum constructors reject named arguments':
      'enum E {a(unused:1)} main()=>0;',
  'const payloads reject anonymous closures':
      'enum E {a(()=>1);const E(this.f);final dynamic f;} main()=>0;',
  'const payloads reject mutable callable variables':
      'final f=()=>1;enum E {a(f);const E(this.f);final dynamic f;} main()=>0;',
  'const defaults reject anonymous closures':
      'enum E {a;const E([this.f=()=>1]);final dynamic f;} main()=>0;',
  'const payload constructors reject nonconstant defaults':
      'int v=1;class P {const P([this.n=v]);final int n;} enum E {a(P());const E(this.p);final P p;} main()=>0;',
  'const expressions reject shadowed identical functions':
      'bool identical(Object? a,Object? b)=>true;enum E {a(identical(1,2));const E(this.value);final bool value;} main()=>0;',
  'concrete classes reject transitive Enum implementation':
      'abstract interface class I implements Enum {} class Bad implements I {final int index=0;} main()=>0;',
  'enum arguments reject incompatible nested bounds':
      'abstract interface class Parent<T>{} class Child<U> implements Parent<List<U>> {const Child();} enum E<T extends Parent<List<String>>> {a<Child<int>>(Child<int>());const E(this.value);final T value;} main()=>0;',
  'enum factories reject incompatible callback return types':
      'enum E<T extends num>{a<int>(1);const E(this.value);final T value;factory E.pick(T Function() make)=>a as E<T>;} String wrong()=>"x";main()=>E<int>.pick(wrong);',
  'imported failed constants reject initialization':
      "import 'package:broken/p.dart' as p;enum E {a(p.failed);const E(this.value);final dynamic value;} main()=>0;",
  'imported forward constant cycles reject initialization':
      "import 'package:broken/p.dart' as p;enum E {a(p.a);const E(this.value);final dynamic value;} main()=>0;",
  'distinct same-named interfaces require every nominal obligation':
      "import 'package:a/api.dart' as a;import 'package:b/api.dart' as b;enum E implements a.I,b.I{v;void read(){}}main()=>E.v;",
  'ambiguous class owner inference rejects instead of choosing Object':
      'class Base {const Base();}class A extends Base{const A();}class B extends Base{const B();}enum E<T>{a<Base>(Base());const E(this.n);final T n;factory E.pick(T left,T right)=>a as E<T>;}main()=>E.pick(A(),B());',
  'callback owner inference rejects an unannotated result before execution':
      'enum E<T extends num>{a<int>(1);const E(this.n);final T n;factory E.pick(T Function() make)=>a as E<T>;}main()=>E.pick(()=>1);',
  'specialized generic constructor payloads reject type erasure':
      'class P<T>{const P();}enum E{a(P<int>.new);const E(this.make);final dynamic make;}main()=>E.a.make();',
};

/// Library fixtures for invalid imported constant consumers.
const enumCorrectionInvalidModules = <String, Map<String, String>>{
  'imported failed constants reject initialization': {
    'package:broken/p.dart':
        'class P {const P(this.n):assert(n>0);final int n;} const failed=P(-1);'
  },
  'imported forward constant cycles reject initialization': {
    'package:broken/p.dart': 'const a=b;const b=a;'
  },
  'distinct same-named interfaces require every nominal obligation': {
    'package:a/api.dart': 'abstract interface class I {void read();}',
    'package:b/api.dart': 'abstract interface class I {void write();}',
  },
};

/// Runs actual public execution, compilation and module entry points.
Future<Object?> executeEnumCorrection(D4rt interpreter, String source,
    Map<String, String> sources, String mode) async {
  final imported = mode == 'imported' || mode == 'compiledImported';
  final program = imported
      ? "import 'package:correction/consumer.dart' as consumer; main()=>consumer.main();"
      : source;
  final modules = {
    ...sources,
    if (imported) 'package:correction/consumer.dart': source
  };
  return mode == 'compiled' || mode == 'compiledImported'
      ? await interpreter.executeCompiled(interpreter.compile(source: program),
          sources: modules)
      : await interpreter.execute(source: program, sources: modules);
}

/// Invalid enum-owned constant dependencies, consumed after a native payload.
const enumStaticConstantRejections =
    <String, ({String fields, String argument, Map<String, String> sources})>{
  'unqualified static constant mutation': (
    fields: 'static const bad=++n;',
    argument: 'bad',
    sources: {}
  ),
  'qualified static constant mutation': (
    fields: 'static const bad=--n;',
    argument: 'E.bad',
    sources: {}
  ),
  'transitive static constant mutation': (
    fields: 'static const alias=bad;static const bad=n++;',
    argument: 'alias',
    sources: {}
  ),
  'cyclic static constant dependency': (
    fields: 'static const alias=bad;static const bad=alias;',
    argument: 'alias',
    sources: {}
  ),
  'qualified imported static constant mutation': (
    fields: '',
    argument: 'p.Constants.alias',
    sources: {
      'package:constant/model.dart':
          'const n=0;enum Constants{a;static const alias=bad;static const bad=++n;}'
    }
  ),
  'forward static constant mutation': (
    fields: '',
    argument: 'Constants.alias',
    sources: {}
  ),
  'qualified static constant cycle': (
    fields: 'static const alias=E.bad;static const bad=E.alias;',
    argument: 'alias',
    sources: {}
  ),
  'constant default mutation': (
    fields: 'static const bad=++n;',
    argument: 'bad',
    sources: {}
  ),
  'nonconstant enum getter': (
    fields: 'static int get bad=>effect();',
    argument: 'bad',
    sources: {}
  ),
};

/// Invalid independent declarations cannot inherit constructor-local permissions.
const enumParameterProvenanceRejections =
    <String, ({String source, Map<String, String> sources})>{
  'enum constant parameter-name collision': (
    source:
        "import 'package:payload/native.dart';enum E{a(Payload());const E(this.value,{int dummy=1}):assert(alias>0);final dynamic value;static const alias=dummy;static int get dummy=>effect();}main()=>E.a;",
    sources: {}
  ),
  'class constant parameter-name collision': (
    source:
        "import 'package:payload/native.dart';enum E{a(Payload());const E(this.value,{int dummy=1}):assert(Constants.alias>0);final dynamic value;}class Constants{static const alias=dummy;static int get dummy=>effect();}main()=>E.a;",
    sources: {}
  ),
  'top-level constant parameter-name collision': (
    source:
        "import 'package:payload/native.dart';enum E{a(Payload());const E(this.value,{int dummy=1}):assert(alias>0);final dynamic value;}const alias=dummy;int get dummy=>effect();main()=>E.a;",
    sources: {}
  ),
  'imported enum constant parameter-name collision': (
    source:
        "import 'package:payload/native.dart';import 'package:constant/collision.dart' as p;enum E{a(Payload());const E(this.value,{int dummy=1}):assert(p.Constants.alias>0);final dynamic value;}main()=>E.a;",
    sources: {
      'package:constant/collision.dart':
          'enum Constants{a;static const alias=dummy;static int get dummy=>effect();}'
    }
  ),
};

/// Verifies whole-enum preflight without evaluating a native constructor first.
Future<List<Object?>> runEnumStaticConstantPreflight(
    String name, String mode) async {
  final fixture = enumStaticConstantRejections[name]!;
  final imported = fixture.sources.isEmpty
      ? ''
      : "import 'package:constant/model.dart' as p;";
  final constructor = name == 'constant default mutation'
      ? 'const E([this.value=bad]);'
      : 'const E(this.value);';
  final second =
      name == 'constant default mutation' ? 'b()' : 'b(${fixture.argument})';
  final forward = name == 'forward static constant mutation'
      ? 'enum Constants{a;static const alias=bad;static const bad=++n;}'
      : '';
  return _runEnumConstantPreflight(
      "import 'package:payload/native.dart';$imported const n=0;enum E{a(Payload()),$second;$constructor final dynamic value;${fixture.fields}}$forward main()=>E.a;",
      fixture.sources,
      mode);
}

/// Verifies constant provenance across constructor/declaration scope boundaries.
Future<List<Object?>> runEnumParameterProvenancePreflight(
    String name, String mode) {
  final fixture = enumParameterProvenanceRejections[name]!;
  return _runEnumConstantPreflight(fixture.source, fixture.sources, mode);
}

Future<List<Object?>> _runEnumConstantPreflight(
    String source, Map<String, String> sources, String mode) async {
  var effects = 0;
  final interpreter = D4rt();
  interpreter.registerBridgedClass(
      BridgedClass(nativeType: Object, name: 'Payload', constantConstructors: {
        ''
      }, constructors: {
        '': (visitor, args, named) {
          effects++;
          return Object();
        }
      }),
      'package:payload/native.dart');
  interpreter.registertopLevelFunction('effect', (visitor, args, named, types) {
    effects++;
    return 99;
  });
  var rejected = false;
  try {
    await executeEnumCorrection(interpreter, source, sources, mode);
  } on RuntimeError {
    rejected = true;
  }
  return [rejected, effects];
}

/// Valid forward, imported and transitive enum constants/defaults/tearoffs.
const enumStaticConstantPositive = (
  source:
      "import 'package:constant/model.dart' as p;enum Values{a(),b(p.Constants.value),c(own),d(p.Constants.maker);const Values([this.n=p.Constants.value]);final dynamic n;static const own=p.Constants.base;}main()=>[Values.a.n,Values.b.n,Values.c.n,Values.d.n(),p.effects];",
  sources: <String, String>{
    'package:constant/model.dart':
        'int effects=0;int effect(){effects++;return 99;}enum Constants{a;static const base=3;static const value=base+2;static const maker=own;static int own()=>7;static final unrelated=effect();}'
  },
  expected: <Object?>[5, 5, 3, 7, 0],
);

/// Forward declaration metadata is inspected without populating the other enum.
const enumStaticConstantForward = (
  source:
      'int effects=0;int effect(){effects++;return 99;}enum Values{a(),b(Constants.value),c(own),d(Constants.maker);const Values([this.n=Constants.value]);final dynamic n;static const own=Constants.base;}enum Constants{a;static const base=3;static const value=base+2;static const maker=own;static int own()=>7;static final unrelated=effect();}main()=>[Values.a.n,Values.b.n,Values.c.n,Values.d.n(),effects];',
  sources: <String, String>{},
  expected: <Object?>[5, 5, 3, 7, 0],
);

String _enumDeferredSource(String kind, {bool effects = false}) {
  final work = effects ? 'touch();var n=1;' : 'var n=0;while(n<1000){n++;}';
  final body = switch (kind) {
    'sync*' => 'static Iterable<int> work() sync*{$work yield n;}',
    'async*' =>
      'static Stream<int> work() async*{await Future.value(0);$work yield n;}',
    _ => 'static int work(){$work return n;}'
  };
  final result = kind == 'Stream.map'
      ? 'Stream.fromIterable([1]).map((_)=>E.work())'
      : 'E.work()';
  return "import 'dart:async';enum E{a;$body}main()=>$result;";
}

/// Exercises real retained generator/stream bodies through current invocations.
Future<Map<String, Object?>> runEnumDeferredAuthority(
    [String mode = 'direct']) async {
  final result = <String, Object?>{};
  final fresh = <String, D4rt>{};
  for (final kind in ['sync*', 'async*', 'Stream.map']) {
    final low = D4rt();
    var budgetEffects = 0;
    low.registertopLevelFunction('touch', (visitor, args, named, types) {
      budgetEffects++;
      return 1;
    });
    final deferred = await executeEnumCorrection(
        low,
        _enumDeferredSource(kind)
            .replaceFirst('while(n<1000){n++;}', 'while(n<1000){n++;}touch();'),
        const {},
        mode);
    low.registertopLevelFunction(
        'retained', (visitor, args, named, types) => deferred);
    var limited = false;
    try {
      await low.execute(source: 'main()=>retained().toList();', maxSteps: 100);
    } on ExecutionLimitException {
      limited = true;
    }
    result['$kind budget effects'] = budgetEffects;
    var effects = 0;
    final outside = D4rt();
    outside.registertopLevelFunction('touch', (visitor, args, named, types) {
      effects++;
      return 1;
    });
    final escaped = await executeEnumCorrection(
        outside, _enumDeferredSource(kind, effects: true), const {}, mode);
    var refused = false;
    try {
      if (escaped is Stream) {
        await escaped.toList();
      } else {
        (escaped as Iterable).toList();
      }
    } on RuntimeError {
      refused = true;
    }
    final interpreter = D4rt();
    final retained = interpreter.execute(
        source: _enumDeferredSource(kind), timeout: const Duration(seconds: 1));
    interpreter.registertopLevelFunction(
        'retained', (visitor, args, named, types) => retained);
    fresh[kind] = interpreter;
    result[kind] = <Object?>[limited, null, refused, effects];
  }
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  for (final entry in fresh.entries) {
    (result[entry.key] as List)[1] = await entry.value.execute(
        source: 'main()=>retained().toList();',
        maxSteps: 20000,
        timeout: const Duration(seconds: 5));
  }
  result['awaitedContinuation'] = await D4rt().execute(
      source:
          "import 'dart:async';enum E{a;static Stream<int> work() async*{yield a.index;await Future.value(0);yield a.index+1;}}main()=>E.work().toList();");
  final explicit = D4rt();
  explicit.registertopLevelFunction(
      'explicit',
      (visitor, args, named, types) =>
          Zone.root.run(() => (args.single as Callable).call(visitor, [])));
  result['explicitHostEntry'] = explicit.execute(
      source:
          'enum E{a;static Iterable<int> work() sync*{yield 1;yield 2;}}make()=>E.work().toList();main()=>explicit(make);');
  return result;
}

/// Deadlines and deferred resumes refuse further effects in the current entry.
Future<Map<String, Object?>> runEnumDeferredTransitions() async {
  final result = <String, Object?>{};
  for (final kind in ['sync*', 'async*', 'Stream.map']) {
    var effects = 0;
    final interpreter = D4rt();
    interpreter.registertopLevelFunction('pause',
        (visitor, args, named, types) {
      sleep(const Duration(milliseconds: 100));
      return null;
    });
    interpreter.registertopLevelFunction('touch',
        (visitor, args, named, types) {
      effects++;
      return 1;
    });
    final deferred = interpreter.execute(
        source: _enumDeferredSource(kind, effects: true)
            .replaceFirst('touch();', 'pause();touch();'));
    interpreter.registertopLevelFunction(
        'retained', (visitor, args, named, types) => deferred);
    var timedOut = false;
    try {
      await interpreter.execute(
          source: 'main()=>retained().toList();',
          timeout: const Duration(milliseconds: 50));
    } on ExecutionTimeoutException {
      timedOut = true;
    }
    result['$kind deadline'] = [timedOut, effects];
  }
  final interpreter = D4rt();
  var effects = 0;
  interpreter.registertopLevelFunction('touch', (visitor, args, named, types) {
    effects++;
    return 1;
  });
  final iterable = interpreter.execute(
          source:
              'enum E{a;static Iterable<int> work() sync*{touch();yield 1;yield 2;}}main()=>E.work();')
      as Iterable;
  final iterator = iterable.iterator;
  interpreter.registertopLevelFunction(
      'next', (visitor, args, named, types) => iterator.moveNext());
  final first = interpreter.execute(source: 'main()=>next();');
  var refused = false;
  try {
    iterator.moveNext();
  } on RuntimeError {
    refused = true;
  }
  final next = interpreter.execute(source: 'main()=>next();');
  result['sync resume'] = [first, refused, next, iterator.current, effects];
  result['ordinary continuations'] = await D4rt().execute(source: """
import 'dart:async';
enum E{a;
  static Stream<int> work() async*{yield 1;await Future.value(0);yield 2;}
}
main() async {
  final values=await E.work().asyncMap((n) async {
    await Future.value(0);return n+1;
  }).where((n)=>n>1).toList();
  return values;
}
""");
  return result;
}

/// Verifies invocation authority after closures cross a host reentry boundary.
Future<List<Object?>> runEnumInvocationCorrection() async {
  final interpreter = D4rt();
  final closure = interpreter.execute(
      source:
          "import 'package:limit/model.dart' as model;main()=>[model.E.make(),model.E.asyncMake()];",
      sources: {
        'package:limit/model.dart':
            'enum E {a;static int get work {var n=0;while(n<1000){n++;}return n;} static make()=>()=>work;static asyncMake()=>() async {await Future.value(0);return work;};}'
      },
      timeout: const Duration(seconds: 1)) as List;
  interpreter.registertopLevelFunction(
      'syncRun',
      (visitor, args, named, types) =>
          (closure[0] as Callable).call(visitor, []));
  interpreter.registertopLevelFunction(
      'asyncRun',
      (visitor, args, named, types) =>
          (closure[1] as Callable).call(visitor, []));
  final limited = <bool>[];
  for (final name in ['syncRun', 'asyncRun']) {
    try {
      await interpreter.execute(source: 'main()=>$name();', maxSteps: 100);
      limited.add(false);
    } catch (error) {
      limited.add(error is ExecutionLimitException);
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 1100));
  final fresh = await interpreter.execute(
      source: 'main() async =>[syncRun(),await asyncRun()];',
      maxSteps: 20000,
      timeout: const Duration(seconds: 5));
  return [...limited, fresh];
}

void main() {
  for (final name in enumParameterProvenanceRejections.keys) {
    test('$name rejects before native payload and getter effects', () async {
      for (final mode in [
        'direct',
        'compiled',
        'imported',
        'compiledImported'
      ]) {
        expect(await runEnumParameterProvenancePreflight(name, mode), [true, 0],
            reason: mode);
      }
    });
  }
  for (final name in enumStaticConstantRejections.keys) {
    test('$name rejects before native payload effects', () async {
      for (final mode in [
        'direct',
        'compiled',
        'imported',
        'compiledImported'
      ]) {
        expect(await runEnumStaticConstantPreflight(name, mode), [true, 0],
            reason: mode);
      }
    });
  }
  for (final fixture in {
    'imported': enumStaticConstantPositive,
    'forward': enumStaticConstantForward,
  }.entries) {
    test(
        '${fixture.key} enum constants/defaults retain provenance without effects',
        () async {
      for (final mode in [
        'direct',
        'compiled',
        'imported',
        'compiledImported'
      ]) {
        expect(
            await executeEnumCorrection(
                D4rt(), fixture.value.source, fixture.value.sources, mode),
            fixture.value.expected,
            reason: mode);
      }
    });
  }
  for (final mode in ['direct', 'compiled', 'imported', 'compiledImported']) {
    test(
        'deferred enum generators and streams require current authority: $mode',
        () async {
      expect(await runEnumDeferredAuthority(mode), {
        'sync*': [
          true,
          [1000],
          true,
          0
        ],
        'async*': [
          true,
          [1000],
          true,
          0
        ],
        'Stream.map': [
          true,
          [1000],
          true,
          0
        ],
        'sync* budget effects': 0,
        'async* budget effects': 0,
        'Stream.map budget effects': 0,
        'awaitedContinuation': [0, 1],
        'explicitHostEntry': [1, 2],
      });
    });
  }
  test('deferred deadlines and resumes preserve authority and continuation',
      () async {
    expect(await runEnumDeferredTransitions(), {
      'sync* deadline': [true, 0],
      'async* deadline': [true, 0],
      'Stream.map deadline': [true, 0],
      'sync resume': [true, true, true, 2, 1],
      'ordinary continuations': [2, 3],
    });
  });
  for (final entry in enumCorrectionScenarios.entries) {
    test(entry.key, () async {
      for (final mode in [
        'direct',
        'compiled',
        'imported',
        'compiledImported'
      ]) {
        expect(
            await executeEnumCorrection(
                D4rt(), entry.value.source, entry.value.sources, mode),
            entry.value.expected,
            reason: mode);
      }
    });
  }
  for (final entry in enumCorrectionInvalidSources.entries) {
    test(entry.key, () async {
      for (final mode in [
        'direct',
        'compiled',
        'imported',
        'compiledImported'
      ]) {
        await expectLater(
            executeEnumCorrection(D4rt(), entry.value,
                enumCorrectionInvalidModules[entry.key] ?? const {}, mode),
            throwsA(anything),
            reason: mode);
      }
    });
  }
  test('escaped sync async reentry uses current limits and deadlines',
      () async {
    expect(await runEnumInvocationCorrection(), [
      true,
      true,
      [1000, 1000]
    ]);
  });
  test('imported const cycles propagate in the owning library', () {
    expect(
        () => D4rt().execute(
            source:
                "import 'package:p/p.dart' as p; enum E {a(p.a);const E(this.value);final dynamic value;} main()=>0;",
            sources: {'package:p/p.dart': 'const a=b;const b=a;'}),
        throwsA(anything));
  });
  for (final lazyExpression in [
    '[1].map((_)=>E.work())',
    '{1}.map((_)=>E.work())',
    'Iterable.generate(1,(_)=>E.work())',
  ]) {
    test('native lazy callback current authority: $lazyExpression', () async {
      final interpreter = D4rt();
      final values = interpreter.execute(
          source:
              'enum E{a;static int work(){var n=0;while(n<1000){n++;}return n;}}main()=>$lazyExpression;',
          timeout: const Duration(seconds: 1)) as Iterable;
      interpreter.registertopLevelFunction(
          'read', (visitor, args, named, types) => values.single);
      interpreter.registertopLevelFunction(
          'iterate', (visitor, args, named, types) => values);
      expect(
          () => interpreter.execute(source: 'main()=>read();', maxSteps: 100),
          throwsA(isA<ExecutionLimitException>()));
      expect(
          () => interpreter.execute(
              source: 'main()=>iterate().toList();', maxSteps: 100),
          throwsA(isA<ExecutionLimitException>()));
      expect(() => values.single, throwsA(isA<RuntimeError>()));
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(
          interpreter.execute(
              source: 'main()=>read();',
              maxSteps: 20000,
              timeout: const Duration(seconds: 5)),
          1000);
    });
  }
  test('native lazy adapters refuse absent authority before callback effects',
      () {
    for (final receiver in ['[1]', '{1}', 'Iterable.generate(1)']) {
      for (final operation in [
        'map((_)=>touch())',
        'where((_)=>touch()>0)',
        'expand((_)=>[touch()])',
        'takeWhile((_)=>touch()>0)',
        'skipWhile((_)=>touch()<0)',
      ]) {
        var effects = 0;
        final interpreter = D4rt();
        interpreter.registertopLevelFunction(
            'touch', (visitor, args, named, types) => ++effects);
        final values = interpreter.execute(
            source: 'main()=>$receiver.$operation;') as Iterable;
        expect(() => values.single, throwsA(isA<RuntimeError>()));
        expect(effects, 0);
      }
    }
  });
  test('top-level native iteration establishes explicit execution authority',
      () {
    const source =
        'enum E{a;static int get value=>3;}final values=[1].map((_)=>E.value).toList();main()=>values;';
    expect(D4rt().execute(source: source), [3]);
    expect(
        D4rt().execute(
            source:
                "import 'package:p/initializers.dart' as p;main()=>p.main();",
            sources: {'package:p/initializers.dart': source}),
        [3]);
  });
  test('constant mutation rejects before native payload initialization', () {
    for (final expression in ['++n', 'n++', '--n', 'n--', 'n+=1']) {
      var effects = 0;
      final interpreter = D4rt();
      interpreter.registerBridgedClass(
          BridgedClass(
              nativeType: Object,
              name: 'Payload',
              constantConstructors: {
                ''
              },
              constructors: {
                '': (visitor, args, named) {
                  effects++;
                  return Object();
                }
              }),
          'package:payload/native.dart');
      expect(
          () => interpreter.execute(
              source:
                  "import 'package:payload/native.dart'; const n=0; enum E{a(Payload()),b($expression);const E(this.value);final dynamic value;}main()=>E.a;"),
          throwsA(isA<RuntimeError>()));
      expect(effects, 0, reason: expression);
    }
  });
  test('nonconstant forward static payload rejects before initializer effects',
      () {
    var effects = 0;
    final interpreter = D4rt();
    interpreter.registertopLevelFunction('effect',
        (visitor, args, named, types) {
      effects++;
      return 1;
    });
    expect(
        () => interpreter.execute(
            source:
                'enum E{a(Payload.value);const E(this.n);final int n;}class Payload{static final value=effect();}main()=>E.a;'),
        throwsA(isA<RuntimeError>()));
    expect(effects, 0);
  });
}
