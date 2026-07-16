// flutter_test의 문자열 matcher `matches`와 우리 로직 함수 `matches`가 동명 → hide로 해소
import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:naduri_alimi/logic/matcher.dart';
import 'package:naduri_alimi/models/event.dart';

Event ev({String area = '서울', bool kid = true, bool? free, String title = '어린이 체험전', String cat = '전시'}) =>
    Event(
      id: 'x', source: 'seoul', title: title, place: '어딘가', area: area, sigungu: '',
      start: '2026-07-18', end: '2026-07-19', cat: cat, kid: kid, age: '',
      free: free, price: '', img: '', url: '', lat: null, lng: null, seen: '',
    );

void main() {
  test('kidOnly(기본 ON) — kid=false 행사는 제외', () {
    const s = Subscription();
    expect(matches(ev(kid: true), s), true);
    expect(matches(ev(kid: false), s), false);
    expect(matches(ev(kid: false), s.copyWith(kidOnly: false)), true);
  });

  test('freeOnly — null(모름)은 보수적으로 제외', () {
    final s = const Subscription().copyWith(freeOnly: true);
    expect(matches(ev(free: true), s), true);
    expect(matches(ev(free: false), s), false);
    expect(matches(ev(free: null), s), false);
  });

  test('지역 — 빈 셋=전체, 값끼리 OR', () {
    expect(matches(ev(area: '인천'), const Subscription()), true);
    final s = const Subscription().copyWith(areas: {'경기', '인천'});
    expect(matches(ev(area: '인천'), s), true);
    expect(matches(ev(area: '서울'), s), false);
  });

  test('키워드 — 제목/분류/장소 텍스트 매칭, 공백 키워드는 무시', () {
    final s = const Subscription().copyWith(keywords: ['인형극', '박물관']);
    expect(matches(ev(title: '피노키오 인형극'), s), true);
    expect(matches(ev(title: '재즈의 밤'), s), false);
    // 공백뿐인 키워드만 있으면 그룹 비활성(전체 허용) — 알림이 조용히 죽는 엣지 방지
    final blank = const Subscription().copyWith(keywords: ['  ']);
    expect(matches(ev(title: '아무거나'), blank), true);
  });

  test('isDefault — kidOnly=true는 기본 상태로 취급', () {
    expect(const Subscription().isDefault, true);
    expect(const Subscription().copyWith(freeOnly: true).isDefault, false);
    expect(const Subscription().copyWith(kidOnly: false).isDefault, false);
  });

  test('직렬화 왕복', () {
    final s = const Subscription(areas: {'경기'}, kidOnly: false, freeOnly: true, keywords: ['a']);
    final r = Subscription.fromJson(s.toJson());
    expect(r.areas, {'경기'});
    expect(r.kidOnly, false);
    expect(r.freeOnly, true);
    expect(r.keywords, ['a']);
  });
}
