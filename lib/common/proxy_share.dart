import 'dart:convert';

import 'string.dart';
import 'yaml.dart';

const supportedProxyShareSchemes = {
  'vless',
  'vmess',
  'hysteria2',
  'hy2',
  'tuic',
  'anytls',
};

enum ProxyShareFailure { invalid, unsupportedScheme }

final class ProxyShareException implements Exception {
  final ProxyShareFailure failure;
  final int line;
  final String scheme;

  const ProxyShareException({
    required this.failure,
    required this.line,
    required this.scheme,
  });

  @override
  String toString() {
    return switch (failure) {
      ProxyShareFailure.invalid => 'Invalid $scheme proxy link on line $line',
      ProxyShareFailure.unsupportedScheme =>
        'Unsupported proxy link scheme on line $line: $scheme',
    };
  }
}

bool isProfileImportInput(String input) {
  final value = input.trim();
  if (value.isUrl) {
    return true;
  }
  final links = _shareLines(input).toList();
  return links.isNotEmpty &&
      links.every((item) {
        final scheme = _schemeOf(_normalizeLink(item.value));
        return supportedProxyShareSchemes.contains(scheme);
      });
}

({String label, String yaml}) parseProxyShareInput(String input) {
  final links = _shareLines(input).toList();
  if (links.isEmpty) {
    throw const ProxyShareException(
      failure: ProxyShareFailure.invalid,
      line: 1,
      scheme: '',
    );
  }

  final proxies = <Map<String, Object?>>[];
  for (final item in links) {
    final link = _normalizeLink(item.value);
    final scheme = _schemeOf(link);
    if (!supportedProxyShareSchemes.contains(scheme)) {
      throw ProxyShareException(
        failure: ProxyShareFailure.unsupportedScheme,
        line: item.line,
        scheme: scheme,
      );
    }
    try {
      proxies.add(switch (scheme) {
        'vless' => _parseVless(link, item.line),
        'vmess' => _parseVmess(link, item.line),
        'hysteria2' || 'hy2' => _parseHysteria2(link, item.line),
        'tuic' => _parseTuic(link, item.line),
        'anytls' => _parseAnytls(link, item.line),
        _ => throw StateError('unreachable scheme'),
      });
    } on ProxyShareException {
      rethrow;
    } catch (_) {
      throw ProxyShareException(
        failure: ProxyShareFailure.invalid,
        line: item.line,
        scheme: scheme,
      );
    }
  }

  _makeNamesUnique(proxies);
  final names = proxies.map((proxy) => proxy['name']! as String).toList();
  final groupName = _uniqueName('Proxy', names.toSet());
  final config = <String, Object?>{
    'proxies': proxies,
    'proxy-groups': [
      {
        'name': groupName,
        'type': 'select',
        'proxies': [...names, 'DIRECT'],
      },
    ],
    'rules': ['MATCH,$groupName'],
  };
  final label = names.length == 1
      ? names.single
      : '${names.first} +${names.length - 1}';
  return (label: label, yaml: yaml.encode(config));
}

Iterable<({int line, String value})> _shareLines(String input) sync* {
  final lines = input.split(RegExp(r'\r?\n'));
  for (int index = 0; index < lines.length; index++) {
    final value = lines[index].trim();
    if (value.isNotEmpty) {
      yield (line: index + 1, value: value);
    }
  }
}

String _normalizeLink(String value) {
  return value.replaceAllMapped(
    RegExp(r'\\([:/@_?&=#])'),
    (match) => match.group(1)!,
  );
}

String _schemeOf(String link) {
  final separator = link.indexOf('://');
  if (separator <= 0) {
    return '';
  }
  return link.substring(0, separator).toLowerCase();
}

