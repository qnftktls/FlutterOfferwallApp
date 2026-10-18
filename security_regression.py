#!/usr/bin/env python3
"""
Rewards Hub — security regression check.

Answers ONE question honestly: **can a random attacker take money out?**

Every check below actually attempts the attack against the LIVE project and
reports what happened. It is not a code review and it does not trust any
documentation — if the exploit works, this script says so.

Why this exists
---------------
A balance-inflation exploit was proven end-to-end against this project:

    create account -> PATCH users/{uid}.points = 50000
    -> requestPayout(paypal, 50000) -> "Requested $50.00 via PayPal."

Two independent defences were then added (a server-only `serverLedger` and
hardened security rules). This script verifies BOTH are actually live, because
"the code is written" and "the code is deployed" are different things.

Usage
-----
    python3 security_regression.py                 # run all checks
    python3 security_regression.py --json          # machine-readable

Exit code 0 = no known way to extract money. Non-zero = action required.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROJECT = "flutter-offerwall-app"
REGION = "us-central1"
BASE = f"https://{REGION}-{PROJECT}.cloudfunctions.net"
FS = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

SA_PATH = "/opt/flutter/firebase-admin-sdk.json"
GS_PATH = "/opt/flutter/google-services.json"

GREEN, RED, YELLOW, DIM, RESET = "\033[0;32m", "\033[0;31m", "\033[0;33m", "\033[0m", "\033[0m"

# Points an attacker would try to mint. 1000 points = $1, so this is $50.
ATTACK_BALANCE = 50_000
# Server-side cap on client-credited points, mirrored from functions/src/index.ts.
MAX_UNVERIFIED_POINTS = 2_000

results: list[dict] = []


def record(name: str, ok: bool, detail: str, fatal: bool = False) -> None:
    results.append({"check": name, "ok": ok, "detail": detail, "fatal": fatal})
    mark = f"{GREEN}✅{RESET}" if ok else (f"{RED}❌{RESET}" if fatal else f"{YELLOW}⚠️ {RESET}")
    print(f"  {mark} {name}")
    if detail:
        for line in detail.splitlines():
            print(f"       {DIM}{line}{RESET}")


def _sa_token(scope: str = "https://www.googleapis.com/auth/cloud-platform") -> str | None:
    try:
        import jwt  # PyJWT
    except ImportError:
        print(f"{RED}PyJWT is required:  pip install pyjwt cryptography{RESET}")
        return None
    with open(SA_PATH) as fh:
        sa = json.load(fh)
    now = int(time.time())
    claim = {
        "iss": sa["client_email"],
        "scope": scope,
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now,
        "exp": now + 3600,
    }
    sig = jwt.encode(claim, sa["private_key"], algorithm="RS256")
    body = urllib.parse.urlencode(
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": sig,
        }
    ).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            # NOTE: the token endpoint returns `id_token` for some scopes and
            # `access_token` for others. We need the access token explicitly.
            return json.loads(resp.read().decode()).get("access_token")
    except (urllib.error.HTTPError, KeyError, json.JSONDecodeError):
        return None


def http(
    url: str,
    payload=None,
    headers: dict | None = None,
    method: str | None = None,
    timeout: int = 30,
) -> tuple[int, str]:
    data = json.dumps(payload).encode() if payload is not None else None
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()
    except Exception as exc:  # noqa: BLE001 - surfaced as an error code
        return 0, str(exc)


def api_key() -> str:
    with open(GS_PATH) as fh:
        return json.load(fh)["client"][0]["api_key"][0]["current_key"]


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_service_account() -> str | None:
    print(f"\n{DIM}0) 환경{RESET}")
    token = _sa_token()
    record("service-account token", token is not None,
           "" if token else "SA 키를 읽을 수 없거나 토큰 발급 실패")
    return token


def check_auth(token: str | None) -> None:
    print(f"\n{DIM}1) Firebase Authentication{RESET}")
    if not token:
        record("Auth 활성", False, "토큰 없음 — 건너뜀", fatal=True)
        return
    code, body = http(
        f"https://identitytoolkit.googleapis.com/admin/v2/projects/{PROJECT}/config",
        headers={"Authorization": f"Bearer {token}"},
    )
    ok = code == 200
    detail = ""
    if ok:
        try:
            signin = json.loads(body).get("signIn", {})
            enabled = [k for k, v in signin.items() if isinstance(v, dict) and v.get("enabled")]
            detail = f"활성 provider: {', '.join(enabled) or '(없음)'}"
        except json.JSONDecodeError:
            pass
    else:
        detail = "Auth 미설정 → claimOffer/requestPayout 가 모두 401 (보상 전면 불가)"
    record("Auth 활성 (이메일/비밀번호)", ok, detail, fatal=not ok)


def check_rules_block_balance(token: str | None) -> None:
    """
    Read the LIVE ruleset and assert the client cannot write `points`.

    Reading the deployed rules is more reliable than probing, because a probe
    only tells you about one field on one path.
    """
    print(f"\n{DIM}2) 배포된 보안 규칙 (잔액 조작 차단){RESET}")
    if not token:
        record("규칙 확인", False, "토큰 없음 — 건너뜀", fatal=True)
        return

    code, body = http(
        f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}/releases",
        headers={"Authorization": f"Bearer {token}"},
    )
    if code != 200:
        record("ruleset 조회", False, f"HTTP {code}: {body[:120]}", fatal=True)
        return

    ruleset = None
    for rel in json.loads(body).get("releases", []):
        ruleset = rel.get("rulesetName")
    if not ruleset:
        record("ruleset 조회", False, "릴리스된 규칙 없음", fatal=True)
        return

    code, body = http(f"https://firebaserules.googleapis.com/v1/{ruleset}",
                      headers={"Authorization": f"Bearer {token}"})
    if code != 200:
        record("ruleset 내용", False, f"HTTP {code}", fatal=True)
        return

    content = "\n".join(
        f.get("content", "")
        for f in json.loads(body).get("source", {}).get("files", [])
    )

    # The dev rules use a blanket `allow read, write: if <owner>` — that is the
    # hole. Hardened rules pin points/tx to their server-written values.
    blanket_write = "allow read, write: if request.auth != null" in content
    pins_points = ('untouched("points")' in content
                   or "request.resource.data.points == resource.data.points" in content)
    protects_ledger = "serverLedger" in content

    record(
        "클라이언트가 `points` 를 쓸 수 없다",
        pins_points and not blanket_write,
        "" if (pins_points and not blanket_write)
        else ("포괄적 allow read, write 발견 → 잔액 무한 조작 가능\n"
              "수정: powershell -ExecutionPolicy Bypass -File .\\deploy.ps1 -ApplyRules"),
        fatal=True,
    )
    record(
        "`serverLedger` 가 클라이언트로부터 보호된다",
        protects_ledger,
        "" if protects_ledger else "규칙이 서버 전용 원장을 잠그지 않음 (심층 방어 약화)",
    )


def check_payout_exploit(token: str | None) -> None:
    """Run the ACTUAL exploit. Clean up afterwards, always."""
    print(f"\n{DIM}3) 출금 익스플로잇 실제 시도{RESET}")
    key = api_key()

    code, body = http(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}",
        {"email": f"sec{int(time.time())}@rewardshub-test.com",
         "password": "SecRegress!2345x", "returnSecureToken": True},
    )
    if code != 200:
        record("공격자 계정 생성", False, f"HTTP {code}: {body[:150]}")
        return
    j = json.loads(body)
    uid, idtoken = j["localId"], j["idToken"]
    print(f"       {DIM}테스트 계정: {uid}{RESET}")

    try:
        # Attack 1 — inflate the mirrored balance through the client API.
        code, body = http(
            f"{FS}/users/{uid}?updateMask.fieldPaths=points&updateMask.fieldPaths=tx",
            {"fields": {"points": {"integerValue": str(ATTACK_BALANCE)},
                        "tx": {"arrayValue": {"values": []}}}},
            {"Authorization": f"Bearer {idtoken}"},
            method="PATCH",
        )
        inflated = code == 200
        record(
            "잔액 조작 시도가 규칙에 의해 차단된다",
            not inflated,
            "" if not inflated else
            f"HTTP {code}: 클라이언트가 자기 잔액을 {ATTACK_BALANCE} 로 설정하는 데 성공",
            fatal=inflated,
        )

        # Attack 2 — try to cash out whatever balance now exists.
        code, body = http(
            f"{BASE}/requestPayout",
            {"data": {"method": "paypal", "points": ATTACK_BALANCE}},
            {"Authorization": f"Bearer {idtoken}"},
        )
        paid = code == 200 and '"ok":true' in body.replace(" ", "")
        detail = ""
        if paid:
            detail = (f"HTTP {code}: 출금 요청이 생성됨 → ${ATTACK_BALANCE / 1000:.2f}\n"
                      "서버 전용 원장(serverLedger)이 배포되지 않았습니다.")
        else:
            detail = f"HTTP {code}: {body[:160]}"
        record("조작된 잔액으로 출금할 수 없다", not paid, detail, fatal=paid)

        if paid:
            try:
                rid = json.loads(body)["result"]["requestId"]
                http(f"{FS}/payouts/{rid}",
                     headers={"Authorization": f"Bearer {token}"}, method="DELETE")
            except (KeyError, json.JSONDecodeError):
                pass
    finally:
        # Always clean up: user doc + auth account.
        if token:
            http(f"{FS}/users/{uid}", headers={"Authorization": f"Bearer {token}"},
                 method="DELETE")
        tk2 = _sa_token("https://www.googleapis.com/auth/identitytoolkit")
        if tk2:
            http(f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:delete",
                 {"localId": uid}, {"Authorization": f"Bearer {tk2}"})
        print(f"       {DIM}테스트 흔적 정리 완료 (user, auth, payout){RESET}")


def check_ledger_deployed(token: str | None) -> None:
    """
    Confirm the server-side defence shipped.

    We cannot list functions with this SA, so we probe behaviour instead:
    a payout far above MAX_UNVERIFIED_POINTS must be refused even when the
    mirrored balance claims the user has it.
    """
    print(f"\n{DIM}4) 서버 전용 원장 배포 여부{RESET}")
    key = api_key()
    code, body = http(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}",
        {"email": f"ledger{int(time.time())}@rewardshub-test.com",
         "password": "Ledger!2345xyz", "returnSecureToken": True},
    )
    if code != 200:
        record("원장 검증", False, f"계정 생성 실패 HTTP {code}")
        return
    j = json.loads(body)
    uid, idtoken = j["localId"], j["idToken"]
    attempt = MAX_UNVERIFIED_POINTS + 1

    try:
        # If the client CAN still write points, seed just above the cap so the
        # only thing that can refuse this is the ledger logic itself.
        http(
            f"{FS}/users/{uid}?updateMask.fieldPaths=points",
            {"fields": {"points": {"integerValue": str(attempt)}}},
            {"Authorization": f"Bearer {idtoken}"},
            method="PATCH",
        )
        code, body = http(
            f"{BASE}/requestPayout",
            {"data": {"method": "paypal", "points": attempt}},
            {"Authorization": f"Bearer {idtoken}"},
        )
        # $5 minimum means a small request is refused for a different reason;
        # we specifically want the "insufficient verified balance" path.
        ledger_active = "verified balance" in body.lower() or "could not be verified" in body.lower()
        refused = code != 200
        record(
            "원장 상한 초과분은 지급 불가",
            ledger_active,
            "" if ledger_active else
            ("원장 로직이 응답에서 확인되지 않음 — 함수 재배포 필요\n"
             "수정: powershell -ExecutionPolicy Bypass -File .\\deploy.ps1"),
        )
        if not refused:
            record("출금이 거부됨", False, f"HTTP {code}: {body[:120]}", fatal=False)
    finally:
        if token:
            http(f"{FS}/users/{uid}", headers={"Authorization": f"Bearer {token}"},
                 method="DELETE")
        tk2 = _sa_token("https://www.googleapis.com/auth/identitytoolkit")
        if tk2:
            http(f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:delete",
                 {"localId": uid}, {"Authorization": f"Bearer {tk2}"})
        print(f"       {DIM}테스트 흔적 정리 완료{RESET}")


def check_postback_signature() -> None:
    print(f"\n{DIM}5) postback 서명 검증{RESET}")
    for label, headers, expect in [
        ("서명 없음", {}, 401),
        ("가짜 서명", {"x-signature": "sha256=deadbeef"}, 401),
    ]:
        code, _ = http(f"{BASE}/offerwallPostback",
                       {"user_id": "x", "points": 100}, headers)
        record(f"{label} → 거부", code == expect, f"HTTP {code} (기대 {expect})", fatal=code == 200)


def main() -> int:
    ap = argparse.ArgumentParser(description="Rewards Hub security regression check")
    ap.add_argument("--json", action="store_true", help="JSON 으로 출력")
    args = ap.parse_args()

    if not args.json:
        print("=" * 68)
        print(" Rewards Hub — 보안 회귀 검사 (실제 공격 시도)")
        print("=" * 68)

    token = check_service_account()
    check_auth(token)
    check_rules_block_balance(token)
    if token:
        check_payout_exploit(token)
        check_ledger_deployed(token)
    check_postback_signature()

    fatal = [r for r in results if r["fatal"] and not r["ok"]]
    warn = [r for r in results if not r["ok"] and not r["fatal"]]

    if args.json:
        print(json.dumps({"results": results, "fatal": len(fatal), "warnings": len(warn)},
                         ensure_ascii=False, indent=2))
    else:
        print()
        print("=" * 68)
        if fatal:
            print(f"{RED}  치명적 문제 {len(fatal)}개 — 돈을 빼낼 수 있습니다{RESET}")
            for r in fatal:
                print(f"{RED}   • {r['check']}{RESET}")
        else:
            print(f"{GREEN}  치명적 문제 없음 — 알려진 출금 경로가 막혀 있습니다{RESET}")
        if warn:
            print(f"{YELLOW}  경고 {len(warn)}개{RESET}")
            for r in warn:
                print(f"{YELLOW}   • {r['check']}{RESET}")
        print("=" * 68)

    return 1 if fatal else 0


if __name__ == "__main__":
    sys.exit(main())
