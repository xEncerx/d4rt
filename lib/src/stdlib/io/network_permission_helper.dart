import 'dart:io';

import 'package:d4rt/d4rt.dart';
import 'package:d4rt/src/exceptions.dart' show InterpreterPolicyError;

final _proxyEndpoint = RegExp(
  r'^PROXY\s+(\[[^\]]+\]|[^\s:/;@\[\]?#\\]+):([0-9]+)$',
);

bool hasUnrestrictedNetworkConnect(InterpreterVisitor? visitor) =>
    visitor?.moduleLoader.d4rt?.checkPermission({
      'type': 'network',
      'connect': true,
    }) ??
    false;

void checkNetworkPermission(
  InterpreterVisitor? visitor,
  String operation, {
  Object? host,
  int? port,
}) {
  final address = host is InternetAddress ? host.address : host;
  if (visitor?.moduleLoader.d4rt?.checkPermission({
        'type': 'network',
        operation: true,
        'host': ?address,
        'port': ?port,
      }) ??
      false) {
    return;
  }
  throw InterpreterPolicyError(
    'Network permission denied for $operation '
    '${address ?? "network information"}${port == null ? "" : ":$port"}. '
    'Grant an appropriate NetworkPermission.',
  );
}

// Stream-socket String inputs decode one RFC 6874 "25" after '%' before
// parsing. Constructed InternetAddress values, DNS and UDP binding do not.
void checkSocketPermission(
  InterpreterVisitor? visitor,
  String operation, {
  Object? host,
  int? port,
}) {
  if (host is String &&
      host.length >= 7 &&
      host.startsWith('fe') &&
      '89ab'.contains(host[2])) {
    final zone = host.indexOf('%');
    if (zone >= 0 && host.startsWith('25', zone + 1)) {
      host = host.replaceRange(zone + 1, zone + 3, '');
    }
  }
  checkNetworkPermission(visitor, operation, host: host, port: port);
}

int effectiveHttpPort(int port, {bool secure = false}) => port == 0
    ? (secure ? HttpClient.defaultHttpsPort : HttpClient.defaultHttpPort)
    : port;

void checkNetworkUri(InterpreterVisitor? visitor, Uri uri) {
  checkSocketPermission(
    visitor,
    'connect',
    host: uri.host,
    port: effectiveHttpPort(uri.port, secure: uri.isScheme('https')),
  );
}

// Validate the entire native proxy fallback list before any candidate is used.
String checkedProxy(InterpreterVisitor? visitor, Uri uri, String rules) {
  checkNetworkUri(visitor, uri);
  if (rules.trim() == 'DIRECT') return 'DIRECT';
  final validated = <String>[];
  for (final rule in rules.split(';')) {
    final directive = rule.trim();
    if (directive == 'DIRECT') {
      validated.add('DIRECT');
      continue;
    }
    final match = _proxyEndpoint.firstMatch(directive);
    if (match == null) {
      throw RuntimeError(
        'Invalid proxy rule: "$directive". '
        'Expected DIRECT or PROXY host:port.',
      );
    }
    final host = match[1]!;
    final port = int.tryParse(match[2]!);
    if (port == null ||
        port < 1 ||
        port > 65535 ||
        (host.startsWith('[') &&
            InternetAddress.tryParse(
                  host.substring(1, host.length - 1),
                )?.type !=
                InternetAddressType.IPv6)) {
      throw RuntimeError('Invalid proxy endpoint: "$directive".');
    }
    checkSocketPermission(
      visitor,
      'connect',
      host: host.startsWith('[') ? host.substring(1, host.length - 1) : host,
      port: port,
    );
    validated.add('PROXY $host:$port');
  }
  return validated.join('; ');
}
