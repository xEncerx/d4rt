import 'dart:async';

import 'package:d4rt/d4rt.dart';
import 'package:test/test.dart';

const _sources = <String, String>{
  'package:probe/sdk.dart': '''
abstract class ProviderBase {
  Future<int> immediateValue();
  Future<int> delayedValue(int value);
  Future<int> failImmediately();
  Future<int> failAfterAwait();
}

class ExpectedFailure implements Exception {
  final String marker;
  bool caught = false;

  ExpectedFailure(this.marker);
}

final class ExpectedChildFailure extends ExpectedFailure {
  ExpectedChildFailure(String marker) : super(marker);
}

final class DifferentFailure implements Exception {}
final class UnrelatedFailure implements Exception {}

class BaseFailure implements Exception {}

final class PrefixedFailure extends BaseFailure {}

Future<int> delayedSdkValue(int value) async {
  await Future.delayed(Duration(milliseconds: 1));
  return value;
}

Future<int> delayedSdkFailure(ExpectedFailure error) async {
  await Future.delayed(Duration(milliseconds: 1));
  throw error;
}
''',
  'package:probe/decoy.dart': '''
class BaseFailure implements Exception {}
''',
  'package:probe/author.dart': '''
import 'package:probe/sdk.dart';

int providerCalls = 0;
int synchronousPrefixCalls = 0;
int combinedCalls = 0;
int nestedCatchCount = 0;
int nestedFinallyCount = 0;
int outerFinallyCount = 0;
int innerFinallyCount = 0;
int overridingFinallyCount = 0;
int awaitedCleanupStartCount = 0;
int awaitedCleanupEndCount = 0;
int switchSelectorCalls = 0;
List<String> structuralEvents = [];
List<String> generatorEvents = [];
int canonicalAllocations = 0;
int canonicalObservations = 0;
List<String> evaluationOrder = [];
List<String> assignmentEvents = [];
ExpectedFailure? lastFailure;
CanonicalValue? firstCanonicalValue;
final AssignmentBox assignmentBox = AssignmentBox();

Object? readLastFailure() => lastFailure;
int readProviderCalls() => providerCalls;
int readSynchronousPrefixCalls() => synchronousPrefixCalls;
int readCombinedCalls() => combinedCalls;
int readNestedCatchCount() => nestedCatchCount;
int readNestedFinallyCount() => nestedFinallyCount;
int readOuterFinallyCount() => outerFinallyCount;
int readInnerFinallyCount() => innerFinallyCount;
int readOverridingFinallyCount() => overridingFinallyCount;
int readAwaitedCleanupStartCount() => awaitedCleanupStartCount;
int readAwaitedCleanupEndCount() => awaitedCleanupEndCount;
int readSwitchSelectorCalls() => switchSelectorCalls;
List<String> readStructuralEvents() => structuralEvents;
List<String> readGeneratorEvents() => generatorEvents;
int readCanonicalAllocations() => canonicalAllocations;
int readCanonicalObservations() => canonicalObservations;
List<String> readEvaluationOrder() => evaluationOrder;
List<String> readAssignmentEvents() => assignmentEvents;
int readAssignmentValue() => assignmentBox.valueWithoutEvent;
int readAssignmentSlot(int index) => assignmentBox.slotWithoutEvent(index);

final class CanonicalValue {}

CanonicalValue allocateCanonicalValue() {
  canonicalAllocations++;
  final value = CanonicalValue();
  firstCanonicalValue ??= value;
  return value;
}

void observeCanonicalValue(CanonicalValue value) {
  canonicalObservations++;
}

bool isFirstCanonicalValue(CanonicalValue value) =>
    firstCanonicalValue == value;

String markSwitchSelector(String value) {
  switchSelectorCalls++;
  return value;
}

String markStructuralString(String marker, String value) {
  structuralEvents.add(marker);
  return value;
}

int markStructuralInt(String marker, int value) {
  structuralEvents.add(marker);
  return value;
}

bool markStructuralBool(String marker, bool value) {
  structuralEvents.add(marker);
  return value;
}

List<int> markStructuralIterable(String marker, List<int> value) {
  structuralEvents.add(marker);
  return value;
}

Future<String> delayedStructuralString(String marker, String value) async {
  structuralEvents.add(marker + ':start');
  await delayedSdkValue(0);
  structuralEvents.add(marker + ':end');
  return value;
}

Future<int> delayedStructuralInt(String marker, int value) async {
  structuralEvents.add(marker + ':start');
  await delayedSdkValue(0);
  structuralEvents.add(marker + ':end');
  return value;
}

Future<bool> delayedStructuralBool(String marker, bool value) async {
  structuralEvents.add(marker + ':start');
  await delayedSdkValue(0);
  structuralEvents.add(marker + ':end');
  return value;
}

void markGeneratorEvent(String marker) {
  generatorEvents.add(marker);
}

final class AssignmentBox {
  int _value = 10;
  final List<int> _slots = [20, 30];

  int get value {
    assignmentEvents.add('property:get');
    return _value;
  }

  set value(int value) {
    assignmentEvents.add('property:set:' + value.toString());
    _value = value;
  }

  int operator [](int index) {
    assignmentEvents.add('index:get:' + index.toString());
    return _slots[index];
  }

  void operator []=(int index, int value) {
    assignmentEvents.add(
      'index:set:' + index.toString() + ':' + value.toString(),
    );
    _slots[index] = value;
  }

  int get valueWithoutEvent => _value;
  int slotWithoutEvent(int index) => _slots[index];
}

Future<AssignmentBox> loadAssignmentBox(String marker) async {
  assignmentEvents.add(marker + ':start');
  await delayedSdkValue(0);
  assignmentEvents.add(marker + ':end');
  return assignmentBox;
}

Future<int> loadAssignmentIndex(String marker, int index) async {
  assignmentEvents.add(marker + ':start');
  await delayedSdkValue(0);
  assignmentEvents.add(marker + ':end');
  return index;
}

Future<int> loadAssignmentValue(String marker, int value) async {
  assignmentEvents.add(marker + ':start');
  await delayedSdkValue(0);
  assignmentEvents.add(marker + ':end');
  return value;
}

int markSynchronousPrefix(int value) {
  synchronousPrefixCalls++;
  evaluationOrder.add('sync:' + value.toString());
  return value;
}

List<int> combineValues(int first, int second, int third) {
  combinedCalls++;
  evaluationOrder.add('combine');
  return [first, second, third];
}

final class Provider extends ProviderBase {
  Future<int> immediateValue() async {
    providerCalls++;
    return 7;
  }

  Future<int> delayedValue(int value) async {
    providerCalls++;
    evaluationOrder.add('async-start:' + value.toString());
    final result = await delayedSdkValue(value);
    evaluationOrder.add('async-end:' + value.toString());
    return result;
  }

  Future<int> failImmediately() async {
    providerCalls++;
    final error = ExpectedFailure('immediate');
    lastFailure = error;
    throw error;
  }

  Future<int> failAfterAwait() async {
    providerCalls++;
    final error = ExpectedChildFailure('delayed');
    lastFailure = error;
    return await delayedSdkFailure(error);
  }

  Future<int> failDifferently() async {
    providerCalls++;
    throw UnrelatedFailure();
  }

  Future<int> nestedValue() async {
    providerCalls++;
    try {
      final value = await delayedSdkValue(10);
      return value + 1;
    } finally {
      nestedFinallyCount++;
    }
  }

  Future<int> nestedFailure() async {
    providerCalls++;
    final error = ExpectedFailure('nested');
    lastFailure = error;
    try {
      return await delayedSdkFailure(error);
    } on ExpectedFailure {
      nestedCatchCount++;
      rethrow;
    } finally {
      nestedFinallyCount++;
    }
  }

  Future<int> returnOverriddenByFailure() async {
    providerCalls++;
    try {
      try {
        return 99;
      } finally {
        nestedFinallyCount++;
        final error = ExpectedFailure('finally');
        lastFailure = error;
        await delayedSdkFailure(error);
      }
    } finally {
      nestedFinallyCount++;
    }
  }

  Future<int> returnThroughOuterFinalizers(bool suspend) async {
    try {
      try {
        try {
          if (suspend) {
            return await delayedSdkValue(82);
          }
          return 81;
        } catch (_) {
          return -1;
        }
      } finally {
        innerFinallyCount++;
      }
    } finally {
      outerFinallyCount++;
    }
  }

  Future<int> finallyReturnOverridesReturn() async {
    try {
      return 91;
    } finally {
      overridingFinallyCount++;
      return 92;
    }
  }

  Future<int> finallyReturnOverridesAsyncError() async {
    try {
      final error = ExpectedFailure('overridden-error');
      lastFailure = error;
      await delayedSdkFailure(error);
      return -1;
    } finally {
      overridingFinallyCount++;
      return 93;
    }
  }

  Future<void> failWithAwaitedCleanup() async {
    final error = ExpectedFailure('awaited-cleanup');
    lastFailure = error;
    try {
      await delayedSdkFailure(error);
    } finally {
      awaitedCleanupStartCount++;
      await delayedSdkValue(0);
      awaitedCleanupEndCount++;
    }
  }

  Future<void> failWithPrefixedBaseType() async {
    throw PrefixedFailure();
  }
}
''',
  'package:probe/dispatcher.dart': '''
import 'package:probe/author.dart' as author;
import 'package:probe/decoy.dart' as decoy;
import 'package:probe/sdk.dart';
import 'package:probe/sdk.dart' as sdk;

int unhandledFinallyCount = 0;

Future<int> returnAwaited(int value) async =>
    await author.Provider().delayedValue(value);

Future<Object?> dispatch(String operation, int input) async {
  final provider = author.Provider();
  Object? outcome;
  int finallyCount = 0;

  try {
    switch (operation) {
      case 'immediate':
        final value = await provider.immediateValue();
        outcome = {'kind': 'value', 'value': value};
        break;
      case 'delayed':
        final value = await provider.delayedValue(input);
        outcome = {'kind': 'value', 'value': value};
        break;
      case 'initializer':
        final initialized = await provider.delayedValue(12);
        outcome = {'kind': 'initializer', 'value': initialized + 1};
        break;
      case 'return':
        outcome = {'kind': 'return', 'value': await returnAwaited(14)};
        break;
      case 'branch':
        if (await provider.delayedValue(1) == 1) {
          outcome = {'kind': 'branch', 'value': 'then'};
        } else {
          outcome = {'kind': 'branch', 'value': 'else'};
        }
        break;
      case 'collection':
        outcome = {'kind': 'collection', 'values': [
          await provider.delayedValue(16),
        ]};
        break;
      case 'failImmediately':
        await provider.failImmediately();
        outcome = {'kind': 'unexpected-success'};
        break;
      case 'failAfterAwait':
        await provider.failAfterAwait();
        outcome = {'kind': 'unexpected-success'};
        break;
      case 'generic':
        await provider.failDifferently();
        outcome = {'kind': 'unexpected-success'};
        break;
      case 'nestedValue':
        outcome = {'kind': 'nested', 'value': await provider.nestedValue()};
        break;
      case 'nestedFailure':
        await provider.nestedFailure();
        outcome = {'kind': 'unexpected-success'};
        break;
      case 'nestedTryMismatch':
        try {
          await provider.failAfterAwait();
        } on DifferentFailure {
          outcome = {'kind': 'wrong-inner-catch'};
        }
        outcome = {'kind': 'unexpected-success'};
        break;
      case 'nestedInnerCatch':
        try {
          await provider.failAfterAwait();
          outcome = {'kind': 'unexpected-success'};
        } on ExpectedFailure catch (error) {
          error.caught = true;
          outcome = {
            'kind': 'inner-catch',
            'marker': error.marker,
            'sameInstanceObserved': author.readLastFailure() == error,
          };
        }
        break;
      case 'returnOverriddenByFailure':
        await provider.returnOverriddenByFailure();
        outcome = {'kind': 'unexpected-success'};
        break;
      default:
        outcome = {'kind': 'unknown'};
    }
  } on DifferentFailure {
    outcome = {'kind': 'wrong-typed-catch'};
  } on ExpectedFailure catch (error) {
    error.caught = true;
    outcome = {
      'kind': 'expected-catch',
      'marker': error.marker,
      'sameInstanceObserved': author.readLastFailure() == error,
    };
  } catch (_) {
    outcome = {'kind': 'generic-catch'};
  } finally {
    finallyCount++;
  }

  return {
    'outcome': outcome,
    'finallyCount': finallyCount,
    'providerCalls': author.readProviderCalls(),
    'nestedCatchCount': author.readNestedCatchCount(),
    'nestedFinallyCount': author.readNestedFinallyCount(),
  };
}

Future<void> dispatchUnhandled() async {
  try {
    await author.Provider().failAfterAwait();
  } finally {
    unhandledFinallyCount++;
  }
}

int readUnhandledFinallyCount() => unhandledFinallyCount;
Object? readLastFailure() => author.readLastFailure();
List<String> readGeneratorEvents() => author.readGeneratorEvents();

Future<Object?> evaluateCompound(String context) async {
  final provider = author.Provider();
  Object? value;

  if (context == 'invocation') {
    value = author.combineValues(
      author.markSynchronousPrefix(1),
      await provider.delayedValue(2),
      await provider.delayedValue(3),
    );
  } else if (context == 'collection') {
    value = [
      author.markSynchronousPrefix(4),
      await provider.delayedValue(5),
      author.markSynchronousPrefix(6),
      await provider.delayedValue(7),
    ];
  } else if (context == 'map') {
    value = {
      author.markSynchronousPrefix(10): await provider.delayedValue(11),
      await provider.delayedValue(12): author.markSynchronousPrefix(13),
    };
  } else if (context == 'repeated') {
    final values = <Object?>[];
    for (var index = 0; index < 2; index++) {
      values.add([
        author.markSynchronousPrefix(index),
        await provider.delayedValue(index + 20),
      ]);
    }
    value = values;
  } else if (context == 'expression') {
    value = author.markSynchronousPrefix(30) +
        await provider.delayedValue(31) +
        await provider.delayedValue(32);
  } else if (context == 'nestedInvocation') {
    value = author.combineValues(
      author.markSynchronousPrefix(40),
      author.combineValues(
        author.markSynchronousPrefix(41),
        await provider.delayedValue(42),
        await provider.delayedValue(43),
      )[1],
      await provider.delayedValue(44),
    );
  } else if (context == 'set') {
    value = <int>{
      author.markSynchronousPrefix(50),
      await provider.delayedValue(51),
      author.markSynchronousPrefix(52),
      await provider.delayedValue(53),
    }.toList();
  } else if (context == 'record') {
    final record = (
      author.markSynchronousPrefix(60),
      await provider.delayedValue(61),
      named: await provider.delayedValue(62),
    );
    value = [record.\$1, record.\$2, record.named];
  } else if (context == 'interpolation') {
    value = 'a\${author.markSynchronousPrefix(70)}:\${await provider.delayedValue(71)}:\${author.markSynchronousPrefix(72)}:\${await provider.delayedValue(73)}z';
  }

  return {
    'value': value,
    'providerCalls': author.readProviderCalls(),
    'synchronousPrefixCalls': author.readSynchronousPrefixCalls(),
    'combinedCalls': author.readCombinedCalls(),
    'order': author.readEvaluationOrder(),
  };
}

Future<Object?> evaluateSwitchProgress() async {
  Object? outcome;
  switch (author.markSwitchSelector('target')) {
    case 'target':
      final canonical = author.allocateCanonicalValue();
      author.observeCanonicalValue(canonical);
      final awaited = await author.Provider().delayedValue(55);
      outcome = {
        'awaited': awaited,
        'sameCanonical': author.isFirstCanonicalValue(canonical),
      };
      break;
    default:
      outcome = {'unexpected': true};
  }
  return {
    'outcome': outcome,
    'selectorCalls': author.readSwitchSelectorCalls(),
    'allocations': author.readCanonicalAllocations(),
    'observations': author.readCanonicalObservations(),
  };
}

Future<Object?> evaluateSwitchCaughtErrorProgress() async {
  Object? outcome;
  switch (author.markSwitchSelector('target')) {
    case 'target':
      final canonical = author.allocateCanonicalValue();
      author.observeCanonicalValue(canonical);
      try {
        await author.Provider().failAfterAwait();
      } on ExpectedFailure {
        outcome = {
          'caught': true,
          'sameCanonical': author.isFirstCanonicalValue(canonical),
        };
      }
      break;
    default:
      outcome = {'unexpected': true};
  }
  return {
    'outcome': outcome,
    'selectorCalls': author.readSwitchSelectorCalls(),
    'allocations': author.readCanonicalAllocations(),
    'observations': author.readCanonicalObservations(),
  };
}

Future<Object?> evaluateAssignment(String context) async {
  if (context == 'property') {
    (await author.loadAssignmentBox('target')).value =
        await author.loadAssignmentValue('rhs', 21);
  } else if (context == 'index') {
    (await author.loadAssignmentBox('target'))[
        await author.loadAssignmentIndex('index', 1)] =
        await author.loadAssignmentValue('rhs', 41);
  } else if (context == 'compoundProperty') {
    (await author.loadAssignmentBox('target')).value +=
        await author.loadAssignmentValue('rhs', 5);
  } else if (context == 'compoundIndex') {
    (await author.loadAssignmentBox('target'))[
        await author.loadAssignmentIndex('index', 0)] +=
        await author.loadAssignmentValue('rhs', 7);
  } else if (context == 'nullAwareCompound') {
    (await author.loadAssignmentBox('target')).value ??=
        await author.loadAssignmentValue('rhs', 99);
  }
  return {
    'value': author.readAssignmentValue(),
    'slots': [author.readAssignmentSlot(0), author.readAssignmentSlot(1)],
    'events': author.readAssignmentEvents(),
  };
}

Future<Object?> preserveErrorThroughAwaitedFinally() async {
  try {
    await author.Provider().failWithAwaitedCleanup();
    return {'kind': 'unexpected-success'};
  } on ExpectedFailure catch (error) {
    return {
      'kind': 'caught',
      'sameError': author.readLastFailure() == error,
      'cleanupStarts': author.readAwaitedCleanupStartCount(),
      'cleanupEnds': author.readAwaitedCleanupEndCount(),
    };
  }
}

Future<String> catchPrefixedBaseType() async {
  try {
    await author.Provider().failWithPrefixedBaseType();
    return 'unexpected-success';
  } on decoy.BaseFailure {
    return 'wrong-decoy-catch';
  } on sdk.BaseFailure {
    return 'sdk-catch';
  } catch (_) {
    return 'generic-catch';
  }
}

Future<Object?> returnThroughOuterFinalizers(bool suspend) async {
  final value = await author.Provider().returnThroughOuterFinalizers(suspend);
  return {
    'value': value,
    'innerFinallyCount': author.readInnerFinallyCount(),
    'outerFinallyCount': author.readOuterFinallyCount(),
  };
}

Future<Object?> runFinallyReturnOverride(String operation) async {
  final provider = author.Provider();
  final value = operation == 'return'
      ? await provider.finallyReturnOverridesReturn()
      : await provider.finallyReturnOverridesAsyncError();
  return {
    'value': value,
    'overridingFinallyCount': author.readOverridingFinallyCount(),
  };
}

Future<Object?> evaluateSwitchExpressionSelector() async {
  final value = switch (
    await author.delayedStructuralString('selector', 'target')
  ) {
    'target' => author.markStructuralString('result', 'selected'),
    _ => 'unexpected',
  };
  return {'value': value, 'events': author.readStructuralEvents()};
}

Future<Object?> evaluateSwitchExpressionGuard() async {
  final value = switch (
    author.markStructuralString('selector', 'target')
  ) {
    'target' when await author.delayedStructuralBool('guard', true) =>
      author.markStructuralString('result', 'selected'),
    _ => 'unexpected',
  };
  return {'value': value, 'events': author.readStructuralEvents()};
}

Future<Object?> evaluateSwitchExpressionResult() async {
  final value = switch (
    author.markStructuralString('selector', 'target')
  ) {
    'target' => author.markStructuralString('result-prefix', 'selected') +
        await author.delayedStructuralString('result-await', '!'),
    _ => 'unexpected',
  };
  return {'value': value, 'events': author.readStructuralEvents()};
}

Future<Object?> evaluateCollectionIf() async {
  final values = [
    if (author.markStructuralBool('if:condition', true))
      author.markStructuralString('if:branch-prefix', 'a') +
          await author.delayedStructuralString('if:branch-await', 'b')
    else
      author.markStructuralString('if:unexpected', 'x'),
  ];
  return {'values': values, 'events': author.readStructuralEvents()};
}

Future<Object?> evaluateCollectionFor() async {
  final values = [
    for (final item in author.markStructuralIterable('for:iterable', [1, 2, 3]))
      author.markStructuralInt('for:prefix:' + item.toString(), item * 10) +
          await author.delayedStructuralInt(
            'for:await:' + item.toString(),
            item,
          ),
  ];
  return {'values': values, 'events': author.readStructuralEvents()};
}

Stream<int> cancellableGenerator() async* {
  try {
    author.markGeneratorEvent('start');
    yield 1;
    author.markGeneratorEvent('before-await');
    await Future.delayed(Duration(milliseconds: 80));
    author.markGeneratorEvent('after-await');
    yield 2;
  } finally {
    author.markGeneratorEvent('finally-start');
    await Future.delayed(Duration(milliseconds: 1));
    author.markGeneratorEvent('finally-end');
  }
}

Stream<int> cancellableInnerGenerator() async* {
  try {
    author.markGeneratorEvent('inner:start');
    yield 1;
    author.markGeneratorEvent('inner:before-await');
    await Future.delayed(Duration(milliseconds: 80));
    author.markGeneratorEvent('inner:after-await');
    yield 2;
  } finally {
    author.markGeneratorEvent('inner:finally');
  }
}

Stream<int> cancellableDelegatingGenerator() async* {
  try {
    author.markGeneratorEvent('outer:start');
    yield* cancellableInnerGenerator();
    author.markGeneratorEvent('outer:after-yield-star');
    yield 3;
  } finally {
    author.markGeneratorEvent('outer:finally-start');
    await Future.delayed(Duration(milliseconds: 1));
    author.markGeneratorEvent('outer:finally-end');
  }
}

Stream<int> yieldImportedValue() async* {
  yield await author.Provider().delayedValue(44);
}

Stream<int> yieldImportedError() async* {
  yield await author.Provider().failAfterAwait();
}
''',
};

