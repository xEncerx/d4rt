import 'dart:isolate';

void main(List<String> args, Object? message) {
  final receive = ReceivePort();
  if (message is SendPort) message.send([args, receive.sendPort]);
  receive.listen((message) {
    if (message == 'close') receive.close();
  });
}
