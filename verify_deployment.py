#!/usr/bin/env python3
"""
Rewards Hub — 배포 후 안티프라우드 원격 검증

배포가 끝난 뒤 실행하면, 실제 살아있는 Cloud Functions에 대고
공격 시나리오를 던져서 방어되는지 확인합니다.

사용법:
    python3 verify_deployment.py
    python3 verify_deployment.py --project flutter-offerwall-app
"""
import argparse
import hashlib
import hmac
import json
import urllib.error
import urllib.request

G, R, Y, B, N = "\033[0;32m", "\033[0;31m", "\033[0;33m", "\033[1;34m", "\033[0m"


def hr():
    print("-" * 62)


def ok(msg):
    print(f"  {G}✅ {msg}{N}")


def bad(msg):
    print(f"  {R}❌ {msg}{N}")


def warn(msg):
    print(f"  {Y}⚠️  {msg}{N}")


def step(msg):
    print(f"\n{B}{msg}{N}")
    hr()


def request(url, payload, method="POST", headers=None, timeout=15):
    """임의 메서드 요청 → (status, body text). 네트워크 실패 시 (0, '')."""
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)


def post(url, payload, headers=None, timeout=15):
    """POST 요청 (onCall / postback 용)."""
    return request(url, payload, method="POST", headers=headers, timeout=timeout)


def patch(url, payload, timeout=15):
    """PATCH 요청 (Firestore REST 업데이트 용)."""
    return request(url, payload, method="PATCH", timeout=timeout)


