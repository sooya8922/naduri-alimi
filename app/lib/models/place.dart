/// places.json 모델 — 파이프라인(places.py)의 출력과 1:1.
/// 행사(feed.json)와 별개 트랙: 상설 나들이 장소(테마파크·동물원·박물관·체험…).
library;

class Place {
  final String id;
  final String title;
  final String area; // 서울 | 경기 | 인천
  final String sigungu;
  final String cat; // 큐레이션 카테고리(테마파크/동물원/과학관/체험…)
  final String img;
  final String addr;
  final double? lat;
  final double? lng;
  final String stroller; // 유모차 대여 원문('있음'/'없음'/'') — 파이프라인 detailIntro2
  final String age; // 체험가능연령 원문('6세 이상' 등)
  final String exp; // 체험 내용 요약
  final String rest; // 휴무일
  final String parking; // 주차 안내 원문 (빈 문자열 가능)
  final int score;

  const Place({
    required this.id,
    required this.title,
    required this.area,
    required this.sigungu,
    required this.cat,
    required this.img,
    required this.addr,
    required this.lat,
    required this.lng,
    required this.stroller,
    required this.age,
    required this.exp,
    required this.rest,
    required this.parking,
    required this.score,
  });

  bool get hasLocation =>
      lat != null && lng != null && lat! >= 33 && lat! <= 39 && lng! >= 124 && lng! <= 132;

  bool get strollerOk => stroller.startsWith('있') || stroller.startsWith('가능');

  static double? _toDouble(dynamic v) => v == null ? null : double.tryParse(v.toString());

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        area: (j['area'] ?? '') as String,
        sigungu: (j['sigungu'] ?? '') as String,
        cat: (j['cat'] ?? '') as String,
        img: (j['img'] ?? '') as String,
        addr: (j['addr'] ?? '') as String,
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        stroller: (j['stroller'] ?? '') as String,
        age: (j['age'] ?? '') as String,
        exp: (j['exp'] ?? '') as String,
        rest: (j['rest'] ?? '') as String,
        // 구 places.json(v0.2 데이터)엔 parking이 없음 → 빈 값(전방호환)
        parking: (j['parking'] ?? '') as String,
        score: (j['score'] ?? 0) as int,
      );
}

/// places.json 전체
class Places {
  final int version;
  final String generatedAt;
  final List<Place> places;

  const Places({required this.version, required this.generatedAt, required this.places});

  factory Places.fromJson(Map<String, dynamic> j) {
    final version = (j['version'] ?? 0) as int;
    if (version != 1) {
      throw FormatException('지원하지 않는 places version: $version');
    }
    return Places(
      version: version,
      generatedAt: (j['generated_at'] ?? '') as String,
      places: ((j['places'] ?? []) as List)
          .map((e) => Place.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
