import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/map_links.dart';
import '../models/place.dart';
import '../services/places_service.dart';

/// 카테고리 그룹 — places.py의 cat 값을 사용자용 칩 4개로 묶는다.
/// (파이프라인 카테고리가 늘어도 여기 안 걸리면 '기타'가 아니라 전체에서만 보임 — 조용한 누락 방지)
const catGroups = <String, Set<String>>{
  '테마·놀이': {'테마파크', '워터파크', '물놀이', '레포츠', '공원', '명소'},
  '동물·자연': {'동물원', '수족관', '자연휴양림', '수목원·정원', '생태습지'},
  '과학·전시': {'과학관', '천문대', '박물관', '전시관'},
  '체험': {'전통체험', '공예체험', '농촌체험'},
};

/// 가볼 만한 곳 탭 — 상설 나들이 장소 큐레이션(행사와 별개 데이터 트랙).
/// 알림/구독조건과 무관하게 탭 안에서만 필터링한다.
class PlacesTab extends StatefulWidget {
  final PlacesService? service;

  const PlacesTab({super.key, this.service});

  @override
  State<PlacesTab> createState() => _PlacesTabState();
}

class _PlacesTabState extends State<PlacesTab> with AutomaticKeepAliveClientMixin {
  late final PlacesService _svc = widget.service ?? PlacesService();

  Places? _data;
  Object? _error;
  String _area = ''; // ''=전체
  String _group = ''; // ''=전체

  // 탭 전환 때마다 다시 fetch하지 않도록 상태 유지
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await _svc.load();
      setState(() => _data = r.places);
    } catch (e) {
      setState(() => _error = e);
    }
  }

  List<Place> get _filtered {
    final all = _data?.places ?? const <Place>[];
    final cats = catGroups[_group];
    return all.where((p) {
      if (_area.isNotEmpty && p.area != _area) return false;
      if (cats != null && !cats.contains(p.cat)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _data == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          const Text('장소 데이터를 불러오지 못했어요'),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('다시 시도')),
        ]),
      );
    }
    if (_data == null) return const Center(child: CircularProgressIndicator());

    final list = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final a in ['', '서울', '경기', '인천'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(a.isEmpty ? '전지역' : a),
                    selected: _area == a,
                    onSelected: (_) => setState(() => _area = a),
                    showCheckmark: false,
                  ),
                ),
              const SizedBox(width: 8),
              for (final g in ['', ...catGroups.keys])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(g.isEmpty ? '전체' : g),
                    selected: _group == g,
                    onSelected: (_) => setState(() => _group = g),
                    showCheckmark: false,
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('조건에 맞는 장소가 없어요'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => _PlaceCard(place: list[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final Place place;

  const _PlaceCard({required this.place});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = place;
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
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: p.img.isEmpty
                      ? Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(Icons.park_outlined, color: cs.onSurfaceVariant))
                      : Image.network(p.img, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(Icons.park_outlined, color: cs.onSurfaceVariant))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      _chip('${p.area}${p.sigungu.isNotEmpty ? ' ${p.sigungu}' : ''}',
                          cs.secondaryContainer, cs.onSecondaryContainer),
                      if (p.cat.isNotEmpty) _chip(p.cat, cs.surfaceContainerHighest, cs.onSurfaceVariant),
                      if (p.strollerOk) _chip('유모차', const Color(0xFFD7F0DF), const Color(0xFF1B5E20)),
                    ]),
                    if (p.age.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(p.age, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(fontSize: 11, color: fg)),
      );

  void _showDetail(BuildContext context) {
    final p = place;
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
              if (p.img.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Image.network(p.img, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                  ),
                ),
              const SizedBox(height: 12),
              Text(p.title, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('${p.area}${p.sigungu.isNotEmpty ? ' ${p.sigungu}' : ''}'
                  '${p.cat.isNotEmpty ? ' · ${p.cat}' : ''}'),
              if (p.addr.isNotEmpty) Text(p.addr, style: const TextStyle(fontSize: 13)),
              if (p.age.isNotEmpty) Text('연령: ${p.age}', style: const TextStyle(fontSize: 13)),
              if (p.exp.isNotEmpty) Text('체험: ${p.exp}', style: const TextStyle(fontSize: 13), maxLines: 3, overflow: TextOverflow.ellipsis),
              if (p.rest.isNotEmpty) Text('휴무: ${p.rest}', style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (p.strollerOk) const Text('유모차 대여 가능', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('네이버에서 검색'),
                  // TourAPI엔 홈페이지가 목록에 없어(추가 호출 필요) 검색 링크가 실용적 대안
                  onPressed: () => launchUrl(
                      Uri.parse('https://search.naver.com/search.naver?query=${Uri.encodeQueryComponent(p.title)}'),
                      mode: LaunchMode.externalApplication),
                ),
              ),
              if (p.hasLocation) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.place_outlined),
                    label: const Text('위치 보기'),
                    onPressed: () async {
                      final ok = await launchMap(p.lng!, p.lat!);
                      if (!ok && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('지도 앱을 열 수 없어요')));
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
