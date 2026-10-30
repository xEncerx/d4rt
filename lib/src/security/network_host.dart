import 'dart:io';

// Literal addresses compare by value; hostnames remain lexical identities.
String normalizeNetworkHost(String host) {
  final literal = host.startsWith('[') && host.endsWith(']')
      ? host.substring(1, host.length - 1)
      : host;
  final address = InternetAddress.tryParse(literal);
  if (address == null) return host.toLowerCase();
  final bytes = InternetAddress.fromRawAddress(address.rawAddress).address;
  // The native scope is separate from rawAddress. Keep its lexical identity,
  // including case-sensitive interface names, rather than merging interfaces.
  final zone = literal.indexOf('%');
  return zone < 0
      ? bytes.toLowerCase()
      : '${bytes.toLowerCase()}${literal.substring(zone)}';
}
