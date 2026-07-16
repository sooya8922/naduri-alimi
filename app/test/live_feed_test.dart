@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/models/event.dart';
import 'package:naduri_alimi/services/feed_service.dart';

/// 라이브 feed 통합 테스트 — 실제 raw.githubusercontent.com 의 feed.json이
/// 현재 앱 모델로 파싱되는지 CI에서 확인(스키마 드리프트 조기 발견 — chwiso 패턴).
void main() {
  test('라이브 feed 파싱 + 최소 볼륨', () async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(FeedService.feedUrl));
    final res = await req.close();
    expect(res.statusCode, 200);
    final body = await res.transform(utf8.decoder).join();
    final feed = Feed.fromJson(json.decode(body) as Map<String, dynamic>);
    expect(feed.version, 1);
    expect(feed.events.length, greaterThan(50));
    // 세 지역이 모두 존재해야 한다(소스 하나가 죽으면 여기서 걸림)
    final areas = feed.events.map((e) => e.area).toSet();
    expect(areas.containsAll({'서울', '경기', '인천'}), true,
        reason: '지역 누락: $areas');
    // 아이 행사가 실제로 있는지(이 앱의 존재 이유)
    expect(feed.events.where((e) => e.kid).length, greaterThan(20));
  }, timeout: const Timeout(Duration(minutes: 1)));
}
