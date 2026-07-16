// 홈 화면 위젯 테스트 — 페이크 서비스 주입(네트워크/파일IO/플러그인 비의존).
// ⚠ testWidgets(FakeAsync 존)에서 실제 파일 IO를 await하면 영원히 안 끝난다 —
// FeedService에 실제 캐시 파일을 물리지 말고 Fake 서브클래스로 load()를 통째로 대체할 것.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naduri_alimi/logic/matcher.dart';
import 'package:naduri_alimi/logic/notif_planner.dart';
import 'package:naduri_alimi/models/event.dart';
import 'package:naduri_alimi/screens/home_screen.dart';
import 'package:naduri_alimi/services/feed_service.dart';
import 'package:naduri_alimi/services/prefs_service.dart';

import 'feed_parse_test.dart' show sampleFeed;
import 'places_tab_test.dart' show FakePlacesService;

class FakeFeedService extends FeedService {
  final bool fail;
  int loadCount = 0;
  FakeFeedService({this.fail = false});

  @override
  Future<({Feed feed, bool fromCache})> load() async {
    loadCount++;
    if (fail) throw Exception('offline');
    return (feed: Feed.fromJson(json.decode(sampleFeed) as Map<String, dynamic>), fromCache: false);
  }
}

class FakePrefsService extends PrefsService {
  Subscription stored = const Subscription();
  QuietConfig storedQuiet = const QuietConfig();
  bool digestOn = true;
  String? digestWeek;

  @override
  Future<Subscription> load() async => stored;

  @override
  Future<void> save(Subscription s) async => stored = s;

  @override
  Future<QuietConfig> loadQuiet() async => storedQuiet;

  @override
  Future<void> saveQuiet(QuietConfig q) async => storedQuiet = q;

  @override
  Future<bool> loadDigestEnabled() async => digestOn;

  @override
  Future<void> saveDigestEnabled(bool v) async => digestOn = v;

  @override
  Future<String?> loadDigestWeek() async => digestWeek;

  @override
  Future<void> saveDigestWeek(String w) async => digestWeek = w;
}

Widget app({bool fail = false, DateTime? clock, FeedService? svc}) => MaterialApp(
      home: HomeScreen(
        feedService: svc ?? FakeFeedService(fail: fail),
        prefsService: FakePrefsService(),
        placesService: FakePlacesService(),
        // 2026-07-18(토) — sampleFeed의 인형극(7/18~19)이 '이번 주말'에 걸린다
        clock: () => clock ?? DateTime(2026, 7, 18, 10, 0),
      ),
    );

void main() {
  testWidgets('성공 경로: 이번 주말 탭에 아이 행사 카드 렌더 (kidOnly 기본 ON)', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(); // _init 완료
    await tester.pump();

    expect(find.text('나들이 알리미'), findsOneWidget);
    expect(find.textContaining('어린이 인형극'), findsOneWidget);
    // kid=false인 재즈 콘서트는 기본(아이만) 필터로 안 보임
    expect(find.textContaining('재즈 콘서트'), findsNothing);
  });

  testWidgets('다가오는 탭: 주말 밖 미래 행사도 보임', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('다가오는'));
    await tester.pumpAndSettle();
    // 8/1 재즈 콘서트는 kid=false → 여전히 안 보임(필터는 탭 공통), 인형극은 보임
    expect(find.textContaining('어린이 인형극'), findsOneWidget);
    expect(find.textContaining('재즈 콘서트'), findsNothing);
  });

  testWidgets('새 소식 탭: 48시간 신규 행사', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('새 소식'));
    await tester.pumpAndSettle();
    expect(find.textContaining('새로 올라온 행사'), findsOneWidget);
    expect(find.textContaining('어린이 인형극'), findsOneWidget);
  });

  testWidgets('주말 지난 시점(월) — 이번 주말 탭에서 지난 행사 제외', (tester) async {
    // 7/20(월): 인형극(7/18~19)은 끝남 → 다음 주말(7/25~26)에도 없음 → 빈 상태 문구
    await tester.pumpWidget(app(clock: DateTime(2026, 7, 20, 10, 0)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('이번 주말 행사가 없어요'), findsOneWidget);
  });

  testWidgets('포그라운드 복귀 시 자동 새로고침 — 3분 가드 반영 (chwiso MAJOR-6)', (tester) async {
    var clock = DateTime(2026, 7, 18, 9, 0);
    final feedSvc = FakeFeedService();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
          feedService: feedSvc,
          prefsService: FakePrefsService(),
          placesService: FakePlacesService(),
          clock: () => clock),
    ));
    await tester.pump();
    await tester.pump();
    final afterInit = feedSvc.loadCount;
    expect(afterInit, greaterThanOrEqualTo(1));

    // 1) 즉시 복귀(가드 3분 미만) → 새로고침 없음
    clock = DateTime(2026, 7, 18, 9, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(feedSvc.loadCount, afterInit, reason: '3분 내 복귀는 스킵');

    // 2) 5분 뒤 복귀 → 새로고침 발생
    clock = DateTime(2026, 7, 18, 9, 6);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(feedSvc.loadCount, greaterThan(afterInit), reason: '3분 경과 복귀는 새로고침');
  });

  testWidgets('실패 경로(오프라인 첫 실행): 크래시 없이 오류 UI + 다시 시도', (tester) async {
    await tester.pumpWidget(app(fail: true));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('불러오지 못했'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
