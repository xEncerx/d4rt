import 'package:d4rt/d4rt.dart';

class NullCore {
  static BridgedClass get definition => BridgedClass(
        nativeType: Null,
        name: 'Null',
        typeParameterCount: 0,
        methods: {
          'toString': (_, _, _, _) => null.toString(),
        },
        getters: {
          'hashCode': (_, _) => null.hashCode,
        },
      );
}
