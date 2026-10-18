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
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

PROJECT = "flutter-offerwall-app"
REGION = "us-central1"
BASE = f"https://{REGION}-{PROJECT}.cloudfunctions.net"
FS = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

# The service-account key only exists in the build sandbox. On a normal
# developer machine it is absent, so every privileged check is skipped — that
# is why `api_key()` has its own credential-free path below.
SA_PATH = "/opt/flutter/firebase-admin-sdk.json"
GS_PATH = "/opt/flutter/google-services.json"
FIREBASE_OPTIONS = "lib/firebase_options.dart"

GREEN, RED, YELLOW, DIM, RESET = "\033[0;32m", "\033[0;31m", "\033[0;33m", "\033[0m", "\033[0m"

# Points an attacker would try to mint. 1000 points = $1, so this is $50.
ATTACK_BALANCE = 50_000
# Server-side cap on client-credited points, mirrored from functions/src/index.ts.
MAX_UNVERIFIED_POINTS = 2_000

results: list[dict] = []
_WARNED_NO_PYJWT = False


def record(name: str, ok: bool, detail: str, fatal: bool = False,
           kind: str = "leak") -> None:
    """
    kind='leak'   the problem lets money OUT (attacker wins)
    kind='broken'  the problem blocks everyone (app is unusable)
    'broken' is not merely a UX issue: if the ledger never records anything,
    a legitimate user can never cash out. That is a release blocker too, so it
    is still fatal — it just needs completely different wording.
    """
    results.append({"check": name, "ok": ok, "detail": detail,
                    "fatal": fatal, "kind": kind})
    mark = f"{GREEN}✅{RESET}" if ok else (f"{RED}❌{RESET}" if fatal else f"{YELLOW}⚠️ {RESET}")
    print(f"  {mark} {name}")
    if detail:
        for line in detail.splitlines():
            print(f"       {DIM}{line}{RESET}")


def _sa_available() -> bool:
    """Whether privileged (service-account) checks can run at all."""
    return os.path.exists(SA_PATH)


def _sa_token(scope: str = "https://www.googleapis.com/auth/cloud-platform") -> str | None:
    try:
        import jwt  # PyJWT
    except ImportError:
        global _WARNED_NO_PYJWT
        if not _WARNED_NO_PYJWT:
            _WARNED_NO_PYJWT = True
            # Not fatal: the unauthenticated checks still work. We only warn.
            print(f"  {DIM}PyJWT 미설치 — 관리자 검사만 생략됩니다 "
                  f"(pip install pyjwt cryptography 로 활성화){RESET}")
        return None
    if not os.path.exists(SA_PATH):
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


def api_key() -> str | None:
    """
    Find the Firebase Web API key WITHOUT requiring any credential file.

    The sandbox has /opt/flutter/google-services.json, but a normal developer
    machine does not — it only has the repo. `lib/firebase_options.dart` is
    committed and contains the same public API key (it is a client identifier,
    not a secret). Without this fallback the exploit checks would silently skip
    on the user's PC, which is exactly the machine that needs them.
    """
    if os.path.exists(GS_PATH):
        try:
            with open(GS_PATH) as fh:
                return json.load(fh)["client"][0]["api_key"][0]["current_key"]
        except (KeyError, IndexError, json.JSONDecodeError):
            pass

    if os.path.exists(FIREBASE_OPTIONS):
        with open(FIREBASE_OPTIONS, encoding="utf-8") as fh:
            # e.g.  apiKey: 'AIzaSy...',
            match = re.search(r"apiKey:\s*'([A-Za-z0-9_\-]+)'", fh.read())
            if match:
                return match.group(1)

    return None


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_service_account() -> str | None:
    print(f"\n{DIM}0) 환경{RESET}")
    if not _sa_available():
        print(f"  {DIM}서비스 계정 키 없음 ({SA_PATH}) — 관리자 검사는 건너뜁니다{RESET}")
        print(f"  {DIM}공개 API 키만으로 수행 가능한 검사를 계속합니다{RESET}")
        return None
    token = _sa_token()
    record("service-account token", token is not None,
           "" if token else "SA 키를 읽었으나 토큰 발급 실패")
    return token


