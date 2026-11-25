import 'package:d4rt/src/bridge/bridge_helpers.dart';
import 'package:d4rt/src/bridge/bridged_enum.dart';
import 'package:d4rt/src/bridge/bridged_types.dart';
import 'package:test/test.dart';

enum Shade { light, dark }

class Token {}

void main() {
  final type = BridgedEnum('Shade', {});
  final light = BridgedEnumValue(type, 'light', 0, Shade.light);
  final dark = BridgedEnumValue(type, 'dark', 1, Shade.dark);

  test('native enum arguments and collection elements are unwrapped', () {
    final positional = <Object?>[
      light,
      [light, dark],
      {light: dark},
      {light},
    ];
    final named = <String, Object?>{
      'value': light,
      'list': [light, dark],
      'map': {light: dark},
      'set': {light},
    };
    expect(positional.required<Shade>(0, 'value'), Shade.light);
    expect(positional.optional<Shade>(0, 'value', Shade.dark), Shade.light);
    expect(positional.optionalNullable<Shade>(0, 'value'), Shade.light);
    expect(positional.asList<Shade>(1, 'list'), [Shade.light, Shade.dark]);
    expect(BridgePositionalArgs(positional).asMap<Shade, Shade>(2, 'map'), {
      Shade.light: Shade.dark,
    });
    expect(positional.asSet<Shade>(3, 'set'), {Shade.light});
    expect(named.required<Shade>('value'), Shade.light);
    expect(named.optional<Shade>('value', Shade.dark), Shade.light);
    expect(named.optionalNullable<Shade>('value'), Shade.light);
    expect(named.asList<Shade>('list'), [Shade.light, Shade.dark]);
    expect(named.asMap<Shade, Shade>('map'), {Shade.light: Shade.dark});
    expect(named.asSet<Shade>('set'), {Shade.light});
  });

  test('direct coercion extracts enum values and preserves scalar policy', () {
    expect(light.coerce<Shade>('shade'), same(Shade.light));
    expect((null as Object?).coerce<Shade?>('shade'), isNull);
    expect(() => (null as Object?).coerce<Shade>('shade'), throwsArgumentError);
    expect((3 as Object?).coerce<double>('number'), 3.0);
    expect((3.8 as Object?).coerce<int>('number'), 3);
    expect(() => 'wrong'.coerce<Shade>('shade'), throwsArgumentError);
    expect(<Object?>[].optional<Shade>(0, 'shade', Shade.dark), Shade.dark);
  });

  test('typed native collections preserve identity', () {
    final list = <Shade>[Shade.light];
    final map = <Shade, Shade>{Shade.light: Shade.dark};
    final set = <Shade>{Shade.light};
    final positional = <Object?>[list, map, set];
    final named = <String, Object?>{'list': list, 'map': map, 'set': set};
    expect(identical(positional.asList<Shade>(0, 'list'), list), isTrue);
    expect(
      identical(
        BridgePositionalArgs(positional).asMap<Shade, Shade>(1, 'map'),
        map,
      ),
      isTrue,
    );
    expect(identical(positional.asSet<Shade>(2, 'set'), set), isTrue);
    expect(identical(named.asList<Shade>('list'), list), isTrue);
    expect(identical(named.asMap<Shade, Shade>('map'), map), isTrue);
    expect(identical(named.asSet<Shade>('set'), set), isTrue);
  });

  test('iterable extraction preserves typed values and defers conversion', () {
    final typed = <Shade>{Shade.light, Shade.dark};
    expect(
      identical(<Object?>[typed].asIterable<Shade>(0, 'values'), typed),
      isTrue,
    );
    expect(
      identical(
        <String, Object?>{'values': typed}.asIterable<Shade>('values'),
        typed,
      ),
      isTrue,
    );
    final entries = <Object?, Object?>{'a': 1, null: 'b'}.entries;
    final extracted = <Object?>[
      entries,
    ].asIterable<MapEntry<Object?, Object?>>(0, 'entries');
    expect(identical(extracted, entries), isTrue);
    expect(extracted.map((entry) => entry.key), ['a', null]);

    var visits = 0;
    final source = Iterable<Object?>.generate(2, (index) {
      visits++;
      return index == 0 ? light : dark;
    });
    final converted = <Object?>[source].asIterable<Shade>(0, 'values');
    expect(visits, 0);
    expect(converted.toList(), [Shade.light, Shade.dark]);
    expect(visits, 2);
    final token = Token();
    final wrapped = BridgedInstance(
      BridgedClass(nativeType: Token, name: 'Token'),
      token,
    );
    expect(
      <Object?>[
        [wrapped],
      ].asIterable<Token>(0, 'tokens').single,
      same(token),
    );
  });

  test('iterable extraction preserves null and deferred failures', () {
    final absent = <Object?>[];
    final named = <String, Object?>{'values': null};
    expect(absent.asIterableOrNull<int>(0, 'values'), isNull);
    expect(named.asIterableOrNull<int>('values'), isNull);
    expect(
      () => <Object?>[1].asIterable<int>(0, 'values'),
      throwsArgumentError,
    );
    expect(
      () => <String, Object?>{'values': 1}.asIterableOrNull<int>('values'),
      throwsArgumentError,
    );
    final error = StateError('iteration');
    final source = Iterable<Object?>.generate(1, (_) => throw error);
    final converted = <Object?>[source].asIterable<int>(0, 'values');
    expect(() => converted.toList(), throwsA(same(error)));
    final wrong = <Object?>[
      ['not an integer'],
    ].asIterable<int>(0, 'values');
    expect(() => wrong.toList(), throwsA(isA<TypeError>()));
  });
}
