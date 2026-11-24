import 'dart:async';
import 'package:d4rt/d4rt.dart';

Object? _invokeErrorCallback(
  InterpretedFunction callback,
  Object error,
  StackTrace stack,
) {
  final signature = callback.callableRuntimeType;
  final takesStack =
      signature is FunctionRuntimeType &&
      signature.positionalParameterTypes.length > 1;
  return InterpreterVisitor.invokeCallback(
    callback,
    takesStack ? [error, stack] : [error],
  );
}

class FutureAsync {
  static BridgedClass get definition => BridgedClass(
    nativeType: Future,
    name: 'Future',
    typeParameterCount: 1, // Future<T>
    isSubtypeOfFunc: (value) => value is Future,
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        if (positionalArgs.length == 1 &&
            positionalArgs[0] is InterpretedFunction) {
          final computation = positionalArgs[0] as InterpretedFunction;
          return Future(
            () => InterpreterVisitor.invokeCallback(computation, []),
          );
        }
        throw RuntimeError('Invalid arguments for Future constructor.');
      },
    },
    staticMethods: {
      'delayed': (visitor, positionalArgs, namedArgs) {
        final duration = positionalArgs[0] as Duration;
        final computation = positionalArgs.get<InterpretedFunction?>(1);
        return Future.delayed(
          duration,
          computation == null
              ? null
              : () => InterpreterVisitor.invokeCallback(computation, []),
        );
      },
      'value': (visitor, positionalArgs, namedArgs) {
        return Future.value(positionalArgs.get<dynamic>(0));
      },
      'error': (visitor, positionalArgs, namedArgs) {
        final error = positionalArgs[0];
        if (error == null) {
          throw RuntimeError('Future.error requires a non-null error object.');
        }
        final stackTrace = positionalArgs.get<StackTrace?>(1);
        return Future.error(error, stackTrace);
      },
      'microtask': (visitor, positionalArgs, namedArgs) {
        final computation = positionalArgs[0];
        if (computation is! InterpretedFunction) {
          throw RuntimeError('Future.microtask requires an Function.');
        }
        return Future.microtask(
          () => InterpreterVisitor.invokeCallback(computation, []),
        );
      },
      'sync': (visitor, positionalArgs, namedArgs) {
        final computation = positionalArgs[0];
        if (computation is! InterpretedFunction) {
          throw RuntimeError('Future.sync requires an Function.');
        }
        return Future.sync(
          () => InterpreterVisitor.invokeCallback(computation, []),
        );
      },
      'wait': (visitor, positionalArgs, namedArgs) {
        final futures = positionalArgs[0];
        if (futures is! Iterable) {
          throw RuntimeError('Future.wait requires an Iterable.');
        }
        final eagerError = namedArgs.get<bool?>('eagerError') ?? false;
        final cleanUp = namedArgs.get<InterpretedFunction?>('cleanUp');
        final normalizedFutures = futures.map(
          (e) => e is Future ? e : Future.value(e),
        );
        return Future.wait(
          normalizedFutures,
          eagerError: eagerError,
          cleanUp: cleanUp == null
              ? null
              : (successValue) =>
                    InterpreterVisitor.invokeCallback(cleanUp, [successValue]),
        );
      },
      'any': (visitor, positionalArgs, namedArgs) {
        final futures = positionalArgs[0];
        if (futures is! Iterable) {
          throw RuntimeError('Future.any requires an Iterable.');
        }
        final normalizedFutures = futures.map(
          (e) => e is Future ? e : Future.value(e),
        );
        return Future.any(normalizedFutures);
      },
      'forEach': (visitor, positionalArgs, namedArgs) {
        final elements = positionalArgs[0] as Iterable;
        final action = positionalArgs[1];
        if (action is! InterpretedFunction) {
          throw RuntimeError('Future.forEach requires an Function for action.');
        }
        return Future.forEach(
          elements,
          (element) =>
              InterpreterVisitor.invokeCallback(action, [element])
                  as FutureOr<void>,
        );
      },
      'doWhile': (visitor, positionalArgs, namedArgs) {
        final action = positionalArgs[0];
        if (action is! InterpretedFunction) {
          throw RuntimeError('Future.doWhile requires an Function for action.');
        }
        // Handle both sync and async functions properly
        return Future.doWhile(() {
          final result = InterpreterVisitor.invokeCallback(action, []);
          if (result is Future) {
            // Async function returns Future - ensure it resolves to bool
            return result.then((value) => value as bool);
          } else {
            // Sync function returns bool directly
            return result as bool;
          }
        });
      },
    },
    methods: {
      'then': (visitor, target, positionalArgs, namedArgs) {
        final onValue = positionalArgs[0];
        final onError = namedArgs.get<InterpretedFunction?>('onError');
        if (onValue is! InterpretedFunction) {
          throw RuntimeError('Future.then requires an Function for onValue.');
        }
        return (target as Future).then(
          (value) => InterpreterVisitor.invokeCallback(onValue, [value]),
          onError: onError == null
              ? null
              : (error, stackTrace) =>
                    _invokeErrorCallback(onError, error, stackTrace),
        );
      },
      'catchError': (visitor, target, positionalArgs, namedArgs) {
        final onError = positionalArgs[0];
        final test = namedArgs.get<InterpretedFunction?>('test');
        if (onError is! InterpretedFunction) {
          throw RuntimeError(
            'Future.catchError requires an Function for onError.',
          );
        }
        return (target as Future).catchError(
          (error, stackTrace) =>
              _invokeErrorCallback(onError, error, stackTrace),
          test: test == null
              ? null
              : (error) =>
                    InterpreterVisitor.invokeCallback(test, [error]) as bool,
        );
      },
      'whenComplete': (visitor, target, positionalArgs, namedArgs) {
        final action = positionalArgs[0];
        if (action is! InterpretedFunction) {
          throw RuntimeError(
            'Future.whenComplete requires an Function for action.',
          );
        }
        return (target as Future).whenComplete(
          () => InterpreterVisitor.invokeCallback(action, []),
        );
      },
      'timeout': (visitor, target, positionalArgs, namedArgs) {
        final timeLimit = positionalArgs[0] as Duration;
        final onTimeout = namedArgs.get<InterpretedFunction?>('onTimeout');
        return (target as Future).timeout(
          timeLimit,
          onTimeout: onTimeout == null
              ? null
              : () => InterpreterVisitor.invokeCallback(onTimeout, []),
        );
      },
      'asStream': (visitor, target, positionalArgs, namedArgs) {
        return (target as Future).asStream();
      },
      // FutureExtensions methods
      'onError': (visitor, target, positionalArgs, namedArgs) {
        final handleError = positionalArgs[0];
        final test = namedArgs.get<InterpretedFunction?>('test');
        if (handleError is! InterpretedFunction) {
          throw RuntimeError(
            'Future.onError requires a Function for handleError.',
          );
        }
        return (target as Future).catchError(
          (error, stackTrace) =>
              _invokeErrorCallback(handleError, error, stackTrace),
          test: test == null
              ? null
              : (error) =>
                    InterpreterVisitor.invokeCallback(test, [error]) as bool,
        );
      },
      'ignore': (visitor, target, positionalArgs, namedArgs) {
        final future = target as Future;
        future.then<void>(
          (value) => null,
          onError: (error, stackTrace) => null,
        );
        return null;
      },
    },
    getters: {
      'hashCode': (visitor, target) => (target as Future).hashCode,
      'runtimeType': (visitor, target) => (target as Future).runtimeType,
    },
  );
}

