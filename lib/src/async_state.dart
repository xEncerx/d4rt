import 'dart:async';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:d4rt/src/callable.dart';
import 'package:d4rt/src/environment.dart';
import 'package:d4rt/src/exceptions.dart';

/// Represents the state of an ongoing asynchronous function execution.
/// This object tracks the progress and context needed for resumption.
class AsyncExecutionState {
  /// The unique environment for this specific function call.
  final Environment environment;

  /// The completer associated with the Future returned to the caller.
  final Completer<Object?> completer;

  /// An identifier for the next block of code (state) to execute.
  /// This could be an integer index, an AST node reference, etc.
  /// (Needs further definition based on the state machine implementation).
  AstNode? nextStateIdentifier;

  /// The result value from the most recently completed Future (from await).
  Object? lastAwaitResult;

  /// Frame-owned continuation data for expressions interrupted by suspension.
  ///
  /// Values are private interpreter continuation objects keyed by their owning
  /// AST node. They exist only until that expression completes or the frame
  /// terminates.
  final Map<AstNode, Object> expressionContinuations = {};

  /// The exact await expression whose completed value is ready to substitute.
  AwaitExpression? completedAwaitExpression;

  /// The completed value for [completedAwaitExpression].
  Object? completedAwaitValue;

  /// Distinguishes a completed `null` value from no completed await.
  bool hasCompletedAwaitValue = false;

  /// Lexical environment captured by the currently suspended await.
  ///
  /// This preserves block-local bindings when an asynchronous error transfers
  /// control directly into a lexical catch clause.
  Environment? awaitingEnvironment;

  /// Try statements completed while error handling ran outside their caller.
  ///
  /// The marker lasts only until the owning control continuation re-enters the
  /// statement and advances past it.
  final Set<TryStatement> completedTryStatements = {};

  /// The error from the most recently completed Future (if it failed).
  Object? lastAwaitError;

  /// The stack trace from the most recently completed Future (if it failed).
  StackTrace? lastAwaitStackTrace;

  /// Optional: Store the iterator for ongoing for-in loops.
  Iterator<Object?>? currentForInIterator;

  /// Optional: Flag for standard for-loops.
  bool forLoopInitialized = true;

  /// Optional: Environment for the current standard for-loop scope.
  Environment? forLoopEnvironment;

  /// Stack of loop environments for nested loops
  final List<Environment> loopEnvironmentStack = [];

  /// Stack of initialization flags for nested loops
  final List<bool> loopInitializedStack = [];

  /// Stack of ForStatement nodes corresponding to the environments
  final List<ForStatement> loopNodeStack = [];

  /// Map of ForStatement -> Iterator for for-in loops
  final Map<ForStatement, Iterator<Object?>?> forInIteratorMap = {};

  /// Stack of loop nodes (ForStatement, WhileStatement, etc.) for break/continue.
  final List<AstNode> loopStack = [];

  /// Flag to indicate that a `continue` is being handled for a `for` loop.
  bool isHandlingContinue = false;

  /// Optional: A reference back to the function definition might be useful.
  final InterpretedFunction function;

  /// NEW FLAG
  bool resumedFromInitializer = false;

  /// Track pending finally block to execute after try/catch
  Block? pendingFinallyBlock;

  /// Track the error currently being handled (either from await or sync throw)
  Object? currentError;

  /// Track the stack trace currently being handled (either from await or sync throw)
  StackTrace? currentStackTrace;

  /// Lexical node where error lookup resumes after an inner finally completes.
  AstNode? resumeErrorAfterFinallyFrom;

  /// Track the TryStatement we are currently inside or handling
  TryStatement? activeTryStatement;

  /// Lexical environment owned by the catch block currently being executed.
  Environment? activeCatchEnvironment;

  /// Store return value if a return happens inside a try with a finally.
  Object? returnAfterFinally;

  /// Distinguishes a pending `return null` from no pending return.
  bool hasReturnAfterFinally = false;

