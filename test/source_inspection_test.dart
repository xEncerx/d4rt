import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  test(
    'inspects unavailable imports and executable syntax without effects',
    () {
      var effects = 0;
      final printed = <String>[];
      final interpreter = D4rt(onPrint: printed.add);
      interpreter.registertopLevelFunction('touch', (
        visitor,
        args,
        named,
        types,
      ) {
        effects++;
        return 9;
      });
      interpreter.execute(source: 'int keep = 7; int main() => keep;');
      final result = runZoned(
        () => inspectSource(
          source: '''
import 'package:missing/unavailable.dart';
import 'dart:io';
@touch()
class _Sample {
  static final field = touch();
  _Sample() { touch(); }
  int get value => touch();
}
final root = touch();
enum _Choice { value(touch()); const _Choice(int value); }
void callback() => print('must not run');
''',
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
      expect(result.hasErrors, isFalse);
      expect(result.directives.map((item) => item.uri), [
        'package:missing/unavailable.dart',
        'dart:io',
      ]);
      expect(result.declarations.map((item) => item.name), [
        '_Sample',
        null,
        '_Choice',
        'callback',
      ]);
      expect(effects, 0);
      expect(printed, isEmpty);
      interpreter.grant(DangerousPermission.codeEvaluation);
      expect(interpreter.eval('keep'), 7);
      expect(() => result.declarations.clear(), throwsUnsupportedError);
    },
  );

  test(
    'retains aliases, unnamed declarations, accessor pairs and duplicates',
    () {
      final result = inspectSource(
        source: '''
import 'dart:math' as shared;
import 'dart:async' as shared;
class _Same {}
class _Same {}
typedef _Alias = int;
typedef int _OldAlias();
class _ClassAlias = Object with _Mixin;
mixin _Mixin {}
extension on String {}
extension _Named on int {}
extension type _Wrapped(int value) {}
int get _property => 1;
set _property(int value) {}
final first = 1, second = 2, _ = 3;
''',
      );
      expect(result.hasErrors, isFalse);
      expect(result.directives.map((item) => item.prefix), [
        'shared',
        'shared',
      ]);
      expect(result.declarations.map((item) => item.name), [
        '_Same',
        '_Same',
        '_Alias',
        '_OldAlias',
        '_ClassAlias',
        '_Mixin',
        null,
        '_Named',
        '_Wrapped',
        '_property',
        '_property',
        null,
      ]);
      expect(
        result.declarations.where(
          (item) => item.kind == SourceDeclarationKind.alias,
        ),
        hasLength(3),
      );
      final variables = result.declarations.last as SourceVariables;
      expect(variables.variables.map((item) => item.name), [
        'first',
        'second',
        '_',
      ]);
      final accessors = result.declarations
          .whereType<SourceCallable>()
          .toList();
      expect(accessors[0].isGetter, isTrue);
      expect(accessors[1].isSetter, isTrue);
      final implicit = result.declarations.first as SourceTypeDeclaration;
      expect(implicit.members, isEmpty);
    },
  );

  test(
    'retains exact callable and declared type syntax without resolution',
    () {
      const source = '''
final class Sample<T> extends p.Base<int> with M implements I {
  Sample(this.field, {required super.value});
  factory Sample.named() = Other;
  Sample.redirect() : this(1, value: 2);
  final int field;
  external static Future<List<p.Item?>> run<U>(int input,
      [String fallback = 'x']);
  Stream<int> values() async* { yield 1; }
  int get count => 1;
  set count(int value) {}
  void callback(int oldStyle(String value), int Function(String)? modern,
      (int, String) record, {required int named, int optional = 0}) {}
  void modified(covariant int input) {}
  untyped(value) => value;
}
''';
      final result = inspectSource(source: source);
      expect(
        result.hasErrors,
        isFalse,
        reason: result.diagnostics.map((d) => d.message).join('\n'),
      );
      final owner = result.declarations.single as SourceTypeDeclaration;
      expect(owner.modifiers, contains('final'));
      expect(owner.superclass!.prefix, 'p');
      expect(owner.superclass!.arguments.single.canonicalName, 'int');
      expect(owner.mixins.single.name, 'M');
      expect(owner.interfaces.single.name, 'I');
      final constructors = owner.members
          .whereType<SourceCallable>()
          .where((member) => member.kind == SourceDeclarationKind.constructor)
          .toList();
      expect(constructors.map((item) => item.name), [
        null,
        'named',
        'redirect',
      ]);
      expect(constructors[0].parameters[0].form, SourceParameterForm.field);
      expect(
        constructors[0].parameters[1].form,
        SourceParameterForm.superFormal,
      );
      expect(constructors[1].isFactory, isTrue);
      expect(constructors[1].isRedirecting, isTrue);
      expect(constructors[2].initializerCount, 1);
      final methods = owner.members
          .whereType<SourceCallable>()
          .where((member) => member.kind == SourceDeclarationKind.method)
          .toList();
      final run = methods.first;
      expect(run.isExternal && run.isStatic && run.hasTypeParameters, isTrue);
      expect(run.bodyKind, SourceBodyKind.empty);
      expect(run.returnType!.canonicalName, isNull);
      final item = run.returnType!.arguments.single.arguments.single;
      expect(item.name, 'Item');
      expect(item.prefix, 'p');
      expect(item.isNullable, isTrue);
      final modified = methods[5].parameters.single;
      expect(modified.isCovariant, isTrue);
      expect(modified.hasModifier, isFalse);
      final recoveredModifier = inspectSource(
        source: 'void f(final int value) {}',
      );
      expect(recoveredModifier.hasErrors, isTrue);
      expect(
        (recoveredModifier.declarations.single as SourceCallable)
            .parameters
            .single
            .hasModifier,
        isTrue,
      );
      expect(run.parameters.last.kind, SourceParameterKind.optionalPositional);
      expect(
        run.parameters.last.defaultValue!.kind,
        SourceExpressionKind.literal,
      );
      expect(methods[1].isAsync && methods[1].isGenerator, isTrue);
      expect(methods[2].isGetter, isTrue);
      expect(methods[3].isSetter, isTrue);
      final callback = methods[4];
      expect(callback.parameters[0].isFunctionTyped, isTrue);
      expect(callback.parameters[1].type!.kind, SourceTypeKind.function);
      expect(callback.parameters[2].type!.kind, SourceTypeKind.record);
      expect(callback.parameters[3].kind, SourceParameterKind.requiredNamed);
      expect(callback.parameters[4].kind, SourceParameterKind.optionalNamed);
      expect(methods.last.returnType, isNull);
      expect(methods.last.parameters.single.type, isNull);
      expect(
        source.substring(methods[1].bodySpan.offset, methods[1].bodySpan.end),
        'async* { yield 1; }',
      );
    },
  );

  test(
    'reports nested type and field occurrences in recursive source order',
    () {
      final result = inspectSource(
        source: '''
enum Sample with M {
  first(<String, List<Payload>>{}), second(null);
  const Sample(this.value);
  final Object? value;
  static final a = -1, b = [1, {'x': 2}], c = [if (true) 1];
  final int Function(Payload)? callback = null;
  T method<T extends Payload>() => throw 1;
}
''',
      );
      expect(result.hasErrors, isFalse);
      final owner = result.declarations.single as SourceTypeDeclaration;
      expect(owner.constants.map((item) => item.name), ['first', 'second']);
      expect(
        owner.constants.first.arguments.single.kind,
        SourceExpressionKind.setOrMap,
      );
      expect(owner.syntax.whereType<SourceType>().map((item) => item.name), [
        'M',
        'String',
        'List',
        'Payload',
        'Object',
        'int',
        'Payload',
        'T',
        'Payload',
      ]);
      final field = owner.syntax.whereType<SourceVariables>().firstWhere(
        (item) => item.isStatic,
      );
      expect(
        identical(
          field,
          owner.members.whereType<SourceVariables>().firstWhere(
            (item) => item.isStatic,
          ),
        ),
        isTrue,
      );
      expect(field.variables[0].initializer!.operator, '-');
      expect(
        field.variables[1].initializer!.children.last.kind,
        SourceExpressionKind.setOrMap,
      );
      expect(
        field.variables[2].initializer!.children.single.kind,
        SourceExpressionKind.other,
      );
      expect(owner.memberNames(), [
        'value',
        'a',
        'b',
        'c',
        'callback',
        'method',
      ]);
      expect(owner.memberNames(instanceOnly: true), [
        'value',
        'callback',
        'method',
      ]);
    },
  );

  test(
    'preserves directive variants rather than treating every directive as an import',
    () {
      final result = inspectSource(
        source: '''
library sample;
import 'a.dart' deferred as a show One;
import 'b.dart' if (dart.library.io) 'c.dart' hide Two;
export 'd.dart';
part 'part.dart';
''',
      );
      expect(result.hasErrors, isFalse);
      expect(result.directives.map((item) => item.kind), [
        SourceDirectiveKind.library,
        SourceDirectiveKind.import,
        SourceDirectiveKind.import,
        SourceDirectiveKind.export,
        SourceDirectiveKind.part,
      ]);
      expect(result.directives[1].isDeferred, isTrue);
      expect(result.directives[1].hasCombinators, isTrue);
      expect(result.directives[2].isConditional, isTrue);
      expect(result.directives[2].hasCombinators, isTrue);
      expect(
        inspectSource(source: "part of 'owner.dart';").directives.single.kind,
        SourceDirectiveKind.partOf,
      );
    },
  );

  test(
    'ranges address UTF-16 source and malformed syntax remains an error',
    () {
      const source = '// 😀 é\nsealed class Sample { void run(); }';
      final valid = inspectSource(source: source);
      final owner = valid.declarations.single as SourceTypeDeclaration;
      final sealed = owner.sealedSpan!;
      expect(sealed.offset, source.indexOf('sealed'));
      expect(source.substring(sealed.offset, sealed.end), 'sealed');
      final method = owner.members.single as SourceCallable;
      expect(
        source.substring(method.bodySpan.offset, method.bodySpan.end),
        ';',
      );
      const malformed = '// 😀 é\nint broken = ;\nvoid run(';
      final invalid = inspectSource(source: malformed);
      expect(invalid.hasErrors, isTrue);
      final errors = invalid.diagnostics
          .where((d) => d.severity == SourceDiagnosticSeverity.error)
          .toList();
      expect(errors.first.span.offset, malformed.indexOf(';'));
      expect(errors.first.span.length, 1);
      expect(
        errors.any((error) => error.span.offset == malformed.length),
        isTrue,
      );
      expect(
        errors
            .where((error) => error.span.offset == malformed.length)
            .any((error) => error.span.length == 1),
        isTrue,
      );
      for (final error in errors) {
        expect(error.span.offset, inInclusiveRange(0, malformed.length));
        expect(
          error.span.end,
          inInclusiveRange(error.span.offset, malformed.length + 1),
        );
        expect(error.code, isNotEmpty);
      }
      expect(inspectSource(source: '').declarations, isEmpty);
    },
  );
}