/// Explicitly ignores a future.
class UnawaitedAsync {
  static BridgedClass get definition => BridgedClass(
    nativeType: Function,
    name: 'unawaited',
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        unawaited((positionalArgs[0] as Future));
        return null;
      },
    },
  );
}

/// Thrown when a scheduled timeout happens while waiting for an async result.
class TimeoutExceptionAsync {
  static BridgedClass get definition => BridgedClass(
    nativeType: TimeoutException,
    name: 'TimeoutException',
    isSubtypeOfFunc: (value) => value is TimeoutException,
    constructors: {
      '': (visitor, positionalArgs, namedArgs) {
        final message = positionalArgs.get<String?>(0);
        final duration = positionalArgs.get<Duration?>(1);
        return TimeoutException(message, duration);
      },
    },
    getters: {
      'message': (visitor, target) => (target as TimeoutException).message,
      'duration': (visitor, target) => (target as TimeoutException).duration,
      'toString': (visitor, target) => (target as TimeoutException).toString(),
      'hashCode': (visitor, target) => (target as TimeoutException).hashCode,
      'runtimeType': (visitor, target) =>
          (target as TimeoutException).runtimeType,
    },
    methods: {
      'toString': (visitor, target, positionalArgs, namedArgs) {
        return (target as TimeoutException).toString();
      },
    },
  );
}

class FutureStdlib {
  static void register(Environment environment) {
    environment.defineBridge(FutureAsync.definition);
    environment.defineBridge(TimeoutExceptionAsync.definition);
    environment.defineBridge(UnawaitedAsync.definition);
  }
}
