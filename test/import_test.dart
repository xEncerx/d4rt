import 'dart:io' as io;

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    final directories = ['test_fs_imports'];
    for (final directoryName in directories) {
      final directory = io.Directory(directoryName);
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  });

  group('Import Tests', () {
    final Map<String, String> sources = {
      "d4rt-mem:/lib_common.dart": '''
    String getMessage() {
      return "Hello from lib_common!";
    }
    int getNumber() {
      return 42;
    }
    String getExtraMessage() {
      return "Extra message from lib_common!";
    }
    ''',
      "d4rt-mem:/main_source.dart": '''
    import 'lib_common.dart';

    String main() {
      return "Message from lib: " +
          getMessage() +
          " and number is " +
          getNumber().toString() +
          " and extra: " +
          getExtraMessage();
    }
    ''',
      "package:my_test_pkg/utils.dart": '''
    String getPackageUtilMessage() {
      return "Hello from my_test_pkg/utils!";
    }
    int getPackageUtilNumber() {
      return 123;
    }
    ''',
      "d4rt-mem:/main_pkg_import.dart": '''
    import 'package:my_test_pkg/utils.dart';
    String main() {
      return "PkgMsg: " +
          getPackageUtilMessage() +
          " | PkgNum: " +
          getPackageUtilNumber().toString();
    }
    ''',
      "d4rt-mem:/main_prefixed_pkg_import.dart": '''
    import 'package:my_test_pkg/utils.dart' as mypkg;
    String main() {
      return "PrefixedPkgMsg: " +
          mypkg.getPackageUtilMessage() +
          " | PrefixedPkgNum: " +
          mypkg.getPackageUtilNumber().toString();
    }
    ''',
      "d4rt-mem:/main_dart_math_import.dart": '''
    import 'dart:math';
    String main() {
      var result = sin(pi / 2);
      return "sin(pi/2) = " + result.toString();
    }
    ''',
      "d4rt-mem:/main_import_show.dart": '''
    import 'lib_common.dart' show getMessage, getNumber;
    String main() {
      return getMessage() + " | " + getNumber().toString();
    }
    ''',
      "d4rt-mem:/main_import_show_check_hidden.dart": '''
    import 'lib_common.dart' show getMessage, getNumber;
    String main() {
      return getExtraMessage();
    }
    ''',
      "d4rt-mem:/main_import_hide.dart": '''
    import 'lib_common.dart' hide getExtraMessage;
    String main() {
      return getMessage() + " | " + getNumber().toString();
    }
    ''',
      "d4rt-mem:/main_import_hide_check_hidden.dart": '''
    import 'lib_common.dart' hide getExtraMessage;
    String main() {
      return getExtraMessage();
    }
    ''',
      "d4rt-mem:/main_prefixed_import_show.dart": '''
    import 'lib_common.dart' as common show getMessage, getNumber;
    String main() {
      return common.getMessage() + " | " + common.getNumber().toString();
    }
    ''',
      "d4rt-mem:/main_prefixed_import_show_check_hidden.dart": '''
    import 'lib_common.dart' as common show getMessage, getNumber;
    String main() {
      return common.getExtraMessage();
    }
    ''',
      "d4rt-mem:/main_prefixed_import_hide.dart": '''
    import 'lib_common.dart' as common hide getExtraMessage;
    String main() {
      return common.getMessage() + " | " + common.getNumber().toString();
    }
    ''',
      "d4rt-mem:/main_prefixed_import_hide_check_hidden.dart": '''
    import 'lib_common.dart' as common hide getExtraMessage;
    String main() {
      return common.getExtraMessage();
    }
    ''',
      "d4rt-mem:/main_import_conflict_show.dart": '''
    import 'lib_common.dart' show getNumber;
    String getMessage() {
      return "Local getMessage";
    }
    String main() {
      return getMessage() + " | " + getNumber().toString();
    }
    ''',
      "d4rt-mem:/main_import_conflict_hide.dart": '''
    import 'lib_common.dart' hide getMessage;
    String getMessage() {
      return "Local getMessage";
    }
    String main() {
      return getMessage() + " | " + getNumber().toString() + " | " + getExtraMessage();
    }
    ''',
      "d4rt-mem:/cycle_a.dart": '''
    import 'cycle_b.dart';

    String fromA() => 'A';

    String main() {
      return fromB();
    }
    ''',
      "d4rt-mem:/cycle_b.dart": '''
    import 'cycle_a.dart';

    String fromB() => fromA();
    ''',
      "d4rt-mem:/export_cycle_a.dart": '''
    export 'export_cycle_b.dart';

    String fromExportA() => 'A';
    ''',
      "d4rt-mem:/export_cycle_b.dart": '''
    export 'export_cycle_a.dart';

    String fromExportB() => 'B';
    ''',
      "d4rt-mem:/main_export_cycle.dart": '''
    import 'export_cycle_a.dart';

    String main() {
      return fromExportA();
    }
    ''',
      "d4rt-mem:/missing_import_root.dart": '''
    import 'missing_import_target.dart';

    String main() {
      return 'never';
    }
    ''',
      "d4rt-mem:/missing_export_root.dart": '''
    export 'missing_export_target.dart';

    String main() {
      return 'never';
    }
    ''',
    };

    test(
      'Import local simple file (memory) - check all symbols of the common lib',
      () {
        final d4rt = D4rt();
        final mainlibrary = "d4rt-mem:/main_source.dart";
        final result = d4rt.execute(
          library: mainlibrary,
          sources: sources,
        );
        expect(
          result,
          equals(
              "Message from lib: Hello from lib_common! and number is 42 and extra: Extra message from lib_common!"),
        );
      },
    );

    test('Import package simple (memory)', () {
      final d4rt = D4rt();
      final mainlibrary = "d4rt-mem:/main_pkg_import.dart";
      final result = d4rt.execute(
        library: mainlibrary,
        sources: sources,
      );
      expect(
        result,
        equals("PkgMsg: Hello from my_test_pkg/utils! | PkgNum: 123"),
      );
    });

    test(
        'Library execution reuses one fully populated module graph across inheritance and initialization',
        () {
      final inheritanceSources = <String, String>{
        'package:sdk/model.dart': '''
class InputModel {
  final String value;

  InputModel(this.value);
}

class OutputModel {
  final String value;

  OutputModel(this.value);
}
''',
        'package:sdk/base.dart': '''
import 'package:sdk/model.dart';

int rootInitializationCount = 0;

void recordRootInitialization() {
  rootInitializationCount++;
}

int readRootInitializationCount() => rootInitializationCount;

class Base {
  String constructorState = 'field-initializer-only';

  Base() {
    constructorState = 'constructor-body-ran';
  }

  String inheritedMethod() => 'base:' + constructorState;

  OutputModel inheritedTransform(InputModel input) {
    return OutputModel('base:' + input.value + ':' + constructorState);
  }
}
''',
        'package:author/author.dart': '''
import 'package:sdk/base.dart';
import 'package:sdk/model.dart';

final class Author extends Base {
  String ownMethod() => 'author';

  OutputModel transform(InputModel input) {
    return OutputModel('author:' + input.value);
  }
}
''',
        'd4rt-mem:/inheritance_main.dart': '''
import 'package:author/author.dart';
import 'package:sdk/base.dart';
import 'package:sdk/model.dart';

final String initializedReport = initializeRoot();

final class Entry extends Author {
  String entryMethod() => 'entry';
}

String initializeRoot() {
  recordRootInitialization();
  print('root initialized');
  final entry = Entry();
  final input = InputModel('payload');
  final ownModel = entry.transform(input);
  final inheritedModel = entry.inheritedTransform(input);
  return entry.entryMethod() +
      '|' +
      entry.ownMethod() +
      '|' +
      entry.inheritedMethod() +
      '|' +
      ownModel.value +
      '|' +
      inheritedModel.value;
}

String main() => initializedReport +
    '|count:' +
    readRootInitializationCount().toString();
''',
      };

      final d4rt = D4rt();
      final printedMessages = <String>[];
      final result = d4rt.execute(
        library: 'd4rt-mem:/inheritance_main.dart',
        sources: inheritanceSources,
        onPrint: printedMessages.add,
      );

      expect(
        result,
        equals(
          'entry|author|base:constructor-body-ran|author:payload|base:payload:constructor-body-ran|count:1',
        ),
      );
      expect(printedMessages, equals(['root initialized']));
      expect(
        d4rt.eval('initializedReport'),
        equals(
          'entry|author|base:constructor-body-ran|author:payload|base:payload:constructor-body-ran',
        ),
      );
    });

    test('Imported symbols are available to module top-level initializers', () {
      final initializerSources = <String, String>{
        'package:initializer/provider.dart': '''
String buildMessage(String value) => 'initialized:' + value;
''',
        'package:initializer/consumer.dart': '''
import 'package:initializer/provider.dart';

final String loadedMessage = buildMessage('ready');

String readLoadedMessage() => loadedMessage;
''',
        'd4rt-mem:/initializer_main.dart': '''
import 'package:initializer/consumer.dart';

String main() => readLoadedMessage();
''',
      };

      final result = D4rt().execute(
        library: 'd4rt-mem:/initializer_main.dart',
        sources: initializerSources,
      );

      expect(result, equals('initialized:ready'));
    });

    test(
        'Local functions are callable by eager static initializers after imports',
        () {
      final staticInitializerSources = <String, String>{
        'package:static_initializers/model.dart': '''
class StaticValue {
  final String label;

  StaticValue(this.label);
}
''',
        'package:static_initializers/class_holder.dart': '''
import 'package:static_initializers/model.dart';

class ClassHolder {
  static final StaticValue value = buildClassValue();
}

StaticValue buildClassValue() => StaticValue('class');
''',
        'package:static_initializers/mixin_holder.dart': '''
import 'package:static_initializers/model.dart';

mixin MixinHolder {
  static final StaticValue value = buildMixinValue();
}

StaticValue buildMixinValue() => StaticValue('mixin');
''',
        'package:static_initializers/enum_holder.dart': '''
import 'package:static_initializers/model.dart';

enum EnumHolder {
  only;

  static final StaticValue value = buildEnumValue();
}

StaticValue buildEnumValue() => StaticValue('enum');
''',
        'package:static_initializers/extension_holder.dart': '''
import 'package:static_initializers/model.dart';

extension ExtensionHolder on String {
  static final StaticValue value = buildExtensionValue();
}

StaticValue buildExtensionValue() => StaticValue('extension');
''',
        'd4rt-mem:/static_initializers_main.dart': '''
import 'package:static_initializers/class_holder.dart';
import 'package:static_initializers/enum_holder.dart';
import 'package:static_initializers/extension_holder.dart';
import 'package:static_initializers/mixin_holder.dart';

String main() => ClassHolder.value.label +
    '|' +
    MixinHolder.value.label +
    '|' +
    EnumHolder.value.label +
    '|' +
    ExtensionHolder.value.label;
''',
      };

      final result = D4rt().execute(
        library: 'd4rt-mem:/static_initializers_main.dart',
        sources: staticInitializerSources,
      );

      expect(result, equals('class|mixin|enum|extension'));
    });

    test('Imported class bounds are resolved after imports and enforced', () {
      final boundSources = <String, String>{
        'package:bounds/model.dart': '''
class ImportedModel {
  final String value;

  ImportedModel(this.value);
}
''',
        'package:bounds/container.dart': '''
import 'package:bounds/model.dart';

class Child<T extends ImportedModel> {
  final T value;

  Child(this.value);

  String describe() => 'child:' + value.value;
}
''',
        'package:bounds/valid_main.dart': '''
import 'package:bounds/container.dart';
import 'package:bounds/model.dart';

String main() => Child<ImportedModel>(ImportedModel('ready')).describe();
''',
        'package:bounds/invalid_main.dart': '''
import 'package:bounds/container.dart';

String main() => Child<String>('invalid').describe();
''',
      };

      expect(
        D4rt().execute(
          library: 'package:bounds/valid_main.dart',
          sources: boundSources,
        ),
        equals('child:ready'),
      );
      expect(
        () => D4rt().execute(
          library: 'package:bounds/invalid_main.dart',
          sources: boundSources,
        ),
        throwsA(
          isA<RuntimeError>().having(
            (error) => error.message,
            'message',
            contains('does not satisfy bound'),
          ),
        ),
      );
    });

    test('Library-private declarations stay inside their defining library', () {
      const ownerUri = 'package:privacy/owner.dart';
      const exporterUri = 'package:privacy/exporter.dart';
      const transitiveExporterUri = 'package:privacy/transitive_exporter.dart';
      final privacySources = <String, String>{
        ownerUri: '''
String _privateValue = 'value';

String _privateFunction() => 'function';

class _PrivateClass {
  String reveal() => 'class';
}

String publicFunction() =>
    _privateFunction() + ':' + _privateValue + ':' + _PrivateClass().reveal();

class PublicClass {
  String reveal() => publicFunction();
}
''',
        exporterUri: '''
export 'package:privacy/owner.dart'
    show _privateValue, _privateFunction, _PrivateClass, publicFunction, PublicClass;
''',
        transitiveExporterUri: '''
export 'package:privacy/exporter.dart';
''',
        'package:privacy/public_import_main.dart': '''
import 'package:privacy/owner.dart';

String main() => publicFunction() + '|' + PublicClass().reveal();
''',
        'package:privacy/public_export_main.dart': '''
import 'package:privacy/exporter.dart';

String main() => publicFunction() + '|' + PublicClass().reveal();
''',
      };

      expect(
        D4rt().execute(
          library: 'package:privacy/public_import_main.dart',
          sources: privacySources,
        ),
        equals('function:value:class|function:value:class'),
      );
      expect(
        D4rt().execute(
          library: 'package:privacy/public_export_main.dart',
          sources: privacySources,
        ),
        equals('function:value:class|function:value:class'),
      );

      final privateExpressions = <String, String>{
        '_privateValue': '_privateValue',
        '_privateFunction': '_privateFunction()',
        '_PrivateClass': '_PrivateClass().reveal()',
      };
      for (final entry in privateExpressions.entries) {
        final directMainUri = 'package:privacy/direct_${entry.key}.dart';
        final exportMainUri = 'package:privacy/export_${entry.key}.dart';
        final transitiveMainUri =
            'package:privacy/transitive_${entry.key}.dart';
        privacySources[directMainUri] = '''
import '$ownerUri';

dynamic main() => ${entry.value};
''';
        privacySources[exportMainUri] = '''
import '$exporterUri';

dynamic main() => ${entry.value};
''';
        privacySources[transitiveMainUri] = '''
import '$transitiveExporterUri';

dynamic main() => ${entry.value};
''';

        expect(
          () => D4rt().execute(
            library: directMainUri,
            sources: privacySources,
          ),
          throwsA(isA<RuntimeError>()),
          reason: '${entry.key} must not be available through an import',
        );
        expect(
          () => D4rt().execute(
            library: exportMainUri,
            sources: privacySources,
          ),
          throwsA(isA<RuntimeError>()),
          reason: '${entry.key} must not be available through an export',
        );
        expect(
          () => D4rt().execute(
            library: transitiveMainUri,
            sources: privacySources,
          ),
          throwsA(isA<RuntimeError>()),
          reason:
              '${entry.key} must not be available through transitive exports',
        );
      }

      final prefixedExpressions = <String, String>{
        '_privateValue': 'owner._privateValue',
        '_privateFunction': 'owner._privateFunction()',
      };
      for (final entry in prefixedExpressions.entries) {
        final mainUri = 'package:privacy/prefixed_${entry.key}.dart';
        privacySources[mainUri] = '''
import '$ownerUri' as owner;

dynamic main() => ${entry.value};
''';

        expect(
          () => D4rt().execute(library: mainUri, sources: privacySources),
          throwsA(isA<RuntimeError>()),
          reason: '${entry.key} must not be available through a prefix',
        );
      }
    });

    test('Invalid imported type declarations fail module loading', () {
      final invalidDeclarationSources = <String, String>{
        'package:invalid/child.dart': '''
class BrokenChild extends MissingBase {
  String method() => 'must-not-run';
}
''',
        'package:invalid/mixin.dart': '''
mixin BrokenMixin on MissingBase {
  String method() => 'must-not-run';
}
''',
        'package:invalid/extension.dart': '''
extension BrokenExtension on MissingType {
  String method() => 'must-not-run';
}
''',
        'd4rt-mem:/invalid_superclass_main.dart': '''
import 'package:invalid/child.dart';

String main() => 'must-not-complete';
''',
        'd4rt-mem:/invalid_mixin_main.dart': '''
import 'package:invalid/mixin.dart';

String main() => 'must-not-complete';
''',
        'd4rt-mem:/invalid_extension_main.dart': '''
import 'package:invalid/extension.dart';

String main() => 'must-not-complete';
''',
      };

      expect(
        () => D4rt().execute(
          library: 'd4rt-mem:/invalid_superclass_main.dart',
          sources: invalidDeclarationSources,
        ),
        throwsA(
          isA<RuntimeError>().having(
            (error) => error.message,
            'message',
            contains(
              "Superclass 'MissingBase' not found for class 'BrokenChild'",
            ),
          ),
        ),
      );
      expect(
        () => D4rt().execute(
          library: 'd4rt-mem:/invalid_mixin_main.dart',
          sources: invalidDeclarationSources,
        ),
        throwsA(
          isA<RuntimeError>().having(
            (error) => error.message,
            'message',
            contains("Type 'MissingBase' in 'on' clause of mixin"),
          ),
        ),
      );
      expect(
        () => D4rt().execute(
          library: 'd4rt-mem:/invalid_extension_main.dart',
          sources: invalidDeclarationSources,
        ),
        throwsA(
          isA<RuntimeError>().having(
            (error) => error.message,
            'message',
            contains("Could not resolve 'on' type 'MissingType'"),
          ),
        ),
      );
    });

    test('Ordinary imports do not become transitive exports', () {
      final nonTransitiveSources = <String, String>{
        'package:non_transitive/origin.dart': '''
String originValue() => 'origin';
''',
        'package:non_transitive/middle.dart': '''
import 'package:non_transitive/origin.dart';

String middleValue() => 'middle:' + originValue();
''',
        'd4rt-mem:/middle_access_main.dart': '''
import 'package:non_transitive/middle.dart';

String main() => middleValue();
''',
        'd4rt-mem:/origin_leak_main.dart': '''
import 'package:non_transitive/middle.dart';

String main() => originValue();
''',
      };

      expect(
        D4rt().execute(
          library: 'd4rt-mem:/middle_access_main.dart',
          sources: nonTransitiveSources,
        ),
        equals('middle:origin'),
      );
      expect(
        () => D4rt().execute(
          library: 'd4rt-mem:/origin_leak_main.dart',
          sources: nonTransitiveSources,
        ),
        throwsA(
          isA<RuntimeError>().having(
            (error) => error.message,
            'message',
            contains('Undefined variable: originValue'),
          ),
        ),
      );
    });

    test('Imported unnamed extensions do not become transitive exports', () {
      final extensionSources = <String, String>{
        'package:extension/origin.dart': '''
extension on String {
  String decorated() => this + ':decorated';
}
''',
        'package:extension/middle.dart': '''
import 'package:extension/origin.dart';

String useImportedExtension() => 'middle'.decorated();
''',
        'package:extension/exporter.dart': '''
export 'package:extension/origin.dart';
''',
        'd4rt-mem:/extension_access_main.dart': '''
import 'package:extension/middle.dart';

String main() => useImportedExtension();
''',
        'd4rt-mem:/extension_leak_main.dart': '''
import 'package:extension/middle.dart';

String main() => 'root'.decorated();
''',
        'd4rt-mem:/extension_export_main.dart': '''
import 'package:extension/exporter.dart';

String main() => 'exported'.decorated();
''',
      };

      expect(
        D4rt().execute(
          library: 'd4rt-mem:/extension_access_main.dart',
          sources: extensionSources,
        ),
        equals('middle:decorated'),
      );
      expect(
        () => D4rt().execute(
          library: 'd4rt-mem:/extension_leak_main.dart',
          sources: extensionSources,
        ),
        throwsA(isA<RuntimeError>()),
      );
      expect(
        D4rt().execute(
          library: 'd4rt-mem:/extension_export_main.dart',
          sources: extensionSources,
        ),
        equals('exported:decorated'),
      );
    });

    test('Import prefixed package (memory)', () {
      final d4rt = D4rt();
      final mainlibrary = "d4rt-mem:/main_prefixed_pkg_import.dart";
      final result = d4rt.execute(
        library: mainlibrary,
        sources: sources,
      );
      expect(
        result,
        equals(
            "PrefixedPkgMsg: Hello from my_test_pkg/utils! | PrefixedPkgNum: 123"),
      );
    });

    test('Import dart:math (global functions)', () {
      final d4rt = D4rt();
      final mainlibrary = "d4rt-mem:/main_dart_math_import.dart";
      final result = d4rt.execute(
        library: mainlibrary,
        sources: sources,
      );
      expect(result, equals("sin(pi/2) = 1.0"));
    });

    group('Combinators (show/hide)', () {
      test('Import with "show" (no prefix) - access allowed symbols', () {
        final d4rt = D4rt();
        final result = d4rt.execute(
          library: "d4rt-mem:/main_import_show.dart",
          sources: sources,
        );
        expect(result, equals("Hello from lib_common! | 42"));
      });

      test(
        'Import with "show" (no prefix) - check that the hidden symbol is not accessible',
        () {
          final d4rt = D4rt();
          expect(
            () => d4rt.execute(
                library: "d4rt-mem:/main_import_show_check_hidden.dart",
                sources: sources),
            throwsA(
              isA<RuntimeError>().having(
                (e) => e.message,
                'message',
                contains("Undefined variable: getExtraMessage"),
              ),
            ),
          );
        },
      );

      test('Import with "hide" (no prefix) - access allowed symbols', () {
        final d4rt = D4rt();
        final result = d4rt.execute(
          library: "d4rt-mem:/main_import_hide.dart",
          sources: sources,
        );
        expect(result, equals("Hello from lib_common! | 42"));
      });

      test(
        'Import with "hide" (no prefix) - check that the hidden symbol is not accessible',
        () {
          final d4rt = D4rt();
          expect(
            () => d4rt.execute(
                library: "d4rt-mem:/main_import_hide_check_hidden.dart",
                sources: sources),
            throwsA(
              isA<RuntimeError>().having(
                (e) => e.message,
                'message',
                contains("Undefined variable: getExtraMessage"),
              ),
            ),
          );
        },
      );

      test('Import prefixed with "show" - access allowed symbols', () {
        final d4rt = D4rt();
        final result = d4rt.execute(
            library: "d4rt-mem:/main_prefixed_import_show.dart",
            sources: sources);
        expect(result, equals("Hello from lib_common! | 42"));
      });

      test(
        'Import prefixed with "show" - check that the hidden symbol is not accessible',
        () {
          final d4rt = D4rt();
          expect(
            () => d4rt.execute(
                library:
                    "d4rt-mem:/main_prefixed_import_show_check_hidden.dart",
                sources: sources),
            throwsA(
              isA<RuntimeError>().having(
                (e) => e.message,
                'message',
                contains(
                    "Method 'getExtraMessage' not found in imported module 'common'. Error: Undefined variable: getExtraMessage"),
              ),
            ),
          );
        },
      );

      test('Import prefixed with "hide" - access allowed symbols', () {
        final d4rt = D4rt();
        final result = d4rt.execute(
            library: "d4rt-mem:/main_prefixed_import_hide.dart",
            sources: sources);
        expect(result, equals("Hello from lib_common! | 42"));
      });

      test(
        'Import prefixed with "hide" - check that the hidden symbol is not accessible',
        () {
          final d4rt = D4rt();
          expect(
            () => d4rt.execute(
                library:
                    "d4rt-mem:/main_prefixed_import_hide_check_hidden.dart",
                sources: sources),
            throwsA(
              isA<RuntimeError>().having(
                (e) => e.message,
                'message',
                contains(
                    "Method 'getExtraMessage' not found in imported module 'common'. Error: Undefined variable: getExtraMessage"),
              ),
            ),
          );
        },
      );

      test('Import with "show" avoids name conflict with local definition', () {
        final d4rt = D4rt();
        final result = d4rt.execute(
            library: "d4rt-mem:/main_import_conflict_show.dart",
            sources: sources);
        expect(result, equals("Local getMessage | 42"));
      });

      test(
        'Import with "hide" avoids name conflict and allows access to other imported symbols',
        () {
          final d4rt = D4rt();
          final result = d4rt.execute(
              library: "d4rt-mem:/main_import_conflict_hide.dart",
              sources: sources);
          expect(result,
              equals("Local getMessage | 42 | Extra message from lib_common!"));
        },
      );

      test('Circular imports fail with a clear error', () {
        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            library: 'd4rt-mem:/cycle_a.dart',
            sources: sources,
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Circular module dependency detected'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('d4rt-mem:/cycle_a.dart'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('d4rt-mem:/cycle_b.dart'),
                ),
          ),
        );
      });

      test('Circular exports fail with a clear error', () {
        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            library: 'd4rt-mem:/main_export_cycle.dart',
            sources: sources,
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Circular module dependency detected'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('d4rt-mem:/export_cycle_a.dart'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('d4rt-mem:/export_cycle_b.dart'),
                ),
          ),
        );
      });

      test('Missing exports fail with module and target context', () {
        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            library: 'd4rt-mem:/missing_export_root.dart',
            sources: sources,
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains(
                      'Failed to load export "missing_export_target.dart"'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('d4rt-mem:/missing_export_root.dart'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('Module source not preloaded for URI'),
                ),
          ),
        );
      });

      test('Missing imports fail with module and target context', () {
        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            library: 'd4rt-mem:/missing_import_root.dart',
            sources: sources,
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains(
                      'Failed to load import "missing_import_target.dart"'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('d4rt-mem:/missing_import_root.dart'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('Module source not preloaded for URI'),
                ),
          ),
        );
      });

      test('Direct source can import relative filesystem module', () {
        io.Directory('test_fs_imports/lib').createSync(recursive: true);
        io.File('test_fs_imports/lib/utils.dart').writeAsStringSync('''
String greetFromUtils() {
  return "hello from fs";
}
''');

        final d4rt = D4rt();
        d4rt.grant(FilesystemPermission.readPath('test_fs_imports/lib'));

        final result = d4rt.execute(
          source: '''
import './utils.dart';

String main() {
  return greetFromUtils();
}
''',
          basePath: 'test_fs_imports/lib',
          allowFileSystemImports: true,
        );

        expect(result, equals('hello from fs'));
      });

      test('Filesystem root library can be loaded when enabled', () {
        io.Directory('test_fs_imports/app').createSync(recursive: true);
        io.File('test_fs_imports/app/helpers.dart').writeAsStringSync('''
String helperValue() {
  return "from helper";
}
''');
        io.File('test_fs_imports/app/main.dart').writeAsStringSync('''
import './helpers.dart';

String main() {
  return helperValue();
}
''');

        final d4rt = D4rt();
        d4rt.grant(FilesystemPermission.readPath('test_fs_imports/app'));

        final result = d4rt.execute(
          library:
              io.File('test_fs_imports/app/main.dart').absolute.uri.toString(),
          allowFileSystemImports: true,
          basePath: 'test_fs_imports/app',
        );

        expect(result, equals('from helper'));
      });

      test('Filesystem imports fail without matching filesystem permission',
          () {
        io.Directory('test_fs_imports/lib').createSync(recursive: true);
        io.File('test_fs_imports/lib/utils.dart').writeAsStringSync('''
String greetFromUtils() {
  return "hello from fs";
}
''');

        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            source: '''
import './utils.dart';

String main() {
  return greetFromUtils();
}
''',
            basePath: 'test_fs_imports/lib',
            allowFileSystemImports: true,
          ),
          throwsA(
            isA<RuntimeError>().having(
              (e) => e.message,
              'message',
              contains('requires FilesystemPermission'),
            ),
          ),
        );
      });

      test('Filesystem imports resolve nested relatives without shared state',
          () {
        final rootDirectory = io.Directory('test_fs_imports/nested');
        final featuresDirectory = io.Directory(io.Platform.pathSeparator == '/'
            ? '${rootDirectory.path}/features/messages'
            : '${rootDirectory.path}\\features\\messages');
        featuresDirectory.createSync(recursive: true);

        io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/main.dart'
              : '${rootDirectory.path}\\main.dart',
        ).writeAsStringSync('''
import 'features/feature.dart';

      String entryMessage() => loadMessage();
''');

        io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/features/feature.dart'
              : '${rootDirectory.path}\\features\\feature.dart',
        ).writeAsStringSync('''
import 'messages/value.dart';

String loadMessage() => featureValue();
''');

        io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/features/messages/value.dart'
              : '${rootDirectory.path}\\features\\messages\\value.dart',
        ).writeAsStringSync('''
String featureValue() => 'nested-ok';
''');

        final d4rt = D4rt();
        d4rt.grant(FilesystemPermission.readPath(rootDirectory.absolute.path));

        final result = d4rt.execute(
          source: '''
import 'main.dart';

String main() => entryMessage();
''',
          basePath: rootDirectory.absolute.path,
          allowFileSystemImports: true,
        );

        expect(result, equals('nested-ok'));
      });

      test('Filesystem imports reuse one module identity across URI forms', () {
        final rootDirectory = io.Directory('test_fs_imports/canonical');
        final helperFile = io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/helper.dart'
              : '${rootDirectory.path}\\helper.dart',
        );
        rootDirectory.createSync(recursive: true);

        helperFile.writeAsStringSync('''
String helperMessage() => 'canonical-ok';
''');

        io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/main.dart'
              : '${rootDirectory.path}\\main.dart',
        ).writeAsStringSync('''
import './helper.dart';
import '${helperFile.absolute.uri}';

String main() => helperMessage();
''');

        final d4rt = D4rt();
        d4rt.grant(FilesystemPermission.readPath(rootDirectory.absolute.path));

        final result = d4rt.execute(
          library: 'main.dart',
          basePath: rootDirectory.absolute.path,
          allowFileSystemImports: true,
        );

        expect(result, equals('canonical-ok'));
      });

      test('Filesystem imports reuse one module identity across symlinks', () {
        if (io.Platform.isWindows) {
          return;
        }

        final rootDirectory = io.Directory('test_fs_imports/symlink_canonical');
        rootDirectory.createSync(recursive: true);

        final realHelperFile = io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/real_helper.dart'
              : '${rootDirectory.path}\\real_helper.dart',
        );
        final linkedHelperPath = io.Platform.pathSeparator == '/'
            ? '${rootDirectory.path}/linked_helper.dart'
            : '${rootDirectory.path}\\linked_helper.dart';

        realHelperFile.writeAsStringSync('''
String symlinkedMessage() => 'symlink-ok';
''');
        io.Link(linkedHelperPath).createSync(realHelperFile.absolute.path);

        io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/main.dart'
              : '${rootDirectory.path}\\main.dart',
        ).writeAsStringSync('''
import './real_helper.dart';
import './linked_helper.dart';

String main() => symlinkedMessage();
''');

        final d4rt = D4rt();
        d4rt.grant(FilesystemPermission.readPath(rootDirectory.absolute.path));

        final result = d4rt.execute(
          library: 'main.dart',
          basePath: rootDirectory.absolute.path,
          allowFileSystemImports: true,
        );

        expect(result, equals('symlink-ok'));
      });

      test('Missing filesystem imports fail with a resolved path in the error',
          () {
        final rootDirectory = io.Directory('test_fs_imports/missing_fs');
        rootDirectory.createSync(recursive: true);

        final d4rt = D4rt();
        d4rt.grant(FilesystemPermission.readPath(rootDirectory.absolute.path));

        expect(
          () => d4rt.execute(
            source: '''
import './missing.dart';

String main() => 'never';
''',
            basePath: rootDirectory.absolute.path,
            allowFileSystemImports: true,
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('Failed to load import "./missing.dart"'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('Module source not found on filesystem'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('missing.dart'),
                ),
          ),
        );
      });

      test('Missing package imports fail with a package-specific error', () {
        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            source: '''
import 'package:missing_pkg/feature.dart';

String main() => 'never';
''',
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains(
                      'Failed to load import "package:missing_pkg/feature.dart"'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('Package module source not preloaded'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('package:missing_pkg/feature.dart'),
                ),
          ),
        );
      });

      test('Relative filesystem imports require a basePath', () {
        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            source: '''
import './utils.dart';

String main() => 'never';
''',
            allowFileSystemImports: true,
          ),
          throwsA(
            isA<RuntimeError>().having(
              (e) => e.message,
              'message',
              contains('Base URI not defined'),
            ),
          ),
        );
      });

      test(
          'Root filesystem libraries fail clearly when filesystem imports are disabled',
          () {
        final rootDirectory = io.Directory('test_fs_imports/disabled_root');
        rootDirectory.createSync(recursive: true);
        io.File(
          io.Platform.pathSeparator == '/'
              ? '${rootDirectory.path}/main.dart'
              : '${rootDirectory.path}\\main.dart',
        ).writeAsStringSync('''
String main() => 'disabled';
''');

        final d4rt = D4rt();

        expect(
          () => d4rt.execute(
            library: 'main.dart',
            basePath: rootDirectory.absolute.path,
          ),
          throwsA(
            isA<SourceCodeException>()
                .having(
                  (e) => e.message,
                  'message',
                  contains('was not found in sources'),
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains('enable allowFileSystemImports'),
                ),
          ),
        );
      });
    });
  });
}
