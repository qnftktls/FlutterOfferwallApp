# 🔥 Firestore 연동 가이드 (기기 간 동기화)

Rewards Hub는 **Firebase Auth(로그인) + Cloud Firestore(데이터 동기화)** 구조입니다.
코드는 이미 완성되어 있고, **Firestore API 활성화 1단계만** 남았습니다.

---

## ⚠️ 현재 상태

| 항목 | 상태 |
|------|------|
| Firebase Auth (로그인) | ✅ 작동 중 |
| **Cloud Firestore API** | ❌ **비활성** (프로젝트에서 아직 활성화 안 됨) |
| 앱 코드 | ✅ 완성 — API 비활성 상태에서도 로컬 전용으로 정상 동작 |

앱은 **오프라인 폴백(offline-first)** 으로 설계되어 있어, Firestore가 꺼져 있어도
크래시 없이 로컬 저장(`shared_preferences`)으로 작동하고 프로필에
**"로컬 전용 (로그인 시 동기화)"** 로 표시됩니다.

---

## 1단계 — Firestore Database 생성 (필수, 2분)

> 서비스 계정에 API 활성화 권한이 없어 **콘솔에서 직접** 해야 합니다.

1. **https://console.firebase.google.com/** 접속
2. 프로젝트 **`flutter-offerwall-app`** 선택
3. 왼쪽 메뉴 → **Build** → **Firestore Database**
4. **Create database** 클릭
5. 모드 선택: **Production mode** (보안 규칙은 3단계에서 적용)
6. 위치 선택: **`nam5 (us-central)`** 권장 (또는 사용자와 가까운 리전)
7. **Enable** 클릭 → 1~2분 대기

생성 후 아래 주소에서 API 활성화를 확인할 수 있습니다:
```
https://console.developers.google.com/apis/api/firestore.googleapis.com/overview?project=flutter-offerwall-app
```

---

## 2단계 — 빌드/배포

API 활성화 후 **코드 변경 없이** 바로 동기화가 작동합니다.

```bash
cd /home/user/flutter_app
flutter build apk --release     # 또는 flutter build web --release
```

> ℹ️ `cloud_firestore: 5.4.3`은 이미 `pubspec.yaml`에 추가되어 있고,
> `google-services.json`도 이미 프로젝트에 포함되어 있어 추가 설정이 필요 없습니다.

---

## 3단계 — 보안 규칙 적용 (권장)

`firestore.rules` 파일을 그대로 사용하세요.

**콘솔에서 적용:**
1. Firestore Database → **Rules** 탭
2. `firestore.rules` 내용을 붙여넣기
3. **Publish**

**CLI로 적용 (선택):**
```bash
npm install -g firebase-tools
firebase login
firebase deploy --only firestore:rules --project flutter-offerwall-app
```

### 규칙 요약
- `users/{uid}` 문서는 **본인만** 읽기/쓰기 가능 (`request.auth.uid == uid`)
- `points`는 음수 아닌 정수, `tx`는 배열(최대 200개)만 허용
- 그 외 모든 경로는 **차단**

---

## 4단계 — 동작 확인

1. 앱 실행 → **내 정보(Profile)** 탭
2. 로그인 (이메일/비밀번호)
3. **클라우드 동기화** 카드가 **"최신 상태"** (초록 체크)로 바뀌면 성공
4. 다른 기기에서 **같은 계정**으로 로그인 → 잔액·내역이 그대로 보임 ✅

| 상태 표시 | 의미 |
|-----------|------|
| 🔵 동기화 중… | 업로드/다운로드 진행 |
| 🟢 최신 상태 | 클라우드와 일치 |
| 🟠 로컬 전용 (로그인 시 동기화) | 미로그인 또는 게스트 |
| 🔴 동기화 실패 — 재시도 예정 | 네트워크/규칙/API 오류 |

---

## 📐 데이터 모델

**컬렉션 1개, 문서 1개** — 복합 인덱스(composite index)가 **전혀 필요 없습니다.**

```
users/{uid}
  ├─ points:    int                         // 현재 잔액 (1,000 pts = $1)
  ├─ tx:        array<map>                  // 리워드 내역 (최대 200건, 내장 배열)
  │    └─ { title, points, timestamp, offerId }
  └─ updatedAt: timestamp (serverTimestamp)
```

**왜 내역을 서브컬렉션이 아닌 배열로 저장하나요?**
`where()` + `orderBy()` 조합은 복합 인덱스를 요구하는데, 내역을 문서 내 배열로
저장하면 **모든 읽기/쓰기가 단일 문서 연산**이 되어 인덱스 문제가 원천 차단됩니다.
(200건 초과 시 오래된 항목은 자동 절사)

---

## 🔄 동기화 로직

| 시점 | 동작 |
|------|------|
| 로그인 | 클라우드 문서 **pull** → 데이터가 있으면 클라우드가 우선, 없으면 로컬을 push (첫 기기) |
| 포인트 적립/차감 | 로컬 저장 → **백그라운드 push** (UI 블로킹 없음) |
| 로그아웃 | 동기화 분리 (로컬 데이터 유지) |
| 게스트 | 로컬 전용 (uid = `guest` → 동기화 제외) |
| 수동 | 프로필 **"지금 동기화"** 버튼 |

---

## 🚨 프로덕션 주의사항

현재 잔액은 **클라이언트에서 계산**되어 Firestore에 기록됩니다. 실제 출금(돈)이
걸린 서비스에서는 반드시 **서버 검증**이 필요합니다:

1. **Cloud Functions**로 오퍼 완료를 서버에서 검증
2. 서버만 `points` 필드를 쓸 수 있게 규칙 강화
   ```
   allow update: if ... && request.resource.data.points == resource.data.points;  // 클라이언트 잔액 변경 금지
   ```
3. 출금은 서버(Functions)가 포인트를 확인한 뒤 결제 API 호출

---

## 관련 파일

| 파일 | 역할 |
|------|------|
| `lib/services/sync_service.dart` | Firestore 읽기/쓰기 + 오프라인 폴백 |
| `lib/services/points_repository.dart` | `bindUser()` / `syncNow()` / 자동 push |
| `lib/services/auth_service.dart` | 로그인·로그아웃 시 동기화 트리거 |
| `lib/screens/profile_screen.dart` | 동기화 상태 카드 UI |
| `firestore.rules` | 보안 규칙 |
| `test/widget_test.dart` | 동기화/폴백 단위 테스트 |
