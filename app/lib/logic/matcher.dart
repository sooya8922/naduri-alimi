/// 구독조건 매칭 — 순수 함수만. UI/IO 없음(단위테스트 대상).
///
/// 매칭 의미론(결정 사항, 테스트로 고정):
///  - 조건 그룹(지역/아이만/무료만/키워드)끼리는 AND, 그룹 안의 값끼리는 OR.
///  - 비어있는 그룹 = 전체 허용.
///  - 아이만: 기본 ON — 이 앱의 정체성(아이와 나들이). 끄면 전체 행사.
///  - 무료만: free가 정확히 true인 것만. null(모름)은 제외(보수적 — chwiso와 동일 원칙).
library;

import '../models/event.dart';

/// 사용자 구독조건. shared_preferences에 JSON으로 저장된다.
class Subscription {
  final Set<String> areas; // {'서울','경기','인천'} 부분집합 — 빈 셋=전체
  final bool kidOnly; // 아이 관련 행사만 (기본 true)
  final bool freeOnly;
  final List<String> keywords; // 빈 리스트=전체

  const Subscription({
    this.areas = const {},
    this.kidOnly = true,
    this.freeOnly = false,
    this.keywords = const [],
  });

  Map<String, dynamic> toJson() => {
        'areas': areas.toList(),
        'kidOnly': kidOnly,
        'freeOnly': freeOnly,
        'keywords': keywords,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        areas: ((j['areas'] ?? []) as List).map((e) => e.toString()).toSet(),
        kidOnly: (j['kidOnly'] ?? true) as bool,
        freeOnly: (j['freeOnly'] ?? false) as bool,
        keywords: ((j['keywords'] ?? []) as List).map((e) => e.toString()).toList(),
      );

  Subscription copyWith({Set<String>? areas, bool? kidOnly, bool? freeOnly, List<String>? keywords}) =>
      Subscription(
        areas: areas ?? this.areas,
        kidOnly: kidOnly ?? this.kidOnly,
        freeOnly: freeOnly ?? this.freeOnly,
        keywords: keywords ?? this.keywords,
      );

  /// 기본 구독 상태(추가 조건 없음)인가. kidOnly=true가 기본이라 '조건'으로 치지 않는다.
  bool get isDefault => areas.isEmpty && kidOnly && !freeOnly && keywords.isEmpty;
}

bool _matchArea(Event e, Set<String> areas) => areas.isEmpty || areas.contains(e.area);

bool _matchKeywords(Event e, List<String> keywords) {
  // 공백뿐인 키워드는 버린다 — 유효 키워드 0개면 그룹 비활성(전체 허용).
  // (안 그러면 '  ' 하나 저장된 순간 모든 알림이 조용히 죽는 엣지 — chwiso 교훈)
  final effective = keywords.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();
  if (effective.isEmpty) return true;
  final text = '${e.title} ${e.cat} ${e.place} ${e.age}'.toLowerCase();
  return effective.any((k) => text.contains(k.toLowerCase()));
}

/// 행사 e가 구독조건 s에 걸리는가.
bool matches(Event e, Subscription s) {
  if (s.kidOnly && !e.kid) return false;
  if (s.freeOnly && e.free != true) return false;
  return _matchArea(e, s.areas) && _matchKeywords(e, s.keywords);
}

/// 리스트 필터링 헬퍼
List<Event> filterEvents(List<Event> all, Subscription s) => all.where((e) => matches(e, s)).toList();
