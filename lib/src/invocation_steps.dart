import 'package:d4rt/src/exceptions.dart';

/// Step accounting shared by every visitor participating in one invocation.
class InvocationSteps {
  final int? maxSteps;
  int _count = 0;

  InvocationSteps(this.maxSteps);

  int get count => _count;

  /// Preserve the visitor's charging policy: count only configured invocations.
  void charge({required bool hasDeadline}) {
    if (maxSteps == null && !hasDeadline) return;
    _count++;
    if (maxSteps != null && _count > maxSteps!) {
      throw ExecutionLimitException(
        'Execution step limit of $maxSteps steps exceeded.',
        maxSteps: maxSteps,
      );
    }
  }
}
