import 'package:d4rt/d4rt.dart';

/// Dart's enum type, explicit name extension and enum iterable operations.
class EnumCore {
  /// Registers the enum type and the explicit EnumName extension application.
  static void register(Environment environment) {
    environment.defineBridge(BridgedClass(
      nativeType: Enum,
      name: 'Enum',
      getters: {'index': (visitor, target) => indexOf(target)},
      methods: {
        'toString': (visitor, target, args, named) => target.toString(),
      },
      staticMethods: {
        'compareByIndex': (visitor, args, named) =>
            indexOf(args[0]).compareTo(indexOf(args[1])),
        'compareByName': (visitor, args, named) =>
            nameOf(args[0]).compareTo(nameOf(args[1])),
      },
    ));
    environment.defineBridge(BridgedClass(
      nativeType: _EnumNameAccess,
      name: 'EnumName',
      constructors: {
        '': (visitor, args, named) => _EnumNameAccess(nameOf(args.single))
      },
      getters: {'name': (visitor, target) => (target as _EnumNameAccess).name},
    ));
  }

  /// The underlying constant name, never a user instance member override.
  static String nameOf(Object? value) {
    if (value is InterpretedEnumValue) return value.name;
    if (value is BridgedEnumValue) return value.name;
    if (value is Enum) return value.name;
    throw RuntimeError('Expected an enum value.');
  }

  /// The declaration index shared by interpreted and native enum constants.
  static int indexOf(Object? value) {
    if (value is InterpretedEnumValue) return value.index;
    if (value is BridgedEnumValue) return value.index;
    if (value is Enum) return value.index;
    throw RuntimeError('Expected an enum value.');
  }

  /// Implements EnumByName.byName against underlying constant names.
  static Object? byName(InterpreterVisitor visitor, Object target,
      List<Object?> arguments, Map<String, Object?> named) {
    final name = arguments.single as String;
    for (final value in target as Iterable) {
      if (nameOf(value) == name) return value;
    }
    throw ArgumentError.value(name, 'name', 'No enum value with that name');
  }

  /// Implements EnumByName.asNameMap with a mutable, last-entry-wins map.
  static Object? asNameMap(InterpreterVisitor visitor, Object target,
          List<Object?> arguments, Map<String, Object?> named) =>
      <String, Object?>{
        for (final value in target as Iterable) nameOf(value): value
      };
}

class _EnumNameAccess {
  final String name;
  _EnumNameAccess(this.name);
}
