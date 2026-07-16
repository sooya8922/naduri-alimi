/// 플랫폼 알림 래퍼 — flutter_local_notifications 호출을 여기 격리.
/// 계획(무엇을/언제)은 notif_planner.dart 순수함수가 만들고, 여기는 실행만 한다.
/// (chwiso와 달리 예약 알람이 없다 — 나들이는 '접수 오픈' 개념이 없어 즉시 알림만 쓴다)
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../logic/notif_planner.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void>? _initFuture; // 동시 진입해도 initialize를 한 번만(Future 캐시)

  static const _instantChannel = AndroidNotificationDetails(
    'instant', '새 행사 알림',
    channelDescription: '조건에 맞는 나들이 행사가 새로 올라오면 알림',
    importance: Importance.high, priority: Priority.high,
  );
  static const _digestChannel = AndroidNotificationDetails(
    'digest', '주말 나들이 다이제스트',
    channelDescription: '목·금 저녁, 이번 주말 아이랑 갈 만한 곳 요약',
    importance: Importance.high, priority: Priority.high,
  );

  /// 첫 호출의 Future를 캐시해, 앱 시작 시 addPostFrameCallback과 feed 경로가 거의 동시에
  /// init()을 불러도 initialize가 딱 한 번만 실행되게 한다(중복 초기화 race 방지 — chwiso).
  /// 실패하면 캐시를 비워 다음 호출이 재시도할 수 있게 한다.
  static Future<void> init() {
    return _initFuture ??= _doInit().catchError((e) {
      _initFuture = null; // 다음 init()에서 재시도 가능
      throw e;
    });
  }

  static Future<void> _doInit() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );
    // 앱이 종료된 상태에서 알림 탭으로 실행된 경우, 그 payload(딥링크)를 처리.
    // best-effort — 실패해도 핵심 알림 초기화까지 무효화되면 안 됨(일부 OEM에서 던짐).
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final resp = launch!.notificationResponse;
        if (resp != null) _onTap(resp);
      }
    } catch (_) {/* cold-start 딥링크만 유실, 알림 기능은 정상 */}
  }

  static void _onTap(NotificationResponse resp) {
    final url = resp.payload;
    if (url != null && url.startsWith('http')) {
      final uri = Uri.tryParse(url); // 파손 URL이어도 탭 핸들러가 죽지 않게
      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Android 13+ 알림 권한 요청. 결과: 허용 여부(다른 플랫폼/버전은 true 취급)
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    final granted = await android.requestNotificationsPermission();
    return granted ?? true;
  }

  static Future<void> showInstant(PlannedNotification n) async {
    await init();
    final isDigest = n.key.startsWith('digest_');
    await _plugin.show(
      id: stableId(n.key),
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(android: isDigest ? _digestChannel : _instantChannel),
      payload: n.url,
    );
  }

  /// 진단용: 즉시 테스트 알림 — 알림 '전달' 자체가 되는지 검증(chwiso M4 도구의 축소판).
  static Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      id: 999999901,
      title: '🔔 테스트 알림',
      body: '이게 보이면 알림 경로 정상',
      notificationDetails: const NotificationDetails(android: _instantChannel),
    );
  }
}