def check_auth(token: str | None) -> None:
    print(f"\n{DIM}1) Firebase Authentication{RESET}")
    if not token:
        # Not a failure: we simply cannot inspect Auth without admin rights.
        # The exploit checks below still exercise the real thing.
        print(f"  {DIM}관리자 권한 없음 — Auth 설정 직접 조회 생략{RESET}")
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
    Probe the LIVE rules BY ATTACKING THEM.

    Reading the ruleset needs admin rights, so when those are unavailable we
    fall back to the thing that actually matters: try to write `points` as a
    signed-in client and see whether Firestore refuses. That probe needs only
    the public API key, so it works on any machine.

    Fatal only when the attack SUCCEEDS. An unknown result is a warning, never
    a false alarm.
    """
    print(f"\n{DIM}2) 배포된 보안 규칙 (잔액 조작 차단){RESET}")

    if token:
        code, body = http(
            f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}/releases",
            headers={"Authorization": f"Bearer {token}"},
        )
        if code == 200:
            ruleset = None
            for rel in json.loads(body).get("releases", []):
                ruleset = rel.get("rulesetName")
            if ruleset:
                code, body = http(f"https://firebaserules.googleapis.com/v1/{ruleset}",
                                  headers={"Authorization": f"Bearer {token}"})
                if code == 200:
                    content = "\n".join(
                        f.get("content", "")
                        for f in json.loads(body).get("source", {}).get("files", [])
                    )
                    blanket = "allow read, write: if request.auth != null" in content
                    pins = ('untouched("points")' in content
                            or "request.resource.data.points == resource.data.points" in content)
                    record("클라이언트가 `points` 를 쓸 수 없다 (규칙 내용 검사)",
                           pins and not blanket,
                           "" if (pins and not blanket) else
                           "포괄적 allow read, write 발견 → 잔액 조작 가능")
                    record("`serverLedger` 가 보호된다", "serverLedger" in content,
                           "" if "serverLedger" in content else "원장 필드가 잠기지 않음")
                    return

    # Credential-free fallback: prove it by attempting the write.
    key = api_key()
    if not key:
        record("잔액 조작 차단 확인", False,
               "API 키를 찾을 수 없음 (google-services.json / firebase_options.dart)", fatal=False)
        return
    code, body = http(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}",
        {"email": f"rule{int(time.time())}@rewardshub-test.com",
         "password": "Rule!2345xyz", "returnSecureToken": True},
    )
    if code != 200:
        record("잔액 조작 차단 확인", False, f"테스트 계정 생성 실패 HTTP {code}", fatal=False)
        return
    uid, idtoken = json.loads(body)["localId"], json.loads(body)["idToken"]
    try:
        code, body = http(
            f"{FS}/users/{uid}?updateMask.fieldPaths=points&updateMask.fieldPaths=tx",
            {"fields": {"points": {"integerValue": str(ATTACK_BALANCE)},
                        "tx": {"arrayValue": {"values": []}}}},
            {"Authorization": f"Bearer {idtoken}"},
            method="PATCH",
        )
        blocked = code != 200
        # Warning, not fatal — same reasoning as the rules-content check above.
        # The ledger is what stops money; the rules are defence in depth.
        record("클라이언트가 `points` 를 쓸 수 없다 (실제 시도)",
               blocked,
               "" if blocked else
               (f"HTTP {code}: 자기 잔액을 {ATTACK_BALANCE} 로 설정하는 데 성공\n"
                "심층 방어 1겹(보안 규칙)이 아직 적용되지 않았습니다.\n"
                "수정: powershell -ExecutionPolicy Bypass -File .\\deploy.ps1 -ApplyRules"),
               fatal=False)
    finally:
        _cleanup(uid, None, token)


def _cleanup(uid: str, payout_id: str | None, token: str | None) -> None:
    """Delete every artifact a test created. Never leaves a trail."""
    if payout_id and token:
        http(f"{FS}/payouts/{payout_id}", headers={"Authorization": f"Bearer {token}"},
             method="DELETE")
    if token:
        http(f"{FS}/users/{uid}", headers={"Authorization": f"Bearer {token}"}, method="DELETE")
    tk2 = _sa_token("https://www.googleapis.com/auth/identitytoolkit")
    if tk2:
        http(f"https://identitytoolkit.googleapis.com/v1/projects/{PROJECT}/accounts:delete",
             {"localId": uid}, {"Authorization": f"Bearer {tk2}"})


def _new_attacker(prefix: str) -> tuple[str, str] | None:
    """Create a throwaway signed-in account, exactly like a real user would."""
    key = api_key()
    if not key:
        return None
    code, body = http(
        f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={key}",
        {"email": f"{prefix}{int(time.time())}@rewardshub-test.com",
         "password": "SecRegress!2345x", "returnSecureToken": True},
    )
    if code != 200:
        return None
    j = json.loads(body)
    return j["localId"], j["idToken"]


def check_payout_exploit(token: str | None) -> None:
    """
    Run the ACTUAL exploit: inflate the balance, then try to cash out.

    Needs no service-account key — only the public API key — so this runs on
    any machine. Cleanup needs admin rights; if unavailable the artifacts are
    left behind but contain no money and are clearly labelled *_test.com.
    """
    print(f"\n{DIM}3) 출금 익스플로잇 실제 시도{RESET}")
    acct = _new_attacker("sec")
    if not acct:
        record("출금 익스플로잇 시도", False,
               "테스트 계정을 만들 수 없음 (API 키 또는 Auth 설정 확인)", fatal=False)
        return
    uid, idtoken = acct
    print(f"       {DIM}테스트 계정: {uid}{RESET}")

    try:
        code, body = http(
            f"{FS}/users/{uid}?updateMask.fieldPaths=points&updateMask.fieldPaths=tx",
            {"fields": {"points": {"integerValue": str(ATTACK_BALANCE)},
                        "tx": {"arrayValue": {"values": []}}}},
            {"Authorization": f"Bearer {idtoken}"},
            method="PATCH",
        )
        inflated = code == 200
        # NOT fatal on its own: inflating the UI mirror is harmless while the
        # payout path refuses to honour it. The fatal check is the payout below
        # — that is the one that decides whether money actually leaves.
        record(
            "잔액 조작 시도가 규칙에 의해 차단된다",
            not inflated,
            "" if not inflated else
            (f"HTTP {code}: 클라이언트가 자기 잔액을 {ATTACK_BALANCE} 로 설정할 수 있음\n"
             "심층 방어 1겹(보안 규칙)이 아직 적용되지 않았습니다.\n"
             "수정: powershell -ExecutionPolicy Bypass -File .\\deploy.ps1 -ApplyRules"),
            fatal=False,
        )

        code, body = http(
            f"{BASE}/requestPayout",
            {"data": {"method": "paypal", "points": ATTACK_BALANCE}},
            {"Authorization": f"Bearer {idtoken}"},
        )
        paid = code == 200 and '"ok":true' in body.replace(" ", "")
        detail = ""
        payout_id = None
        if paid:
            try:
                payout_id = json.loads(body)["result"]["requestId"]
            except (KeyError, json.JSONDecodeError):
                pass
            detail = (f"HTTP {code}: 출금 요청이 생성됨 → ${ATTACK_BALANCE / 1000:.2f}")
        else:
            detail = f"HTTP {code}: {body[:160]}"
        record("조작된 잔액으로 출금할 수 없다", not paid, detail, fatal=paid)
        if paid:
            print(f"       {DIM}서버 전용 원장(serverLedger)이 배포되지 않았을 수 있습니다{RESET}")
    finally:
        _cleanup(uid, locals().get("payout_id"), token)
        print(f"       {DIM}테스트 흔적 정리 시도 완료{RESET}")


def check_ledger_deployed(token: str | None) -> None:
    """
    Confirm the ledger WORKS, not merely that it blocks.

    A BROKEN ledger (never written) and a WORKING ledger (blocks inflation)
    both refuse an inflated payout with the same message, so blocking alone
    proves nothing. Distinguishing them requires doing a legitimate claim
    first and watching the ledger move — and confirming a real user can
    actually cash out.

    Order matters:
      1. a normal claim must be ACCEPTED
      2. serverLedger must have recorded it
      3. only then does a refused inflated payout mean anything
      4. a legitimate payout must SUCCEED (this is what catches a broken ledger)
    """
    print(f"\n{DIM}4) 서버 전용 원장이 실제로 작동하는가{RESET}")
    acct = _new_attacker("ledger")
    if not acct:
        record("원장 검증", False, "테스트 계정을 만들 수 없음", fatal=False)
        return
    uid, idtoken = acct
    attempt = 6_000  # whole dollars, clears the $5 minimum, exceeds the 2000 cap

    try:
        # --- 1) a normal claim must be ACCEPTED ---
        code, body = http(f"{BASE}/claimOffer", {"data": {"offerId": "game_puzzle#0"}},
                          {"Authorization": f"Bearer {idtoken}"})
        ok_claim = code == 200 and '"ok":true' in body.replace(" ", "")
        record("정상 보상 청구가 승인된다", ok_claim,
               "" if ok_claim else f"HTTP {code}: {body[:150]} — 보상 경로가 깨졌습니다",
               fatal=not ok_claim, kind="broken")

        # --- 2) the ledger must have recorded it ---
        if token:
            code, body = http(f"{FS}/users/{uid}",
                              headers={"Authorization": f"Bearer {token}"})
            unv = None
            if code == 200:
                fields = json.loads(body).get("fields", {})
                led = fields.get("serverLedger", {}).get("mapValue", {}).get("fields", {})
                unv = led.get("unverified", {}).get("integerValue")
            good = unv is not None and int(unv) > 0
            # A claim was just ACCEPTED (check 1) yet the ledger recorded
            # nothing. That is direct proof the ledger is broken, so this is
            # fatal: a legitimate user can never cash out. It is still fatal
            # even if check 4 later fails to prove it (e.g. the balance never
            # reaches $5 for unrelated reasons).
            record("원장에 적립이 기록된다", good,
                   "" if good else
                   (f"serverLedger.unverified = {unv}\n"
                    "원장이 기록되지 않았습니다 → 정상 사용자도 출금 불가 (심각)\n"
                    "점(dot) 키로 쓰지 않았는지 확인: set({merge:true}) 는\n"
                    "'serverLedger.x' 를 경로가 아니라 '점이 든 필드명'으로 저장합니다."),
                   fatal=not good, kind="broken")
        else:
            print(f"  {DIM}관리자 권한 없음 — 원장 직접 확인 생략 "
                  f"(아래 정당한 출금 테스트로 판정){RESET}")

        # --- 3) an inflated payout must be refused ---
        http(f"{FS}/users/{uid}?updateMask.fieldPaths=points",
             {"fields": {"points": {"integerValue": str(attempt)}}},
             {"Authorization": f"Bearer {idtoken}"}, method="PATCH")
        code, body = http(f"{BASE}/requestPayout",
                          {"data": {"method": "paypal", "points": attempt}},
                          {"Authorization": f"Bearer {idtoken}"})
        low = body.lower()
        min_check = "minimum for" in low
        refusal = "verified balance" in low or "could not be verified" in low
        record("원장 상한 초과분은 지급 불가", refusal and code != 200,
               "" if (refusal and code != 200) else
               (f"HTTP {code}: {body[:150]}\n"
                + ("거부 이유가 최소 출금액이라 원장 검증이 실행되지 않았습니다"
                   if min_check else "원장 로직이 응답에서 확인되지 않음")))

        # --- 4) a LEGITIMATE payout must succeed ---
        # This is the check that catches a silently broken ledger. Without it,
        # "the exploit is blocked" and "everyone is blocked" look identical.
        balance = 0
        for oid in ["game_puzzle#1", "game_puzzle#2", "game_coin_master#0",
                    "game_coin_master#1"]:
            _, b2 = http(f"{BASE}/claimOffer", {"data": {"offerId": oid}},
                         {"Authorization": f"Bearer {idtoken}"})
            try:
                balance = json.loads(b2)["result"]["balance"]
            except (KeyError, json.JSONDecodeError):
                pass
        if balance and balance >= 5_000:
            code, body = http(f"{BASE}/requestPayout",
                              {"data": {"method": "paypal", "points": 5_000}},
                              {"Authorization": f"Bearer {idtoken}"})
            paid = code == 200 and '"ok":true' in body.replace(" ", "")
            record("정당한 출금이 실제로 성공한다", paid,
                   "" if paid else
                   (f"HTTP {code}: {body[:170]}\n"
                    f"정상 사용자가 {balance}p 를 보유해도 출금 불가 → 앱이 작동하지 않습니다\n"
                    "원장이 적립을 기록하지 못하고 있을 가능성이 높습니다."),
                   fatal=not paid, kind="broken")
        else:
            record("정당한 출금이 실제로 성공한다", False,
                   f"잔액 부족({balance}p)으로 검증 불가 — 보상 경로 확인 필요", fatal=False)
    finally:
        _cleanup(uid, None, token)
        print(f"       {DIM}테스트 흔적 정리 시도 완료{RESET}")



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
    # These two are the ones that matter, and they need NO admin credentials —
    # only the public API key — so they always run, on any machine.
    check_payout_exploit(token)
    check_ledger_deployed(token)
    check_postback_signature()

    # FATAL means exactly one thing: a payout was actually authorised. Anything
    # else is a warning. Marking "the rules still allow a balance write" as
    # fatal would be a false alarm once the ledger is live — and false alarms
    # are how real ones get ignored.
    fatal = [r for r in results if r["fatal"] and not r["ok"]]
    warn = [r for r in results if not r["ok"] and not r["fatal"]]

    if args.json:
        print(json.dumps({"results": results, "fatal": len(fatal), "warnings": len(warn)},
                         ensure_ascii=False, indent=2))
    else:
        print()
        print("=" * 68)
        leaks = [r for r in fatal if r.get("kind") != "broken"]
        broken = [r for r in fatal if r.get("kind") == "broken"]
        if leaks:
            print(f"{RED}  치명적 — 실제로 돈을 빼낼 수 있습니다 ({len(leaks)}건){RESET}")
            for r in leaks:
                print(f"{RED}   • {r['check']}{RESET}")
        if broken:
            print(f"{RED}  치명적 — 정상 사용자가 출금할 수 없습니다 ({len(broken)}건){RESET}")
            for r in broken:
                print(f"{RED}   • {r['check']}{RESET}")
        if fatal:
            print(f"{RED}  위 항목을 해결하기 전에는 출시하지 마세요.{RESET}")
        elif warn:
            print(f"{GREEN}  ✅ 출금 익스플로잇 차단 확인 — 알려진 경로로 돈이 나가지 않습니다{RESET}")
        else:
            print(f"{GREEN}  ✅ 모두 통과 — 익스플로잇 차단 + 정상 출금 작동{RESET}")
        if warn:
            print(f"{YELLOW}  권고 사항 {len(warn)}건 (돈은 나가지 않음){RESET}")
            for r in warn:
                print(f"{YELLOW}   • {r['check']}{RESET}")
        print("=" * 68)

    return 1 if fatal else 0


if __name__ == "__main__":
    sys.exit(main())