Map<String, Object?> _parseVless(String link, int line) {
  final uri = _parseUri(link, 'vless', line);
  final params = uri.queryParameters;
  final proxy =
      _baseProxy(name: _linkName(uri, 'VLESS $line'), type: 'vless', uri: uri)
        ..['uuid'] = _requiredUserInfo(uri)
        ..['udp'] = _boolParameter(params, const ['udp']) ?? true;

  final flow = _parameter(params, const ['flow']);
  if (flow != null) {
    proxy['flow'] = flow;
  }
  final packetEncoding = _parameter(params, const [
    'packetEncoding',
    'packet-encoding',
  ]);
  if (packetEncoding != null) {
    proxy['packet-encoding'] = packetEncoding;
  }

  final network =
      _parameter(params, const ['type', 'network'])?.toLowerCase() ?? 'tcp';
  _applyTransport(proxy, network, params);

  final security =
      _parameter(params, const ['security'])?.toLowerCase() ?? 'none';
  if (security == 'tls' || security == 'reality') {
    proxy['tls'] = true;
    _applyXrayTlsOptions(proxy, params);
  }
  if (security == 'reality') {
    final publicKey = _requiredParameter(params, const ['pbk', 'public-key']);
    final realityOptions = <String, Object?>{'public-key': publicKey};
    final shortId = _parameter(params, const ['sid', 'short-id']);
    if (shortId != null) {
      realityOptions['short-id'] = shortId;
    }
    proxy['reality-opts'] = realityOptions;
  }
  return proxy;
}

Map<String, Object?> _parseVmess(String link, int line) {
  final payloadWithFragment = link.substring('vmess://'.length);
  final fragmentIndex = payloadWithFragment.indexOf('#');
  final payload = fragmentIndex == -1
      ? payloadWithFragment
      : payloadWithFragment.substring(0, fragmentIndex);
  final decoded = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(payload))),
  );
  if (decoded is! Map) {
    throw const FormatException('VMess payload must be an object');
  }
  final data = decoded.map((key, value) => MapEntry(key.toString(), value));
  final params = data.map(
    (key, value) => MapEntry(key, value?.toString() ?? ''),
  );
  final proxy = <String, Object?>{
    'name': _mapString(data, 'ps') ?? 'VMESS $line',
    'type': 'vmess',
    'server': _requiredMapString(data, 'add'),
    'port': _requiredPort(data['port']),
    'uuid': _requiredMapString(data, 'id'),
    'alterId': _intValue(data['aid']) ?? 0,
    'cipher': _mapString(data, 'scy') ?? 'auto',
    'udp': _boolValue(data['udp']) ?? true,
  };
  final network = _mapString(data, 'net')?.toLowerCase() ?? 'tcp';
  _applyTransport(proxy, network, params);

  final tls = data['tls'];
  if (_securityEnabled(tls)) {
    proxy['tls'] = true;
    _applyXrayTlsOptions(proxy, params);
  }
  return proxy;
}

Map<String, Object?> _parseHysteria2(String link, int line) {
  final scheme = _schemeOf(link);
  final uri = _parseUri(link, scheme, line);
  final params = uri.queryParameters;
  final proxy = _baseProxy(
    name: _linkName(uri, 'HYSTERIA2 $line'),
    type: 'hysteria2',
    uri: uri,
  )..['password'] = _requiredUserInfo(uri);
  _applyNativeTlsOptions(proxy, params);

  final obfs = _parameter(params, const ['obfs']);
  if (obfs != null) {
    proxy['obfs'] = obfs;
  }
  final obfsPassword = _parameter(params, const [
    'obfs-password',
    'obfsPassword',
  ]);
  if (obfsPassword != null) {
    proxy['obfs-password'] = obfsPassword;
  }
  final fingerprint = _parameter(params, const ['pinSHA256', 'fingerprint']);
  if (fingerprint != null) {
    proxy['fingerprint'] = fingerprint;
  }
  return proxy;
}

Map<String, Object?> _parseTuic(String link, int line) {
  final uri = _parseUri(link, 'tuic', line);
  final credentials = _credentials(uri);
  final params = uri.queryParameters;
  final proxy =
      _baseProxy(name: _linkName(uri, 'TUIC $line'), type: 'tuic', uri: uri)
        ..['uuid'] = credentials.username
        ..['password'] = credentials.password;
  _applyNativeTlsOptions(proxy, params);

  _copyParameter(proxy, 'congestion-controller', params, const [
    'congestion-controller',
    'congestion_control',
    'congestionControl',
  ]);
  _copyParameter(proxy, 'udp-relay-mode', params, const [
    'udp-relay-mode',
    'udp_relay_mode',
    'udpRelayMode',
  ]);
  _copyBooleanParameter(proxy, 'reduce-rtt', params, const [
    'reduce-rtt',
    'reduce_rtt',
    'reduceRtt',
  ]);
  return proxy;
}

