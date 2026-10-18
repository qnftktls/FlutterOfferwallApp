# 🪟 Windows 배포 가이드 (PowerShell)

> `bash deploy_all.sh` 가 WSL 오류로 안 되시나요? **정상입니다.**
> Windows에서 `bash` 는 WSL(Ubuntu)을 부르는데, 그 WSL 디스크가 깨져 있으면
> 스크립트가 실행되기도 전에 실패합니다. → **PowerShell 네이티브 스크립트를 쓰세요.**

---

## 🚨 왜 `bash deploy_all.sh` 가 실패하나?

```
디스크 '...Ubuntu22.04LTS...\ext4.vhdx'을(를) WSL2에 연결하지 못함:
지정된 파일을 찾을 수 없습니다.
오류 코드: ERROR_FILE_NOT_FOUND
```

**해석**: 님 PC의 WSL Ubuntu 가상 디스크 파일(`ext4.vhdx`)이 없어졌습니다.
PowerShell의 `bash` 명령은 WSL을 실행하므로, **WSL이 고쳐지기 전까지는 `bash ...` 가 전부 실패**합니다.

**해결**: WSL을 고치지 않아도 됩니다. **`deploy_all.ps1` (PowerShell 버전)** 을 쓰면 됩니다.

---

## ✅ 방법 1 — PowerShell 네이티브 배포 (권장, WSL 불필요)

### ① 먼저 도구가 있는지 확인

PowerShell 창을 열고 **아래 한 줄**을 붙여넣으세요:

```powershell
node -v; npm -v; firebase --version; git --version
```

결과별 대처:

| 안 나오는 항목 | 설치 방법 |
|---|---|
| `node` / `npm` | https://nodejs.org → **LTS** 다운로드 후 설치 (재시작 필요) |
| `firebase` | `npm install -g firebase-tools` |
| `git` | https://git-scm.com/download/win |

> 💡 `firebase` 가 `npm install -g` 후에도 안 잡히면 PowerShell을 **껐다 다시** 여세요.

### ② 코드 받기 (아직 안 받았다면)

```powershell
cd $HOME
git clone https://github.com/qnftktls/FlutterOfferwallApp.git
cd FlutterOfferwallApp
```

**git 이 없으면** — GitHub 웹에서 ZIP 다운로드:
```
https://github.com/qnftktls/FlutterOfferwallApp
→ 초록색 [<> Code] 버튼 → [Download ZIP] → 압축 풀기
→ PowerShell에서 그 폴더로 이동:  cd "$HOME\Downloads\FlutterOfferwallApp-main"
```

### ③ Firebase 로그인 (최초 1회)

```powershell
firebase login
```
→ 브라우저가 열립니다. **님의 Google 계정**(flutter-offerwall-app 소유자)으로 로그인.

### ④ 배포 실행 (한 줄)

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy_all.ps1
```

> `-ExecutionPolicy Bypass` 가 중요합니다. 없으면 "스크립트를 실행할 수 없습니다" 오류가 납니다.

---

## 🖐 방법 2 — 스크립트 없이 수동 배포

```powershell
cd functions
npm install
npm run build
cd ..

# 시크릿 등록 (아무 긴 문자열 입력, 안 보이는 게 정상)
firebase functions:secrets:set OFFERWALL_SECRET

# 함수 배포 (API 활성화 프롬프트 뜨면 [사용 설정] 클릭)
firebase deploy --only functions --project flutter-offerwall-app

# (선택) 함수 정상 확인 후 안티프라우드 규칙 적용
Copy-Item firestore.rules firestore.rules.clientonly.bak
Copy-Item firestore.rules.antifraud firestore.rules
firebase deploy --only firestore:rules --project flutter-offerwall-app
```

---

## 🚨 자주 나는 오류 & 해결

### A. `API has not been used in project ... or it is disabled`
**정상입니다.** 첫 배포에서 뜹니다.
```
https://console.firebase.google.com/project/flutter-offerwall-app/functions
→ "함수 만들기" / "시작하기" 클릭 → "API 사용 설정" 클릭
```
5개 API가 **한 번에** 켜집니다. 그 후 스크립트 재실행.

### B. `Your project must be on the Blaze (pay-as-you-go) plan`
```
https://console.firebase.google.com/project/flutter-offerwall-app/usage/details
```
업그레이드. Functions 월 200만 호출 **무료** → 개인 개발은 **청구 $0**.

### C. `이 시스템에서 스크립트를 실행할 수 없으므로 ...`
PS 5.1 실행 정책 때문입니다. **반드시 이렇게** 실행:
```powershell
powershell -ExecutionPolicy Bypass -File .\deploy_all.ps1
```

### D. `firebase : 'firebase' 용어가 cmdlet, 함수, 스크립트 파일 또는 실행할 수 있는 프로그램 이름으로 인식되지 않습니다.`
npm 전역 경로가 PATH에 없는 경우입니다:
```powershell
npm install -g firebase-tools
# 그래도 안 되면 PATH 확인:
npm config get prefix
# 출력된 경로를 PATH에 추가하거나, PowerShell을 재시작
```

### E. 한글이 깨져 보일 때
`chcp 65001` 을 먼저 실행하면 UTF-8로 표시됩니다. (`deploy_all.ps1` 자체는 영문이라 영향 없음)

---

## 🔧 (선택) WSL 자체를 고치고 싶다면

> **꼭 필요하지 않습니다.** PowerShell 배포로 충분합니다.
> 다만 `bash` 를 다시 쓰고 싶다면:

### 1단계 — WSL 상태 확인
```powershell
wsl --status
wsl --list --verbose
```

### 2단계 — 종료 후 재시도 (가벼운 복구)
```powershell
wsl --shutdown
wsl -d Ubuntu-22.04
```
→ 그래도 `ERROR_FILE_NOT_FOUND` 면 디스크가 실제로 유실된 것.

### 3단계 — 재설치 (⚠️ WSL 내부 데이터 삭제됨)
```powershell
# 먼저 등록 해제
wsl --unregister Ubuntu-22.04

# Microsoft Store 에서 "Ubuntu 22.04 LTS" 설치
# 또는:
wsl --install -d Ubuntu-22.04
```
> ⚠️ `wsl --unregister` 는 WSL 안의 파일을 **전부 삭제**합니다.
> Windows 쪽(`C:\Users\13182\...`) 파일은 안전합니다.

### 4단계 — WSL에서 배포하고 싶다면
WSL이 복구되면 Linux 환경이므로 `deploy_all.sh` 를 쓸 수 있습니다. 단 WSL 안에도 Node.js 설치가 필요합니다:
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
sudo npm install -g firebase-tools
```

---

## 📋 배포 성공 확인

배포가 끝나면 함수 3개가 살아납니다:

```
https://us-central1-flutter-offerwall-app.cloudfunctions.net/offerwallPostback
https://us-central1-flutter-offerwall-app.cloudfunctions.net/claimOffer
https://us-central1-flutter-offerwall-app.cloudfunctions.net/requestPayout
```

브라우저에서 열어보세요:
- `offerwallPostback` → **401** (서명 없음 거부) ← 정상!
- `claimOffer` / `requestPayout` → **400/403** ← 정상!

**"401/403이 뜨는 게 성공의 증거"** 입니다. 안티프라우드가 작동한다는 뜻이니까요.

---

## 📞 배포 후

`deploy_all.ps1` 실행이 끝나면 **"배포 완료"** 라고 알려주세요.
제가 원격에서 **엔드투엔드 검증**(위조 요청 차단 테스트)을 돌려드립니다.
