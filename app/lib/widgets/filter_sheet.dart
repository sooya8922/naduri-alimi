import 'package:flutter/material.dart';

import '../logic/matcher.dart';
import '../logic/notif_planner.dart';

/// 필터 시트 결과 — 구독조건 + 조용시간 + 다이제스트 on/off
typedef FilterResult = ({Subscription sub, QuietConfig quiet, bool digestOn});

/// 구독조건 편집 바텀시트. 저장은 호출측(HomeScreen)이 한다.
class FilterSheet extends StatefulWidget {
  final Subscription initial;
  final QuietConfig initialQuiet;
  final bool initialDigestOn;

  const FilterSheet(
      {super.key, required this.initial, this.initialQuiet = const QuietConfig(), this.initialDigestOn = true});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  static const allAreas = ['서울', '경기', '인천'];

  late Set<String> areas = {...widget.initial.areas};
  late bool kidOnly = widget.initial.kidOnly;
  late bool freeOnly = widget.initial.freeOnly;
  late QuietConfig quiet = widget.initialQuiet;
  late bool digestOn = widget.initialDigestOn;
  late final TextEditingController kwCtrl =
      TextEditingController(text: widget.initial.keywords.join(', '));

  @override
  void dispose() {
    kwCtrl.dispose();
    super.dispose();
  }

  FilterResult _build() => (
        sub: Subscription(
          areas: areas,
          kidOnly: kidOnly,
          freeOnly: freeOnly,
          keywords: kwCtrl.text
              .split(RegExp(r'[,\s]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        ),
        quiet: quiet,
        digestOn: digestOn,
      );

  Widget _hourDropdown(int value, ValueChanged<int?> onChanged) => DropdownButton<int>(
        value: value,
        isDense: true,
        items: List.generate(24, (h) => DropdownMenuItem(value: h, child: Text('$h시'))),
        onChanged: quiet.enabled ? onChanged : null,
      );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (ctx, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Text('보기·알림 조건', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('목록과 알림 모두에 적용돼요. 비워두면 전체.',
                    style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('아이 관련 행사만'),
                  subtitle: const Text('아동공연·가족행사 등만 보여요 (끄면 전체 행사)', style: TextStyle(fontSize: 12)),
                  value: kidOnly,
                  onChanged: (v) => setState(() => kidOnly = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('무료만'),
                  value: freeOnly,
                  onChanged: (v) => setState(() => freeOnly = v),
                ),
                const SizedBox(height: 8),
                Text('지역 (${areas.isEmpty ? '전체' : areas.join('·')})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: allAreas
                      .map((a) => FilterChip(
                            label: Text(a),
                            selected: areas.contains(a),
                            onSelected: (v) => setState(() => v ? areas.add(a) : areas.remove(a)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                const Text('키워드 (쉼표로 구분)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: kwCtrl,
                  decoration: const InputDecoration(
                      hintText: '예: 인형극 박물관 체험', border: OutlineInputBorder(), isDense: true),
                ),
                const Divider(height: 32),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('🧺 주말 다이제스트'),
                  subtitle: const Text('목·금 저녁, 이번 주말 갈 만한 곳 요약을 한 번 보내드려요', style: TextStyle(fontSize: 12)),
                  value: digestOn,
                  onChanged: (v) => setState(() => digestOn = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('조용시간 사용'),
                  subtitle: const Text('이 시간엔 알림을 아침으로 미뤄요', style: TextStyle(fontSize: 12)),
                  value: quiet.enabled,
                  onChanged: (v) => setState(() => quiet = quiet.copyWith(enabled: v)),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    _hourDropdown(quiet.startHour, (v) => setState(() => quiet = quiet.copyWith(startHour: v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('부터')),
                    _hourDropdown(quiet.endHour, (v) => setState(() => quiet = quiet.copyWith(endHour: v))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('까지')),
                  ],
                ),
                // start==end면 조용시간이 실제로 적용 안 됨 — 사용자가 오해하지 않게 경고
                if (quiet.enabled && quiet.startHour == quiet.endHour)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('같은 시간이라 조용시간이 적용되지 않아요',
                        style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.error)),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() {
                      areas.clear();
                      kidOnly = true;
                      freeOnly = false;
                      kwCtrl.clear();
                      quiet = const QuietConfig();
                      digestOn = true;
                    }),
                    child: const Text('초기화'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, _build()),
                    child: const Text('적용'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
