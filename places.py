#!/usr/bin/env python3
"""
가볼 만한 곳 파이프라인 — TourAPI(KorService2)에서 수도권 상설 나들이 장소를 큐레이션해
places.json 을 만든다. 행사(poller.py/feed.json)와 별개 트랙: 거의 안 변하는 정적 데이터라
월 1회 갱신이면 충분하고, 신규 감지가 필요 없어 TourAPI의 약점(신규 신호 없음)이 문제 안 됨.

큐레이션(핵심): 수도권 관광지 원본 ~4천 건 중 대부분은 유적지·근린공원이라 그대로 내보내면
디렉토리 쓰레기장이 된다 → 신분류체계(lclsSystm) 화이트리스트 + 제목 키워드 + 상세(체험연령·
유모차) 스코어링으로 아이 적합 장소만 추린다.

분류 코드(2026-07-16 lclsSystmCode2 실측):
  Tier A(아이 명소 확정): VE020100 테마파크 / VE020200 워터파크 / VE020300 동물원 /
    VE020400 수족관 / VE020500 천문대 / VE070500 과학관
  Tier B(대체로 적합): VE070100 박물관 / VE070300 전시관 / EX01·02·03 체험(전통·공예·농산어촌) /
    NA040600 자연휴양림 / NA040700 수목원·정원 / NA030400 생태습지
  그 외는 제목 키워드가 있을 때만(예: VE03 도시공원 중 '어린이대공원', LS 중 '눈썰매장').

호출 예산: data.go.kr 개발키 일 1,000회 제한 → 목록(≈20콜)은 싸고, 상세(detailIntro2)는
후보에게만 + places_state.json 캐시로 재실행 시 0에 수렴. DETAIL_BUDGET로 상한.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

KST = timezone(timedelta(hours=9))
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_PATH = os.environ.get("PLACES_STATE", os.path.join(BASE_DIR, "places_state.json"))
OUT_PATH = os.environ.get("PLACES_OUT", os.path.join(BASE_DIR, "places.json"))
BASE = "https://apis.data.go.kr/B551011/KorService2"
DETAIL_BUDGET = int(os.environ.get("DETAIL_BUDGET", "500"))
TIMEOUT = 30

REGIONS = {"11": "서울", "28": "인천", "41": "경기"}
CONTENT_TYPES = ("12", "14", "28")  # 관광지 / 문화시설 / 레포츠

TIER_A = {"VE020100": "테마파크", "VE020200": "워터파크", "VE020300": "동물원",
          "VE020400": "수족관", "VE020500": "천문대", "VE070500": "과학관"}
TIER_B = {"VE070100": "박물관", "VE070300": "전시관",
          "NA040600": "자연휴양림", "NA040700": "수목원·정원", "NA030400": "생태습지"}
TIER_B2 = {"EX01": "전통체험", "EX02": "공예체험", "EX03": "농촌체험"}  # 중분류 단위
KID_KW = re.compile(r"어린이|아이|키즈|유아|가족|체험|동물|목장|승마|썰매|물놀이|놀이공원|"
                    r"테마파크|아쿠아|공룡|과학관|천문|캠핑|피크닉|짚라인|레일바이크|트램펄린")
# 화이트리스트 밖 폴백용 '강한' 키워드 — 약한 신호(체험/가족/공원)로 폴백을 열면
# '명소' 400건이 쏟아진다(1차 실행 실측) → 폴백은 확실한 것만.
STRONG_KW = re.compile(r"어린이|키즈|동물|아쿠아|썰매|공룡|놀이공원|테마파크|목장|천문|트램펄린|짚라인|레일바이크")
EXCLUDE_KW = re.compile(r"골프|사격|클레이|카지노|경륜|성인|유흥|둘레길|올림픽홀")
# 대표 가족 명소 수동 시드 — 분류코드(레저/랜드마크)와 키워드 양쪽에서 새는 유명 장소들.
# 1차 실행 검증에서 렛츠런파크(경마공원)·허브아일랜드·임진각이 빠진 것을 보고 도입.
SEED = ("렛츠런파크", "허브아일랜드", "임진각", "평화누리", "헤이리", "쁘띠프랑스",
        "포천아트밸리", "광명동굴", "두물머리", "물의정원", "서울숲", "월미테마파크",
        "월미공원", "소래습지", "국립수목원", "서울식물원", "하늘공원", "올림픽공원")


def _key():
    v = os.environ.get("DATA_GO_KR_KEY", "").strip()
    if v:
        return v
    p = os.path.expanduser("~/.datago_key")
    return open(p).read().strip() if os.path.exists(p) else ""


KEY = _key()


def get(op, retries=3, **params):
    q = {"serviceKey": KEY, "MobileOS": "ETC", "MobileApp": "naduri", "_type": "json"}
    q.update(params)
    url = f"{BASE}/{op}?" + urllib.parse.urlencode(q)
    for a in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as r:
                body = json.loads(r.read().decode("utf-8", "replace"))
            return body["response"]["body"]
        except Exception:
            if a == retries - 1:
                raise
            time.sleep(2 * (a + 1))


def items_of(body):
    it = (body.get("items") or {})
    if not it:
        return []
    lst = it.get("item", [])
    return lst if isinstance(lst, list) else [lst]


def clean(s):
    return re.sub(r"\s+", " ", str(s)).strip() if s else ""


def fetch_lists():
    """지역×타입 전량 목록. 페이지당 1000행."""
    out = []
    for regn, area in REGIONS.items():
        for ct in CONTENT_TYPES:
            page = 1
            while True:
                b = get("areaBasedList2", contentTypeId=ct, lDongRegnCd=regn,
                        numOfRows=1000, pageNo=page)
                rows = items_of(b)
                total = int(b.get("totalCount") or 0)
                for r in rows:
                    r["_area"] = area
                out.extend(rows)
                if page * 1000 >= total or not rows:
                    break
                page += 1
    return out


def base_score(r):
    """목록 필드만으로 1차 스코어. (상세 호출 대상 선정용)"""
    l3, l2 = clean(r.get("lclsSystm3")), clean(r.get("lclsSystm2"))
    title = clean(r.get("title"))
    if EXCLUDE_KW.search(title):
        return 0, ""
    fallback_cat = {"VE03": "공원", "LS01": "레포츠", "LS02": "물놀이", "VE01": "명소"}.get(l2, "명소")
    if any(s in title for s in SEED):
        # 시드는 무조건 포함 — 분류가 있으면 그 카테고리, 없으면 폴백 라벨
        cat = TIER_A.get(l3) or TIER_B.get(l3) or TIER_B2.get(l2) or fallback_cat
        return 4, cat
    if l3 in TIER_A:
        return 3, TIER_A[l3]
    if l3 in TIER_B:
        return 2, TIER_B[l3]
    if l2 in TIER_B2:
        return 2, TIER_B2[l2]
    if STRONG_KW.search(title):
        # 화이트리스트 밖(도시공원·레포츠 등)은 '강한' 아이 신호가 있을 때만 후보
        return 2, fallback_cat
    return 0, ""


CACHE_VER = 2  # 추출 필드가 늘면 올린다(v2: parking 추가) — 구버전 캐시는 예산 내에서 재조회


def detail_intro(state, cid, ct, budget):
    """detailIntro2 캐시 조회 — 유모차/체험연령/체험내용/휴무일/주차.
    성공(내용이 비어도)만 캐시한다. 실패를 캐시하면 일시 장애(일일 쿼터 초과 등)가
    영구 빈값으로 굳는다 → 실패는 캐시 없이 다음 실행에서 재시도."""
    cache = state.setdefault("intro", {})
    det = cache.get(cid)
    if det is not None and (det.get("_v") == CACHE_VER or budget[0] <= 0):
        return det  # 최신 캐시, 또는 구버전이지만 예산이 없어 그대로 사용
    if budget[0] <= 0:
        return None  # 예산 소진 — 캐시 안 함(다음 실행에서 재시도)
    budget[0] -= 1
    try:
        b = get("detailIntro2", contentId=cid, contentTypeId=ct)
        row = (items_of(b) or [{}])[0]
        det = {"_v": CACHE_VER}
        for k, v in row.items():
            v = clean(v)
            if not v:
                continue
            lk = k.lower()
            if "babycarriage" in lk and "rent" not in lk:
                det["stroller"] = v  # '있음'/'없음' 등 원문
            elif "agerange" in lk:
                det["age"] = v
            elif lk == "expguide":
                det["exp"] = v
            elif "restdate" in lk:
                det["rest"] = v
            elif lk.startswith("parking") and "fee" not in lk:
                det["parking"] = v  # 주차 안내 원문('가능 (소형 1000대)' 등)
        cache[cid] = det
        return det
    except Exception:
        return {}


def main():
    now = datetime.now(KST).replace(tzinfo=None)
    try:
        state = json.load(open(STATE_PATH, encoding="utf-8"))
    except Exception:
        state = {}

    rows = fetch_lists()
    print(f"목록 수집: {len(rows)}건 (지역 3 × 타입 3)")

    # contentid 중복 제거(문화시설/관광지 양쪽 등록 사례) — 먼저 나온 것 우선
    seen, uniq = set(), []
    for r in rows:
        cid = clean(r.get("contentid"))
        if cid and cid not in seen:
            seen.add(cid)
            uniq.append(r)

    budget = [DETAIL_BUDGET]
    places, dropped_budget = [], 0
    for r in uniq:
        score, cat = base_score(r)
        if score < 2:
            continue
        cid, ct = clean(r.get("contentid")), clean(r.get("contenttypeid"))
        title = clean(r.get("title"))
        det = detail_intro(state, cid, ct, budget)
        if det is None:
            dropped_budget += 1
            det = {}
        # 상세 신호로 보정: 체험연령/유모차 있으면 +1, 제목 키워드 +1
        if det.get("age") or det.get("stroller", "").startswith("있"):
            score += 1
        if KID_KW.search(title):
            score += 1
        addr = clean(r.get("addr1"))
        m = re.match(r"\S+\s+(\S+?[시군구])", addr)
        try:
            lat, lng = float(r.get("mapy") or 0), float(r.get("mapx") or 0)
        except ValueError:
            lat = lng = 0
        places.append({
            "id": cid,
            "title": title,
            "area": r["_area"],
            "sigungu": m.group(1) if m else "",
            "cat": cat,
            "img": clean(r.get("firstimage")),
            "addr": addr,
            "lat": lat if 33 <= lat <= 39 else None,
            "lng": lng if 124 <= lng <= 132 else None,
            "stroller": det.get("stroller", ""),
            "age": det.get("age", ""),
            "exp": det.get("exp", "")[:120],
            "rest": det.get("rest", "")[:80],
            "parking": det.get("parking", "")[:80],
            "score": score,
        })

    # 품질 컷: 스코어 내림차순 정렬. 이미지 없는 곳은 뒤로(카드 UX).
    places.sort(key=lambda p: (-p["score"], not p["img"], p["title"]))

    out = {
        "version": 1,
        "generated_at": now.strftime("%Y-%m-%d %H:%M:%S"),
        "counts": {"places": len(places),
                   **{a: sum(1 for p in places if p["area"] == a) for a in REGIONS.values()}},
        "places": places,
    }
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, separators=(",", ":"))
    print(f"places.json: {out['counts']} budget_left={budget[0]} budget_miss={dropped_budget} "
          f"({os.path.getsize(OUT_PATH)//1024}KB)")

    # sanity: 너무 적으면(분류 개편 등) 실패 처리 — 빈 파일 커밋 방지
    if len(places) < 80:
        print("[fatal] sanity 실패 — 장소가 비정상적으로 적음", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
