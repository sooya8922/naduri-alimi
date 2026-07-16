import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/background.dart';
import 'services/notification_service.dart';

/// 알림/백그라운드 초기화 오류 — 크래시 대신 홈 배너로 노출(원격 진단용).
final ValueNotifier<String?> initError = ValueNotifier(null);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 원칙: 어떤 플러그인 초기화도 첫 화면을 막거나 죽이면 안 된다.
  // (chwiso 실기기 M4: 시작 시 플러그인 crash → 앱 즉시 종료. UI 먼저, 초기화는 뒤에서.)
  runApp(const NaduriApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await NotificationService.init();
      await NotificationService.requestPermission();
    } catch (e) {
      initError.value = '알림 초기화 실패: $e';
      return; // 알림 없이도 열람은 가능
    }
    try {
      await registerBackgroundRefresh();
    } catch (e) {
      initError.value = '백그라운드 등록 실패: $e';
    }
  });
}

class NaduriApp extends StatelessWidget {
  const NaduriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '나들이 알리미',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8A3D)),
        useMaterial3: true,
      ),
      // 앱을 열 때마다 최신 feed로 신규 알림 점검 + 다이제스트 점검.
      home: HomeScreen(
        onFeedLoaded: (feed) => refreshAndNotify(preloaded: feed),
        initError: initError,
      ),
    );
  }
}
