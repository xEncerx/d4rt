import 'package:d4rt/src/exceptions.dart';

/// Monotonic, invocation-owned terminal deadline shared by all module visitors.
final class InvocationDeadline {
  /// Starts a monotonic deadline for one public execution invocation.
  InvocationDeadline(this.timeout) : _clock = Stopwatch()..start();

  /// The maximum duration for the owning invocation.
  final Duration timeout;
  final Stopwatch _clock;
  bool _timedOut = false;

  /// Time left before this invocation expires.
  Duration get remaining => Duration(
      microseconds: timeout.inMicroseconds - _clock.elapsedMicroseconds);

  /// Whether elapsed time or an explicit timeout has terminated the invocation.
  bool get expired {
    if (!_timedOut && _clock.elapsedMicroseconds >= timeout.inMicroseconds) {
      _timedOut = true;
    }
    return _timedOut;
  }

  /// Creates the public timeout error for this invocation.
  ExecutionTimeoutException get exception => ExecutionTimeoutException(
        'Execution timed out after ${timeout.inMilliseconds}ms.',
        timeout: timeout,
      );

  /// Marks this invocation as terminal after its timer fires.
  void expire() => _timedOut = true;
}
