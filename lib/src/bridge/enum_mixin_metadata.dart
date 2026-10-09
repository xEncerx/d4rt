import 'package:d4rt/src/bridge/enum_type_metadata.dart';

/// Declaration constraints required when a native mixin is applied to an enum.
class EnumMixinMetadata {
  /// Generic mixin parameters, bounds and implemented types.
  final EnumTypeMetadata typeMetadata;

  /// Generic superclass constraints from the mixin's `on` clause.
  final List<String> constraints;

  /// Whether the native mixin declares any instance fields.
  final bool hasInstanceFields;

  /// Abstract requirements keyed by member name, with method/getter/setter kind.
  final Map<String, String> abstractMembers;

  /// Creates metadata for a bridged mixin's enum application constraints.
  EnumMixinMetadata(
      {required this.typeMetadata,
      List<String> constraints = const [],
      this.hasInstanceFields = false,
      Map<String, String> abstractMembers = const {}})
      : constraints = List.unmodifiable(constraints),
        abstractMembers = Map.unmodifiable(abstractMembers);
}
