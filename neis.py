"""NEIS 오픈 API 래퍼 — 시간표앱(SPEC.md)용 검증 코드이자 Swift 포팅의 원본.

2026-08-26 실측 조사(에이전트 6개, 호출 64회)로 확인된 규칙을 코드로 고정한다.
사용:  python neis.py --check
키:    발급받으면 환경변수 NEIS_KEY로 전달 (없으면 응답이 5행에서 조용히 잘림)
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

BASE = "https://open.neis.go.kr/hub/"
KEY = os.environ.get("NEIS_KEY", "")


class NeisError(RuntimeError):
    pass


def call(endpoint, **params):
    params = {"Type": "json", "pSize": 100, **params}
    if KEY:
        params["KEY"] = KEY
    # urlencode가 한글을 UTF-8로 percent-encoding — CP949로 보내면 서버가 조용히 INFO-200을 준다
    url = BASE + endpoint + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=10) as r:
        body = json.load(r)
    if endpoint in body:  # 성공 봉투: {엔드포인트명: [{head: [총계, RESULT]}, {row: [...]}]}
        head = body[endpoint][0]["head"]
        rows = body[endpoint][1]["row"]
        total = head[0]["list_total_count"]
        if len(rows) < total:
            print(f"경고: {endpoint} {len(rows)}/{total}행만 수신 — 키 없는 호출은 5행 제한 (NEIS_KEY 필요)",
                  file=sys.stderr)
        return rows
    # 실패/빈결과 봉투: 루트 키 없이 {RESULT: {CODE}}. HTTP는 항상 200이라 코드로만 판별
    code = body.get("RESULT", {}).get("CODE", "?")
    if code == "INFO-200":  # 주말 / 미업로드 / 잘못된 필터 / 잘못된 학교코드 — 구분 불가, 전부 빈 결과
        return []
    raise NeisError(f"{endpoint}: {code} {body.get('RESULT', {}).get('MESSAGE', '')}")


def search_school(name, kind=None):
    """SCHUL_NM은 부분일치라 '중앙중학교'도 전국 29곳 — 정확명 매칭·표시는 호출자 몫."""
    p = {"SCHUL_NM": name}
    if kind:
        p["SCHUL_KND_SC_NM"] = kind  # 초등학교/중학교/고등학교 — 서버측 필터 동작 확인됨
    return [{
        "office": r["ATPT_OFCDC_SC_CODE"], "code": r["SD_SCHUL_CODE"],  # 이 쌍이 학교의 영구 키
        "name": r["SCHUL_NM"], "kind": r["SCHUL_KND_SC_NM"],
        "region": r["LCTN_SC_NM"], "addr": r.get("ORG_RDNMA") or "",  # 동명 학교 구분용
    } for r in call("schoolInfo", **p)]


TIMETABLE_EP = {"초등학교": "elsTimetable", "중학교": "misTimetable", "고등학교": "hisTimetable"}


def timetable(school, ymd, grade, class_nm):
    """하루치 시간표. AY/SEM은 보내지 않는다 — 없어도 되고, 틀리면 INFO-200 (실측).
    빈 결과는 정상 상황(주말·업로드 지연)이므로 앱은 최근 캐시로 폴백할 것."""
    rows = call(TIMETABLE_EP[school["kind"]],
                ATPT_OFCDC_SC_CODE=school["office"], SD_SCHUL_CODE=school["code"],
                ALL_TI_YMD=ymd, GRADE=str(grade), CLASS_NM=str(class_nm))
    rows.sort(key=lambda r: int(r["PERIO"]))  # 모든 값이 문자열 — 교시는 숫자로 정렬
    return [{"period": int(r["PERIO"]), "subject": r["ITRT_CNTNT"]} for r in rows]


ALLERGY_RE = re.compile(r"\(([0-9.]+)\)")  # 메뉴명 자체의 괄호("유부초밥(덕)")는 숫자·점만 매칭해 배제


def meals(school, ymd):
    rows = call("mealServiceDietInfo",
                ATPT_OFCDC_SC_CODE=school["office"], SD_SCHUL_CODE=school["code"], MLSV_YMD=ymd)
    out = []
    for r in rows:  # 행 정렬이 끼니 우선이라 날짜 그룹핑이 필요하면 호출자에서
        dishes = []
        for seg in r["DDISH_NM"].split("<br/>"):
            seg = seg.strip()
            if not seg:
                continue
            m = ALLERGY_RE.search(seg)
            allergy = [int(n) for n in m.group(1).split(".") if n] if m else []  # 표준 1~19 코드
            dishes.append({"name": ALLERGY_RE.sub("", seg).strip(), "allergy": allergy})
        out.append({"meal": r["MMEAL_SC_NM"], "dishes": dishes, "kcal": r["CAL_INFO"]})
    return out


def schedule(school, from_ymd, to_ymd):
    """학사일정. AY 파라미터는 조용히 무시되므로 날짜 범위로만 거른다.
    시험은 '고사'가 EVENT_NM에 포함된 하루당 1행 — D-day는 연속 행을 묶어 min(date)."""
    return [{"date": r["AA_YMD"], "name": r["EVENT_NM"]}
            for r in call("SchoolSchedule",
                          ATPT_OFCDC_SC_CODE=school["office"], SD_SCHUL_CODE=school["code"],
                          AA_FROM_YMD=from_ymd, AA_TO_YMD=to_ymd)]


def check():
    """실측으로 고정된 날짜·값에 대한 자가검증. 네트워크 필요."""
    seoul = next(s for s in search_school("서울고등학교", kind="고등학교")
                 if s["name"] == "서울고등학교")  # 부분일치 대응: 정확명은 클라이언트에서
    assert (seoul["office"], seoul["code"]) == ("B10", "7010083"), seoul

    tt = timetable(seoul, "20260824", 1, 1)  # 검증된 날짜 (총 6행, 키 없으면 5행 수신)
    assert tt and tt[0]["period"] == 1, tt
    assert tt == sorted(tt, key=lambda x: x["period"]), tt
    assert any(x["subject"] == "공통국어2" for x in tt), tt

    assert timetable(seoul, "20260829", 1, 1) == []  # 토요일 → INFO-200 → 빈 목록

    lunch = next(x for x in meals(seoul, "20260826") if x["meal"] == "중식")
    rice = next(d for d in lunch["dishes"] if d["name"] == "쌀밥")
    assert rice["allergy"] == [], rice                       # 무알레르기 메뉴는 빈 목록
    assert any(d["allergy"] for d in lunch["dishes"]), lunch  # 알레르기 숫자 파싱 동작

    ev = schedule(seoul, "20261012", "20261013")  # 중간고사 이틀 (실측 확인)
    assert ev and all("고사" in e["name"] for e in ev), ev

    print("OK — 자가검증 통과" + ("" if KEY else " (키 없는 모드: 5행 잘림 경고는 정상)"))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    check() if "--check" in sys.argv else print(__doc__)
