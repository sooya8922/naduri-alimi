import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../logic/matcher.dart';
import '../logic/notif_planner.dart';
import '../models/event.dart';
import '../services/feed_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../widgets/event_card.dart';
import '../widgets/filter_sheet.dart';

/// 홈 — 탭 3개: 이번 주말 / 다가오는 / 새 소식
/// 서비스는 주입 가능(테스트에서 페이크로 교체 — 네트워크/플러그인 비의존).
class HomeScreen extends StatefulWidget {
  final FeedService? feedService;
  final PrefsService? prefsService;

  /// feed 로드/필터 변경 성공 시 호출 — main이 알림 점검을 꽂는다(테스트에선 null).
  final Future<void> Function(Feed feed)? onFeedLoaded;

  /// 알림/백그라운드 초기화 오류(진단용 배너). null이면 정상.
  final ValueListenable<String?>? initError;

  /// 현재 시각 공급자 — 테스트에서 고정 시각 주입용.
  final DateTime Function()? clock;

  const HomeScreen(
      {super.key, this.feedService, this.prefsService, this.onFeedLoaded, this.initError, this.clock});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final FeedService _feedSvc = widget.feedService ?? FeedService();
  late final PrefsService _prefsSvc = widget.prefsService ?? PrefsService();

  Feed? _feed;
  bool _fromCache = false;
  Object? _error;
  Subscription _sub = const Subscription();
  QuietConfig _quiet = const QuietConfig();
  bool _digestOn = true;
  DateTime? _lastRefresh; // 포그라운드 복귀 시 과도한 새로고침 방지용
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드→포그라운드 복귀 시 최신 feed로 갱신. 3분 내 재개는 스킵.
    if (state == AppLifecycleState.resumed) {
      final last = _lastRefresh;
      final now = (widget.clock ?? DateTime.now)();
      if (last == null || now.difference(last).inMinutes >= 3) {
        _refresh();
      }
    }
  }

  Future<void> _init() async {
    // prefs 로드 실패(일부 OEM 저장소 이슈)여도 기본값으로 진행 — 무한 로딩 방지.
    try {
      _sub = await _prefsSvc.load();
      _quiet = await _prefsSvc.loadQuiet();
      _digestOn = await _prefsSvc.loadDigestEnabled();
    } catch (_) {/* 필드 기본값 사용 */}
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return; // 중복 호출(연타/동시 pull) 디바운스
    _refreshing = true;
    setState(() => _error = null);
    try {
      final r = await _feedSvc.load();
      setState(() {
        _feed = r.feed;
        _fromCache = r.fromCache;
      });
      _lastRefresh = (widget.clock ?? DateTime.now)();
      // 알림 점검(주입된 경우만). 실패해도 화면은 정상 동작해야 하므로 삼킨다.
      try {
        await widget.onFeedLoaded?.call(r.feed);
      } catch (_) {}
    } catch (e) {
      // feed 버전 불일치는 네트워크 문제가 아니라 앱 업데이트 필요 — 메시지를 구분.
      final isVersion = e is FormatException && e.message.contains('feed version');
      setState(() => _error = isVersion ? '앱을 업데이트해 주세요 (새 데이터 형식)' : e);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: _sub, initialQuiet: _quiet, initialDigestOn: _digestOn),
    );
    if (result != null) {
      setState(() {
        _sub = result.sub;
        _quiet = result.quiet;
        _digestOn = result.digestOn;
      });
      try {
        await _prefsSvc.save(result.sub);
        await _prefsSvc.saveQuiet(result.quiet);
        await _prefsSvc.saveDigestEnabled(result.digestOn);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('설정 저장 실패 — 앱 재시작 시 이전 설정으로 돌아갈 수 있어요')));
        }
      }
    }
  }

  /// 진단 시트 — 알림 경로가 살아있는지 앱 안에서 확인(chwiso M4 도구의 축소판).
  Future<void> _showDiagnostics() async {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('알림 진단', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                '새 행사 알림은 몇 시간 간격으로 자동 확인돼요. '
                '테스트 알림이 안 보이면 기기의 절전/배터리 설정에서 이 앱을 예외로 추가해주세요.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('테스트 알림 보내기'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await NotificationService.showTestNotification();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('알림 실패: $e')));
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('나들이 알리미'),
          actions: [
            IconButton(onPressed: _showDiagnostics, icon: const Icon(Icons.info_outline)),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            IconButton(
              onPressed: _feed == null ? null : _openFilter,
              icon: Badge(
                isLabelVisible: !_sub.isDefault,
                child: const Icon(Icons.tune),
              ),
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: '이번 주말'),
            Tab(text: '다가오는'),
            Tab(text: '새 소식'),
          ]),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_error != null && _feed == null) {
      final msg = _error is String
          ? _error as String
          : '데이터를 불러오지 못했어요.\n네트워크 연결을 확인해 주세요.';
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _refresh, child: const Text('다시 시도')),
        ]),
      );
    }
    final feed = _feed;
    if (feed == null) return const Center(child: CircularProgressIndicator());

    final now = (widget.clock ?? kstNow)();

    // 이번 주말: 주말과 겹치는 행사. 짧은(=이벤트성) 행사를 위로, 상시전시는 아래로.
    final weekend = weekendEvents(feed, _sub, now)..sort(_byDurationThenStart);
    // 다가오는: 아직 안 끝난 행사 전부. 진행중(과거 시작)은 오늘로 클램프해 정렬 —
    // 2019년 시작 오픈런 상시공연이 맨 위를 차지하는 것 방지(실측 데이터 엣지).
    final today = DateTime(now.year, now.month, now.day);
    final upcoming = filterEvents(feed.events.where((e) => !e.ended(now)).toList(), _sub)
      ..sort((a, b) {
        final sa = _clamp(a.startDt, today), sb = _clamp(b.startDt, today);
        final c = sa.compareTo(sb);
        return c != 0 ? c : _duration(a).compareTo(_duration(b));
      });

    return Column(
      children: [
        // 알림 초기화 실패 진단 배너 (앱은 계속 사용 가능)
        if (widget.initError != null)
          ValueListenableBuilder<String?>(
            valueListenable: widget.initError!,
            builder: (ctx, err, _) => err == null
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    color: Theme.of(ctx).colorScheme.errorContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text('⚠️ $err', maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                  ),
          ),
        if (_fromCache)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text('오프라인 — 마지막 데이터(${feed.generatedAt})를 보여드려요',
                style: const TextStyle(fontSize: 12)),
          ),
        Expanded(
          child: TabBarView(children: [
            _eventList(weekend, empty: '조건에 맞는 이번 주말 행사가 없어요'),
            _eventList(upcoming, empty: '조건에 맞는 행사가 없어요'),
            _newsList(feed),
          ]),
        ),
      ],
    );
  }

  static DateTime _clamp(DateTime? d, DateTime floor) =>
      (d == null || d.isBefore(floor)) ? floor : d;

  static int _duration(Event e) {
    final s = e.startDt, en = e.endDt;
    if (s == null || en == null) return 1 << 20;
    return en.difference(s).inDays;
  }

  static int _byDurationThenStart(Event a, Event b) {
    final c = _duration(a).compareTo(_duration(b));
    return c != 0 ? c : a.start.compareTo(b.start);
  }

  Widget _eventList(List<Event> list, {required String empty}) {
    if (list.isEmpty) return Center(child: Text(empty));
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (_, i) => EventCard(event: list[i]),
      ),
    );
  }

  Widget _newsList(Feed feed) {
    final byId = {for (final e in feed.events) e.id: e};
    final now = (widget.clock ?? kstNow)();
    final items = feed.newEvents.where((n) {
      final e = byId[n.id];
      return e != null && matches(e, _sub) && !e.ended(now);
    }).toList();
    if (items.isEmpty) return const Center(child: Text('새로 올라온 행사가 없어요 (48시간 기준)'));
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('🆕 새로 올라온 행사 (48시간)', style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        ...items.map((n) => EventCard(event: byId[n.id]!)),
      ],
    );
  }
}
