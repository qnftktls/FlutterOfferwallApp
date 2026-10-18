# 🚀 Rewards Hub — Cloud Functions 배포 가이드 (5분)

> 이 문서는 **님의 PC(또는 서버)** 에서 안티프라우드 Cloud Functions를 배포하는 방법입니다.
> 샌드박스에서는 배포 권한이 없어 여기서만 가능합니다 (아래 "왜?" 참고).

---

## ⚠️ 먼저 읽어주세요 — 실제로 막혔던 두 가지

**1) `deploy_all.ps1` 은 폐기되었습니다. `deploy.ps1` 을 쓰세요.**

`deploy_all.ps1` 의 배포 단계는 `Select-Object -Last 30` 으로 출력을 파이프했습니다.
이 명령은 프로세스가 **끝날 때까지 전체 출력을 버퍼링**하므로 배포 중 화면이 비어 있습니다.

그리고 `--force` 는 **함수 삭제** 프롬프트만 우회합니다.
Blaze 업그레이드 후 첫 배포에서는 CLI 가 이걸 물어봅니다:

```
? Would you like to enable the required APIs? (Y/n)
```

`--force` 는 이걸 막지 못합니다 → **키 입력을 기다리며 20분 멈춤** → 화면은 계속 비어 있음.

`deploy.ps1` 은 `--non-interactive`, 실시간 출력, 프롬프트 감지, 프로세스 트리 종료로
이 문제를 전부 해결합니다. **`deploy_all.ps1` 을 실행하면 자동으로 `deploy.ps1` 로 넘어갑니다.**

**2) 🔴 Firebase Authentication 이 꺼져 있습니다 (더 급한 문제)**

실측 결과 `CONFIGURATION_NOT_FOUND` 입니다. `claimOffer`/`requestPayout` 는 로그인이
필수이므로, **지금은 서버 보상이 아무에게도 지급되지 않습니다.**

👉 https://console.firebase.google.com/project/flutter-offerwall-app/authentication
→ 시작하기 → Sign-in method → **이메일/비밀번호 사용 설정**

자세한 내용은 **`CRITICAL_PATHS.md`** 를 보세요.

---

## ⚡ 초간단 (복사-붙여넣기)

### 0단계 — 준비 (최초 1회만)

```powershell
# Node.js 20+ 필요 → https://nodejs.org

# Firebase CLI 설치
npm install -g firebase-tools

# 본인 Google 계정으로 로그인 (브라우저 열림)
firebase login

# 코드 받기
git clone https://github.com/qnftktls/FlutterOfferwallApp.git
cd FlutterOfferwallApp
```

### 1단계 — 원샷 배포

```powershell
# 첫 실행은 API 활성화에 5~10분 걸릴 수 있어 타임아웃을 넉넉히
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -TimeoutSeconds 1200
```

**끝입니다.** 스크립트가 아래를 자동으로 처리합니다:

| 단계 | 내용 |
|---|---|
| 0 | 도구 확인 (node, npm, firebase) |
| 1 | 로그인 확인 |
| 2 | `npm install` + TypeScript 빌드 |
| 3 | **함수 배포** (실시간 출력 + 프롬프트 자동 차단) |
| 4 | 엔드포인트 3개 응답 확인 |
| 5 | 안티프라우드 규칙 — **기본은 건너뜀** (`-ApplyRules` 로 옵트인) |

> ⏱ 소요: 약 3~5분 (첫 배포는 API 활성화 포함 최대 10분)
> 🔒 규칙 적용은 기본 OFF 입니다. 모든 크레딧 경로가 서버 기반이 된 뒤에 `-ApplyRules` 를 쓰세요.

> ⚠️ **WSL(`bash`) 을 쓰지 마세요.** `bash deploy_all.sh` 는 PowerShell 에서 WSL 을 부르는데,
> 님 PC 는 WSL 이 손상되어(`ext4.vhdx` ERROR_FILE_NOT_FOUND) 실패합니다.
> 위의 PowerShell 명령을 쓰세요. (`WINDOWS_DEPLOY.md` 참고)

---

## 🖐 만약 `deploy_all.sh` 없이 수동으로 하려면

```bash
cd functions && npm install && cd ..

# 시크릿 등록 (아무 긴 문자열 입력)
firebase functions:secrets:set OFFERWALL_SECRET

# 함수 배포
firebase deploy --only functions --project flutter-offerwall-app

# (선택) 함수 정상 동작 확인 후, 안티프라우드 규칙 적용
cp firestore.rules.antifraud firestore.rules
firebase deploy --only firestore:rules --project flutter-offerwall-app
```

---

## 🚨 자주 나는 에러 & 해결

