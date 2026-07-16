import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/models/event.dart';
import 'package:naduri_alimi/services/background.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// refreshAndNotify의 저장/가드 로직 검증.
/// 플랫폼 알림 호출이 일어나지 않는 경로만 사용한다(첫 실행 기준선/조용시간/이중 실행 가드) —
/// 실제 발송 계획은 notif_planner_test가 순수 함수로 검증.
Feed feedWithNew() {
  const e = Event(
    id: 'seoul:n1', source: 'seoul', title: '새 행사', place: 'p', area: '서울', sigungu: '',
    start: '2099-01-01', end: '2099-01-02', cat: '전시', kid: true, age: '', free: true,
    price: '', img: '', url: '', lat: null, lng: null, seen: '',
  );
  return Feed(
    version: 1, generatedAt: '', sources: const {},
    events: const [e],
    newEvents: const [
      NewEvent(id: 'seoul:n1', title: '새 행사', area: '서울', sigungu: '', start: '2099-01-01',
          end: '2099-01-02', kid: true, free: true, url: '', seenAt: ''),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('첫 실행 — 발송 없이 기준선(notified 셋)만 저장', () async {
    SharedPreferences.setMockInitialValues({});
    // 다이제스트 창 밖 + 조용시간 아님 (수요일 낮)
    await refreshAndNotify(preloaded: feedWithNew(), now: DateTime(2026, 7, 15, 10));
    final sp = await SharedPreferences.getInstance();
    final stored = (json.decode(sp.getString('notified_keys_v1')!) as List).toSet();
    expect(stored, {'new_seoul:n1'}); // 발송은 없었지만 '본 것'으로 마킹
  });

  test('60초 내 재실행 — 즉시알림 파트 스킵(이중 발송 가드)', () async {
    SharedPreferences.setMockInitialValues({
      'notify_run_ts_v1': DateTime.now().millisecondsSinceEpoch, // 방금 실행된 것으로
      // notified가 이미 있으므로(빈 목록) 재실행이면 새 행사 발송을 시도할 상황
      'notified_keys_v1': '[]',
    });
    // 가드가 스킵하므로 플랫폼 알림 호출까지 안 가서 테스트 환경에서도 예외가 없어야 한다
    await refreshAndNotify(preloaded: feedWithNew(), now: DateTime(2026, 7, 15, 10));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), '[]'); // 마킹도 안 됨(파트 전체 스킵)
  });

  test('조용시간(밤 11시) — 발송/저장 모두 미룸 (기존 사용자)', () async {
    SharedPreferences.setMockInitialValues({'notified_keys_v1': '[]'});
    await refreshAndNotify(preloaded: feedWithNew(), now: DateTime(2026, 7, 15, 23, 0));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), '[]'); // 아침에 알리도록 '안 본' 상태 유지
  });

  test('조용시간이라도 첫 실행 기준선은 저장 (밤 설치 → 아침 폭탄 방지)', () async {
    SharedPreferences.setMockInitialValues({});
    await refreshAndNotify(preloaded: feedWithNew(), now: DateTime(2026, 7, 15, 23, 0));
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('notified_keys_v1'), isNotNull);
  });

  test('손상된 notified 저장소 — self-heal(빈 셋 폴백, 예외 없음)', () async {
    SharedPreferences.setMockInitialValues({'notified_keys_v1': '{broken'});
    // 손상 → 빈 셋 폴백 → 새 행사가 '미발송' 취급되지만, allKeys 저장은 성공해야 함.
    // 발송 시도는 플랫폼 채널이 없어 던질 수 있으므로 조용시간으로 발송 자체를 피해 저장 로직만 검증…
    // 은 불가(조용시간이면 저장도 안 함) → 다이제스트 창 밖 낮 시간 + kid=false 구독으로 발송 0건 유도.
    SharedPreferences.setMockInitialValues({
      'notified_keys_v1': '{broken',
      'subscription_v1': '{"areas":[],"kidOnly":true,"freeOnly":true,"keywords":[]}',
    });
    final feed = Feed(
      version: 1, generatedAt: '', sources: const {},
      events: const [
        Event(id: 'seoul:n2', source: 'seoul', title: 't', place: '', area: '서울', sigungu: '',
            start: '2099-01-01', end: '2099-01-02', cat: '', kid: true, age: '', free: false, // 유료 → freeOnly로 필터
            price: '', img: '', url: '', lat: null, lng: null, seen: ''),
      ],
      newEvents: const [
        NewEvent(id: 'seoul:n2', title: 't', area: '서울', sigungu: '', start: '2099-01-01',
            end: '2099-01-02', kid: true, free: false, url: '', seenAt: ''),
      ],
    );
    await refreshAndNotify(preloaded: feed, now: DateTime(2026, 7, 15, 10));
    final sp = await SharedPreferences.getInstance();
    final stored = (json.decode(sp.getString('notified_keys_v1')!) as List).toSet();
    expect(stored, {'new_seoul:n2'}); // 파손 복구 후 정상 마킹
  });
}
