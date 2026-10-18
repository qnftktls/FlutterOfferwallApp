# Rewards Hub — 남은 필수 작업 (출시 전 체크리스트)

작성 시각 기준 원격 실측 결과입니다. **STEP 6 멈춤보다 훨씬 큰 문제가 3개 있습니다.**

---

## 0. 방금 확인한 사실 (추측 아님, 원격 API 실측)

| 확인 항목 | 방법 | 결과 | 판정 |
|---|---|---|---|
| Functions 3개 배포 | `POST /claimOffer` 등 | HTTP 401 `{"message":"Sign in to claim rewards."}` | ✅ 살아있음 |
| **신규 가격표 반영** | 코드에 `game_puzzle#0` 존재 | 인증 전 401이라 **판정 불가** | ⚠️ 미확정 |
| **Firebase Authentication** | `identitytoolkit admin/v2/projects/.../config` | **HTTP 404 `CONFIGURATION_NOT_FOUND`** | ❌ **비활성** |
| Auth 클라이언트 signUp | `accounts:signUp` (Web API 키) | **HTTP 400 `CONFIGURATION_NOT_FOUND`** | ❌ **비활성** |
| Firestore DB | `firestore/v1/projects/.../databases` | HTTP 200 | ✅ 존재 |
| Firebase 프로젝트 상태 | `firebase/v1beta1/projects/...` | `state=ACTIVE` | ✅ 정상 |
| Blaze 결제 | (이전 확인) | 활성 | ✅ 완료 |
| SA 토큰 | JWT RS256 | 발급 성공 | ✅ 정상 |

---

## 1. 🔴 최우선 — Firebase Authentication 이 초기화되지 않았다

### 왜 치명적인가

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

### 지금 즉시 (브라우저, 5분)
- [ ] **Firebase Console → Authentication → 이메일/비밀번호 사용 설정**  ← 가장 급함
- [ ] 익명 로그인은 사용 안 함으로 유지

### 지금 즉시 (터미널)
- [ ] `deploy_all.ps1` 실행 중이면 **Ctrl + C** (배포는 이미 끝났거나 멈춘 상태, 안전)
- [ ] `cd $HOME\FlutterOfferwallApp; git pull`
- [ ] `powershell -ExecutionPolicy Bypass -File .\deploy.ps1 -TimeoutSeconds 1200`

### 확인 후
- [ ] `python verify_deployment.py` → 신규 가격표 반영 확인
- [ ] `auth_service.dart` 의 `uid='local'` 폴백 제거
- [ ] `.\deploy.ps1 -ApplyRules` 실행 (anti-fraud 규칙 적용)

### 운영 준비
- [ ] **`OFFERWALL_SECRET` 회전** — 이전 값이 터미널에 노출되었습니다 (폐기 대상)
      ```powershell
      powershell -Command "[Convert]::ToHexString((1..32 | ForEach-Object { Get-Random -Max 256 })).ToLower()"
      ```
- [ ] 오퍼월 제공자 대시보드에 postback URL 등록
      `https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback`
- [ ] `offerwall_controller.dart` 의 클라이언트 `addPoints` 를 서버 경로로 전환
      (실제 제공자 postback 이 대체하므로 보류 중)
- [ ] 보안 규칙 적용 **전에** 모든 크레딧 경로가 서버 기반인지 확인
      — 아님 게임 보상이 조용히 막힙니다

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
