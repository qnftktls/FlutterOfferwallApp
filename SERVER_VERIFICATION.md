# 🛡️ 안티프라우드: 서버 검증 잔액 (Cloud Functions)

클라이언트가 계산한 잔액은 **보안 경계가 될 수 없습니다.** APK를 뜯어고쳐
`points`를 위조할 수 있기 때문입니다. 이 문서는 **서버가 유일한 진실 공급원**이
되는 구조를 설명합니다.

```
❌ 취약한 구조 (현재 데모)
   클라이언트 → "저 1000포인트 받았어요" → Firestore     (위조 가능)

✅ 안전한 구조 (이 문서)
   오퍼월 제공자 → 서버(서명 검증) → Firestore            (위조 불가)
   앱 → claimOffer(offerId만 전송) → 서버가 금액 결정
```

---

## 📊 현재 배포 상태

| 항목 | 상태 |
|------|------|
| Firestore Database | ✅ 활성 (`(default)`, `nam5`/native) |
| **보안 규칙 (경화본)** | ✅ **배포 완료** — 무단 읽기/쓰기 403 차단 확인 |
| Cloud Functions 코드 | ✅ **작성 완료** — TypeScript 컴파일 성공 |
| Functions 배포 | ⏳ **Blaze 플랜 필요** |

**검증 결과** (규칙 경화 후):
```bash
# 인증 없이 읽기 → HTTP 403 "Missing or insufficient permissions."
# 인증 없이 쓰기 → HTTP 403 "Missing or insufficient permissions."
# (테스트 모드에서는 200이었음 → 안전하게 차단됨)
```

> ⚠️ 참고: Firestore 생성 시 **테스트 모드** 규칙은 `2026-11-17`에 만료되며
> 그 전까지 **누구나** 읽고 쓸 수 있습니다. 제가 이미 **소유자 전용 규칙으로
> 교체**했으므로 이 위험은 해소되었습니다.

---

## 🏗️ 구현된 3개 함수

### 1. `offerwallPostback` (HTTPS POST) — **안티프라우드의 핵심**

**오퍼월 제공자 서버가** 직접 호출합니다. 앱은 관여하지 않습니다.

```http
POST /offerwallPostback
X-Signature: sha256=<HMAC-SHA256 of raw body>

{ "user_id": "<firebase uid>", "points": 250,
  "offer_id": "2001", "txn_id": "abc123", "provider": "adgem" }
```

**방어 기제 3중:**

| 기제 | 설명 |
|---|---|
| **HMAC 서명 검증** | `OFFERWALL_SECRET`으로 서명 확인 + `timingSafeEqual` (타이밍 공격 방어) |
| **멱등성 (Idempotency)** | `txn_id`를 `processedTxns`에 기록 → 재전송/리플레이 시 **중복 적립 차단** |
| **상한 검증** | 1회 1,000만 포인트 초과 시 거부 (터무니없는 값 방어) |

### 2. `claimOffer` (Callable) — 즉시/데모 오퍼용

앱이 **`offerId`만** 보냅니다. 금액은 **서버의 가격표**(`SERVER_PRICE_TABLE`)가 결정합니다.

```dart
// 클라이언트는 금액을 말할 수 없음 — offerId만 전달
await RewardService.instance.claimOffer(offerId: '2001');
```

APK를 변조해 `points: 999999`를 보내도 **서버가 무시**합니다.

### 3. `requestPayout` (Callable) — 서버 검증 출금

- 서버가 **잔액 검증** → 트랜잭션으로 **원자적 차감** → `payouts` 문서 생성
- 부족하면 `failed-precondition` 오류
- `payouts` 컬렉션은 **서버만 쓰기 가능** (규칙으로 강제)

---

## 🚀 배포 방법 (Blaze 전환 후 3단계)

### 0단계 — Blaze 플랜 전환 (필수)

Cloud Functions는 **Blaze(종량제)** 플랜이 필요합니다. 무료 한도가 넉넉해서
소규모 앱은 사실상 무료지만, **카드 등록**이 필요합니다.

1. https://console.firebase.google.com/project/flutter-offerwall-app/usage/details
2. **Modify plan** → **Blaze** 선택
3. 예산 알림 설정 권장: **$1** (실수로 인한 과금 방지)