Map<String, Object?> _parseAnytls(String link, int line) {
  final uri = _parseUri(link, 'anytls', line);
  final params = uri.queryParameters;
  final proxy =
      _baseProxy(name: _linkName(uri, 'ANYTLS $line'), type: 'anytls', uri: uri)
        ..['password'] = _requiredUserInfo(uri)
        ..['udp'] = _boolParameter(params, const ['udp']) ?? true;
  _applyNativeTlsOptions(proxy, params, clientFingerprint: true);
  _copyIntegerParameter(proxy, 'idle-session-check-interval', params, const [
    'idle-session-check-interval',
    'idle_session_check_interval',
  ]);
  _copyIntegerParameter(proxy, 'idle-session-timeout', params, const [
    'idle-session-timeout',
    'idle_session_timeout',
  ]);
  _copyIntegerParameter(proxy, 'min-idle-session', params, const [
    'min-idle-session',
    'min_idle_session',
  ]);
  return proxy;
}

Uri _parseUri(String link, String scheme, int line) {
  final uri = Uri.parse(link);
  if (uri.scheme.toLowerCase() != scheme ||
      uri.host.isEmpty ||
      !uri.hasPort ||
      uri.port <= 0 ||
      uri.port > 65535) {
    throw ProxyShareException(
      failure: ProxyShareFailure.invalid,
      line: line,
      scheme: scheme,
    );
  }
  return uri;
}

Map<String, Object?> _baseProxy({
  required String name,
  required String type,
  required Uri uri,
}) {
  return {'name': name, 'type': type, 'server': uri.host, 'port': uri.port};
}

String _linkName(Uri uri, String fallback) {
  if (uri.fragment.isEmpty) {
    return fallback;
  }
  final name = Uri.decodeComponent(uri.fragment).trim();
  return name.isEmpty ? fallback : name;
}

String _requiredUserInfo(Uri uri) {
  if (uri.userInfo.isEmpty) {
    throw const FormatException('Missing credentials');
  }
  final value = Uri.decodeComponent(uri.userInfo);
  if (value.isEmpty) {
    throw const FormatException('Missing credentials');
  }
  return value;
}

({String username, String password}) _credentials(Uri uri) {
  final separator = uri.userInfo.indexOf(':');
  if (separator <= 0 || separator == uri.userInfo.length - 1) {
    throw const FormatException('Missing username or password');
  }
  return (
    username: Uri.decodeComponent(uri.userInfo.substring(0, separator)),
    password: Uri.decodeComponent(uri.userInfo.substring(separator + 1)),
  );
}

void _applyTransport(
  Map<String, Object?> proxy,
  String network,
  Map<String, String> params,
) {
  final normalizedNetwork = network == 'raw' ? 'tcp' : network;
  proxy['network'] = normalizedNetwork;
  final host = _parameter(params, const ['host']);
  final path = _parameter(params, const ['path']);
  switch (normalizedNetwork) {
    case 'ws':
      final options = <String, Object?>{'path': path ?? '/'};
      if (host != null) {
        options['headers'] = {'Host': host};
      }
      final earlyData = _intParameter(params, const ['ed', 'max-early-data']);
      if (earlyData != null) {
        options['max-early-data'] = earlyData;
      }
      final earlyDataHeader = _parameter(params, const [
        'eh',
        'early-data-header-name',
      ]);
      if (earlyDataHeader != null) {
        options['early-data-header-name'] = earlyDataHeader;
      }
      proxy['ws-opts'] = options;
    case 'grpc':
      final serviceName = _parameter(params, const [
        'serviceName',
        'service_name',
        'grpc-service-name',
      ]);
      proxy['grpc-opts'] = <String, Object?>{'grpc-service-name': ?serviceName};
    case 'h2':
      proxy['h2-opts'] = <String, Object?>{
        if (host != null) 'host': [host],
        'path': ?path,
      };
    case 'http':
      proxy['http-opts'] = <String, Object?>{
        if (path != null) 'path': [path],
        if (host != null)
          'headers': {
            'Host': [host],
          },
      };
    default:
      break;
  }
}

void _applyXrayTlsOptions(
  Map<String, Object?> proxy,
  Map<String, String> params,
) {
  final serverName = _parameter(params, const ['sni', 'servername']);
  if (serverName != null) {
    proxy['servername'] = serverName;
  }
  final fingerprint = _parameter(params, const ['fp', 'client-fingerprint']);
  if (fingerprint != null) {
    proxy['client-fingerprint'] = fingerprint;
  }
  _applyTlsCommon(proxy, params);
}

