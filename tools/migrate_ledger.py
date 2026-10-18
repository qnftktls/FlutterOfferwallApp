#!/usr/bin/env python3
"""
Rewards Hub — serverLedger 복구 및 이관 도구
=============================================

왜 필요한가
-----------
초기 버전의 Cloud Functions 는 원장을 이렇게 기록했습니다:

    { "serverLedger.verified": FieldValue.increment(250) }

Firestore 의 `set(..., { merge: true })` 는 **점(dot)을 필드 경로로 해석하지
않습니다.** 그래서 실제로는 `serverLedger` 라는 중첩 맵이 아니라,
`serverLedger.verified` 라는 **이름 자체에 점이 들어간 단일 필드**가
저장됐습니다. `readLedger()` 는 중첩 맵만 읽으므로 항상 0 을 반환했고,
결과적으로 **정상 사용자가 출금할 수 없게** 되었습니다.

함수 코드는 이미 중첩 객체를 쓰도록 수정되었습니다(tools/../functions/src/index.ts).
이 스크립트는 그 이전에 이미 잘못 저장된 문서를 되돌립니다.

두 가지 모드
------------
1) --repair (기본값 dry-run)
   `serverLedger.<bucket>` 형태의 점(.) 필드를 찾아, 값을 보존한 채
   올바른 중첩 맵 `serverLedger: { verified, unverified }` 로 옮기고
   잘못된 점(.) 필드를 삭제합니다. **금액은 변하지 않습니다.**

2) --seed (기본값 dry-run, --apply 로 실행)
   원장 도입 이전에 만들어진 계정의 `points` 잔액을
   `serverLedger.verified` 로 옮겨줍니다(= 과거 사용자 보호).

   ⚠️ 안전장치: `tx` 내역이 **한 건도 없는** 계정은 시딩하지 않습니다.
   잔액 조작 공격은 `points` 만 바꾸고 거래 내역을 남기지 않기 때문에,
   tx 가 0건인데 잔액이 큰 계정은 위조 계정일 가능성이 높습니다.
   그런 계정은 자동 처리하지 않고 **목록으로 보고**합니다.

사용법
------
    python3 tools/migrate_ledger.py                      # 점(.) 필드 스캔만
    python3 tools/migrate_ledger.py --repair --apply     # 실제 복구
    python3 tools/migrate_ledger.py --seed               # 시딩 대상 미리보기
    python3 tools/migrate_ledger.py --seed --apply       # 실제 시딩

서비스 계정 키(Admin SDK)가 필요합니다:
    /opt/flutter/firebase-admin-sdk.json
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

SA_PATH = "/opt/flutter/firebase-admin-sdk.json"
PROJECT = "flutter-offerwall-app"
SCOPE = "https://www.googleapis.com/auth/datastore"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

# 원장에 존재할 수 있는 버킷 이름들
BUCKETS = ("verified", "unverified")

# 시딩 시 "위조 의심"으로 판단하는 기준: 거래 내역 0건인데 잔액이 이 이상
SUSPICIOUS_BALANCE = 10_000


# ---------------------------------------------------------------------------
# Firestore REST 헬퍼
# ---------------------------------------------------------------------------

def _token() -> str:
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except ImportError:
        sys.exit(
            "❌ google-auth 미설치.\n"
            "   pip install google-auth requests\n"
            "   (또는 firebase-admin==7.1.0 을 사용하세요)"
        )
    creds = service_account.Credentials.from_service_account_file(SA_PATH, scopes=[SCOPE])
    creds.refresh(Request())
    return creds.token


def _call(url: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url, data=data, method=method,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"❌ Firestore 오류 HTTP {e.code}: {e.read().decode()[:400]}")


def list_users(token: str) -> list[dict]:
    """모든 users 문서를 페이지 단위로 가져온다."""
    docs: list[dict] = []
    url = f"{BASE}/users?pageSize=300"
    while url:
        page = _call(url, token)
        docs.extend(page.get("documents", []))
        tok = page.get("nextPageToken")
        url = f"{BASE}/users?pageSize=300&pageToken={tok}" if tok else ""
    return docs


def _int(field: dict | None) -> int:
    if not field:
        return 0
    for k in ("integerValue", "doubleValue"):
        if k in field:
            try:
                return int(float(field[k]))
            except (TypeError, ValueError):
                return 0
    return 0


def _mask_path(field: str) -> str:
    """
    updateMask 의 필드 경로에 점이 들어가면 **경로 구분자**로 해석된다.
    리터럴 이름 안의 점은 백틱으로 감싸야 한다:
        serverLedger.unverified   -> 경로 (맵 안의 필드)
        `serverLedger.unverified` -> 이름 자체에 점이 있는 필드
    """
    return field if "." in field and "`" in field else f"`{field}`" if "." in field else field


def patch_user(token: str, uid: str, fields: dict, mask: list[str]) -> None:
    """지정한 필드만 갱신한다. mask 에 있으나 fields 에 없는 필드는 삭제된다."""
    qs = "&".join(
        f"updateMask.fieldPaths={urllib.parse.quote(_mask_path(p), safe='')}" for p in mask
    )
    _call(f"{BASE}/users/{uid}?{qs}", token, method="PATCH", body={"fields": fields})


# ---------------------------------------------------------------------------
# 분석
# ---------------------------------------------------------------------------

class UserState:
    def __init__(self, uid: str, fields: dict) -> None:
        self.uid = uid
        self.raw = fields
        self.points = _int(fields.get("points"))
        self.tx_count = len(fields.get("tx", {}).get("arrayValue", {}).get("values", []))
        # 잘못 저장된 점(.) 필드
        self.dotted = {k: _int(fields[k]) for k in fields if k.startswith("serverLedger.")}
        # 올바른 중첩 맵
        nested = fields.get("serverLedger", {}).get("mapValue", {}).get("fields", {})
        self.nested = {k: _int(v) for k, v in nested.items()}
        self.has_map = "serverLedger" in fields and "mapValue" in fields["serverLedger"]

    @property
    def broken(self) -> bool:
        return bool(self.dotted)

    @property
    def ledger_total(self) -> int:
        return sum(self.nested.values()) + sum(self.dotted.values())

    def __str__(self) -> str:
        return (f"{self.uid[:16]}...  points={self.points:>7}p  tx={self.tx_count:>3}  "
                f"dotted={self.dotted or '-'}  nested={self.nested or ('{}' if self.has_map else '-')}")


# ---------------------------------------------------------------------------
# 모드 1 — 점(.) 필드 복구
# ---------------------------------------------------------------------------

def repair(users: list[UserState], apply: bool) -> int:
    broken = [u for u in users if u.broken]
    print("\n" + "=" * 68)
    print("  모드 1 — 잘못 저장된 serverLedger.<bucket> 점(.) 필드 복구")
    print("=" * 68)

    if not broken:
        print("  ✅ 손상된 문서가 없습니다. 복구할 것이 없습니다.")
        return 0

    print(f"  손상된 문서 {len(broken)}건:\n")
    moved = 0
    for u in broken:
        print(f"    {u}")
        # 기존 중첩 맵 값 + 점(.) 필드 값을 합친다 (금액 보존)
        merged = dict(u.nested)
        for k, v in u.dotted.items():
            bucket = k.split(".", 1)[1]
            merged[bucket] = merged.get(bucket, 0) + v
        print(f"      → 복구 후 serverLedger = {merged}")
        moved += sum(u.dotted.values())

    print(f"\n  이동되는 포인트 총액: {moved}p  (금액 자체는 변하지 않습니다)")

    if not apply:
        print("\n  [DRY-RUN] 실제로 쓰지 않았습니다. 적용하려면 --apply 를 붙이세요.")
        return 0

    token = _token()
    for u in broken:
        merged = dict(u.nested)
        for k, v in u.dotted.items():
            bucket = k.split(".", 1)[1]
            merged[bucket] = merged.get(bucket, 0) + v
        fields = {
            "serverLedger": {
                "mapValue": {
                    "fields": {k: {"integerValue": str(v)} for k, v in merged.items()}
                }
            }
        }
        # 중첩 맵을 새로 쓰고, 점(.) 필드들은 마스크에만 넣어 삭제한다.
        mask = ["serverLedger"] + list(u.dotted.keys())
        patch_user(token, u.uid, fields, mask)
        print(f"  [복구 완료] {u.uid}")

    print(f"\n  ✅ {len(broken)}건 복구 완료.")
    return len(broken)


# ---------------------------------------------------------------------------
# 모드 2 — 원장 도입 이전 잔액 시딩
# ---------------------------------------------------------------------------

def seed(users: list[UserState], apply: bool) -> int:
    print("\n" + "=" * 68)
    print("  모드 2 — 원장 도입 이전 계정의 잔액을 serverLedger.verified 로 이관")
    print("=" * 68)

    eligible, suspicious, already = [], [], []
    for u in users:
        if u.ledger_total > 0:
            already.append(u)
        elif u.points <= 0:
            continue
        elif u.tx_count == 0:
            # 거래 내역이 한 건도 없다 = 이 포인트가 정당하게 적립됐다는 증거가
            # 전혀 없다. 잔액 조작 공격은 `points` 만 바꾸고 내역을 남기지 않는다.
            # 돈을 잘못 주는 쪽이 훨씬 위험하므로 자동 이관하지 않고 보고만 한다.
            suspicious.append(u)
        else:
            eligible.append(u)

    print(f"\n  ✅ 이관 대상 (원장 없음 + 거래 내역 존재): {len(eligible)}건")
    for u in eligible:
        print(f"    {u}   → verified += {u.points}p")

    print(f"\n  ⚠️  이관하지 않음 — tx 0건 (적립 근거 없음): {len(suspicious)}건")
    for u in suspicious:
        flag = "  ← 잔액 조작 흔적" if u.points >= SUSPICIOUS_BALANCE else ""
        print(f"    {u}{flag}")
    if suspicious:
        print("    ↑ 잔액만 있고 거래 내역이 없습니다. 잔액 조작 공격의 흔적이거나,")
        print("      앱이 오프라인 로컬 잔액을 올린 뒤 동기화에 실패한 경우입니다.")
        print("      어느 쪽인지 서버가 구분할 수 없으므로 **자동으로 이관하지 않습니다.**")
        print("      실제 사용자라면 본인에게 확인 후 수동으로 지급하세요.")

    print(f"\n  ⏭️  이미 원장이 있는 계정: {len(already)}건 (건너뜀)")

    if not apply:
        print("\n  [DRY-RUN] 실제로 쓰지 않았습니다. 적용하려면 --apply 를 붙이세요.")
        return 0

    if not eligible:
        print("\n  이관할 대상이 없습니다.")
        return 0

    token = _token()
    for u in eligible:
        merged = dict(u.nested)
        merged["verified"] = merged.get("verified", 0) + u.points
        fields = {
            "serverLedger": {
                "mapValue": {
                    "fields": {k: {"integerValue": str(v)} for k, v in merged.items()}
                }
            }
        }
        patch_user(token, u.uid, fields, ["serverLedger"])
        print(f"  [이관 완료] {u.uid}  verified={merged['verified']}p")

    print(f"\n  ✅ {len(eligible)}건 이관 완료.")
    return len(eligible)


def main() -> int:
    ap = argparse.ArgumentParser(description="Rewards Hub serverLedger 복구/이관 도구")
    ap.add_argument("--repair", action="store_true", help="점(.) 필드 복구 모드")
    ap.add_argument("--seed", action="store_true", help="기존 잔액을 verified 로 이관")
    ap.add_argument("--apply", action="store_true", help="실제로 쓴다 (기본은 dry-run)")
    args = ap.parse_args()

    if not args.repair and not args.seed:
        args.repair = True  # 인자 없으면 복구 스캔

    print("=" * 68)
    print("  Rewards Hub — serverLedger 복구 및 이관")
    print("=" * 68)
    print(f"  프로젝트 : {PROJECT}")
    print(f"  모드     : {'repair ' if args.repair else ''}{'seed ' if args.seed else ''}"
          f"({'APPLY' if args.apply else 'DRY-RUN'})")

    token = _token()
    docs = list_users(token)
    users = [UserState(d["name"].split("/")[-1], d.get("fields", {})) for d in docs]

    print(f"\n  전체 users 문서: {len(users)}건\n")
    print(f"  {'uid':<20} {'points':>8}  {'tx':>4}  serverLedger")
    print("  " + "-" * 76)
    for u in users:
        print(f"  {u.uid[:16]:<20} {u.points:>8}  {u.tx_count:>4}  "
              f"dotted={u.dotted or '-'} nested={u.nested or '-'}")

    rc = 0
    if args.repair:
        rc += repair(users, args.apply)
    if args.seed:
        # 시딩 전에 복구를 먼저 하지 않으면 이미 원장이 있는 것으로 오판할 수 있다.
        rc += seed(users, args.apply)

    print("\n" + "=" * 68)
    print("  DONE")
    print("=" * 68)
    return 0 if rc >= 0 else 1


if __name__ == "__main__":
    sys.exit(main())
