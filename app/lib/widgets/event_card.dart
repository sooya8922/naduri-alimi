import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/event.dart';

/// 지도 열기 후보 URL 목록(순수 함수, 테스트 대상). 우선순위: 카카오맵 → 네이버맵 → 구글지도(웹).
/// 앞의 두 개는 '앱 스킴'이라 canLaunchUrl로 설치 여부를 먼저 판정 → 없으면 다음으로
/// 조용히 폴백. 마지막 구글 웹은 항상 열리는 최종 안전망. (chwiso 검증 로직 그대로)
List<String> buildMapCandidates(double lng, double lat) {
  return [
    'kakaomap://look?p=$lat,$lng',
    'nmap://place?lat=$lat&lng=$lng&name=%ED%96%89%EC%82%AC%20%EC%9C%84%EC%B9%98&appname=com.sooya8922.naduri',
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  ];
}

/// 행사 카드 — 리스트의 기본 단위.
class EventCard extends StatelessWidget {
  final Event event;

  const EventCard({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = event;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(cs),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _chip(e.sigungu.isEmpty ? e.area : '${e.area} ${e.sigungu}',
                          cs.secondaryContainer, cs.onSecondaryContainer),
                      if (e.kid) _chip('아이', const Color(0xFFFFE4EC), const Color(0xFFAD1457)),
                      if (e.free == true) _chip('무료', const Color(0xFFD7F0DF), const Color(0xFF1B5E20)),
                      if (e.free == false) _chip('유료', cs.surfaceContainerHighest, cs.onSurfaceVariant),
                      if (e.cat.isNotEmpty) _chip(e.cat, cs.surfaceContainerHighest, cs.onSurfaceVariant),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      '${e.periodLabel}${e.place.isNotEmpty ? ' · ${e.place}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb(ColorScheme cs) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 64,
          height: 80, // 포스터(세로형)가 많아 세로로 약간 길게
          // 이미지 URL이 깨져도 앱이 안 깨지게 (엣지: 404/비이미지 응답 가능)
          child: event.img.isEmpty
              ? _thumbFallback(cs)
              : Image.network(event.img, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _thumbFallback(cs)),
        ),
      );

  Widget _thumbFallback(ColorScheme cs) =>
      Container(color: cs.surfaceContainerHighest, child: Icon(Icons.park_outlined, color: cs.onSurfaceVariant));

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
      );

  void _showDetail(BuildContext context) {
    final e = event;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (e.img.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: Image.network(e.img, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                ),
              const SizedBox(height: 12),
              Text(e.title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('${e.sigungu.isEmpty ? e.area : '${e.area} ${e.sigungu}'}'
                  '${e.cat.isNotEmpty ? ' · ${e.cat}' : ''}'
                  '${e.free == true ? ' · 무료' : e.free == false ? ' · 유료' : ''}'),
              Text('기간: ${e.periodLabel}', style: const TextStyle(fontSize: 13)),
              if (e.place.isNotEmpty) Text('장소: ${e.place}', style: const TextStyle(fontSize: 13)),
              if (e.age.isNotEmpty) Text('대상: ${e.age}', style: const TextStyle(fontSize: 13)),
              if (e.price.isNotEmpty)
                Text('요금: ${e.price}', style: const TextStyle(fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('자세히 보기'),
                  onPressed: e.url.isEmpty
                      ? null
                      // 다중 도메인이라 항상 외부 브라우저로 (chwiso 실측 근거)
                      : () => launchUrl(Uri.parse(e.url), mode: LaunchMode.externalApplication),
                ),
              ),
              // 위치 보기 — 좌표 있는 행사만(약 99%). '갈 만한 거리인지' 판단 보조.
              if (e.hasLocation) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('위치 보기'),
                    onPressed: () => _openMap(ctx, e),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 좌표를 지도로 연다. 카카오맵→네이버맵→구글지도 순서로, 앱 스킴은 설치돼 있을 때만 실행.
  /// 각 시도를 try-catch로 감싸 조용히 다음 후보로 폴백(chwiso 검증 로직).
  Future<void> _openMap(BuildContext context, Event e) async {
    final lat = e.lat!, lng = e.lng!; // hasLocation 가드로 non-null 보장
    final candidates = buildMapCandidates(lng, lat);
    for (var i = 0; i < candidates.length; i++) {
      final uri = Uri.parse(candidates[i]);
      final isLast = i == candidates.length - 1;
      try {
        if (isLast || await canLaunchUrl(uri)) {
          if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
        }
      } catch (_) {
        // 이 후보 실패 → 다음 후보로 (조용히)
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지도 앱을 열 수 없어요')));
    }
  }
}