  /// Lexical node where an outer finally lookup resumes after a return.
  AstNode? resumeReturnAfterFinallyFrom;

  /// Flag to indicate if we are currently executing a catch block body.
  bool isHandlingErrorForRethrow = false;

  /// Store the original exception wrapped for potential rethrow.
  InternalInterpreterException? originalErrorForRethrow;

  /// Flag to indicate we are currently executing a rethrow statement
  /// (as opposed to just being in a catch block)
  bool isCurrentlyRethrowing = false;

  /// Fields for await for loop processing
  List<Object?>? currentAwaitForList;

  /// Current index when processing await for loops with stream conversion.
  /// Used to track position in the converted list from a stream.
  int? currentAwaitForIndex;

  /// Flag indicating if the interpreter is currently waiting for stream conversion.
  /// When true, indicates that a stream is being converted to a list for await-for processing.
  bool awaitingStreamConversion = false;

  /// Stack of lists for nested await-for loops
  /// Each level of nesting has its own list
  final List<List<Object?>> awaitForListStack = [];

  /// Stack of indices for nested await-for loops
  /// Each level of nesting has its own index
  final List<int> awaitForIndexStack = [];

  /// Stack of ForStatement nodes for nested await-for loops
  /// Used to track which await-for loop we're in
  final List<ForStatement> awaitForNodeStack = [];

  /// For async* generators: the stream controller to send yields to
  StreamController<Object?>? generatorStreamController;

  /// For async* generators: flag indicating this is a generator execution
  bool get isGenerator => generatorStreamController != null;

  /// Whether the generator subscription has requested cancellation.
  bool generatorCancelled = false;

  /// Whether the state machine is running finalizers after cancellation.
  bool generatorCancellationCleanup = false;

  /// The lexical suspension point used to locate cancellation finalizers.
  AstNode? generatorSuspendedNode;

  /// The active delegated stream subscription owned by `yield*`.
  StreamSubscription<dynamic>? generatorYieldStarSubscription;

  /// Completes the suspended `yield*` operation when cancellation detaches it.
  Completer<void>? generatorYieldStarCompletion;

  /// Creates a new async execution state.
  ///
  /// [environment] The execution environment for the async function.
  /// [completer] The completer that will complete when the function finishes.
  /// [nextStateIdentifier] The AST node representing the next state to execute.
  /// [function] The interpreted function being executed asynchronously.
  AsyncExecutionState({
    required this.environment,
    required this.completer,
    required this.nextStateIdentifier,
    required this.function,
    this.lastAwaitResult,
    this.lastAwaitError,
    this.lastAwaitStackTrace,
    this.currentForInIterator,
    this.forLoopInitialized = false,
    this.forLoopEnvironment,
    this.pendingFinallyBlock,
    this.currentError,
    this.currentStackTrace,
    this.activeTryStatement,
    this.returnAfterFinally,
    this.isHandlingErrorForRethrow = false,
    this.originalErrorForRethrow,
    this.isHandlingContinue = false,
    this.generatorStreamController,
  });
}

/// Represents a request to suspend execution and wait for a Future.
/// This object is returned by visitor methods when an await is encountered.
class AsyncSuspensionRequest {
  /// The Future that needs to be awaited.
  final Future<Object?> future;

  /// The state object associated with the execution that needs suspension.
  /// This is needed by the scheduler to know which execution to resume later.
  final AsyncExecutionState asyncState;

  /// Flag indicating if this suspension is from a yield statement
  final bool isYieldSuspension;

  /// The exact await expression whose value must be substituted on resumption.
  final AwaitExpression? awaitExpression;

  /// Creates a new async suspension request.
  ///
  /// [future] The Future that the interpreter should wait for.
  /// [asyncState] The current execution state that will be resumed after the Future completes.
  /// [isYieldSuspension] Whether this suspension is from a yield statement.
  /// [awaitExpression] The exact expression that receives the completed value.
  AsyncSuspensionRequest(
    this.future,
    this.asyncState, {
    this.isYieldSuspension = false,
    this.awaitExpression,
  });
}
