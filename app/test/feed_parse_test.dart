import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/models/event.dart';

const sampleFeed = '''
{
  "version": 1,
  "generated_at": "2026-07-15 06:30:00",
  "sources": {"seoul": "ok:300", "kopis": "ok:200", "kcisa": "ok:90", "fstvl": "error:HTTPError"},
  "counts": {"events": 2, "new": 1, "kid": 1},
  "events": [
    {"id": "kopis:PF1", "source": "kopis", "title": "어린이 인형극", "place": "수원문화재단",
     "area": "경기", "sigungu": "수원시", "start": "2026-07-18", "end": "2026-07-19",
     "cat": "연극", "kid": true, "age": "36개월 이상", "free": false, "price": "전석 20,000원",
     "img": "http://img", "url": "http://url", "lat": 37.28, "lng": 127.01, "seen": "2026-07-14 06:30"},
    {"id": "seoul:abc", "source": "seoul", "title": "재즈 콘서트", "place": "세종문화회관",
     "area": "서울", "sigungu": "종로구", "start": "2026-08-01", "end": "2026-08-01",
     "cat": "콘서트", "kid": false, "age": "", "free": null, "price": "",
     "img": "", "url": "", "lat": null, "lng": null, "seen": "2026-07-15 06:30"}
  ],
  "new": [
    {"id": "kopis:PF1", "title": "어린이 인형극", "area": "경기", "sigungu": "수원시",
     "start": "2026-07-18", "end": "2026-07-19", "kid": true, "free": false,
     "url": "http://url", "seen_at": "2026-07-14 06:30"}
  ]
}
''';

void main() {
  test('feed 파싱 — 필드/타입 보존', () {
    final f = Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>);
    expect(f.version, 1);
    expect(f.events.length, 2);
    expect(f.newEvents.length, 1);
    expect(f.sources['fstvl'], startsWith('error'));

    final e = f.events[0];
    expect(e.kid, true);
    expect(e.free, false); // 3값 보존
    expect(f.events[1].free, isNull); // null(모름) 보존이 중요
    expect(e.hasLocation, true);
    expect(f.events[1].hasLocation, false);
  });

  test('지원하지 않는 feed version은 명시적으로 던진다', () {
    expect(() => Feed.fromJson({'version': 2}), throwsFormatException);
  });

  test('overlaps — 종료일은 그날 23:59까지 유효', () {
    final f = Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>);
    final e = f.events[0]; // 7/18~7/19
    // 주말(7/18~7/19)과 겹침
    expect(e.overlaps(DateTime(2026, 7, 18), DateTime(2026, 7, 19, 23, 59)), true);
    // 종료 당일 낮 시각 기준으로도 아직 안 끝남
    expect(e.ended(DateTime(2026, 7, 19, 15, 0)), false);
    expect(e.ended(DateTime(2026, 7, 20, 0, 1)), true);
    // 다음 주말과는 안 겹침
    expect(e.overlaps(DateTime(2026, 7, 25), DateTime(2026, 7, 26, 23, 59)), false);
  });

  test('periodLabel — 하루짜리/기간 표기', () {
    final f = Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>);
    expect(f.events[0].periodLabel, '7/18 ~ 7/19');
    expect(f.events[1].periodLabel, '8/1');
  });
}
