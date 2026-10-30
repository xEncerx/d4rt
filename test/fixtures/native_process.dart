import 'dart:io';

Future<void> main(List<String> args) async {
  switch (args.first) {
    case 'echo':
      stdout.writeln(args.skip(1).join(' '));
    case 'env':
      stdout.writeln(Platform.environment[args[1]]);
    case 'cwd':
      stdout.writeln(Directory.current.path);
    case 'stdin':
      await stdout.addStream(stdin);
    case 'wait':
      stdout.writeln('ready');
      await Future<void>.delayed(const Duration(minutes: 2));
    case 'mark':
      File(args[1]).writeAsStringSync('launched');
      stdout.writeln(args.skip(2).join('|'));
    default:
      throw ArgumentError('Unknown fixture mode: ${args.first}');
  }
}
