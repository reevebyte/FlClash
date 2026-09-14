import 'dart:convert';

import 'package:fl_clash/common/proxy_share.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('accepts remote profile URLs and supported proxy links', () {
    expect(isProfileImportInput('https://example.com/profile.yaml'), isTrue);
    expect(
      isProfileImportInput(
        r'vless\://user-id\@example.com:443?security=reality&pbk=key#node',
      ),
      isTrue,
    );
    expect(isProfileImportInput('trojan://secret@example.com:443'), isFalse);
    expect(isProfileImportInput('plain text'), isFalse);
  });

  test('converts the supported proxy share formats into one profile', () {
    final vmessPayload = base64.encode(
      utf8.encode(
        jsonEncode({
          'v': '2',
          'ps': 'vm-ws',
          'add': 'vm.example.com',
          'port': '2096',
          'id': 'vmess-id',
          'aid': '0',
          'scy': 'auto',
          'net': 'ws',
          'host': 'cdn.example.com',
          'path': '/vm',
          'tls': 'tls',
          'sni': 'vm.example.com',
          'fp': 'chrome',
        }),
      ),
    );
    final input =
        '''
vless://vless-id@reality.example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=apple.com&fp=chrome&pbk=public-key&sid=short-id&type=tcp#vl-reality
vmess://$vmessPayload
hysteria2://hy-password@hy.example.com:8443?alpn=h3&insecure=0&sni=hy.example.com#hy2
tuic://tuic-id:tuic-password@tuic.example.com:443?congestion_control=bbr&udp_relay_mode=native&alpn=h3&sni=tuic.example.com&allowInsecure=0#tuic
anytls://any-password@any.example.com:443?sni=any.example.com&fp=chrome&allow_insecure=0#anytls
''';

    final imported = parseProxyShareInput(input);
    final config = loadYaml(imported.yaml) as YamlMap;
    final proxies = config['proxies'] as YamlList;

    expect(proxies, hasLength(5));
    expect(imported.label, 'vl-reality +4');

    final vless = proxies[0] as YamlMap;
    expect(vless['type'], 'vless');
    expect(vless['server'], 'reality.example.com');
    expect(vless['port'], 443);
    expect(vless['uuid'], 'vless-id');
    expect(vless['flow'], 'xtls-rprx-vision');
    expect(vless['network'], 'tcp');
    expect(vless['tls'], isTrue);
    expect(vless['servername'], 'apple.com');
    expect(vless['client-fingerprint'], 'chrome');
    expect((vless['reality-opts'] as YamlMap)['public-key'], 'public-key');
    expect((vless['reality-opts'] as YamlMap)['short-id'], 'short-id');

    final vmess = proxies[1] as YamlMap;
    expect(vmess['type'], 'vmess');
    expect(vmess['alterId'], 0);
    expect(vmess['network'], 'ws');
    expect(vmess['tls'], isTrue);
    expect((vmess['ws-opts'] as YamlMap)['path'], '/vm');
    expect(
      ((vmess['ws-opts'] as YamlMap)['headers'] as YamlMap)['Host'],
      'cdn.example.com',
    );

    final hysteria2 = proxies[2] as YamlMap;
    expect(hysteria2['type'], 'hysteria2');
    expect(hysteria2['password'], 'hy-password');
    expect(hysteria2['sni'], 'hy.example.com');
    expect(hysteria2['skip-cert-verify'], isFalse);
    expect(hysteria2['alpn'], ['h3']);

    final tuic = proxies[3] as YamlMap;
    expect(tuic['type'], 'tuic');
    expect(tuic['uuid'], 'tuic-id');
    expect(tuic['password'], 'tuic-password');
    expect(tuic['congestion-controller'], 'bbr');
    expect(tuic['udp-relay-mode'], 'native');
    expect(tuic['skip-cert-verify'], isFalse);

    final anytls = proxies[4] as YamlMap;
    expect(anytls['type'], 'anytls');
    expect(anytls['password'], 'any-password');
    expect(anytls['client-fingerprint'], 'chrome');
    expect(anytls['skip-cert-verify'], isFalse);

    final group = (config['proxy-groups'] as YamlList).single as YamlMap;
    expect(group['type'], 'select');
    expect(group['proxies'], [
      'vl-reality',
      'vm-ws',
      'hy2',
      'tuic',
      'anytls',
      'DIRECT',
    ]);
    expect(config['rules'], [
      'DOMAIN,localhost,DIRECT',
      'DOMAIN-SUFFIX,local,DIRECT',
      'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
      'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
      'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
      'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
      'IP-CIDR,100.64.0.0/10,DIRECT,no-resolve',
      'IP-CIDR6,::1/128,DIRECT,no-resolve',
      'IP-CIDR6,fc00::/7,DIRECT,no-resolve',
      'IP-CIDR6,fe80::/10,DIRECT,no-resolve',
      'MATCH,Proxy',
    ]);
  });

  test('normalizes escaped links and makes duplicate names unique', () {
    final imported = parseProxyShareInput('''
vless\\://first\\@one.example.com:443?security=tls&sni=one.example.com#same
vless://second@two.example.com:443?security=tls&sni=two.example.com#same
''');
    final config = loadYaml(imported.yaml) as YamlMap;
    final proxies = config['proxies'] as YamlList;

    expect((proxies[0] as YamlMap)['name'], 'same');
    expect((proxies[1] as YamlMap)['name'], 'same(1)');
  });

  test('reports the line containing an invalid supported link', () {
    expect(
      () => parseProxyShareInput('''
vless://id@example.com:443?security=tls#valid
tuic://missing-password@example.com:443#invalid
'''),
      throwsA(
        isA<ProxyShareException>()
            .having(
              (error) => error.failure,
              'failure',
              ProxyShareFailure.invalid,
            )
            .having((error) => error.line, 'line', 2)
            .having((error) => error.scheme, 'scheme', 'tuic'),
      ),
    );
  });

  test('reports unsupported schemes without exposing the link contents', () {
    expect(
      () => parseProxyShareInput('trojan://secret@example.com:443#private'),
      throwsA(
        isA<ProxyShareException>()
            .having(
              (error) => error.failure,
              'failure',
              ProxyShareFailure.unsupportedScheme,
            )
            .having((error) => error.scheme, 'scheme', 'trojan')
            .having(
              (error) => error.toString(),
              'message',
              isNot(contains('secret')),
            ),
      ),
    );
  });
}
