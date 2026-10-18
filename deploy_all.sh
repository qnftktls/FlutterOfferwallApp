#!/usr/bin/env bash
# =============================================================
#  Rewards Hub — Cloud Functions 원샷 배포 스크립트
#  사용법: bash deploy_all.sh
#  전제 : Firebase 콘솔에서 API 5개 활성화 완료
# =============================================================
set -uo pipefail

PROJECT="flutter-offerwall-app"
SA="/opt/flutter/firebase-admin-sdk.json"
ROOT="/home/user/flutter_app"

export GOOGLE_APPLICATION_CREDENTIALS="$SA"
cd "$ROOT"

hr() { printf '%s\n' "------------------------------------------------------------"; }
ok() { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; }
info() { printf '  · %s\n' "$1"; }

echo "============================================================"
echo " ① 선행 점검 — 필수 API 활성 상태"
echo "============================================================"

python3 - <<'PYEOF'
import json, time, urllib.request, urllib.parse, urllib.error, jwt, sys
PROJECT = "flutter-offerwall-app"
sa = json.load(open("/opt/flutter/firebase-admin-sdk.json"))
now = int(time.time())
p = {"iss": sa["client_email"], "scope": "https://www.googleapis.com/auth/cloud-platform",
     "aud": "https://oauth2.googleapis.com/token", "iat": now, "exp": now+3600}
signed = jwt.encode(p, sa["private_key"], algorithm="RS256")
body = urllib.parse.urlencode({"grant_type":"urn:ietf:params:oauth:grant-type:jwt-bearer","assertion":signed}).encode()
tok = json.loads(urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=body)).read())["access_token"]

eps = {
 "cloudfunctions": f"https://cloudfunctions.googleapis.com/v2/projects/{PROJECT}/locations/-/functions",
 "cloudbuild": f"https://cloudbuild.googleapis.com/v1/projects/{PROJECT}/builds?pageSize=1",
 "artifactregistry": f"https://artifactregistry.googleapis.com/v1/projects/{PROJECT}/locations/-/repositories",
 "run": f"https://run.googleapis.com/v2/projects/{PROJECT}/locations/-/services",
 "eventarc": f"https://eventarc.googleapis.com/v1/projects/{PROJECT}/locations/-/triggers",
}
missing = []
for name, url in eps.items():
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"}))
        print(f"  ✅ {name}: 활성 (HTTP {r.status})")
    except urllib.error.HTTPError as e:
        b = e.read().decode()
        try: m = json.loads(b)["error"]["message"]
        except Exception: m = b
        if "has not been used" in m or "is disabled" in m:
            print(f"  ❌ {name}: 비활성")
            missing.append(name)
        else:
            print(f"  ⚠️  {name}: {m[:80]}")
            missing.append(name)
if missing:
    print()
    print("  ============================================")
    print("  ⛔ 배포 중단 — 다음 API를 먼저 활성화하세요:")
    for m in missing: print(f"     - {m}")
    print("  ============================================")
    print("  콘솔(가장 빠름):")
    print(f"     https://console.firebase.google.com/project/{PROJECT}/functions")
    print("     → '함수 만들기' / '시작하기' 클릭 → API 사용 설정")
    sys.exit(2)
print()
print("  ✅ 필수 API 전부 활성 상태 — 배포 진행 가능")
PYEOF

APICHK=$?
if [ "$APICHK" -ne 0 ]; then
  echo ""
  bad "API가 아직 비활성입니다. 콘솔에서 활성화 후 다시 실행하세요."
  exit 1
fi

hr
echo "② Functions 의존성 설치"
hr
cd "$ROOT/functions"
npm install --silent 2>&1 | tail -3
ok "npm install 완료"

hr
echo "③ TypeScript 빌드"
hr
npm run build 2>&1 | tail -5
if [ -f "$ROOT/functions/lib/index.js" ]; then ok "컴파일 성공"; else bad "컴파일 실패"; exit 1; fi

hr
echo "④ 시크릿 등록 (OFFERWALL_SECRET)"
hr
cd "$ROOT"
if firebase functions:secrets:access OFFERWALL_SECRET --project "$PROJECT" >/dev/null 2>&1; then
  ok "시크릿 이미 존재 (건너뜀)"
else
  SECRET_VAL="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if printf '%s' "$SECRET_VAL" | firebase functions:secrets:set OFFERWALL_SECRET --project "$PROJECT" --data-file=- >/dev/null 2>&1; then
    ok "시크릿 생성 완료 (32바이트 랜덤)"
  else
    info "자동 등록 실패 — 아래 값으로 수동 등록하세요:"
    printf '     OFFERWALL_SECRET = %s\n' "$SECRET_VAL"
  fi
fi

hr
echo "⑤ Cloud Functions 배포"
hr
firebase deploy --only functions --project "$PROJECT" --non-interactive 2>&1 | tail -25

hr
echo "⑥ Firestore 프로덕션 규칙 적용 (points/tx 서버 전용화)"
hr
if [ -f "$ROOT/firestore.rules.antifraud" ]; then
  cp "$ROOT/firestore.rules" "$ROOT/firestore.rules.clientonly.bak"
  cp "$ROOT/firestore.rules.antifraud" "$ROOT/firestore.rules"
  firebase deploy --only firestore:rules,firestore:indexes --project "$PROJECT" --non-interactive 2>&1 | tail -12
  ok "안티프라우드 규칙 배포 시도 완료"
else
  info "firestore.rules.antifraud 없음 — 건너뜀"
fi

hr
echo "⑦ 배포 검증 — 엔드포인트 확인"
hr
for fn in offerwallPostback:onRequest claimOffer:onCall requestPayout:onCall; do
  name="${fn%%:*}"
  url="https://us-central1-$PROJECT.cloudfunctions.net/$name"
  code=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$url" 2>/dev/null || echo "000")
  info "$name → HTTP $code  ($url)"
done

echo ""
echo "============================================================"
ok "배포 파이프라인 종료"
echo "============================================================"
