import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/logic/affiliate_links.dart';

void main() {
  test('MRT 검색 링크 — 브릿지 경유 + mylink_id + 검색어 인코딩', () {
    final url = buildMrtSearchLink('렛츠런파크 서울');
    final uri = Uri.parse(url);
    expect(uri.host, 'www.myrealtrip.com');
    expect(uri.path, '/main/bridge/marketing');

    final ret = Uri.parse(uri.queryParameters['return_url']!);
    expect(ret.host, 'www.myrealtrip.com');
    expect(ret.path, '/search');
    expect(ret.queryParameters['q'], '렛츠런파크 서울');
    expect(ret.queryParameters['mylink_id'], mrtMylinkId);
    expect(ret.queryParameters['utm_source'], 'mktpartner');
    expect(ret.queryParameters['t_scope'], '86400');
  });

  test('특수문자 장소명도 URL이 깨지지 않는다', () {
    final url = buildMrtSearchLink('허브아일랜드 & 불빛동산 (포천)');
    final ret = Uri.parse(Uri.parse(url).queryParameters['return_url']!);
    expect(ret.queryParameters['q'], '허브아일랜드 & 불빛동산 (포천)');
  });
}