Future<Object?> _run(
  String operation, {
  D4rt? d4rt,
  int input = 9,
}) async {
  final interpreter = d4rt ?? D4rt();
  final result = interpreter.execute(
    library: 'package:probe/dispatcher.dart',
    sources: _sources,
    name: 'dispatch',
    positionalArgs: [operation, input],
    allowFileSystemImports: false,
  );

  expect(result, isA<Future<Object?>>());
  return (result as Future<Object?>).timeout(const Duration(seconds: 2));
}

Future<Object?> _runNamed(
  String name, {
  List<Object?> positionalArgs = const [],
  D4rt? d4rt,
}) async {
  final interpreter = d4rt ?? D4rt();
  final result = interpreter.execute(
    library: 'package:probe/dispatcher.dart',
    sources: _sources,
    name: name,
    positionalArgs: positionalArgs,
    allowFileSystemImports: false,
  );

  expect(result, isA<Future<Object?>>());
  return (result as Future<Object?>).timeout(const Duration(seconds: 2));
}

void main() {
  group('imported interpreted async calls', () {
    test('resolve immediate and post-suspension method values', () async {
      expect(
        await _run('immediate'),
        equals({
          'outcome': {'kind': 'value', 'value': 7},
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 0,
        }),
      );
      expect(
        await _run('delayed', input: 8),
        equals({
          'outcome': {'kind': 'value', 'value': 8},
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 0,
        }),
      );
    });

    test('selects typed catches in source order and preserves the error',
        () async {
      for (final operation in ['failImmediately', 'failAfterAwait']) {
        expect(
          await _run(operation),
          equals({
            'outcome': {
              'kind': 'expected-catch',
              'marker':
                  operation == 'failImmediately' ? 'immediate' : 'delayed',
              'sameInstanceObserved': true,
            },
            'finallyCount': 1,
            'providerCalls': 1,
            'nestedCatchCount': 0,
            'nestedFinallyCount': 0,
          }),
        );
      }
    });

    test('uses a generic catch only when typed catches do not match', () async {
      expect(
        await _run('generic'),
        equals({
          'outcome': {'kind': 'generic-catch'},
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 0,
        }),
      );
    });

    test('resumes initializer, return, switch, and branch contexts once',
        () async {
      final outcomes = <String, Object?>{
        'initializer': {'kind': 'initializer', 'value': 13},
        'return': {'kind': 'return', 'value': 14},
        'branch': {'kind': 'branch', 'value': 'then'},
        'collection': {
          'kind': 'collection',
          'values': [16],
        },
      };

      for (final entry in outcomes.entries) {
        expect(
          await _run(entry.key),
          equals({
            'outcome': entry.value,
            'finallyCount': 1,
            'providerCalls': 1,
            'nestedCatchCount': 0,
            'nestedFinallyCount': 0,
          }),
        );
      }
    });

    test('preserves nested imported async frame success and error flow',
        () async {
      expect(
        await _run('nestedValue'),
        equals({
          'outcome': {'kind': 'nested', 'value': 11},
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 1,
        }),
      );
      expect(
        await _run('nestedFailure'),
        equals({
          'outcome': {
            'kind': 'expected-catch',
            'marker': 'nested',
            'sameInstanceObserved': true,
          },
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 1,
          'nestedFinallyCount': 1,
        }),
      );
      expect(
        await _run('nestedTryMismatch'),
        equals({
          'outcome': {
            'kind': 'expected-catch',
            'marker': 'delayed',
            'sameInstanceObserved': true,
          },
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 0,
        }),
      );
      expect(
        await _run('nestedInnerCatch'),
        equals({
          'outcome': {
            'kind': 'inner-catch',
            'marker': 'delayed',
            'sameInstanceObserved': true,
          },
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 0,
        }),
      );
      expect(
        await _run('returnOverriddenByFailure'),
        equals({
          'outcome': {
            'kind': 'expected-catch',
            'marker': 'finally',
            'sameInstanceObserved': true,
          },
          'finallyCount': 1,
          'providerCalls': 1,
          'nestedCatchCount': 0,
          'nestedFinallyCount': 2,
        }),
      );
    });

    test(
        'unmatched errors complete once and run finally without a side channel',
        () async {
      final d4rt = D4rt();
      final sideChannelErrors = <Object>[];
      Object? completedError;
      var errorCompletions = 0;

      await runZonedGuarded(
        () async {
          final result = d4rt.execute(
            library: 'package:probe/dispatcher.dart',
            sources: _sources,
            name: 'dispatchUnhandled',
            allowFileSystemImports: false,
          );
          expect(result, isA<Future<void>>());
          await (result as Future<Object?>).then<void>(
            (_) => fail('Expected dispatchUnhandled to fail.'),
            onError: (Object error, StackTrace _) {
              errorCompletions++;
              completedError = error;
            },
          ).timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 10));
        },
        (error, _) => sideChannelErrors.add(error),
      );

      expect(errorCompletions, 1);
      expect(sideChannelErrors, isEmpty);
      expect(d4rt.eval('readUnhandledFinallyCount()'), 1);
      expect(identical(completedError, d4rt.eval('readLastFailure()')), isTrue);
    });

    test('isolates concurrent fresh interpreter executions', () async {
      final results = await Future.wait<Object?>([
        _run('delayed', input: 21),
        _run('delayed', input: 34),
      ]);

      expect(
        results,
        equals([
          {
            'outcome': {'kind': 'value', 'value': 21},
            'finallyCount': 1,
            'providerCalls': 1,
            'nestedCatchCount': 0,
            'nestedFinallyCount': 0,
          },
          {
            'outcome': {'kind': 'value', 'value': 34},
            'finallyCount': 1,
            'providerCalls': 1,
            'nestedCatchCount': 0,
            'nestedFinallyCount': 0,
          },
        ]),
      );
    });

    test('retains invocation argument prefixes across multiple awaits',
        () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['invocation']),
        equals({
          'value': [1, 2, 3],
          'providerCalls': 2,
          'synchronousPrefixCalls': 1,
          'combinedCalls': 1,
          'order': [
            'sync:1',
            'async-start:2',
            'async-end:2',
            'async-start:3',
            'async-end:3',
            'combine',
          ],
        }),
      );
    });

    test('retains binary and nested invocation prefixes across suspensions',
        () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['expression']),
        equals({
          'value': 93,
          'providerCalls': 2,
          'synchronousPrefixCalls': 1,
          'combinedCalls': 0,
          'order': [
            'sync:30',
            'async-start:31',
            'async-end:31',
            'async-start:32',
            'async-end:32',
          ],
        }),
      );
      expect(
        await _runNamed(
          'evaluateCompound',
          positionalArgs: ['nestedInvocation'],
        ),
        equals({
          'value': [40, 42, 44],
          'providerCalls': 3,
          'synchronousPrefixCalls': 2,
          'combinedCalls': 2,
          'order': [
            'sync:40',
            'sync:41',
            'async-start:42',
            'async-end:42',
            'async-start:43',
            'async-end:43',
            'combine',
            'async-start:44',
            'async-end:44',
            'combine',
          ],
        }),
      );
    });

    test('retains collection and map prefixes across multiple awaits',
        () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['collection']),
        equals({
          'value': [4, 5, 6, 7],
          'providerCalls': 2,
          'synchronousPrefixCalls': 2,
          'combinedCalls': 0,
          'order': [
            'sync:4',
            'async-start:5',
            'async-end:5',
            'sync:6',
            'async-start:7',
            'async-end:7',
          ],
        }),
      );
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['map']),
        equals({
          'value': {10: 11, 12: 13},
          'providerCalls': 2,
          'synchronousPrefixCalls': 2,
          'combinedCalls': 0,
          'order': [
            'sync:10',
            'async-start:11',
            'async-end:11',
            'async-start:12',
            'async-end:12',
            'sync:13',
          ],
        }),
      );
    });

    test('retains set literal prefixes across multiple awaits', () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['set']),
        equals({
          'value': [50, 51, 52, 53],
          'providerCalls': 2,
          'synchronousPrefixCalls': 2,
          'combinedCalls': 0,
          'order': [
            'sync:50',
            'async-start:51',
            'async-end:51',
            'sync:52',
            'async-start:53',
            'async-end:53',
          ],
        }),
      );
    });

    test('retains record literal prefixes across multiple awaits', () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['record']),
        equals({
          'value': [60, 61, 62],
          'providerCalls': 2,
          'synchronousPrefixCalls': 1,
          'combinedCalls': 0,
          'order': [
            'sync:60',
            'async-start:61',
            'async-end:61',
            'async-start:62',
            'async-end:62',
          ],
        }),
      );
    });

    test('retains interpolation prefixes across multiple awaits', () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['interpolation']),
        equals({
          'value': 'a70:71:72:73z',
          'providerCalls': 2,
          'synchronousPrefixCalls': 2,
          'combinedCalls': 0,
          'order': [
            'sync:70',
            'async-start:71',
            'async-end:71',
            'sync:72',
            'async-start:73',
            'async-end:73',
          ],
        }),
      );
    });

    test('resumes a switch after completed case statements exactly once',
        () async {
      expect(
        await _runNamed('evaluateSwitchProgress'),
        equals({
          'outcome': {'awaited': 55, 'sameCanonical': true},
          'selectorCalls': 1,
          'allocations': 1,
          'observations': 1,
        }),
      );
    });

    test('preserves switch progress when an inner try catches await failure',
        () async {
      expect(
        await _runNamed('evaluateSwitchCaughtErrorProgress'),
        equals({
          'outcome': {'caught': true, 'sameCanonical': true},
          'selectorCalls': 1,
          'allocations': 1,
          'observations': 1,
        }),
      );
    });

    test('evaluates an awaited property target before its awaited value',
        () async {
      expect(
        await _runNamed('evaluateAssignment', positionalArgs: ['property']),
        equals({
          'value': 21,
          'slots': [20, 30],
          'events': [
            'target:start',
            'target:end',
            'rhs:start',
            'rhs:end',
            'property:set:21',
          ],
        }),
      );
    });

    test('evaluates awaited index target, index, and value in Dart order',
        () async {
      expect(
        await _runNamed('evaluateAssignment', positionalArgs: ['index']),
        equals({
          'value': 10,
          'slots': [20, 41],
          'events': [
            'target:start',
            'target:end',
            'index:start',
            'index:end',
            'rhs:start',
            'rhs:end',
            'index:set:1:41',
          ],
        }),
      );
    });

    test('reads compound property before evaluating its awaited value',
        () async {
      expect(
        await _runNamed(
          'evaluateAssignment',
          positionalArgs: ['compoundProperty'],
        ),
        equals({
          'value': 15,
          'slots': [20, 30],
          'events': [
            'target:start',
            'target:end',
            'property:get',
            'rhs:start',
            'rhs:end',
            'property:set:15',
          ],
        }),
      );
    });

    test('reads compound index before evaluating its awaited value', () async {
      expect(
        await _runNamed(
          'evaluateAssignment',
          positionalArgs: ['compoundIndex'],
        ),
        equals({
          'value': 10,
          'slots': [27, 30],
          'events': [
            'target:start',
            'target:end',
            'index:start',
            'index:end',
            'index:get:0',
            'rhs:start',
            'rhs:end',
            'index:set:0:27',
          ],
        }),
      );
    });

    test('skips an awaited value when a null-aware compound read is non-null',
        () async {
      expect(
        await _runNamed(
          'evaluateAssignment',
          positionalArgs: ['nullAwareCompound'],
        ),
        equals({
          'value': 10,
          'slots': [20, 30],
          'events': [
            'target:start',
            'target:end',
            'property:get',
          ],
        }),
      );
    });

    test('preserves a pending error through a successful awaited finally',
        () async {
      expect(
        await _runNamed('preserveErrorThroughAwaitedFinally'),
        equals({
          'kind': 'caught',
          'sameError': true,
          'cleanupStarts': 1,
          'cleanupEnds': 1,
        }),
      );
    });

    test('matches prefixed catch types by imported class identity', () async {
      expect(await _runNamed('catchPrefixedBaseType'), 'sdk-catch');
    });

    test('releases completed expression state before the next evaluation',
        () async {
      expect(
        await _runNamed('evaluateCompound', positionalArgs: ['repeated']),
        equals({
          'value': [
            [0, 20],
            [1, 21],
          ],
          'providerCalls': 2,
          'synchronousPrefixCalls': 2,
          'combinedCalls': 0,
          'order': [
            'sync:0',
            'async-start:20',
            'async-end:20',
            'sync:1',
            'async-start:21',
            'async-end:21',
          ],
        }),
      );
    });

    test('returns through all outer finalizers before and after suspension',
        () async {
      expect(
        await _runNamed(
          'returnThroughOuterFinalizers',
          positionalArgs: [false],
        ),
        equals({
          'value': 81,
          'innerFinallyCount': 1,
          'outerFinallyCount': 1,
        }),
      );
      expect(
        await _runNamed(
          'returnThroughOuterFinalizers',
          positionalArgs: [true],
        ),
        equals({
          'value': 82,
          'innerFinallyCount': 1,
          'outerFinallyCount': 1,
        }),
      );
    });

    test('finally return overrides an earlier return and async error',
        () async {
      expect(
        await _runNamed(
          'runFinallyReturnOverride',
          positionalArgs: ['return'],
        ),
        equals({'value': 92, 'overridingFinallyCount': 1}),
      );
      expect(
        await _runNamed(
          'runFinallyReturnOverride',
          positionalArgs: ['error'],
        ),
        equals({'value': 93, 'overridingFinallyCount': 1}),
      );
    });

    test('yield await emits the resolved imported value exactly once',
        () async {
      final result = D4rt().execute(
        library: 'package:probe/dispatcher.dart',
        sources: _sources,
        name: 'yieldImportedValue',
        allowFileSystemImports: false,
      );

      expect(result, isA<Stream<Object?>>());
      expect(
        await (result as Stream<Object?>)
            .toList()
            .timeout(const Duration(seconds: 2)),
        [44],
      );
    });

    test('yield await reports the original imported error on the stream',
        () async {
      final d4rt = D4rt();
      final result = d4rt.execute(
        library: 'package:probe/dispatcher.dart',
        sources: _sources,
        name: 'yieldImportedError',
        allowFileSystemImports: false,
      );
      final values = <Object?>[];
      final errors = <Object>[];
      final done = Completer<void>();

      expect(result, isA<Stream<Object?>>());
      (result as Stream<Object?>).listen(
        values.add,
        onError: (Object error) => errors.add(error),
        onDone: done.complete,
      );
      await done.future.timeout(const Duration(seconds: 2));

      expect(values, isEmpty);
      expect(errors, hasLength(1));
      expect(identical(errors.single, d4rt.eval('readLastFailure()')), isTrue);
    });

    test('switch expression resumes an awaited selector without replay',
        () async {
      expect(
        await _runNamed('evaluateSwitchExpressionSelector'),
        equals({
          'value': 'selected',
          'events': ['selector:start', 'selector:end', 'result'],
        }),
      );
    });

    test('switch expression retains its matched case across an awaited guard',
        () async {
      expect(
        await _runNamed('evaluateSwitchExpressionGuard'),
        equals({
          'value': 'selected',
          'events': ['selector', 'guard:start', 'guard:end', 'result'],
        }),
      );
    });

    test('switch expression resumes an awaited result without replay',
        () async {
      expect(
        await _runNamed('evaluateSwitchExpressionResult'),
        equals({
          'value': 'selected!',
          'events': [
            'selector',
            'result-prefix',
            'result-await:start',
            'result-await:end',
          ],
        }),
      );
    });

    test('collection if retains its selected branch across suspension',
        () async {
      expect(
        await _runNamed('evaluateCollectionIf'),
        equals({
          'values': ['ab'],
          'events': [
            'if:condition',
            'if:branch-prefix',
            'if:branch-await:start',
            'if:branch-await:end',
          ],
        }),
      );
    });

    test('collection for retains iteration progress across body awaits',
        () async {
      expect(
        await _runNamed('evaluateCollectionFor'),
        equals({
          'values': [11, 22, 33],
          'events': [
            'for:iterable',
            'for:prefix:1',
            'for:await:1:start',
            'for:await:1:end',
            'for:prefix:2',
            'for:await:2:start',
            'for:await:2:end',
            'for:prefix:3',
            'for:await:3:start',
            'for:await:3:end',
          ],
        }),
      );
    });

    test(
        'cancelling an async generator stops after await and runs finally once',
        () async {
      final d4rt = D4rt();
      final result = d4rt.execute(
        library: 'package:probe/dispatcher.dart',
        sources: _sources,
        name: 'cancellableGenerator',
        allowFileSystemImports: false,
      );
      final values = <Object?>[];
      final firstValue = Completer<void>();

      expect(result, isA<Stream<Object?>>());
      final subscription = (result as Stream<Object?>).listen((value) {
        values.add(value);
        if (!firstValue.isCompleted) firstValue.complete();
      });
      await firstValue.future.timeout(const Duration(seconds: 2));

      var reachedAwait = false;
      for (var attempt = 0; attempt < 200; attempt++) {
        final events = d4rt.eval('readGeneratorEvents()') as List<Object?>;
        if (events.contains('before-await')) {
          reachedAwait = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(reachedAwait, isTrue);
      await subscription.cancel().timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(values, [1]);
      expect(
        d4rt.eval('readGeneratorEvents()'),
        ['start', 'before-await', 'finally-start', 'finally-end'],
      );
    });

    test('cancelling yield star detaches its stream and runs finalizers once',
        () async {
      final d4rt = D4rt();
      final result = d4rt.execute(
        library: 'package:probe/dispatcher.dart',
        sources: _sources,
        name: 'cancellableDelegatingGenerator',
        allowFileSystemImports: false,
      );
      final values = <Object?>[];
      final firstValue = Completer<void>();

      expect(result, isA<Stream<Object?>>());
      final subscription = (result as Stream<Object?>).listen((value) {
        values.add(value);
        if (!firstValue.isCompleted) firstValue.complete();
      });
      await firstValue.future.timeout(const Duration(seconds: 2));

      var reachedAwait = false;
      for (var attempt = 0; attempt < 200; attempt++) {
        final events = d4rt.eval('readGeneratorEvents()') as List<Object?>;
        if (events.contains('inner:before-await')) {
          reachedAwait = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(reachedAwait, isTrue);
      await subscription.cancel().timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(values, [1]);
      expect(
        d4rt.eval('readGeneratorEvents()'),
        [
          'outer:start',
          'inner:start',
          'inner:before-await',
          'inner:finally',
          'outer:finally-start',
          'outer:finally-end',
        ],
      );
    });

    test('public compiled, eval, and direct invocation paths return Futures',
        () async {
      final d4rt = D4rt();
      final function = d4rt.execute(source: '''
Future<int> work(int value) async {
  return await Future.value(value);
}

Future<void> fallThrough() async {
  await Future.value(99);
}

main() => work;
''') as InterpretedFunction;

      final invoked = d4rt.invokeInterpretedFunction(function, [51]);
      expect(invoked, isA<Future<Object?>>());
      expect(await (invoked as Future<Object?>), 51);

      final evaluated = d4rt.eval('work(52)');
      expect(evaluated, isA<Future<Object?>>());
      expect(await (evaluated as Future<Object?>), 52);

      final fallenThrough = d4rt.eval('fallThrough()');
      expect(fallenThrough, isA<Future<Object?>>());
      expect(await (fallenThrough as Future<Object?>), isNull);

      final compiledD4rt = D4rt();
      final script = compiledD4rt.compile(source: '''
Future<int> main() async {
  return await Future.value(53);
}
''');
      final compiled = compiledD4rt.executeCompiled(script);
      expect(compiled, isA<Future<Object?>>());
      expect(await (compiled as Future<Object?>), 53);
    });
  });
}