def get(url, timeout=15):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return 0, str(e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="flutter-offerwall-app")
    ap.add_argument("--region", default="us-central1")
    ap.add_argument("--secret", default="", help="등록한 OFFERWALL_SECRET (검증 3번에 사용)")
    args = ap.parse_args()

    base = f"https://{args.region}-{args.project}.cloudfunctions.net"
    results = []

    print("=" * 62)
    print(f"  Rewards Hub — 안티프라우드 배포 검증")
    print(f"  project: {args.project}  region: {args.region}")
    print("=" * 62)

    # ---------------------------------------------------------------
    step("1) 함수 엔드포인트 생존 확인")
    endpoints = {
        "offerwallPostback": f"{base}/offerwallPostback",
        "claimOffer": f"{base}/claimOffer",
        "requestPayout": f"{base}/requestPayout",
    }
    deployed_ok = True
    for name, url in endpoints.items():
        # onCall은 {"data":{}} 로 호출. 응답이 오면 배포된 것.
        # 404 = 함수 없음(미배포), 0 = 연결 실패.
        status, _ = post(url, {"data": {}})
        if status in (404, 0):
            bad(f"{name}: HTTP {status} — 배포 안 됨 / 경로 오류")
            results.append((f"{name} 생존", False))
            deployed_ok = False
        else:
            ok(f"{name}: HTTP {status} (함수 살아있음)")
            results.append((f"{name} 생존", True))

    if not deployed_ok:
        print()
        warn("함수가 배포되지 않았습니다. 'bash deploy_all.sh' 를 먼저 실행하세요.")
        warn("이하 방어 테스트는 404를 '통과'로 오판하므로 건너뜁니다.")
        step("결과 요약")
        for name, v in results:
            print(f"  {'✅' if v else '❌'} {name}")
        print()
        return 1

    # ---------------------------------------------------------------
    step("2) postback — 서명 위조/변조 방어")
    url = endpoints["offerwallPostback"]

    # 2-1 서명 헤더 없음
    status, body = post(url, {"userId": "attacker", "offerId": "2001", "points": 999999})
    p1 = status in (401, 403)
    (ok if p1 else bad)(f"서명 없음 → HTTP {status} " + ("(거부됨)" if p1 else "(🚨 통과됨!)"))
    results.append(("postback 서명없음 거부", p1))

    # 2-2 가짜 서명
    fake = "sha256=" + hmac.new(b"wrong_key", b"{}", hashlib.sha256).hexdigest()
    status, _ = post(url, {"userId": "attacker", "offerId": "2001", "points": 999999},
                     headers={"x-signature": fake})
    p2 = status in (401, 403)
    (ok if p2 else bad)(f"가짜 서명 → HTTP {status} " + ("(거부됨)" if p2 else "(🚨 통과됨!)"))
    results.append(("postback 가짜서명 거부", p2))

    # 2-3 (선택) 진짜 서명 — secret 있을 때만
    if args.secret:
        raw = json.dumps({"userId": "test_verify", "offerId": "2001", "points": 999999,
                          "txnId": "verify_txn_001"}, separators=(",", ":"))
        sig = "sha256=" + hmac.new(args.secret.encode(), raw.encode(), hashlib.sha256).hexdigest()
        req = urllib.request.Request(url, data=raw.encode(), method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("x-signature", sig)
        try:
            with urllib.request.urlopen(req, timeout=15) as r:
                status, body = r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            status, body = e.code, e.read().decode()
        except Exception as e:
            status, body = 0, str(e)
        p3 = status == 200
        (ok if p3 else warn)(f"정상 서명 → HTTP {status} {body[:80]}")
        results.append(("postback 정상서명 수락", p3))
        warn("주의: 이 요청은 실제로 포인트를 지급했을 수 있습니다 (test_verify 유저)")
    else:
        warn("정상 서명 테스트 건너뜀 (--secret 값 없음)")

    # 2-4 금액 필드 변조 — 서버가 자기 가격표를 쓰는지
    step("3) claimOffer — 미인증 호출 거부 확인")
    status, body = post(endpoints["claimOffer"], {"data": {"offerId": "2001"}})
    # onCall은 미인증 시 401/403, 알 수 없는 오퍼면 404
    p4 = status in (401, 403)
    if p4:
        ok(f"미인증 claimOffer → HTTP {status} (거부됨)")
    elif status in (400, 404):
        warn(f"미인증 claimOffer → HTTP {status} (인증 계층 통과, 입력검증에서 거부)")
        p4 = True
    else:
        bad(f"미인증 claimOffer → HTTP {status} 🚨")
    results.append(("claimOffer 미인증 거부", p4))

    # ---------------------------------------------------------------
    step("4) requestPayout — 미인증 호출 거부 확인")
    status, body = post(endpoints["requestPayout"],
                        {"data": {"method": "paypal", "points": 999999}})
    p5 = status in (401, 403, 400)
    (ok if p5 else bad)(f"미인증 requestPayout → HTTP {status} " + ("(거부됨)" if p5 else "🚨"))
    results.append(("requestPayout 미인증 거부", p5))

    # ---------------------------------------------------------------
    step("5) Firestore 규칙 — 클라이언트 직접 잔액 조작 차단")
    fs = f"https://firestore.googleapis.com/v1/projects/{args.project}/databases/(default)/documents/users/attacker_probe"
    status, _ = get(fs)
    p6 = status == 403
    (ok if p6 else bad)(f"비인증 읽기 → HTTP {status} " + ("(차단됨)" if p6 else "🚨 통과됨!"))
    results.append(("Firestore 비인증 읽기 차단", p6))

    status, _ = patch(
        fs + "?updateMask.fieldPaths=points",
        {
            "name": f"projects/{args.project}/databases/(default)/documents/users/attacker_probe",
            "fields": {"points": {"integerValue": "9999999"}},
        },
    )
    p7 = status == 403
    (ok if p7 else bad)(f"비인증 쓰기 → HTTP {status} " + ("(차단됨)" if p7 else "🚨 통과됨!"))
    results.append(("Firestore 비인증 쓰기 차단", p7))

    # ---------------------------------------------------------------
    step("결과 요약")
    passed = sum(1 for _, v in results if v)
    total = len(results)
    for name, v in results:
        print(f"  {'✅' if v else '❌'} {name}")
    print()
    if passed == total:
        print(f"{G}  🎉 {passed}/{total} 통과 — 안티프라우드 정상 작동{N}")
    else:
        print(f"{R}  {passed}/{total} 통과 — 실패 항목 확인 필요{N}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    raise SystemExit(main())