> 현재 서비스 계정에는 결제/API 활성화 권한이 없습니다 (403 확인됨).
> 이 단계만은 콘솔에서 직접 하셔야 합니다.

### 1단계 — Functions 배포

```bash
cd /home/user/flutter_app/functions
npm install
firebase login                       # 또는 GOOGLE_APPLICATION_CREDENTIALS 설정

# 오퍼월 서명 비밀키 설정 (제공자 대시보드의 값)
firebase functions:secrets:set OFFERWALL_SECRET

npm run deploy                        # = firebase deploy --only functions
```

배포 완료 시 3개 함수의 URL이 출력됩니다.

### 2단계 — 안티프라우드 규칙 발행

Functions가 살아있고 테스트를 통과한 **후에**:
```bash
firebase deploy --only firestore:rules --config firebase.json
```
또는 `firestore.rules.antifraud` 내용을 콘솔 Rules 탭에 붙여넣고 Publish.

이 규칙이 적용되면 **클라이언트는 잔액을 절대 쓸 수 없습니다.**

### 3단계 — 제공자 대시보드에 Postback URL 등록

오퍼월 제공자(AdGem/Tapjoy 등)의 **Postback/Callback URL** 칸에:
```
https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback
```
제공자 대시보드의 **Secret/Signature Key**를 `OFFERWALL_SECRET`과 동일하게 설정.

---

## 📐 규칙 모드 비교

| 파일 | `points` 쓰기 | 용도 |
|---|---|---|
| `firestore.rules` | 소유자 허용 (검증만) | 개발·데모 |
| `firestore.rules.antifraud` | **서버 전용** (`points`/`tx` 변경 시 거부) | **프로덕션** |

**`firestore.rules.antifraud`의 핵심:**
```
allow update: if request.auth.uid == uid
              && request.resource.data.points == resource.data.points   // ← 잔액 불변
              && request.resource.data.tx == resource.data.tx;           // ← 내역 불변
```
→ 클라이언트가 잔액을 바꾸려는 순간 **거부**됩니다.

---

## 🔧 클라이언트 설정

`lib/config/app_config.dart`:
```dart
class SecurityConfig {
  static const bool useServerVerification = true;   // ← 서버 검증 사용
}
```

**동작 흐름** (앱):
1. 오퍼 완료 → `RewardService.claimOffer(offerId)` 호출
2. 서버가 금액 결정 + 적립 → 새 잔액 반환
3. 앱이 `adoptServerBalance()`로 서버 값 채택 (+ 내역 재pull)
4. **Functions 미배포/오프라인이면** 로컬 폴백 (크래시 없음, 동기화 카드가 "오프라인" 표시)

---

## ✅ 보안 체크리스트

- [x] Firestore 테스트 모드 규칙 제거 (만료 위험 해소)
- [x] 무단 접근 403 차단 검증
- [x] HMAC 서명 검증 (`timingSafeEqual`)
- [x] 멱등성 (중복 적립 방지)
- [x] 상한 검증 (터무니없는 값 거부)
- [x] 서버 가격표 (클라이언트 금액 위조 불가)
- [x] 출금 서버 검증 + 원자적 차감
- [x] `payouts` 컬렉션 서버 전용
- [ ] **Blaze 전환 후 Functions 배포** ← 남은 작업
- [ ] 제공자 Postback URL 등록
- [ ] 안티프라우드 규칙 발행

---

## 🧪 로컬 테스트 (에뮬레이터)

Blaze 없이 검증하려면:
```bash
cd /home/user/flutter_app
firebase emulators:start --only functions,firestore
```
앱을 에뮬레이터에 연결: `FirebaseFunctions.instance.useFunctionsEmulator('localhost', 5001)`

---

## 관련 파일

| 파일 | 역할 |
|---|---|
| `functions/src/index.ts` | 3개 Cloud Functions (서버 검증 핵심) |
| `firestore.rules.antifraud` | 프로덕션 규칙 (points 서버 전용) |
| `firestore.rules` | 개발 규칙 (현재 배포됨) |
| `firebase.json` | Functions/Hosting/Rules 설정 |
| `lib/services/reward_service.dart` | 클라이언트 → Functions 호출 + 폴백 |
| `lib/services/points_repository.dart` | `adoptServerBalance()` — 서버 값 채택 |
| `lib/config/app_config.dart` | `SecurityConfig.useServerVerification` |
