/// 지도 열기 — 행사 카드/장소 카드가 공유하는 로직.
/// 후보 생성은 순수 함수(테스트 대상), 실행은 launchMap이 담당.
library;

import 'package:url_launcher/url_launcher.dart';

/// 지도 후보 URL 목록. 우선순위: 카카오맵 → 네이버맵 → 구글지도(웹).
/// 앞의 두 개는 '앱 스킴'이라 canLaunchUrl로 설치 여부를 먼저 판정 → 없으면 다음으로
/// 조용히 폴백. 마지막 구글 웹은 항상 열리는 최종 안전망. (chwiso 검증 로직)
/// 좌표만 사용하고 이름은 안 넣어 특수문자로 URL이 깨질 여지도 없앤다.
List<String> buildMapCandidates(double lng, double lat) {
  return [
    'kakaomap://look?p=$lat,$lng',
    'nmap://place?lat=$lat&lng=$lng&name=%EB%82%98%EB%93%A4%EC%9D%B4%20%EC%9C%84%EC%B9%98&appname=com.sooya8922.naduri',
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  ];
}

/// 대중교통 길찾기 후보 URL 목록. 우선순위는 위치 보기와 동일(카카오→네이버→구글 웹).
/// 네이버는 도착지 이름이 필수라 인코딩해 넣는다(특수문자는 Uri.encodeQueryComponent가 처리).
List<String> buildRouteCandidates(double lng, double lat, String name) {
  final n = Uri.encodeQueryComponent(name.isEmpty ? '나들이 목적지' : name);
  return [
    'kakaomap://route?ep=$lat,$lng&by=PUBLICTRANSIT',
    'nmap://route/public?dlat=$lat&dlng=$lng&dname=$n&appname=com.sooya8922.naduri',
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=transit',
  ];
}

/// 좌표를 지도로 연다. 각 시도를 try-catch로 감싸 canLaunchUrl/launchUrl이 예외를 던져도
/// (앱 업데이트 중 등) 조용히 다음 후보로 폴백. 세 후보 전부 실패 시 false.
Future<bool> launchMap(double lng, double lat) => _launchFirst(buildMapCandidates(lng, lat));

/// 대중교통 길찾기를 연다. 폴백 규칙은 launchMap과 동일.
Future<bool> launchRoute(double lng, double lat, String name) =>
    _launchFirst(buildRouteCandidates(lng, lat, name));

Future<bool> _launchFirst(List<String> candidates) async {
  for (var i = 0; i < candidates.length; i++) {
    final uri = Uri.parse(candidates[i]);
    final isLast = i == candidates.length - 1;
    try {
      // 마지막(구글 웹)은 항상 열리므로 판정 없이 실행. 앞의 앱 스킴은 설치 확인 후에만.
      if (isLast || await canLaunchUrl(uri)) {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return true;
      }
    } catch (_) {
      // 이 후보 실패 → 다음 후보로 (조용히)
    }
  }
  return false;
}
