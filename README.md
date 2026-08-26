# 다음교시

학교·학년·반만 고르면 시간표와 급식이 자동으로 채워지고, 수업 중엔 다이나믹 아일랜드가 남은 시간을 세어주는 iOS 앱. 스펙은 [SPEC.md](SPEC.md).

**이 저장소는 맥 없이 개발한다.** 맥이 필요한 건 컴파일이지 코딩이 아니다 — 코드는 Windows에서 쓰고, 컴파일은 GitHub Actions의 macOS 머신이, 폰 설치는 TestFlight가 한다.

## 구조

```
App/        앱 타겟 소스 (진입점, 온보딩, 오늘 화면, Live Activity 매니저)
Shared/     앱+위젯 공용 (모델, 나이스 클라이언트, 교시 엔진, Activity 속성)
Widget/     위젯 익스텐션 (다이나믹 아일랜드 UI)
project.yml XcodeGen 스펙 — .xcodeproj는 CI가 생성 (커밋 안 함)
neis.py     나이스 API 검증 스크립트 (Swift 클라이언트의 원본, 실측 근거)
.github/workflows/
  build.yml       push마다 컴파일 검증 (서명·계정 불필요)
  testflight.yml  TestFlight 업로드 (수동 실행, 밀스톤 2)
```

## 밀스톤 1 — 컴파일 성공 (지금, 비용 0원)

GitHub에 **public 저장소**를 만들고 push한다 (public이면 macOS CI가 무료·무제한, private은 월 200분):

```bash
git remote add origin https://github.com/<계정>/daum-gyosi.git
git push -u origin main
```

push하면 Actions 탭에서 `build`가 돈다. **초록불 = 컴파일 성공.** 빨간불이면 로그의 에러를 Claude에게 붙여넣으면 된다 — 이게 우리의 컴파일 루프다 (회당 5~10분).

## 밀스톤 2 — 내 아이폰에 설치 (비용: 애플 개발자 연 $99)

여기서부터 유일하게 피할 수 없는 지출이 나온다. 순서:

1. [developer.apple.com](https://developer.apple.com) 개발자 프로그램 등록 ($99/년) → 멤버십에서 **팀 ID** 확인 → `project.yml`의 `DEVELOPMENT_TEAM`에 기입
2. **App ID 2개** 등록 (Identifiers): `com.daumgyosi.app`, `com.daumgyosi.app.widgets`
   (번들 ID는 전 세계 유일이어야 하므로 본인 것으로 바꿔도 됨 — 바꾸면 project.yml과 testflight.yml의 ID도 같이)
3. **배포 인증서** — 맥 없이 Windows에서 (Git Bash):
   ```bash
   openssl genrsa -out dist.key 2048
   openssl req -new -key dist.key -out dist.csr -subj "/CN=Distribution/C=KR"
   # dist.csr을 developer.apple.com → Certificates → Apple Distribution에 업로드
   # 내려받은 distribution.cer을:
   openssl x509 -inform DER -in distribution.cer -out dist.pem
   openssl pkcs12 -export -inkey dist.key -in dist.pem -out dist.p12
   base64 -w0 dist.p12   # 이 출력이 BUILD_CERTIFICATE_BASE64
   ```
4. **프로비저닝 프로파일 2개** (App Store 타입): "DaumGyosi AppStore"(앱), "DaumGyosi Widget AppStore"(위젯) — 각각 base64로 (`base64 -w0 파일.mobileprovision`)
5. [App Store Connect](https://appstoreconnect.apple.com) → 앱 등록 + 사용자 및 액세스 → 통합 → **API 키** 생성 (App Manager 권한)
6. GitHub 저장소 Settings → Secrets에 등록:
   | Secret | 내용 |
   |---|---|
   | `BUILD_CERTIFICATE_BASE64` | 3번의 p12 base64 |
   | `P12_PASSWORD` | p12 내보낼 때 정한 비밀번호 |
   | `PROFILE_APP_BASE64` / `PROFILE_WIDGET_BASE64` | 4번의 프로파일 base64 |
   | `ASC_ISSUER_ID` / `ASC_KEY_ID` / `ASC_KEY_P8` | 5번 API 키의 Issuer ID, Key ID, .p8 파일 내용 |
   | `NEIS_KEY` | 나이스 인증키 (저장소에 커밋하지 않는다) |
7. Actions → `testflight` → Run workflow → 성공하면 아이폰 TestFlight 앱에서 설치

## 알고 있는 한계 (정직 코너)

- **컴파일 루프가 느리다** (push→결과 5~10분). 로직은 이 루프로 충분한데, Live Activity **디자인을 픽셀 단위로 다듬는 단계**가 오면 그때 맥을 몇 시간 빌리는 게(지인 찬스, 또는 시간제 클라우드 맥) 총비용이 싸다.
- **교시 전환 갱신은 앱을 열 때 일어난다.** 카운트다운은 시스템이 자동 갱신하지만, "3교시 수학" 라벨은 앱이 포그라운드로 올 때 갱신된다 (학생은 쉬는시간마다 폰을 여니 실사용 타격은 작음). 서버 푸시로 올리는 건 v2.
- 나이스 데이터 자체의 한계(당일 미업로드, INFO-200의 중의성)는 [SPEC.md](SPEC.md)의 실측 섹션 참고.

## 데이터 검증

```bash
NEIS_KEY=<키> python neis.py --check
```
