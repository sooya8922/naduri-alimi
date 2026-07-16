#!/usr/bin/env python3
"""
나들이 알리미 폴러 — 4개 공공 API에서 수도권 행사를 수집해 feed.json을 만든다.

소스(실측 검증 2026-07-14~15, 검증 로그는 메모리/README 참고):
  seoul  서울시 문화행사 API(culturalEventInfo)   — 서울 행사 전반, RGSTDATE 없음(피드에선 first_seen으로 신규 판정)
  kopis  공연예술통합전산망(kidstate=Y)           — 서울·경기·인천 아동공연. 목록 조회창 최대 31일 → 청크 분할
  kcisa  한눈에보는문화정보(B553457/cultureinfo)  — 경기·인천 전시/교육체험/아동가족 보강.
                                                  ⚠ 문서의 cPage/rows는 무시됨 → 실제는 PageNo/numOfrows (실측)
  fstvl  전국문화축제표준데이터                    — 대형축제 정적 보강(분기 갱신이라 신규감지 소스로는 안 씀)

구조:
  state.json  id→first_seen 맵 + KOPIS/KCISA 상세 캐시(상세 API 호출을 신규 항목으로 한정)
  feed.json   앱이 raw.githubusercontent.com 으로 받는 유일한 데이터(서버 불필요 — chwiso 패턴)

신규 판정: 이번 수집에서 처음 본 id에 first_seen을 찍고, 48시간 내 first_seen이면 new[].
첫 실행(빈 state)은 기준선만 만들고 new를 비운다(설치 직후 알림 폭탄 방지 — chwiso 교훈).
"""
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from hashlib import sha1

KST = timezone(timedelta(hours=9))
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATE_PATH = os.environ.get("STATE_PATH", os.path.join(BASE_DIR, "state.json"))
FEED_PATH = os.environ.get("FEED_OUT", os.path.join(BASE_DIR, "feed.json"))

HORIZON_DAYS = 42        # 피드에 담을 미래 범위(6주)
NEW_WINDOW_H = 48        # first_seen이 이 시간 내면 '신규'
DETAIL_BUDGET = 400      # 한 번의 실행에서 새로 부를 상세 API 상한(KOPIS+KCISA 합)
TIMEOUT = 30

KID_KW = re.compile(r"어린이|아동|키즈|유아|가족|자녀|초등|인형극|동요|영유아|아기|베이비")


def _env_key(name, path):
    """키 로딩: GHA에선 시크릿 env, 로컬에선 chmod600 파일. 키는 절대 로그에 찍지 않는다."""
    v = os.environ.get(name, "").strip()
    if v:
        return v
    p = os.path.expanduser(path)
    if os.path.exists(p):
        return open(p).read().strip()
    return ""


SEOUL_KEY = _env_key("SEOUL_API_KEY", "~/chwiso-allimi/.seoul_key")
DATAGO_KEY = _env_key("DATA_GO_KR_KEY", "~/.datago_key")
KOPIS_KEY = _env_key("KOPIS_KEY", "~/.kopis_key")


def clean(s):
    """HTML 엔티티 해제(&lt; &middot; 중첩 인코딩 포함) + 공백 정리. None-safe."""
    if not s:
        return ""
    t = str(s)
    for _ in range(3):  # &amp;middot; 같은 이중 인코딩 흡수
        u = html.unescape(t)
        if u == t:
            break
        t = u
    return re.sub(r"\s+", " ", t).strip()


def http_get(url, retries=3, sleep=2):
    for a in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as r:
                return r.read()
        except Exception as e:
            if a == retries - 1:
                raise
            time.sleep(sleep * (a + 1))