void _applyNativeTlsOptions(
  Map<String, Object?> proxy,
  Map<String, String> params, {
  bool clientFingerprint = false,
}) {
  final serverName = _parameter(params, const ['sni', 'servername']);
  if (serverName != null) {
    proxy['sni'] = serverName;
  }
  if (clientFingerprint) {
    final fingerprint = _parameter(params, const ['fp', 'client-fingerprint']);
    if (fingerprint != null) {
      proxy['client-fingerprint'] = fingerprint;
    }
  }
  _applyTlsCommon(proxy, params);
}

void _applyTlsCommon(Map<String, Object?> proxy, Map<String, String> params) {
  final skipCertificateVerification = _boolParameter(params, const [
    'insecure',
    'allowInsecure',
    'allow_insecure',
    'skip-cert-verify',
  ]);
  if (skipCertificateVerification != null) {
    proxy['skip-cert-verify'] = skipCertificateVerification;
  }
  final alpn = _parameter(params, const ['alpn']);
  if (alpn != null) {
    final values = alpn
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (values.isNotEmpty) {
      proxy['alpn'] = values;
    }
  }
}

String? _parameter(Map<String, String> params, List<String> names) {
  final normalizedNames = names.map((name) => name.toLowerCase()).toSet();
  for (final entry in params.entries) {
    if (normalizedNames.contains(entry.key.toLowerCase()) &&
        entry.value.trim().isNotEmpty) {
      return entry.value.trim();
    }
  }
  return null;
}

String _requiredParameter(Map<String, String> params, List<String> names) {
  final value = _parameter(params, names);
  if (value == null) {
    throw const FormatException('Missing required parameter');
  }
  return value;
}

bool? _boolParameter(Map<String, String> params, List<String> names) {
  final normalizedNames = names.map((name) => name.toLowerCase()).toSet();
  for (final entry in params.entries) {
    if (normalizedNames.contains(entry.key.toLowerCase())) {
      return _boolValue(entry.value);
    }
  }
  return null;
}

int? _intParameter(Map<String, String> params, List<String> names) {
  final value = _parameter(params, names);
  return value == null ? null : int.tryParse(value);
}

bool? _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return switch (value.toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => null,
    };
  }
  return null;
}

bool _securityEnabled(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().trim().toLowerCase();
  return text != null && text.isNotEmpty && text != 'none' && text != '0';
}

int? _intValue(Object? value) {
  return switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

int _requiredPort(Object? value) {
  final port = _intValue(value);
  if (port == null || port <= 0 || port > 65535) {
    throw const FormatException('Invalid port');
  }
  return port;
}

String? _mapString(Map<String, Object?> data, String key) {
  final value = data[key]?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

String _requiredMapString(Map<String, Object?> data, String key) {
  final value = _mapString(data, key);
  if (value == null) {
    throw FormatException('Missing $key');
  }
  return value;
}

void _copyParameter(
  Map<String, Object?> proxy,
  String key,
  Map<String, String> params,
  List<String> names,
) {
  final value = _parameter(params, names);
  if (value != null) {
    proxy[key] = value;
  }
}

void _copyBooleanParameter(
  Map<String, Object?> proxy,
  String key,
  Map<String, String> params,
  List<String> names,
) {
  final value = _boolParameter(params, names);
  if (value != null) {
    proxy[key] = value;
  }
}

void _copyIntegerParameter(
  Map<String, Object?> proxy,
  String key,
  Map<String, String> params,
  List<String> names,
) {
  final value = _intParameter(params, names);
  if (value != null) {
    proxy[key] = value;
  }
}

void _makeNamesUnique(List<Map<String, Object?>> proxies) {
  final usedNames = <String>{
    'DIRECT',
    'REJECT',
    'PASS',
    'GLOBAL',
    'COMPATIBLE',
  };
  for (final proxy in proxies) {
    final name = proxy['name']! as String;
    final uniqueName = _uniqueName(name, usedNames);
    proxy['name'] = uniqueName;
    usedNames.add(uniqueName);
  }
}

String _uniqueName(String name, Set<String> usedNames) {
  if (!usedNames.contains(name)) {
    return name;
  }
  int suffix = 1;
  while (usedNames.contains('$name($suffix)')) {
    suffix++;
  }
  return '$name($suffix)';
}
