# Rewards Hub — 남은 필수 작업 (출시 전 체크리스트)

> ## ✅ 진행 상황 (최신)
>
> | 항목 | 이전 | 현재 |
> |---|---|---|
> | Blaze 결제 | ❌ | ✅ 활성 |
> | Functions 3개 배포 | ❌ | ✅ 배포 + 검증 완료 |
> | **Firebase Authentication** | ❌ 404 | ✅ **활성** (`email enabled = True`) |
> | **신규 가격표 반영** | ⚠️ 미확정 | ✅ **확인** (`game_puzzle#0` → 250p) |
> | **실제 포인트 지급** | ❌ | ✅ **E2E 증명** (250p 지급 + Firestore 기록) |
> | 멱등성 (중복 지급 방지) | — | ✅ 작동 (`duplicated:true`) |
> | 서버가 금액 결정 | — | ✅ 클라이언트가 `points:9999999` 보내도 250p만 지급 |
> | 안티프라우드 원격 검증 | — | ✅ **9/9 통과** |
> | **🔴 출금 조작 익스플로잇** | 미인지 | ❌ **증명됨 — 즉시 조치 필요** |
> | 하드닝된 보안 규칙 적용 | ❌ | ❌ **미적용 (최우선)** |
>
> ---
>
> ## 🔴 0순위 — 실제 익스플로잇을 증명했습니다 (지금 바로 조치)
>
> 테스트 계정으로 **실제 공격을 실행해서 성공시켰습니다.** 추측이 아닙니다:
>
> ```
> [1] 공격자 계정 생성 (앱과 동일한 방식)     잔액 0
> [2] Firestore 직접 쓰기 → "내 잔액 = 50000"  HTTP 200  ★ 규칙이 허용
> [3] requestPayout(paypal, 50000p)           HTTP 200
>     → {"message":"Requested $50.00 via PayPal."}   ★★★ 인출 성공
> ```
>
> **누구나 계정 하나 만들고 잔액을 조작해 무제한으로 돈을 뺄 수 있습니다.**
> (테스트 흔적은 전부 삭제했습니다 — payout, user 문서, Auth 계정 모두.)
>
> ### 원인
>
> `requestPayout` 이 `users/{uid}.points` 를 그대로 믿는데,
> **현재 배포된 규칙**이 클라이언트에게 그 필드의 쓰기를 허용합니다:
>
> ```javascript
> // firestore.rules (현재 배포본)
> allow read, write: if request.auth != null && request.auth.uid == uid;
> //                  ^^^^ 자기 문서면 뭐든 쓸 수 있음 → 잔액 무한 조작
> ```
>
> ### 조치 (두 겹으로 막았습니다)
>
> **1겹 — 하드닝된 규칙 적용 (필수):**
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -ApplyRules
> ```
>
> **2겹 — 서버 전용 원장 도입 (코드에 이미 반영):**
> `users/{uid}.serverLedger` 는 **Cloud Functions 만** 쓸 수 있습니다
> (Admin SDK 는 보안 규칙을 우회하므로 클라이언트는 위조 불가).
> 출금은 이제 `points` 가 아니라 원장을 기준으로 계산됩니다:
> ```
> 출금 가능액 = ledger.verified + min(ledger.unverified, 2000)
> ```
> → 규칙 적용 전이라도 **최대 피해가 $2** (모든 출금 최소액 미달 = 인출 불가).
> 출금 시 원장에서도 차감하므로 **반복 출금도 불가**합니다.
>
> **남은 작업: 재배포** (아래 4번 순서 참고) — 배포해야 2겹이 활성화됩니다.
>
> ⚠️ **기존 계정 안내**: 원장 도입 전에 가입한 계정은 `serverLedger` 가 없어
> 출금 가능액이 0으로 보입니다. 의도된 동작입니다 (그 잔액은 검증된 적이 없음).
> 실제로 보상을 받은 사용자는 postback/claim 이후 자동으로 원장이 채워집니다.
> 기존 잔액을 살리려면 최초 1회 마이그레이션이 필요합니다 — 문의 주세요.

---

## 1. ✅ 해결됨 — Firebase Authentication

이전에 `CONFIGURATION_NOT_FOUND` 였으나 **지금은 활성화되었습니다.**
실측: `admin/v2 config → HTTP 200`, `email enabled = True`.

**아래는 기록용으로 남깁니다.**

### 왜 치명적이었는가

`claimOffer` 와 `requestPayout` 은 **로그인이 필수**입니다:

```typescript
const uid = request.auth?.uid;
if (!uid) {
  throw new HttpsError("unauthenticated", "Sign in to claim rewards.");
}
```

그런데 프로젝트에 Auth 설정이 **존재하지 않습니다** (`CONFIGURATION_NOT_FOUND`).
즉 `request.auth` 는 **항상 null** → 두 함수는 **모든 사용자에게 영구히 401** 입니다.

증상: 서버 보상(게임 마일스톤, 오퍼 완료, 출금)이 **아무도 작동하지 않습니다.**
앱은 로컬 폴백 덕분에 "되는 것처럼" 보이지만, 실제로는 로컬 숫자만 올라갑니다.

### 더 나쁜 문제 — 가짜 로그인

`lib/services/auth_service.dart` 는 Firebase 가 준비 안 되면
**입력한 이메일을 그대로 받아들이고 `uid='local'` 로 "로그인 성공" 처리**합니다:

```dart
Future<AuthResult> signIn(String email, String password) async {
  final FirebaseAuth? auth = _auth;
  if (auth == null) {
    // Offline/demo fallback: accept a local guest session.
    user.value = AppUser(uid: 'local', email: email, isGuest: false);
    return const AuthResult(ok: true);      // ← 로그인 성공이라고 거짓 보고
  }
  ...
```

그리고 `sync_service.dart` 는 `uid == 'local'` 을 **거부**합니다:

```dart
if (db == null || uid.isEmpty || uid == 'guest' || uid == 'local') {
  status.value = SyncStatus.offline;
  return;
}
```

→ 사용자는 **아무 비밀번호나 넣어도 로그인되고**, 아무것도 클라우드에 저장되지 않습니다.

### 해결 (5분, 브라우저에서)

1. https://console.firebase.google.com/project/flutter-offerwall-app/authentication
2. **시작하기** 클릭
3. **Sign-in method** 탭 → **이메일/비밀번호** 선택 → **사용 설정** ON → 저장
4. 다시 **Sign-in method** → **익명** 은 **끄고** 둡니다 (출시 요구사항)

### 확인 방법

```powershell
python verify_deployment.py            # 또는
curl "https://identitytoolkit.googleapis.com/v1/projects/flutter-offerwall-app/config"
```
404 가 아니라 200 이면 성공입니다.

### 그 다음 — 가짜 로그인 제거

Auth 를 켠 뒤에는 `auth_service.dart` 의 `uid='local'` 폴백이 **위험**해집니다.
실제 백엔드가 생겼는데도 조용히 로컬로 떨어지기 때문입니다.

```dart
// 변경 전
if (auth == null) {
  user.value = AppUser(uid: 'local', email: email, isGuest: false);
  return const AuthResult(ok: true);
}

// 변경 후 — 실패를 실패라고 말한다
if (auth == null) {
  return const AuthResult(ok: false, error: 'auth_unavailable');
}
```

`uid == 'local'` 로 생성되는 계정은 **클라우드에 아무것도 저장하지 못하므로**
출시 빌드에서는 반드시 이 경로를 닫아야 합니다.

---

## 2. 🟠 STEP 6 이 20분 멈춘 진짜 원인

### 확정된 원인 — 인터랙티브 프롬프트 + 출력 버퍼링

`deploy_all.ps1` 의 STEP 6 은 이렇게 되어 있었습니다:

```powershell
& firebase deploy --only functions --project $Project --force 2>&1 |
    Tee-Object -FilePath $logPath |
    Select-Object -Last 30            # ← 전체 출력을 프로세스 종료까지 버퍼링
```

`Select-Object -Last 30` 은 **스트림을 끝까지 읽어야** 마지막 30줄을 알 수 있습니다.
그래서 배포 중에는 **아무것도 안 보이고**, 진짜 멈춘 것처럼 보입니다.

그리고 결정적으로 — **`--force` 는 함수 삭제 프롬프트만 우회합니다.**
Blaze 업그레이드 후 처음 배포하면 CLI 가 이걸 물어봅니다:

```
? Would you like to enable the required APIs? (Y/n)
```

이건 `--force` 로 안 막힙니다. 키 입력을 기다리며 **영원히** 멈춥니다.

### 검증한 사실

- `firebase --non-interactive` 는 **실재하는 전역 옵션**입니다 (`firebase --help` 확인)
- 위치: **반드시 `deploy` 앞** (전역 옵션)
  - `firebase --non-interactive deploy ...` ✅
  - `firebase deploy --non-interactive ...` — 실은 통과하지만 전역 옵션은 앞에 쓰는 게 규칙
- `firebase deploy --totally-bogus-flag` → `error: unknown option` 으로 거부됨
  → 즉 위 확인은 유효한 테스트였습니다

### 해결 — `deploy.ps1` (신규)

기존 `deploy_all.ps1` 을 대체하기 위해 만들었습니다:

| 기능 | 목적 |
|---|---|
| `CI=true`, `FIREBASE_CLI_DISABLE_PROMPTS=1` | 자동 프롬프트 차단 |
| `firebase --non-interactive deploy ...` | 프롬프트에서 **대기 대신 에러** |
| 로그 파일 **바이트 오프셋 tail** | 부분 줄 유실 없이 실시간 출력 |
| **프롬프트 감지** (`would you like`, `[Y/n]` 등) | 캡처 못 한 프롬프트도 잡아냄 |
| 무출력 `-IdleKillSeconds` 판정 | "질문 후 침묵" = 확정적 멈춤 |
| `taskkill /T /F` | **프로세스 트리 전체 종료** (node 누수 방지) |
| `-TimeoutSeconds` 워치독 | 최후의 안전장치, exit 124 |
| 실패 시 로그 마지막 40줄 자동 표시 | 원인이 화면에서 바로 보임 |
| `-ApplyRules` 옵트인 | 기본은 앱이 안 깨지는 쪽 |

**첫 실행은 `-TimeoutSeconds` 를 넉넉히 주세요** (API 활성화에 5~10분 걸릴 수 있음):

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -TimeoutSeconds 1200
```

---

## 3. 🟡 아직 확인 못 한 것 — 신규 가격표가 배포됐는가

20분 동안 실제로 배포가 됐는지 **아직 확정하지 못했습니다.**

시도한 방법과 막힌 이유:

| 방법 | 결과 |
|---|---|
| `cloudfunctions.functions.list` (SA) | 403 — SA 에 `cloudfunctions` 권한 없음 |
| `claimOffer('game_puzzle#0')` 무인증 | 401 — **인증 검사가 가격표 조회보다 먼저** 실행되어 판정 불가 |
| `claimOffer('2001')` (구버전에도 존재) 무인증 | 401 — 동일 |
| 테스트 계정 생성 후 인증 호출 | ❌ **Auth 가 꺼져 있어 계정 생성 실패** |

→ **Auth 를 켜면 판정 가능해집니다.** 그때 `verify_deployment.py` 로 확인하세요.

```powershell
python verify_deployment.py
```

`game_puzzle#0` 이 `ok:true` 를 반환하면 신규 가격표가 살아있는 것입니다.

---

## 4. 남은 작업 순서

### ✅ 완료 (STEP 3 배포 + 원장 검증)

```
[3] 잔액 조작 시도       → HTTP 200  (규칙은 아직 열려 있음)
[3] 조작된 잔액으로 출금  → HTTP 400
    {"message":"Insufficient verified balance: have 0, need 50000."}
```

**서버 전용 원장이 실제로 돈을 막았습니다.** 보안 규칙이 아직 적용되지 않았는데도
인출이 불가능해졌습니다 — 2겹 방어가 설계대로 작동합니다.

### 🔴 남은 1개 — 보안 규칙 적용 (1겹)

```powershell
cd $HOME\FlutterOfferwallApp
git pull

# 하드닝된 규칙 적용 + 자동 보안 검증
powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -ApplyRules
```

적용하면 `security_regression.py` 의 경고 2건이 ✅ 로 바뀝니다:

| 항목 | 현재 | 적용 후 |
|---|---|---|
| 조작된 잔액 출금 | ✅ 불가 | ✅ 불가 |
| 원장 상한 초과 지급 | ✅ 불가 | ✅ 불가 |
| 잔액 조작 자체 | ⚠️ 가능 (무해) | ✅ 불가 |
| `serverLedger` 보호 | ⚠️ 미보호 | ✅ 보호 |

### 🚨 Node.js 20 지원 종료 — 12일 남음 (수정 완료)

배포 로그에 이 경고가 있었습니다:

```
!  functions: Runtime Node.js 20 was deprecated on 2026-04-30 and will be
   decommissioned on 2026-10-30, after which you will not be able to deploy
   without upgrading.
```

**2026-10-30 이후 함수 배포가 전면 차단됩니다.** 이미 수정했습니다:

| 파일 | 변경 |
|---|---|
| `firebase.json` | `"runtime": "nodejs20"` → `"nodejs22"` |
| `functions/package.json` | `"node": "20"` → `"node": "22"` |

Node.js 22가 GA이고 약 2년 지원이 남아 있어 안전한 선택입니다.
**다음 배포에서 자동으로 적용됩니다** (별도 명령 불필요).

> 참고: `firebase-functions` v6 와 `firebase-admin` v12 는 Node 22를 지원합니다.
> `tsconfig` 의 `target: es2020` 도 그대로 유효합니다 — 검증 완료.


### 적용 후 검증 (터미널)
```powershell
python verify_deployment.py            # 9/9 + 조작 차단 확인
```
그리고 익스플로잇을 **다시 시도**해서 막히는지 확인하세요:
```powershell
# 잔액 조작 시도 → HTTP 403 이어야 정상
# 출금 시도 → failed-precondition 이어야 정상
```

### ✅ 이미 완료된 것
- [x] Blaze 결제 활성
- [x] Firebase Authentication → 이메일/비밀번호 사용 설정
- [x] Functions 3개 배포 + 원격 검증 (9/9)
- [x] 신규 per-milestone 가격표 반영 확인
- [x] E2E 보상 지급 증명 (250p + Firestore 기록)
- [x] 멱등성 작동 확인
- [x] 서버가 금액 결정함을 확인 (클라이언트 조작 무시)

### 운영 준비 (출시 전)
- [ ] **`OFFERWALL_SECRET` 회전** — 이전 값이 터미널에 노출되었습니다 (폐기 대상)
      ```powershell
      powershell -Command "[Convert]::ToHexString((1..32 | ForEach-Object { Get-Random -Max 256 })).ToLower()"
      ```
      > ⚠️ 시크릿을 회전하면 함수를 **재배포**해야 반영됩니다.
- [ ] 오퍼월 제공자 대시보드에 postback URL 등록
      `https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback`
- [ ] `offerwall_controller.dart` 의 클라이언트 `addPoints` 를 서버 경로로 전환
      (실제 제공자 postback 이 대체하므로 보류 중)
- [ ] `auth_service.dart` 의 `uid='local'` 가짜 로그인 폴백 제거
      (Auth 가 켜졌으므로 이제 위험합니다 — 아래 참고)
- [ ] **기존 계정 잔액 마이그레이션** (원장 도입 전 가입자)
      원장이 없어 출금 가능액 0으로 표시됩니다. 실제 지급 이력이 있는 계정만
      최초 1회 `serverLedger.verified` 로 이관하면 됩니다.

### ⚠️ 규칙 적용의 부작용 (반드시 이해하고 진행)

`-ApplyRules` 를 적용하면 **클라이언트는 `points`/`tx` 를 쓸 수 없게 됩니다.**
각 화면이 어떻게 동작하는지 정리했습니다:

| 화면/경로 | 규칙 적용 후 | 조치 |
|---|---|---|
| 오퍼 완료 (`offer_detail_screen`) | ✅ 서버 경로 → 정상 | 없음 |
| 게임 마일스톤 (`games_screen`) | ✅ 서버 경로 → 정상 | 없음 |
| 출금 (`cashout_screen`) | ✅ 서버 경로 → 정상 | 없음 |
| **오퍼월 브리지** (`offerwall_controller`) | ⚠️ **로컬 크레딧 실패** | 아래 참고 |
| `_pushSoon()` 부가 push | ⚠️ 규칙상 거부 (UI 무해) | 없음 (아래 참고) |

**오퍼월 브리지**: `addPoints` 로 로컬 숫자만 올리고 `_pushSoon()` 이 서버에
밀어넣으려다 **규칙에 막힙니다.** 앱은 안 죽지만(에러 삼킴) **사용자는 보상을
못 받습니다.** → 실제 제공자 계정을 연결해 postback 경로로 전환해야 합니다.
그 전까지는 placeholder 오퍼월이므로 실사용자 피해는 없습니다.

**`_pushSoon()` 잔여 push**: `claimOffer` 성공 후 로컬 갱신분을 서버로 밀려다
거부당합니다. 값이 이미 서버와 같으므로(서버가 진실) **아무 영향 없습니다.**
다만 Firestore 로그에 permission-denied 가 남으니 정상적인 현상으로 보세요.

---

## 5. 비용 (Blaze 활성 상태)

| 항목 | 무료 한도 | 예상 |
|---|---|---|
| Cloud Functions | 월 200만 호출 | 사실상 0원 |
| Secret Manager | 6 버전 | 0원 |
| Artifact Registry | 0.5GB | 약 0.01달러 |
| Firestore | 일 5만 읽기 / 2만 쓰기 | 사실상 0원 |
| Firebase Auth | 월 5만 MAU | 사실상 0원 |

**지금 단계에서 월 몇백 원 수준입니다.** 불안하면 예산 알림을 걸어두세요:
https://console.cloud.google.com/billing/budgets

⚠️ 요금이 튀는 유일한 시나리오는 **남용**입니다 (postback 스팸, 함수 무한 호출).
`maxInstances: 10`, `points > 10_000_000` 거부, 멱등성 키가 이미 그 방어선입니다.
Auth 를 켜면 `request.auth` 검사가 한 겹 더 생겨 오히려 **비용이 줄어듭니다.**