def get_json(url):
    raw = http_get(url).decode("utf-8", "replace")
    # 공연행사표준에서 실측된 제어문자 오염 방어(다른 API도 동일 방어)
    return json.loads(re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", " ", raw))


def get_xml(url):
    return ET.fromstring(http_get(url))


def norm_date(s):
    """다양한 날짜 표기 → 'YYYY-MM-DD'. 실패 시 ''."""
    s = clean(s).replace(".", "-").replace("/", "-")
    m = re.match(r"(\d{4})-?(\d{2})-?(\d{2})", s)
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else ""


def parse_coord(v):
    """좌표 파싱 — 서울API에 '37.57~2' 같은 파손값 실존(실측 7건) → 관대 파싱."""
    m = re.match(r"-?\d+\.?\d*", clean(v))
    try:
        return float(m.group()) if m else None
    except ValueError:
        return None


def fix_latlng(a, b):
    """(a,b) 순서 불명의 좌표쌍 → (lat, lng). 서울API는 LAT/LOT 값이 뒤바뀐 행 실존 → 값 범위로 판정.
    한국: lat 33~39, lng 124~132. 범위 밖이면 (None, None)."""
    for lat, lng in ((a, b), (b, a)):
        if lat is not None and lng is not None and 33 <= lat <= 39 and 124 <= lng <= 132:
            return lat, lng
    return None, None


def is_kid(*texts):
    return any(KID_KW.search(t or "") for t in texts)


def event(src, native_id, **kw):
    """정규화 이벤트. id는 소스 프리픽스로 전역 유일."""
    e = {
        "id": f"{src}:{native_id}",
        "source": src,
        "title": "", "place": "", "area": "", "sigungu": "",
        "start": "", "end": "", "cat": "",
        "kid": False, "age": "", "free": None, "price": "",
        "img": "", "url": "", "lat": None, "lng": None,
    }
    e.update(kw)
    return e


# ──────────────────────────── 소스별 수집 ────────────────────────────

def fetch_seoul(today, horizon):
    """서울시 문화행사 — 전량 페이징 후 기간 필터(과거 19k 누적이라 필터 필수)."""
    out, start = [], 1
    total = None
    while True:
        end = start + 999
        url = f"http://openapi.seoul.go.kr:8088/{SEOUL_KEY}/json/culturalEventInfo/{start}/{end}/"
        j = get_json(url)
        body = j.get("culturalEventInfo") or {}
        if total is None:
            total = int(body.get("list_total_count") or 0)
        rows = body.get("row") or []
        if not rows:
            break
        for r in rows:
            s, e = norm_date(r.get("STRTDATE")), norm_date(r.get("END_DATE"))
            if not s or not e or e < today or s > horizon:
                continue
            lat, lng = fix_latlng(parse_coord(r.get("LAT")), parse_coord(r.get("LOT")))
            title = clean(r.get("TITLE"))
            target = clean(r.get("USE_TRGT"))
            free_raw = clean(r.get("IS_FREE"))
            nid = sha1(f"{title}|{s}|{clean(r.get('PLACE'))}".encode()).hexdigest()[:16]
            out.append(event(
                "seoul", nid,
                title=title, place=clean(r.get("PLACE")), area="서울",
                sigungu=clean(r.get("GUNAME")), start=s, end=e,
                cat=clean(r.get("CODENAME")),
                kid=is_kid(title, target, clean(r.get("CODENAME"))),
                age=target,
                free=(True if free_raw == "무료" else False if free_raw == "유료" else None),
                price=clean(r.get("USE_FEE")),
                img=clean(r.get("MAIN_IMG")), url=clean(r.get("ORG_LINK")) or clean(r.get("HMPG_ADDR")),
                lat=lat, lng=lng,
            ))
        start = end + 1
        if start > total:
            break
    return out


def _kopis_list(sig, st, ed):
    rows, page = [], 1
    while True:
        q = urllib.parse.urlencode({
            "service": KOPIS_KEY, "stdate": st, "eddate": ed,
            "cpage": page, "rows": 100, "signgucode": sig, "kidstate": "Y",
        })
        root = get_xml(f"http://www.kopis.or.kr/openApi/restful/pblprfr?{q}")
        batch = root.findall(".//db")
        rows.extend(batch)
        if len(batch) < 100:
            return rows
        page += 1


def fetch_kopis(today, horizon, state, budget):
    """KOPIS 아동공연(서울11/경기41/인천28). 조회창 31일 제한 → 청크. 상세/시설은 캐시."""
    d0 = datetime.strptime(today, "%Y-%m-%d")
    dH = datetime.strptime(horizon, "%Y-%m-%d")
    chunks = []
    cur = d0
    while cur <= dH:
        nxt = min(cur + timedelta(days=30), dH)
        chunks.append((cur.strftime("%Y%m%d"), nxt.strftime("%Y%m%d")))
        cur = nxt + timedelta(days=1)

    dcache = state.setdefault("kopis_detail", {})
    fcache = state.setdefault("kopis_fac", {})
    area_by_sig = {"11": "서울", "41": "경기", "28": "인천"}
    seen, out = set(), []
    for sig, area in area_by_sig.items():
        for st, ed in chunks:
            for db in _kopis_list(sig, st, ed):
                mid = clean(db.findtext("mt20id"))
                if not mid or mid in seen:
                    continue
                seen.add(mid)
                det = dcache.get(mid)
                if det is None and budget[0] > 0:
                    budget[0] -= 1
                    try:
                        droot = get_xml(f"http://www.kopis.or.kr/openApi/restful/pblprfr/{mid}?"
                                        + urllib.parse.urlencode({"service": KOPIS_KEY}))
                        d = droot.find(".//db")
                        det = {
                            "age": clean(d.findtext("prfage")) if d is not None else "",
                            "price": clean(d.findtext("pcseguidance")) if d is not None else "",
                            "fac": clean(d.findtext("mt10id")) if d is not None else "",
                        }
                        dcache[mid] = det
                    except Exception:
                        det = None
                det = det or {}
                lat = lng = None
                fac = det.get("fac", "")
                if fac:
                    fc = fcache.get(fac)
                    if fc is None and budget[0] > 0:
                        budget[0] -= 1
                        try:
                            froot = get_xml(f"http://www.kopis.or.kr/openApi/restful/prfplc/{fac}?"
                                            + urllib.parse.urlencode({"service": KOPIS_KEY}))
                            f = froot.find(".//db")
                            fc = {"la": clean(f.findtext("la")) if f is not None else "",
                                  "lo": clean(f.findtext("lo")) if f is not None else "",
                                  "adres": clean(f.findtext("adres")) if f is not None else ""}
                            fcache[fac] = fc
                        except Exception:
                            fc = None
                    if fc:
                        lat, lng = fix_latlng(parse_coord(fc.get("la")), parse_coord(fc.get("lo")))
                price = det.get("price", "")
                # 시군구는 시설 주소에서 추출("경기도 수원시 …" → 수원시)
                fc0 = fcache.get(fac) or {}
                mg = re.match(r"\S+\s+(\S+?[시군구])", fc0.get("adres", ""))
                out.append(event(
                    "kopis", mid,
                    title=clean(db.findtext("prfnm")), place=clean(db.findtext("fcltynm")),
                    area=area, sigungu=mg.group(1) if mg else "",
                    start=norm_date(db.findtext("prfpdfrom")), end=norm_date(db.findtext("prfpdto")),
                    cat=clean(db.findtext("genrenm")) or "공연",
                    kid=True, age=det.get("age", ""),
                    free=(True if "무료" in price else False if price else None), price=price,
                    img=clean(db.findtext("poster")),
                    url=f"https://www.kopis.or.kr/por/db/pblprfr/pblprfrView.do?mt20Id={mid}",
                    lat=lat, lng=lng,
                ))
    return out


def fetch_kcisa(today, horizon, state, budget):
    """KCISA 한눈에보는문화정보 — 경기·인천만 채택(서울은 서울시API가 더 좋음, 중복만 늘림).
    ⚠ 페이징은 PageNo/numOfrows (문서의 cPage/rows는 무시됨 — 1페이지만 반복 수신되는 함정, 실측)."""
    frm, to = today.replace("-", ""), horizon.replace("-", "")
    rows, seen, page = [], set(), 1
    while True:
        q = urllib.parse.urlencode({"serviceKey": DATAGO_KEY, "from": frm, "to": to,
                                    "numOfrows": 100, "PageNo": page})
        root = get_xml(f"https://apis.data.go.kr/B553457/cultureinfo/period2?{q}")
        code = root.findtext(".//resultCode")
        if code not in ("00", None):
            raise RuntimeError(f"KCISA resultCode={code}")
        total = int(root.findtext(".//totalCount") or 0)
        for it in root.findall(".//item"):
            s = clean(it.findtext("seq"))
            if s and s not in seen:
                seen.add(s)
                rows.append(it)
        if page * 100 >= total:
            break
        page += 1

    dcache = state.setdefault("kcisa_detail", {})
    out = []
    for it in rows:
        area = clean(it.findtext("area"))
        if area not in ("경기", "인천"):
            continue
        seq = clean(it.findtext("seq"))
        title = clean(it.findtext("title"))
        realm = clean(it.findtext("realmName"))
        det = dcache.get(seq)
        if det is None and budget[0] > 0:
            budget[0] -= 1
            try:
                q = urllib.parse.urlencode({"serviceKey": DATAGO_KEY, "seq": seq})
                droot = get_xml(f"https://apis.data.go.kr/B553457/cultureinfo/detail2?{q}")
                d = droot.find(".//item")
                det = {"price": clean(d.findtext("price")) if d is not None else "",
                       "url": clean(d.findtext("url")) if d is not None else ""}
                dcache[seq] = det
            except Exception:
                det = None
        det = det or {}
        lat, lng = fix_latlng(parse_coord(it.findtext("gpsY")), parse_coord(it.findtext("gpsX")))
        price = det.get("price", "")
        out.append(event(
            "kcisa", seq,
            title=title, place=clean(it.findtext("place")), area=area,
            sigungu=clean(it.findtext("sigungu")),
            start=norm_date(it.findtext("startDate")), end=norm_date(it.findtext("endDate")),
            cat=realm,
            kid=(realm == "아동/가족") or is_kid(title, clean(it.findtext("place"))),
            age="",
            free=(True if "무료" in price else False if re.search(r"\d", price) else None), price=price,
            img=clean(it.findtext("thumbnail")), url=det.get("url", ""),
            lat=lat, lng=lng,
        ))
    return out


def fetch_fstvl(today, horizon):
    """전국문화축제표준 — 수도권 + 기간 겹침만. 분기 갱신 정적 데이터라 신규감지엔 안 쓰고
    다이제스트 보강용(대형축제: 펜타포트·송도해변축제 등이 실측에서 정확히 잡힘)."""
    out, page = [], 1
    while True:
        q = urllib.parse.urlencode({"serviceKey": DATAGO_KEY, "pageNo": page,
                                    "numOfRows": 800, "type": "json"})
        j = get_json(f"http://api.data.go.kr/openapi/tn_pubr_public_cltur_fstvl_api?{q}")
        body = j["response"]["body"]
        rows = body.get("items") or []
        total = int(body.get("totalCount") or 0)
        for r in rows:
            s, e = norm_date(r.get("fstvlStartDate")), norm_date(r.get("fstvlEndDate"))
            if not s or not e or e < today or s > horizon:
                continue
            addr = clean(r.get("rdnmadr")) or clean(r.get("lnmadr"))
            area = ("서울" if addr.startswith("서울") else "경기" if addr.startswith("경기")
                    else "인천" if addr.startswith("인천") else "")
            if not area:
                continue
            m = re.match(r"\S+\s+(\S+?[시군구])", addr)
            title = clean(r.get("fstvlNm"))
            desc = clean(r.get("fstvlCo"))
            lat, lng = fix_latlng(parse_coord(r.get("latitude")), parse_coord(r.get("longitude")))
            nid = sha1(f"{title}|{s}".encode()).hexdigest()[:16]
            out.append(event(
                "fstvl", nid,
                title=title, place=clean(r.get("opar")) or addr, area=area,
                sigungu=m.group(1) if m else "", start=s, end=e, cat="축제",
                kid=is_kid(title, desc), age="",
                free=None, price="",
                img="", url=clean(r.get("homepageUrl")),
                lat=lat, lng=lng,
            ))
        if page * 800 >= total:
            break
        page += 1
    return out


# ──────────────────────────── 병합/신규감지 ────────────────────────────

def dedup_key(e):
    """소스 간 중복 판정: 제목 정규화 + 시작일. (KOPIS 공연이 서울시API에도 오는 실측 중복 대응)"""
    t = re.sub(r"[\[\(【〈<].*?[\]\)】〉>]", "", e["title"])  # [서울] (7.31) 같은 프리픽스 제거
    t = re.sub(r"[^0-9a-z가-힣]", "", t.lower())
    return f"{t}|{e['start']}"


PRIORITY = {"seoul": 0, "kopis": 1, "kcisa": 2, "fstvl": 3}
FILL_FIELDS = ("img", "url", "age", "price", "sigungu", "place")


def merge(events):
    by_key = {}
    for e in sorted(events, key=lambda x: PRIORITY[x["source"]]):
        k = dedup_key(e)
        w = by_key.get(k)
        if w is None:
            by_key[k] = e
            continue
        # 승자(우선순위 높은 소스)에 빈 필드만 백필. kid/free는 더 확실한 신호를 채택.
        for f in FILL_FIELDS:
            if not w[f] and e[f]:
                w[f] = e[f]
        if w["lat"] is None and e["lat"] is not None:
            w["lat"], w["lng"] = e["lat"], e["lng"]
        w["kid"] = w["kid"] or e["kid"]
        if w["free"] is None and e["free"] is not None:
            w["free"] = e["free"]
    return list(by_key.values())


def main():
    now = datetime.now(KST).replace(tzinfo=None)
    today = now.strftime("%Y-%m-%d")
    horizon = (now + timedelta(days=HORIZON_DAYS)).strftime("%Y-%m-%d")
    now_s = now.strftime("%Y-%m-%d %H:%M:%S")

    try:
        state = json.load(open(STATE_PATH, encoding="utf-8"))
    except Exception:
        state = {}
    first_seen = state.setdefault("first_seen", {})
    baseline = not first_seen  # 첫 실행 → new 발행 억제
    if baseline:
        state["baseline_at"] = now_s
    baseline_at = state.get("baseline_at", "0000-01-01 00:00:00")

    budget = [DETAIL_BUDGET]
    all_events, status = [], {}
    for name, fn in (("seoul", lambda: fetch_seoul(today, horizon)),
                     ("kopis", lambda: fetch_kopis(today, horizon, state, budget)),
                     ("kcisa", lambda: fetch_kcisa(today, horizon, state, budget)),
                     ("fstvl", lambda: fetch_fstvl(today, horizon))):
        try:
            evs = fn()
            all_events.extend(evs)
            status[name] = f"ok:{len(evs)}"
        except Exception as ex:
            # 한 소스 장애가 전체 피드를 막지 않는다. 단 아래 sanity에서 최소량은 보장.
            status[name] = f"error:{type(ex).__name__}"
            print(f"[warn] {name} 수집 실패: {type(ex).__name__}: {str(ex)[:120]}", file=sys.stderr)

    events = merge(all_events)
    events.sort(key=lambda e: (e["start"], e["title"]))

    # 신규 감지 — first_seen이 48h 내면 new (실행 시점이 아니라 최초 목격 기준: 앱이 피드를
    # 늦게 받아도 신규를 놓치지 않음, 중복 발송은 앱의 notified 셋이 막음 — chwiso 의미론).
    # 베이스라인 시점에 찍힌 항목은 제외(첫 가동 직후 48h 동안 전량이 '신규'로 나가는 폭탄 방지).
    # fstvl은 분기 스냅샷이라 신규 신호에서 제외.
    for e in events:
        fs = first_seen.get(e["id"])
        if fs is None:
            first_seen[e["id"]] = fs = now_s
        e["seen"] = fs[:16]
    cutoff_new = (now - timedelta(hours=NEW_WINDOW_H)).strftime("%Y-%m-%d %H:%M:%S")
    new_events = [e for e in events
                  if e["source"] != "fstvl"
                  and first_seen[e["id"]] >= cutoff_new
                  and first_seen[e["id"]] > baseline_at]

    # state 청소: 이번에 안 보인 id 중 first_seen이 90일 지난 것 제거(파일 무한성장 방지)
    live = {e["id"] for e in events}
    cutoff = (now - timedelta(days=90)).strftime("%Y-%m-%d %H:%M:%S")
    for k in [k for k, v in first_seen.items() if k not in live and v < cutoff]:
        del first_seen[k]

    feed = {
        "version": 1,
        "generated_at": now_s,
        "sources": status,
        "counts": {"events": len(events), "new": len(new_events),
                   "kid": sum(1 for e in events if e["kid"])},
        "events": events,
        "new": [{"id": e["id"], "title": e["title"], "area": e["area"], "sigungu": e["sigungu"],
                 "start": e["start"], "end": e["end"], "kid": e["kid"], "free": e["free"],
                 "url": e["url"], "seen_at": e["seen"]} for e in new_events],
    }
    with open(FEED_PATH, "w", encoding="utf-8") as f:
        json.dump(feed, f, ensure_ascii=False, separators=(",", ":"))
    with open(STATE_PATH, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, separators=(",", ":"))
    print(f"feed.json: {feed['counts']} sources={status} baseline={baseline} "
          f"detail_budget_left={budget[0]} ({os.path.getsize(FEED_PATH)//1024}KB)")

    # sanity: 서울(주 소스)이 죽었거나 총량이 비정상이면 실패 처리(GHA에서 커밋 방지)
    if len(events) < 50 or not status.get("seoul", "").startswith("ok"):
        print("[fatal] sanity 실패 — 피드 커밋하면 안 됨", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
