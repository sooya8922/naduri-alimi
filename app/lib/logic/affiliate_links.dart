/// 어필리에이트 링크 생성 — 순수 함수(테스트 대상).
///
/// 마이리얼트립 마케팅 파트너 구조(2026-07-16 실측, 유저 발급 링크 리다이렉트 분석):
///   https://myrealt.rip/xxxx → /main/bridge/marketing?return_url=<상품URL+utm_source=mktpartner&t_scope=86400&mylink_id=NNN>
///   - mylink_id: 파트너 대시보드에서 만든 링크의 ID(파트너 귀속이 서버에 매핑, 비밀 아님 — 공유 링크에 노출되는 값)
///   - t_scope=86400: 어트리뷰션 창 24시간
/// 브릿지는 같은 도메인의 임의 return_url을 수용(검색 페이지 200 확인) → 장소명 검색 링크를 템플릿화.
/// ⚠ 공식 대시보드는 상품 단위 링크만 만들어주므로 이 방식은 회색지대 —
///   배포 후 대시보드 클릭 집계로 귀속 동작을 검증하고, 안 되면 대표 장소 수동 링크(플랜B)로 전환.
library;

/// 유저(sooya8922)의 마이리얼트립 마케팅 파트너 링크 ID.
const mrtMylinkId = '2405198';

/// 장소명으로 마이리얼트립 검색 결과에 어필리에이트 트래킹을 태워 보내는 URL.
String buildMrtSearchLink(String placeTitle) {
  final search = Uri(
    scheme: 'https',
    host: 'www.myrealtrip.com',
    path: '/search',
    queryParameters: {
      'q': placeTitle,
      'utm_source': 'mktpartner',
      't_scope': '86400',
      'mylink_id': mrtMylinkId,
    },
  ).toString();
  return Uri(
    scheme: 'https',
    host: 'www.myrealtrip.com',
    path: '/main/bridge/marketing',
    queryParameters: {'return_url': search},
  ).toString();
}