### 1. `API has not been used in project ... or it is disabled`
**정상입니다.** 첫 배포 시 뜨는 안내입니다.
```
➜ 콘솔에서 [사용 설정] 클릭:
   https://console.firebase.google.com/project/flutter-offerwall-app/functions
   → "함수 만들기" / "시작하기" 버튼 → "API 사용 설정"
```
5개 API(cloudfunctions, cloudbuild, artifactregistry, run, eventarc)가 **한 번에** 켜집니다.
그 후 `bash deploy_all.sh` 다시 실행.

### 2. `Your project must be on the Blaze (pay-as-you-go) plan`
Cloud Functions는 Blaze 플랜 필요:
```
https://console.firebase.google.com/project/flutter-offerwall-app/usage/details
```
> 💡 **무료로 쓸 수 있습니다**: Functions 월 200만 회 호출 무료. 개인 개발 규모면 **청구 $0**.

### 3. `Error: HTTP Error: 403, Permission denied to enable service`
님 계정에 `Service Usage Admin` 역할이 없는 경우입니다.
```
https://console.cloud.google.com/iam-admin/iam?project=flutter-offerwall-app
→ 본인 계정에 "Service Usage Admin" 역할 추가
```

### 4. `Permission denied to get service [cloudfunctions.googleapis.com]`
**샌드박스에서만 나는 에러입니다** (님 PC에서는 안 남). 아래 "왜?" 참고.

---

## ❓ 왜 샌드박스에서 배포가 안 되나?

샌드박스는 **Firebase Admin SDK 서비스 계정**(`firebase-adminsdk-fbsvc@...`)을 사용합니다.
이 계정은 **데이터 접근용**으로 설계됐고, **인프라 배포/API 활성화 권한이 없습니다.**

```
✅ 서비스 계정으로 되는 것:   Firestore 읽기/쓰기, Auth 관리, 규칙 배포
❌ 서비스 계정으로 안 되는 것: Cloud Functions API 활성화, Functions 배포
```

이건 **버그가 아니라 올바른 보안 설계**입니다 — "데이터 권한"과 "인프라 권한"을 분리해서
자동화 도구가 함부로 인프라를 바꾸지 못하게 막습니다.

**님의 Google 계정(소유자)** 으로 `firebase login` 하면 모든 권한이 있어서 배포됩니다.

---

## 📋 배포 후 체크리스트

배포가 끝나면 함수 3개가 이 URL로 살아납니다:

```
https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback  (광고주 postback)
https://us-central1-flutter-offerwall-app.cloudfunctions.net/claimOffer         (오퍼 클레임)
https://us-central1-flutter-offerwall-app.cloudfunctions.net/requestPayout      (출금 요청)
```

### 다음 할 일
1. **광고주 대시보드에 postback URL 등록**
   → `https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback`
2. **안티프라우드 규칙 적용 확인** (deploy_all.sh가 자동 처리)
3. **앱에서 오퍼 완료 테스트** → 서버 검증 경로 동작 확인

### ⚠️ 안티프라우드 규칙 적용 후 주의사항
`firestore.rules.antifraud`를 적용하면 **클라이언트는 `points`/`tx`를 직접 못 씁니다.**
모든 잔액 변경은 **Cloud Functions 경유**로만 가능해집니다.
- 앱의 오퍼 완료 → `claimOffer` 함수 호출 ✅
- 앱의 출금 요청 → `requestPayout` 함수 호출 ✅
- 로컬 데모 경로는 **자동으로 비활성** (서버가 권위)

만약 문제가 생기면 백업으로 복원:
```bash
cp firestore.rules.clientonly.bak firestore.rules
firebase deploy --only firestore:rules --project flutter-offerwall-app
```

---

## 🔍 배포 검증 명령

```bash
# 함수 목록
firebase functions:list --project flutter-offerwall-app

# 함수 로그 실시간 확인
firebase functions:log --project flutter-offerwall-app

# 엔드포인트 응답 확인 (postback은 서명 없으면 401 반환 = 정상)
curl -s -o /dev/null -w "%{http_code}\n" \
  https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback
```

정상이라면 `offerwallPostback`은 **401** (서명 없음 거부), `claimOffer`/`requestPayout`은 **400/403** (인증 필요)을 반환합니다.
→ **이게 바로 안티프라우드가 작동한다는 증거**입니다.

---

## 📞 배포 후 알려주세요

`bash deploy_all.sh` 실행 후 결과를 알려주시면, 제가 **원격에서 엔드투엔드 검증**을 돌려드립니다:
- 위조 서명 요청 → 거부되는지
- 금액 조작 요청 → 서버 값으로 덮어써지는지
- 중복 지급 → 차단되는지
