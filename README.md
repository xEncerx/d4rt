# d4rt

[![Pub package](https://img.shields.io/pub/v/d4rt.svg)](https://pub.dev/packages/d4rt)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

**d4rt** (pronounced "dart") is an interpreter and runtime for the Dart language, written in Dart.  
It allows you to execute Dart code dynamically, bridge native classes, and build advanced scripting or plugin systems in your Dart/Flutter applications.

---

## Features

- **Dart interpreter**: Run Dart code dynamically at runtime.
- **Precompiled scripts & AST caching**: Pre-parse and validate scripts with `compile()` and execute repeatedly with `executeCompiled()` for maximum performance.
- **Execution limits & timeouts**: Protect against infinite loops and runaway CPU usage with `timeout` and `maxSteps` sandbox limits.
- **Interactive CLI & REPL**: Run scripts directly or launch an interactive shell with `dart run d4rt`.
- **Full generics support**: Complete support for generic classes, functions, and type constraints with runtime validation.
- **Type bounds checking**: Enforce generic type constraints (e.g., `T extends num`) with dynamic resolution.
- **Bridging system**: Expose your own Dart/Flutter classes, enums, and methods to interpreted code.
- **Async/await support**: Handle asynchronous code and Futures.
- **Class, enum, and extension support**: Use most Dart language features, including classes, inheritance, mixins, enums, and extensions.
- **Pattern matching**: Support for Dart's pattern matching in switch/case and assignments.
- **Runtime type validation**: Validate generic type arguments and method parameters at runtime.
- **Security sandboxing**: Permission-based security system to restrict dangerous operations and prevent malicious code execution.
- **Custom logging**: Integrated, configurable logger for debugging interpreted code.
- **Function argument passing**: Pass positional and named arguments directly to functions via `execute()`.
- **Code introspection**: Analyze Dart code structure with the `analyze()` method to extract metadata.
- **Dynamic code evaluation**: Execute code dynamically with `eval()` while preserving execution state.
- **Extensible**: Add your own bridges for custom types and native APIs.

---

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  d4rt: ^0.5.1
```

Then run:

```sh
dart pub get
```

---

## Usage Example

```dart
import 'package:d4rt/d4rt.dart';

void main() {
  final code = '''
    int fib(int n) {
      if (n <= 1) return n;
      return fib(n - 1) + fib(n - 2);
    }
    main() {
      return fib(6);
    }
  ''';

  final interpreter = D4rt();
  final result = interpreter.execute(source: code);
  print('Result: $result'); // Result: 8
}
```
## Advanced Features

### Function Argument Passing

Pass positional and named arguments directly to functions:

```dart
final interpreter = D4rt();

final result = interpreter.execute(
  source: '''
    String greet(String name, {String greeting = "Hello"}) {
      return "\$greeting, \$name!";
    }
  ''',
  name: 'greet',
  positionalArgs: ['Alice'],
  namedArgs: {'greeting': 'Hi'},
);
print(result); // Hi, Alice!
```

### Interpreted function invocation

Invoke interpreted functions from host dart code:
```dart
final interpreter = D4rt();

final interpretedFn = interpreter.execute( 
  source: '''
      int sum(int a, int b) => a+b;
      main() => sum;
  '''
);

final result = d4rt.invokeInterpretedFunction(interpretedFn, [1,2]);
print(result); // 3
```

Promote interpreted functions to host functions to better integration:

```dart
final interpreter = D4rt();

final interpretedFn = interpreter.execute( 
  source: '''
      int sum(int a, int b) => a+b;
      main() => sum;
  '''
);

T Function(A, B) bindFunction2<T, A, B>(D4rt d, InterpretedFunction fn) {
  return (A a, B b) => d.invokeInterpretedFunction(fn, [a, b]);
}

final nativeFn = bindFunction2(interpreter,interpretedFn);
print( nativeFn(1,2) ); // 3
```

Note that it is possible to pass `InterpretedFunction` as argumento to `invokeInterpretedFunction`, but pass a native function it is not currently supported.

### Source Inspection

Inspect declared syntax without loading imports or executing code:

```dart
import 'package:d4rt/d4rt.dart';

void main() {
  final syntax = inspectSource(source: '''
    import 'package:unavailable/library.dart';
    final class Example {
      String greet(int count) => 'hello';
    }
  ''');
  if (syntax.hasErrors) throw FormatException(syntax.diagnostics.first.message);
  final owner = syntax.declarations.single as SourceTypeDeclaration;
  final method = owner.members.single as SourceCallable;
  print(method.returnType?.canonicalName); // String
  print(method.parameters.single.type?.canonicalName); // int
}
```

### Code Introspection

Analyze declarations without running initializers, constructors, getters, or function bodies.
Imported sources can be supplied through `sources`. Analysis does not change an existing
execution context.

```dart
import 'package:d4rt/d4rt.dart';

void main() {
  final analysis = D4rt().analyze(source: '''
    int count = 42;
    int add(int left, int right) => left + right;
  ''');

  print(analysis.functions.first.parameterNames); // [left, right]
  final count = analysis.variables.first;
  print(count.declaredType); // int
  print(count.isValueAvailable); // false
}
```

Analysis reports declared types, not inferred runtime values. Variable values and
runtime types remain unavailable (`isValueAvailable == false`, `value == null`,
`valueType == 'unavailable'`), even for literal initializers. `toMap()` and `toJson()`
include the availability flag; text output displays `<unavailable>`.

### Dynamic Code Evaluation

Execute code dynamically while preserving execution state. Each `eval()` call
requires `DangerousPermission.codeEvaluation` (or `DangerousPermission.any`);
revoking that authority blocks subsequent calls. Ordinary `execute()` does not
require it.

```dart
final interpreter = D4rt()..grant(DangerousPermission.codeEvaluation);

interpreter.execute(source: 'int x = 10;');
final result = interpreter.eval('x + 5'); // Returns 15
```

### Precompiled Scripts & AST Caching

For high-performance scenarios where the same script is executed multiple times, precompile the AST once to avoid re-parsing overhead:

```dart
final d4rt = D4rt();

// Compile once
final script = d4rt.compile(source: '''
  int multiply(int a, int b) => a * b;
''');

// Execute repeatedly with zero parsing overhead
final r1 = d4rt.executeCompiled(script, name: 'multiply', positionalArgs: [6, 7]); // 42
final r2 = d4rt.executeCompiled(script, name: 'multiply', positionalArgs: [10, 5]); // 50
```

You can also enable automatic AST caching for repeated source strings:

```dart
final d4rt = D4rt(enableAstCache: true);
// Subsequent execute() calls with identical source strings will reuse cached ASTs
```

### Execution Limits & Timeout Protection

Protect against infinite loops and runaway CPU usage by setting maximum step quotas or execution timeouts:

```dart
final d4rt = D4rt();

try {
  d4rt.execute(
    source: '''
      void main() {
        while (true) { /* infinite loop */ }
      }
    ''',
    maxSteps: 1000, // Maximum execution steps
    timeout: Duration(milliseconds: 500), // Maximum execution duration
  );
} on ExecutionLimitException catch (e) {
  print('Step limit exceeded: $e');
} on ExecutionTimeoutException catch (e) {
  print('Timed out: $e');
}
```

### Command-Line Interface (CLI) & Interactive REPL

d4rt includes a built-in CLI runner and an interactive REPL shell:

```sh
# Run a Dart script file directly
dart run d4rt path/to/script.dart [args...]

# Start an interactive REPL session
dart run d4rt repl
# or simply
dart run d4rt
```

CLI defaults allow **read-only access to the script's directory subtree**.
Eval (`-e CODE`) and REPL use the current working directory subtree and explicitly
enable code evaluation. Writes, outside-subtree reads, network access, native
process execution, isolates, and other dangerous operations require opt-in:

| Option | Additional authority |
| --- | --- |
| `--allow-fs` | `FilesystemPermission.any` |
| `--allow-net` | `NetworkPermission.any` |
| `--allow-process` | `ProcessRunPermission.any` + `DangerousPermission.processExecution` (not signals) |
| `--allow-isolate` | `IsolatePermission.any` |
| `--allow-dangerous` | `DangerousPermission.any` (does not itself grant process/isolate permission) |
| `--allow-all` | All grants above |

Place CLI options **before** the script, `repl`, or `-e CODE` target. Every argument
after a script path is delivered unchanged, including `--help` and `--allow-all`.
Code is a single opaque operand; extra operands to eval, introspection, or REPL
are errors. Use `--` before an option-like script filename:

```sh
dart run d4rt --allow-net path/to/script.dart --script-option
dart run d4rt -e "2 + 3"
dart run d4rt --allow-fs repl
dart run d4rt -- -script.dart --help
```

`:clear` resets REPL state without changing its selected grants or read root.
Introspection (`-i` / `--json-introspection`) remains metadata-only.
These interpreter permissions are **not an OS-grade sandbox for hostile code**:
unrestricted filesystem, native processes, native isolate code, dangerous
operations, and custom bridges can expose host authority.

Inside the REPL:
```text
==============================================
  d4rt v0.5.1 - Interactive Dart REPL
  Type :help for help, :exit or Ctrl+C to quit
==============================================

d4rt> var x = 10;
d4rt> int double(int n) => n * 2;
d4rt> double(x)
=> 20
d4rt> :exit
Goodbye!
```

## Security Sandboxing

Access to `dart:io`, `dart:isolate`, and `dart:developer` requires permissions.

### Granting Permissions

```dart
import 'package:d4rt/d4rt.dart';

void main() {
  final interpreter = D4rt()
    ..grant(FilesystemPermission.any)
    ..grant(NetworkPermission.any)
    ..grant(ProcessRunPermission.any)
    ..grant(DangerousPermission.processExecution)
    ..grant(IsolatePermission.any);
}
```

### Permission Types

- **`FilesystemPermission`**: Controls file and directory operations
  - `FilesystemPermission.any` - Allow all filesystem operations
  - `FilesystemPermission.read` - Allow read-only operations
  - `FilesystemPermission.write` - Allow write operations
  - `FilesystemPermission.readPath('/specific/path')` - Allow reads within a subtree
  - `FilesystemPermission.writePath('/specific/path')` - Allow writes within a subtree
  - `FilesystemPermission.executePath('/specific/path')` - Allow execution within a subtree
  - `FilesystemPermission.path('/specific/path')` - Allow all operations within a subtree

- **`NetworkPermission`**: Controls network operations
  - `NetworkPermission.any` - Allow all network operations
  - `NetworkPermission.connect` - Allow connections to any host/port
  - `NetworkPermission.connectTo('api.example.com')` - Allow connections to a specific host
  - `NetworkPermission.connectToPort('api.example.com', 443)` - Restrict both host and port
  - `NetworkPermission.listen` - Allow TCP/HTTP listeners on any port
  - `NetworkPermission.bind` - Allow UDP binding (not sending)
  - `NetworkPermission.listenOn(8080)` - Allow listening on a specific port

- **`ProcessRunPermission`**: Controls process execution
  - `ProcessRunPermission.any` - Allow execution of any command
  - `ProcessRunPermission.command('specific-command')` - Allow that exact command with any arguments
  - `ProcessRunPermission.commandWithArgs('specific-command', ['--safe'])` - Require that exact command and ordered argument list

- **`IsolatePermission`**: Controls isolate creation and communication
  - `IsolatePermission.any` - Allow all isolate operations
  - `IsolatePermission.spawn` - Allow native spawning and control, not communication
  - `IsolatePermission.communicate` - Allow communication, not spawning or control

- **`DangerousPermission`**: Controls explicitly requested dangerous operations
  - `DangerousPermission.codeEvaluation` - Allow code evaluation, not native plugins
  - `DangerousPermission.nativePlugins` - Allow native plugins, not code evaluation
  - `DangerousPermission.processExecution` - Allow native child execution (also requires a matching `ProcessRunPermission`)
  - `DangerousPermission.processSignals` - Allow signal watching and process termination, including arbitrary PIDs
  - `DangerousPermission.developerTools` - Allow `dart:developer` import, members, and service-extension invocation
  - `DangerousPermission.any` - Allow all dangerous operations

### Native Capabilities

```dart
final interpreter = D4rt()
  ..grant(FilesystemPermission.any) // Required to import dart:io.
  ..grant(ProcessRunPermission.commandWithArgs('dart', ['--version']))
  ..grant(DangerousPermission.processExecution);
```

Shell execution additionally requires `ProcessRunPermission.any`, including Windows
`.bat`/`.cmd` launches even when `runInShell` is false. Bare executable names and
paths are distinct grants; relative executable paths resolve against the
effective child working directory. `Isolate.spawnUri` also requires
`DangerousPermission.codeEvaluation`, and communication authority when passing
messages or notification ports. `Isolate.spawn` remains unsupported.

Native child processes and native Dart isolates execute outside the interpreter's
filesystem/network sandbox. Revocation protects subsequent adapter operations,
including saved objects/tearoffs and developer extension invocations; it does
not terminate children or cancel already-issued native ports, streams, listeners,
or callbacks. Hosts must own their cleanup. Custom native bridges remain trusted.

### Permission Management

```dart
final interpreter = D4rt();

interpreter.grant(FilesystemPermission.readPath('data'));
final hasReadAccess =
    interpreter.hasPermission(FilesystemPermission.readPath('data'));
interpreter.revoke(FilesystemPermission.readPath('data'));
```

### Scoped Filesystem Access

```dart
final interpreter = D4rt()
  ..grant(FilesystemPermission.readPath('data'))
  ..grant(FilesystemPermission.writePath('data/output'));
```

Relative grants stay anchored to their original working directory. Filesystem
scopes check effective paths, including symbolic links, metadata, directory
results, and watch events. Creating or updating a link requires write access to
its entry and parent plus read access to its target; inspecting its target
requires both entry and target read access. Readable/writable file handles need
both read and write grants.

### Scoped Network Access

Grant access to a specific endpoint:

```dart
final interpreter = D4rt()
  ..grant(FilesystemPermission.any)
  ..grant(NetworkPermission.connectToPort('example.com', 443));
```

Use `response.redirect()` to follow HTTP redirects with scoped permissions.

### Filesystem Module Imports

Use `basePath` together with `allowFileSystemImports: true` when interpreted code imports local files from disk.

```dart
final interpreter = D4rt();
interpreter.grant(FilesystemPermission.readPath('/path/to/project/lib'));

final result = interpreter.execute(
  source: '''
    import './utils.dart';
    String main() => greetFromUtils();
  ''',
  basePath: '/path/to/project/lib',
  allowFileSystemImports: true,
);
```

Rules:

- Relative filesystem imports require `basePath`.
- Filesystem modules are blocked unless `allowFileSystemImports` is enabled.
- Reading modules from disk also requires a matching `FilesystemPermission`.
- Missing local files raise a `SourceCodeException` with the resolved filesystem path.

## Enums

Enum declarations work in source passed to `execute`, `compile` and `executeCompiled`, including imported modules.

```dart
final result = D4rt().execute(source: '''
  enum Priority {
    low(1), high(2);

    const Priority(this.level);
    final int level;

    static Priority? fromLevel(int level) {
      for (final priority in values) {
        if (priority.level == level) return priority;
      }
      return null;
    }
  }

  main() => Priority.fromLevel(2)!.name;
''');
print(result); // high
```

Enums support constructors, fields, methods and static members. Use `values`, `name`, `index` and `values.byName(...)` to work with enum constants.

## Bridging Native Classes & Enums

d4rt provides a powerful bridging system that allows you to automate the process of exposing your Dart and Flutter classes, enums, and functions to the interpreter using `build_runner`.

### Automated Bridge Generation (Recommended)

1. **Add `build_runner` to your dev dependencies:**

   ```yaml
   dev_dependencies:
     build_runner: ^2.16.1
   ```

2. **Annotate your classes or enums with `@D4rtBridge()`:**

   ```dart
   import 'package:d4rt/d4rt.dart';
   part 'color.g.dart';
   @D4rtBridge(libraryUri: 'package:app/color.dart')
   class Color {
     final int value;
     const Color(this.value);
     
     static const Color black = Color(0xFF000000);
     
     int get red => (value >> 16) & 0xFF;
   }
   ```

3. **Run the code generator:**

   ```sh
   dart run build_runner build
   ```

   This will generate a `.g.dart` file containing the bridge definitions and an automatic registration function.

4. **Register the bridges with the interpreter:**

   ```dart
   import 'package:d4rt/d4rt.dart';
   import 'color.dart'; // Import the generated file

   void main() {
     final interpreter = D4rt();
     
     // Register all bridges in the file with a single line:
     registerColorBridges(interpreter);
     
     // Now 'Color' is available in the interpreter under 'package:app/color.dart'
   }
   ```

### Manual Bridge Definition

If you prefer to define bridges manually (without code generation), you can use the `BridgedClass` and `BridgedEnumDefinition` classes:

#### Bridge a Dart Class (Manual)

```dart
import 'package:d4rt/d4rt.dart';

class MyClass {
  int value;
  MyClass(this.value);
  int doubleValue() => value * 2;
}

final myClassBridge = BridgedClass(
  nativeType: MyClass,
  name: 'MyClass',
  constructors: {
    '': (InterpreterVisitor visitor, List<Object?> positionalArgs, Map<String, Object?> namedArgs) {
      if (positionalArgs.length == 1 && positionalArgs[0] is int) {
        return MyClass(positionalArgs[0] as int);
      }
      throw ArgumentError('MyClass constructor expects one integer argument.');
    },
  },
  methods: {
    'doubleValue': (InterpreterVisitor visitor, Object target, List<Object?> positionalArgs, Map<String, Object?> namedArgs) {
      if (target is MyClass) {
        return target.doubleValue();
      }
      throw TypeError();
    },
  },
  getters: {
    'value': (InterpreterVisitor? visitor, Object target) {
      if (target is MyClass) {
        return target.value;
      }
      throw TypeError();
    },
  },
);

void main() {
  final interpreter = D4rt();
  interpreter.registerBridgedClass(myClassBridge, 'package:example/my_class_library.dart');

  final code = '''
    import 'package:example/my_class_library.dart';

    main() {
      var obj = MyClass(21);
      return obj.doubleValue();
    }
  ''';

  final result = interpreter.execute(source: code);
  print(result); // 42
}
```

#### Bridge a Dart Enum (Manual)

```dart
import 'package:d4rt/d4rt.dart';

enum Color { red, green, blue }

final colorEnumBridge = BridgedEnumDefinition<Color>(
  name: 'Color',
  values: Color.values,
);

void main() {
  final interpreter = D4rt();
  interpreter.registerBridgedEnum(colorEnumBridge, 'package:example/my_enum_library.dart');

  final code = '''
    import 'package:example/my_enum_library.dart';

    main() {
      var favoriteColor = Color.green;
      print('My favorite color is \${favoriteColor.name}');
      return favoriteColor.index;
    }
  ''';

  final result = interpreter.execute(source: code);
  print(result); // 1
}
```

For generic native enums, supply `typeMetadata` on `BridgedEnumDefinition` with `typeParameters`, `typeBounds` and `supertypes`. Generic hierarchy edges can be supplied through `supertypeDeclarations`; native constant arguments are recovered from their runtime types or supplied explicitly through `valueTypeArguments`. Generated bridges include this metadata and adapters for declared fields, methods, factories and setters.

Native mixins used by interpreted enums can supply `EnumMixinMetadata` on `BridgedClass` to describe generic types, `on` constraints, instance fields and abstract member obligations. Adapters receive the interpreted enum constant as their receiver; mixin static members are not inherited by the enum.

Native const constructors used by enum entry payloads are listed in `BridgedClass.constantConstructors`. Generated class bridges provide these constructor names automatically.

### Advanced Annotation Options

The `@D4rtBridge` annotation provides several configuration parameters:

- `libraryUri`: The namespace where the class will be registered (e.g., `'package:app/color.dart'`).
- `includePrivate`: Whether to generate bridges for private members (default: `false`).
- `bridgeName`: A custom variable name for the generated bridge (useful for avoiding name collisions).

Example:
```dart
@D4rtBridge(
  libraryUri: 'package:app/models.dart',
  includePrivate: true,
  bridgeName: 'customUserBridge',
)
class User { ... }
```

---

## Supported Features

| Feature                        | Status / Notes                                                                 |
|--------------------------------|-------------------------------------------------------------------------------|
| Classes & Inheritance          | ✅ Full support (abstract, inheritance, mixins, interfaces, sealed, base, final) |
| Enums                          | ✅ Full support (fields, methods, static, named values, index, name)           |
| Mixins                         | ✅ Supported (declaration, application, on clause, constraints)                |
| Extensions                     | ✅ Supported (methods, getters, setters, operators)                            |
| Async/await                    | ✅ Supported (async functions, await, Futures)                                 |
| Pattern matching               | ✅ Supported (switch/case, if-case, destructuring, list/map/record patterns)   |
| Collections (List, Map, Set)   | ✅ Supported (literals, spread, if/for, nested, null-aware, records)           |
| Top-level functions            | ✅ Supported (named, anonymous, closures, nested)                              |
| Getters/Setters                | ✅ Supported (instance, static, extension, bridge)                             |
| Static members                 | ✅ Supported (fields, methods, getters/setters, bridge)                        |
| Switch/case                    | ✅ Supported (classic, pattern, default, fallthrough, exhaustive checks)       |
| Try/catch/finally              | ✅ Supported (multiple catch, on/type, rethrow, stacktrace)                    |
| Imports                        | ✅ Supported (URIs, show/hide clauses for libraries defined in `sources`)      |
| Generics                       | ✅ Full support (generic classes/functions, type constraints, runtime validation) |
| Extension types                | ✅ Full support (representation fields, constructors, methods)                |
| Precompiled scripts & AST Cache| ✅ Full support (`compile`, `executeCompiled`, AST caching)                   |
| Execution limits & Timeouts    | ✅ Full support (`timeout`, `maxSteps`, sandbox exceptions)                   |
| Operator overloading           | ✅ Full support                    |
| FFI                            | 🚫 Not supported                                                               |
| Isolates (`dart:isolate`)      | ✅ Full support                                                               |
| Developer (`dart:developer`)   | ✅ Full support (Timeline, UserTag, Service, log, debugger, inspect)           |
| Reflection/Mirrors             | 🚫 Not supported                                                               |
| Records                        | ✅ Supported (positional, named, pattern matching)                             |
| String interpolation           | ✅ Supported                                                                   |
| Cascade notation (`..`)        | ✅ Supported                                                                   |
| Null safety                    | ✅ Supported (null-aware ops, checks, patterns)                                |
| Type tests (`is`, `as`)        | ✅ Supported                                                                   |
| Exception handling             | ✅ Supported (throw, rethrow, custom errors)                                   |

See the [documentation](#documentation) for details and limitations.

---

## Limitations

- Operator overloading is partially supported (via extensions, not via class operator methods).
- Some advanced Dart features (FFI, mirrors) are not available.
- The interpreter is not a full Dart VM: some language features may behave differently.

---

## Documentation

- [API Reference](https://pub.dev/documentation/d4rt/latest/)
- [Bridging Guide](BRIDGING_GUIDE.md)
- [Supported Features](#supported-features)
- [Examples](example/)

---

## Contributing

Contributions are welcome!  
Feel free to open issues, suggest features, or submit pull requests.

---

## License

MIT License. See [LICENSE](LICENSE).

---

## About the Name

**d4rt** is a play on the word "dart", using "4" as a stylized "A".  
It is pronounced exactly like "dart". 
