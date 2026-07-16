import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/logic/matcher.dart';
import 'package:naduri_alimi/logic/notif_planner.dart';
import 'package:naduri_alimi/models/event.dart';

Event ev(String id, {String area = '서울', bool kid = true, String start = '2026-07-18', String end = '2026-07-19', bool? free}) =>
    Event(
      id: id, source: 'seoul', title: '행사 $id', place: 'p', area: area, sigungu: '구',
      start: start, end: end, cat: '전시', kid: kid, age: '', free: free, price: '',
      img: '', url: 'http://u/$id', lat: null, lng: null, seen: '',
    );

NewEvent ne(Event e) => NewEvent(
    id: e.id, title: e.title, area: e.area, sigungu: e.sigungu,
    start: e.start, end: e.end, kid: e.kid, free: e.free, url: e.url, seenAt: '2026-07-15 06:30');

Feed feedOf(List<Event> events, List<Event> news) => Feed(
    version: 1, generatedAt: '', sources: const {}, events: events,
    newEvents: news.map(ne).toList());

void main() {
  // 2026-07-15는 수요일, 07-16 목, 07-17 금, 07-18 토, 07-19 일
  group('weekendOf', () {
    test('평일 → 다가오는 토·일', () {
      final (sat, sun) = weekendOf(DateTime(2026, 7, 15, 10)); // 수
      expect(sat, DateTime(2026, 7, 18));
      expect(sun, DateTime(2026, 7, 19));
    });
    test('토요일 당일 → 이번 주말 유지', () {
      final (sat, sun) = weekendOf(DateTime(2026, 7, 18, 14));
      expect(sat, DateTime(2026, 7, 18));
      expect(sun, DateTime(2026, 7, 19));
    });
    test('일요일 당일 → 어제(토)부터의 주말 유지', () {
      final (sat, sun) = weekendOf(DateTime(2026, 7, 19, 9));
      expect(sat, DateTime(2026, 7, 18));
      expect(sun, DateTime(2026, 7, 19));
    });
    test('월요일 → 다음 주말', () {
      final (sat, _) = weekendOf(DateTime(2026, 7, 20, 9));
      expect(sat, DateTime(2026, 7, 25));
    });
  });

  group('digest', () {
    final feed = feedOf([ev('a'), ev('b', area: '경기', free: true), ev('c', kid: false)], []);

    test('창 판정 — 목 18시 이후 ~ 금 22시 전', () {
      expect(inDigestWindow(DateTime(2026, 7, 16, 17)), false); // 목 17시
      expect(inDigestWindow(DateTime(2026, 7, 16, 18)), true); // 목 18시
      expect(inDigestWindow(DateTime(2026, 7, 17, 10)), true); // 금 오전
      expect(inDigestWindow(DateTime(2026, 7, 17, 22)), false); // 금 22시
      expect(inDigestWindow(DateTime(2026, 7, 18, 10)), false); // 토
    });

    test('내용 — 조건 매칭 + 지역별 집계, 주 1회 가드', () {
      final now = DateTime(2026, 7, 16, 19); // 목 19시
      final d = planDigest(feed, const Subscription(), now, null);
      expect(d, isNotNull);
      expect(d!.title, contains('2곳')); // kid=false 제외 → a, b
      expect(d.body, contains('서울 1'));
      expect(d.body, contains('경기 1'));
      expect(d.body, contains('무료 1'));
      // 같은 주에 이미 보냈으면 null
      expect(planDigest(feed, const Subscription(), now, isoWeekKey(now)), isNull);
      // 창 밖이면 null
      expect(planDigest(feed, const Subscription(), DateTime(2026, 7, 15, 19), null), isNull);
    });

    test('주말 행사 0건이면 다이제스트 안 보냄', () {
      final empty = feedOf([ev('z', start: '2026-08-01', end: '2026-08-01')], []);
      expect(planDigest(empty, const Subscription(), DateTime(2026, 7, 16, 19), null), isNull);
    });

    test('isoWeekKey — 주 경계', () {
      expect(isoWeekKey(DateTime(2026, 7, 16)), isoWeekKey(DateTime(2026, 7, 19))); // 같은 주(목~일)
      expect(isoWeekKey(DateTime(2026, 7, 19)) == isoWeekKey(DateTime(2026, 7, 20)), false); // 일→월 주 바뀜
    });
  });

  group('planInstantNotifications', () {
    test('notified 스킵 / 조건 필터 / 끝난 행사 스킵 / allKeys는 전부', () {
      final a = ev('a'); // 매칭
      final b = ev('b', kid: false); // kidOnly로 제외
      final c = ev('c', start: '2026-07-10', end: '2026-07-12'); // 이미 종료
      final feed = feedOf([a, b, c], [a, b, c]);
      final now = DateTime(2026, 7, 15, 10);

      final plan = planInstantNotifications(feed, const Subscription(), {}, now: now);
      expect(plan.toShow.map((n) => n.key), ['new_a']);
      // 발송 안 된 것도 전부 '본 것'으로 — 조건 변경 시 소급 발화 방지
      expect(plan.allKeys, {'new_a', 'new_b', 'new_c'});

      final plan2 = planInstantNotifications(feed, const Subscription(), {'new_a'}, now: now);
      expect(plan2.toShow, isEmpty);
    });

    test('본문에 지역·기간·무료 표기', () {
      final a = ev('a', area: '경기', free: true);
      final feed = feedOf([a], [a]);
      final plan = planInstantNotifications(feed, const Subscription(), {}, now: DateTime(2026, 7, 15));
      expect(plan.toShow.single.body, contains('경기 구'));
      expect(plan.toShow.single.body, contains('무료'));
    });
  });

  test('summarizeBurst — 임계 초과 시 요약 1건', () {
    final many = List.generate(8, (i) => PlannedNotification(key: 'new_$i', title: 't', body: 'b', url: ''));
    final out = summarizeBurst(many);
    expect(out.length, 1);
    expect(out.single.title, contains('8건'));
    expect(summarizeBurst(many.sublist(0, 3)).length, 3);
  });

  group('inQuietHours', () {
    test('자정 걸침(22→8)', () {
      expect(inQuietHours(DateTime(2026, 7, 15, 23)), true);
      expect(inQuietHours(DateTime(2026, 7, 15, 5)), true);
      expect(inQuietHours(DateTime(2026, 7, 15, 12)), false);
    });
    test('start==end는 빈 창 / disabled', () {
      expect(inQuietHours(DateTime(2026, 7, 15, 3), const QuietConfig(startHour: 8, endHour: 8)), false);
      expect(inQuietHours(DateTime(2026, 7, 15, 23), const QuietConfig(enabled: false)), false);
    });
  });

  test('stableId — 안정적/양수/빈 문자열 안전', () {
    expect(stableId('new_kopis:PF123'), stableId('new_kopis:PF123'));
    expect(stableId('a') == stableId('b'), false);
    expect(stableId(''), greaterThanOrEqualTo(0));
  });

  test('kstNow는 naive(isUtc=false) — chwiso M4 대참사 회귀 가드', () {
    expect(kstNow().isUtc, false);
  });
}
