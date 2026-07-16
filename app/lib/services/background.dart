/// 백그라운드 갱신 — workmanager 주기 작업(6시간).
/// 파이프라인이 하루 2회 feed를 갱신하므로 6시간 주기면 놓침 없이 따라간다.
///
/// 한 번의 실행에서: feed fetch → 신규 즉시알림 → 주간 다이제스트(목·금 저녁, 주 1회).
/// 앱을 열 때도 같은 루틴이 돌므로(홈 화면), 백그라운드는 보조 경로다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../logic/notif_planner.dart';
import '../models/event.dart';
import 'feed_service.dart';
import 'notification_service.dart';
import 'prefs_service.dart';

const _taskName = 'feed_refresh';
const _notifiedKey = 'notified_keys_v1';
const _lastRunKey = 'notify_run_ts_v1';

/// 백그라운드 isolate 진입점 — 반드시 top-level + vm:entry-point.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await refreshAndNotify();
      return true;
    } catch (_) {
      return false; // 실패 → workmanager 재시도 정책에 맡김
    }
  });
}

/// 공용 갱신 루틴 — 포그라운드(앱 열림)와 백그라운드 양쪽에서 호출.
/// [now]는 테스트 주입용(기본 = 실제 KST 시각).
Future<void> refreshAndNotify({Feed? preloaded, DateTime? now}) async {
  final feed = preloaded ?? (await FeedService().load()).feed;
  final prefs = PrefsService();
  final sub = await prefs.load();
  final quietCfg = await prefs.loadQuiet();
  final nowKst = now ?? kstNow();

  final sp = await SharedPreferences.getInstance();

  // 1) 신규 행사 즉시 알림
  // 이중 실행 가드: 앱 오픈과 WorkManager가 거의 동시에 돌면(별도 isolate라 메모리 락 불가)
  // 같은 알림이 두 번 나간다 → 60초 내 재실행이면 즉시알림 파트는 스킵(chwiso 교훈).
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final lastMs = sp.getInt(_lastRunKey) ?? 0;
  final storedRaw = sp.getString(_notifiedKey);
  // 조용시간(기본 22~08시 KST)에는 즉시알림을 발송도 저장도 하지 않는다 → 밤새 생긴
  // 이벤트는 '안 본' 상태로 남아 아침 첫 확인 때 알림된다.
  // 단 첫 실행 기준선(storedRaw==null)은 발송이 없으므로 조용시간에도 저장한다
  // (밤에 설치 → 아침에 지난 48h치 폭탄 나는 엣지 방지).
  final quiet = inQuietHours(nowKst, quietCfg) && storedRaw != null;
  if (!quiet && (nowMs - lastMs).abs() > 60000) {
    await sp.setInt(_lastRunKey, nowMs); // 먼저 마킹해 레이스 창 최소화
    // 저장소 손상 시 json.decode가 던지면 이후 모든 알림이 영구 실패 → 빈 셋 폴백 + self-heal.
    Set<String> notified;
    try {
      notified = (json.decode(storedRaw ?? '[]') as List).map((e) => e.toString()).toSet();
    } catch (_) {
      notified = {};
      await sp.remove(_notifiedKey);
    }
    final plan = planInstantNotifications(feed, sub, notified, now: nowKst);
    // allKeys를 발송 '전에' 저장한다: showInstant가 배치 도중 던져도
    // 다음 실행에서 같은 알림을 재발송하지 않게 — 최악은 중복이 아니라 누락(더 안전).
    // 첫 실행(storedRaw == null)은 발송 없이 기준선만 저장(설치 직후 폭탄 방지).
    await sp.setString(_notifiedKey, json.encode(plan.allKeys.toList()));
    if (storedRaw != null) {
      for (final n in summarizeBurst(plan.toShow)) {
        await NotificationService.showInstant(n);
      }
    }
  }

  // 2) 주간 다이제스트 (목 18시~금 22시 창, 주 1회, 조용시간 존중)
  if (await prefs.loadDigestEnabled() && !inQuietHours(nowKst, quietCfg)) {
    final lastWeek = await prefs.loadDigestWeek();
    final digest = planDigest(feed, sub, nowKst, lastWeek);
    if (digest != null) {
      // 발송 '전에' 주차를 저장 — show가 던져도 같은 주에 재시도 폭탄이 없다(누락이 중복보다 안전)
      await prefs.saveDigestWeek(isoWeekKey(nowKst));
      await NotificationService.showInstant(digest);
    }
  }
}

/// 주기 작업 등록 — 앱 시작 시 1회 호출(중복 등록은 update로 무해).
Future<void> registerBackgroundRefresh() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName, _taskName,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.linear,
  );
}
