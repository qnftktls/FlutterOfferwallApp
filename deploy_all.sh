#!/usr/bin/env bash
# =============================================================
#  Rewards Hub — Cloud Functions 원샷 배포 스크립트 (사용자 PC용)
#  사용법: bash deploy_all.sh
#
#  전제: firebase login 완료 (본인 Google 계정)
#        Cloud Functions API 활성 프롬프트에서 "사용 설정" 클릭
# =============================================================
set -uo pipefail

PROJECT="flutter-offerwall-app"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 색상
G='\033[0;32m'; R='\033[0;31m'; Y='\033[0;33m'; B='\033[1;34m'; N='\033[0m'
hr()  { printf '%s\n' "------------------------------------------------------------"; }
ok()  { printf "  ${G}✅ %s${N}\n" "$1"; }
bad() { printf "  ${R}❌ %s${N}\n" "$1"; }
warn(){ printf "  ${Y}⚠️  %s${N}\n" "$1"; }
info(){ printf "  · %s\n" "$1"; }
step(){ printf "\n${B}%s${N}\n" "$1"; hr; }

cd "$ROOT"

step "STEP 0 — 도구 확인"
if command -v firebase >/dev/null 2>&1; then
  ok "firebase CLI: $(firebase --version)"
else
  bad "firebase CLI 없음"
  info "설치: npm install -g firebase-tools"
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -ge 20 ]; then
    ok "node $(node -v) (요구: 20+)"
  else
    warn "node $(node -v) — 20 이상 권장"
  fi
else
  bad "node 없음 — https://nodejs.org 에서 설치"
  exit 1
fi

step "STEP 1 — Firebase 로그인 확인"
WHO=$(firebase login:list 2>/dev/null | sed -n '2p')
if [ -z "$WHO" ]; then
  bad "로그인 안 됨"
  info "실행: firebase login"
  info "(브라우저가 열리고 본인 Google 계정으로 로그인)"
  exit 1
fi
ok "로그인: $(echo "$WHO" | sed 's/^ *//')"

step "STEP 2 — 프로젝트 확인"
if firebase projects:list --non-interactive 2>/dev/null | grep -q "$PROJECT"; then
  ok "프로젝트 접근 가능: $PROJECT"
else
  bad "프로젝트 '$PROJECT' 접근 불가 — 계정 확인 필요"
  exit 1
fi

step "STEP 3 — Functions 의존성 설치"
cd "$ROOT/functions"
if npm install --silent 2>&1 | tail -2; then
  ok "npm install 완료"
else
  bad "npm install 실패"
  exit 1
fi

step "STEP 4 — TypeScript 빌드"
npm run build 2>&1 | tail -5
if [ -f "$ROOT/functions/lib/index.js" ]; then
  ok "컴파일 성공 (lib/index.js 생성)"
else
  bad "컴파일 실패"
  exit 1
fi

cd "$ROOT"

step "STEP 5 — 시크릿 등록 (OFFERWALL_SECRET)"
if firebase functions:secrets:access OFFERWALL_SECRET --project "$PROJECT" >/dev/null 2>&1; then
  ok "시크릿 이미 존재 — 건너뜀"
else
  info "광고주 postback 서명 검증용 시크릿을 등록합니다."
  SECRET_VAL="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if printf '%s' "$SECRET_VAL" | firebase functions:secrets:set OFFERWALL_SECRET \
        --project "$PROJECT" --data-file=- >/dev/null 2>&1; then
    ok "시크릿 생성 완료 (값은 의도적으로 출력하지 않음)"
  else
    unset SECRET_VAL
    warn "자동 등록 실패"
    info "보통 프로젝트가 Blaze 플랜이 아닐 때 발생합니다"
    info "Blaze가 필요합니다 (Secret Manager 활성화 조건)"
    echo
    printf "  ${Y}>>> BLAZE_UPGRADE.md 를 참고하세요 <<<${N}\n"
    printf "  ${Y}>>> 업그레이드 후 이 스크립트를 재실행하세요 <<<${N}\n"
    echo
    info "다음 실행 시 새 시크릿이 자동 생성됩니다"
    exit 1
  fi
fi

step "STEP 6 — Cloud Functions 배포 ($PROJECT)"
info "처음이면 'API 사용 설정' 프롬프트가 뜹니다 → [사용 설정] 클릭"
info "배포에는 3~5분 소요됩니다..."
echo
firebase deploy --only functions --project "$PROJECT" 2>&1 | tail -30
DEPLOY_RC=${PIPESTATUS[0]}

if [ "$DEPLOY_RC" -ne 0 ]; then
  bad "함수 배포 실패 (위 로그 확인)"
  info "팁: 'API has not been used' → 콘솔에서 사용 설정 후 재실행"
  exit 1
fi
ok "함수 배포 완료"

step "STEP 7 — Firestore 프로덕션 규칙 적용 (points/tx 서버 전용화)"
RULES_FILE="$ROOT/firestore.rules"
ANTI="$ROOT/firestore.rules.antifraud"
if [ -f "$ANTI" ]; then
  cp "$RULES_FILE" "$ROOT/firestore.rules.clientonly.bak"
  cp "$ANTI" "$RULES_FILE"
  if firebase deploy --only firestore:rules --project "$PROJECT" 2>&1 | tail -8; then
    ok "안티프라우드 규칙 배포 완료"
    info "백업: firestore.rules.clientonly.bak (클라이언트 쓰기 허용 버전)"
  else
    warn "규칙 배포 실패 — 클라이언트 버전으로 복원"
    cp "$ROOT/firestore.rules.clientonly.bak" "$RULES_FILE"
  fi
else
  info "firestore.rules.antifraud 없음 — 건너뜀"
fi

step "STEP 8 — 배포 결과 확인"
firebase functions:list --project "$PROJECT" 2>&1 | tail -12
echo
info "함수 엔드포인트:"
for fn in offerwallPostback claimOffer requestPayout; do
  printf '     https://us-central1-%s.cloudfunctions.net/%s\n' "$PROJECT" "$fn"
done

echo
printf "${G}============================================================${N}\n"
printf "${G}  배포 완료!${N}\n"
printf "${G}============================================================${N}\n"
echo
echo "  다음 할 일:"
echo "   1) 함수가 뜨는지 확인 (위 STEP 8 목록)"
echo "   2) 광고주 대시보드에 postback URL 등록:"
echo "      https://us-central1-$PROJECT.cloudfunctions.net/offerwallPostback"
echo "   3) 앱에서 오퍼 완료 → 서버 검증 경로 동작 확인"
