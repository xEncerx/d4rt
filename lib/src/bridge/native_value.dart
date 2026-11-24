import 'bridged_enum.dart';
import 'bridged_types.dart';

/// Extracts the original native object from a bridge value.
Object? nativeBridgeValue(Object? value) => switch (value) {
  BridgedInstance instance => instance.nativeObject,
  BridgedEnumValue value => value.nativeValue,
  _ => value,
};
