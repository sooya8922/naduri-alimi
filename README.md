# 나들이 알리미 🧺

아이와 주말 나들이 — 서울·경기·인천의 새 행사를 푸시로 알려주는 앱.
"찾아보는 앱"이 아니라 **"알려주는 앱"**: 조건(지역/아이/무료/키워드)을 걸어두면
새 행사가 올라올 때, 그리고 목·금 저녁 "이번 주말 아이랑" 다이제스트로 알림이 온다.

## 구조 (chwiso-allimi 패턴 재사용)

```
poller.py            4개 공공 API → feed.json (GHA cron, 하루 2회)
state.json           id→first_seen + 상세 캐시 (신규 감지·API 호출 절약)
feed.json            앱이 raw.githubusercontent.com 으로 받는 유일한 데이터(서버 없음)
app/                 Flutter 앱 (WorkManager 6h 폴링 + 로컬 알림)
.github/workflows/   poll.yml(수집) · app.yml(CI) · release.yml(태그→APK 릴리스)
```

## 데이터 소스 (2026-07 실측 검증)

| 소스 | 담당 | 신규 감지 |
|---|---|---|
| 서울시 문화행사 API | 서울 행사 전반 | first_seen |
| KOPIS (kidstate=Y) | 서울·경기·인천 아동공연 | first_seen |
| KCISA 한눈에보는문화정보 | 경기·인천 전시·교육체험·아동가족 | first_seen |
| 전국문화축제표준데이터 | 수도권 대형축제 (분기 갱신 — 신규 알림 제외) | — |

소스 간 중복은 제목 정규화+시작일 키로 병합(우선순위 seoul>kopis>kcisa>fstvl, 빈 필드 백필).

주의(실측 함정): KCISA 페이징은 문서(cPage/rows)와 달리 `PageNo`/`numOfrows`.
서울시 API는 LAT/LOT 값이 뒤바뀐 행이 있어 값 범위로 판정. KOPIS 목록 조회창 최대 31일.

## 시크릿 (GH Actions)

`SEOUL_API_KEY` `DATA_GO_KR_KEY` `KOPIS_KEY` — 수집 API 키
`KEYSTORE_BASE64` `KEYSTORE_PASSWORD` — APK 고정 업로드키(업데이트 설치 호환)

## 배포

`git tag v0.x.y && git push --tags` → release.yml이 서명 APK를 GitHub Release에 첨부
→ 폰에서 릴리스 페이지 열어 APK 다운로드/설치.

## 함께 보면 좋은 입장권 🎟

- [에버랜드 입장권 (쿠팡)](https://link.coupang.com/a/fqDTJBSYRE)
- 앱의 "가볼 곳" 탭 → 장소 상세 → **입장권·할인 보기**에서 마이리얼트립 입장권을 볼 수 있습니다.

> 이 저장소와 앱은 쿠팡 파트너스 활동의 일환으로, 이에 따른 일정액의 수수료를 제공받을 수 있습니다.
> 앱의 입장권 링크는 마이리얼트립 마케팅 파트너 활동으로, 구매 시 수수료를 제공받을 수 있습니다.
