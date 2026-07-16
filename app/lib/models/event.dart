/// feed.json 모델 — 파이프라인(poller.py)의 출력과 1:1.
/// 스키마가 바뀌면 poller.py와 이 파일을 같은 커밋에서 고친다(모노레포 이유).
library;

/// 데이터 출처 라벨. 모르는 출처는 그대로 노출(전방호환).
class EventSource {
  static String label(String s) => switch (s) {
        'seoul' => '서울시',
        'kopis' => '공연전산망',
        'kcisa' => '문화정보원',
        'fstvl' => '축제',
        _ => s,
      };
}

/// 행사 하나. 필드는 feed의 events[] 원소와 동일.
class Event {
  final String id;
  final String source; // seoul | kopis | kcisa | fstvl
  final String title;
  final String place;
  final String area; // 서울 | 경기 | 인천
  final String sigungu; // 자치구/시군 (빈 문자열 가능)
  final String start; // "YYYY-MM-DD"
  final String end;
  final String cat; // 장르/분류
  final bool kid; // 아이 관련(kidstate=Y / 아동·가족 장르 / 키워드)
  final String age; // 관람연령 원문 (빈 문자열 가능)
  final bool? free; // true=무료 false=유료 null=모름
  final String price;
  final String img;
  final String url;
  final double? lat;
  final double? lng;
  final String seen; // 최초 목격 "YYYY-MM-DD HH:MM"

  const Event({
    required this.id,
    required this.source,
    required this.title,
    required this.place,
    required this.area,
    required this.sigungu,
    required this.start,
    required this.end,
    required this.cat,
    required this.kid,
    required this.age,
    required this.free,
    required this.price,
    required this.img,
    required this.url,
    required this.lat,
    required this.lng,
    required this.seen,
  });

  DateTime? get startDt => DateTime.tryParse(start);

  // 종료일은 그날 '하루 종일' 유효 → 23:59로 해석해야 종료 당일이 목록에서 안 사라진다
  DateTime? get endDt {
    final d = DateTime.tryParse(end);
    return d?.add(const Duration(hours: 23, minutes: 59));
  }

  /// [from, to]와 행사 기간이 겹치는가. 파싱 불가는 false(보수적).
  bool overlaps(DateTime from, DateTime to) {
    final s = startDt, e = endDt;
    if (s == null || e == null) return false;
    return !s.isAfter(to) && !e.isBefore(from);
  }

  /// 종료일이 지났는가(피드 생성 후 기기에서 시간이 흐른 경우의 실시간 재분류용)
  bool ended(DateTime now) => endDt?.isBefore(now) ?? false;

  /// 지도로 열 수 있는 유효 좌표가 있는가.
  bool get hasLocation =>
      lat != null && lng != null && lat! >= 33 && lat! <= 39 && lng! >= 124 && lng! <= 132;

  /// 기간 표기: 하루짜리는 "7/25", 기간은 "7/25 ~ 8/3"
  String get periodLabel {
    String md(String d) {
      final p = d.split('-');
      return p.length == 3 ? '${int.tryParse(p[1]) ?? p[1]}/${int.tryParse(p[2]) ?? p[2]}' : d;
    }

    if (start.isEmpty) return '';
    return start == end ? md(start) : '${md(start)} ~ ${md(end)}';
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    return double.tryParse(v.toString());
  }

  factory Event.fromJson(Map<String, dynamic> j) => Event(
        id: (j['id'] ?? '') as String,
        source: (j['source'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        place: (j['place'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        sigungu: (j['sigungu'] ?? '') as String,
        start: (j['start'] ?? '') as String,
        end: (j['end'] ?? '') as String,
        cat: (j['cat'] ?? '') as String,
        kid: (j['kid'] ?? false) as bool,
        age: (j['age'] ?? '') as String,
        // free는 3값(true/false/null) — null 보존이 중요(무료 필터에서 '모름'은 제외)
        free: j['free'] as bool?,
        price: (j['price'] ?? '') as String,
        img: (j['img'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        seen: (j['seen'] ?? '') as String,
      );
}

/// 신규 등록 행사 이벤트(알림용 — 상세는 events[]의 같은 id에서 찾는다)
class NewEvent {
  final String id;
  final String title;
  final String area;
  final String sigungu;
  final String start;
  final String end;
  final bool kid;
  final bool? free;
  final String url;
  final String seenAt;

  const NewEvent({
    required this.id,
    required this.title,
    required this.area,
    required this.sigungu,
    required this.start,
    required this.end,
    required this.kid,
    required this.free,
    required this.url,
    required this.seenAt,
  });

  factory NewEvent.fromJson(Map<String, dynamic> j) => NewEvent(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        sigungu: (j['sigungu'] ?? '') as String,
        start: (j['start'] ?? '') as String,
        end: (j['end'] ?? '') as String,
        kid: (j['kid'] ?? false) as bool,
        free: j['free'] as bool?,
        url: (j['url'] ?? '') as String,
        seenAt: (j['seen_at'] ?? '') as String,
      );
}

/// feed.json 전체
class Feed {
  final int version;
  final String generatedAt;
  final Map<String, String> sources; // 소스별 상태 ("ok:123" | "error:...")
  final List<Event> events;
  final List<NewEvent> newEvents;

  const Feed({
    required this.version,
    required this.generatedAt,
    required this.sources,
    required this.events,
    required this.newEvents,
  });

  factory Feed.fromJson(Map<String, dynamic> j) {
    final version = (j['version'] ?? 0) as int;
    if (version != 1) {
      // 스키마가 앞서가면 구버전 앱이 조용히 깨지는 것 방지 — 명시적으로 던진다.
      throw FormatException('지원하지 않는 feed version: $version');
    }
    return Feed(
      version: version,
      generatedAt: (j['generated_at'] ?? '') as String,
      sources: ((j['sources'] ?? {}) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      events: ((j['events'] ?? []) as List)
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList(),
      newEvents: ((j['new'] ?? []) as List)
          .map((e) => NewEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
