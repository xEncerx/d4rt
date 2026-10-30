import 'package:d4rt/d4rt.dart';
import '../native_permissions.dart';

// Decoration is confined to developer bridges. Preserve each bridge's metadata
// and native adapters while enforcing the same live policy on every member.
BridgedClass guardDeveloperBridge(BridgedClass bridge) {
  bridge.constructors = bridge.constructors.map(
    (name, call) => MapEntry(name, (visitor, args, named) {
      requireDeveloperPermission(visitor);
      return call(visitor, args, named);
    }),
  );
  bridge.staticMethods = bridge.staticMethods.map(
    (name, call) => MapEntry(name, (visitor, args, named) {
      requireDeveloperPermission(visitor);
      return call(visitor, args, named);
    }),
  );
  bridge.methods = bridge.methods.map(
    (name, call) => MapEntry(name, (visitor, target, args, named) {
      requireDeveloperPermission(visitor);
      return call(visitor, target, args, named);
    }),
  );
  bridge.staticGetters = bridge.staticGetters.map(
    (name, call) => MapEntry(name, (visitor) {
      requireDeveloperPermission(visitor);
      return call(visitor);
    }),
  );
  bridge.staticSetters = bridge.staticSetters.map(
    (name, call) => MapEntry(name, (visitor, value) {
      requireDeveloperPermission(visitor);
      call(visitor, value);
    }),
  );
  bridge.getters = bridge.getters.map(
    (name, call) => MapEntry(name, (visitor, target) {
      requireDeveloperPermission(visitor);
      return call(visitor, target);
    }),
  );
  bridge.setters = bridge.setters.map(
    (name, call) => MapEntry(name, (visitor, target, value) {
      requireDeveloperPermission(visitor);
      call(visitor, target, value);
    }),
  );
  return bridge;
}
