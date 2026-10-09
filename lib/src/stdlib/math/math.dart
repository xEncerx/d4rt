import 'dart:math';
import 'package:d4rt/d4rt.dart';

class MathMath {
  static void register(Environment environment) {
    // Constants
    environment.define('pi', pi);
    environment.define('e', e);
    environment.define('sqrt2', sqrt2);
    environment.define('sqrt1_2', sqrt1_2);
    environment.define('log2e', log2e);
    environment.define('log10e', log10e);
    environment.define('ln2', ln2);
    environment.define('ln10', ln10);

    // Functions
    environment.defineFunction(
        'sin',
        NativeFunction((visitor, arguments, _, __) => sin(arguments[0] as num),
            arity: 1, name: 'sin'));
    environment.defineFunction(
        'cos',
        NativeFunction((visitor, arguments, _, __) => cos(arguments[0] as num),
            arity: 1, name: 'cos'));
    environment.defineFunction(
        'tan',
        NativeFunction((visitor, arguments, _, __) => tan(arguments[0] as num),
            arity: 1, name: 'tan'));
    environment.defineFunction(
        'asin',
        NativeFunction((visitor, arguments, _, __) => asin(arguments[0] as num),
            arity: 1, name: 'asin'));
    environment.defineFunction(
        'acos',
        NativeFunction((visitor, arguments, _, __) => acos(arguments[0] as num),
            arity: 1, name: 'acos'));
    environment.defineFunction(
        'atan',
        NativeFunction((visitor, arguments, _, __) => atan(arguments[0] as num),
            arity: 1, name: 'atan'));
    environment.defineFunction(
        'atan2',
        NativeFunction(
            (visitor, arguments, _, __) =>
                atan2(arguments[0] as num, arguments[1] as num),
            arity: 2,
            name: 'atan2'));
    environment.defineFunction(
        'sqrt',
        NativeFunction((visitor, arguments, _, __) => sqrt(arguments[0] as num),
            arity: 1, name: 'sqrt'));
    environment.defineFunction(
        'exp',
        NativeFunction((visitor, arguments, _, __) => exp(arguments[0] as num),
            arity: 1, name: 'exp'));
    environment.defineFunction(
        'log',
        NativeFunction((visitor, arguments, _, __) => log(arguments[0] as num),
            arity: 1, name: 'log'));
    environment.defineFunction(
        'pow',
        NativeFunction(
            (visitor, arguments, _, __) =>
                pow(arguments[0] as num, arguments[1] as num),
            arity: 2,
            name: 'pow'));
    environment.defineFunction(
        'max',
        NativeFunction(
            (visitor, arguments, _, __) =>
                max(arguments[0] as num, arguments[1] as num),
            arity: 2,
            name: 'max'));
    environment.defineFunction(
        'min',
        NativeFunction(
            (visitor, arguments, _, __) =>
                min(arguments[0] as num, arguments[1] as num),
            arity: 2,
            name: 'min'));
  }
}
