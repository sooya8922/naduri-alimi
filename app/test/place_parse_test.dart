import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/logic/map_links.dart';
import 'package:naduri_alimi/models/place.dart';

const samplePlaces = '''
{
  "version": 1,
  "generated_at": "2026-07-16 15:00:00",
  "counts": {"places": 2, "서울": 0, "경기": 2, "인천": 0},
  "places": [
    {"id": "127695", "title": "허브아일랜드", "area": "경기", "sigungu": "포천시",
     "cat": "테마파크", "img": "http://img", "addr": "경기도 포천시 신북면",
     "lat": 38.0, "lng": 127.2, "stroller": "있음", "age": "6세 이상",
     "exp": "허브비누 만들기", "rest": "매주 수요일", "score": 5},
    {"id": "2", "title": "어느 박물관", "area": "경기", "sigungu": "수원시",
     "cat": "박물관", "img": "", "addr": "경기도 수원시",
     "lat": null, "lng": null, "stroller": "", "age": "", "exp": "", "rest": "", "score": 2}
  ]
}
''';

void main() {
  test('places 파싱 — 필드/좌표/유모차', () {
    final p = Places.fromJson(json.decode(samplePlaces) as Map<String, dynamic>);
    expect(p.places.length, 2);
    final herb = p.places[0];
    expect(herb.title, '허브아일랜드');
    expect(herb.hasLocation, true);
    expect(herb.strollerOk, true);
    expect(p.places[1].hasLocation, false);
    expect(p.places[1].strollerOk, false);
  });

  test('지원하지 않는 places version은 던진다', () {
    expect(() => Places.fromJson({'version': 9}), throwsFormatException);
  });

  test('지도 후보 — 카카오→네이버→구글 순서, 좌표 삽입', () {
    final c = buildMapCandidates(127.2, 38.0);
    expect(c.length, 3);
    expect(c[0], startsWith('kakaomap://'));
    expect(c[0], contains('38.0,127.2'));
    expect(c[1], startsWith('nmap://'));
    expect(c[2], contains('google.com/maps'));
  });
}
