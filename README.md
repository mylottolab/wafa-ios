# 와파 WAFA iOS 앱 껍데기 (2026-11-19)

- 화면은 https://wafa.kr 에서 그대로 불러옵니다(첫 화면 wafa_start.html). 화면 수정은 wafa 저장소만 고치면 아이폰에도 반영됩니다.
- 폴더 없이 파일만 둡니다. Codemagic 이 빌드 때 `npx cap add ios` 로 아이폰 폴더를 만들고 ios_setup.py 가 설정을 끼워 넣습니다.
- AppDelegate.swift 는 바로너(부름) 껍데기와 같은 파일에서 왔습니다: CallKit 전화 · VoIP 알림 · 애플 결제(StoreKit 2) · 스피커 단추. 위젯은 뺐습니다.
- 앱 아이디 `com.weaveapp.wafa` · 홈 화면 이름 `WAFA` · 주소 `wafa://` · Capacitor 8.

## 결제
- 화면이 `AliasNative.storeSubscribe('wafa_plan', 'wafa-1m', 사람번호)` 를 부르면 애플 상품 `wafa_1m` 을 엽니다(- → _). 사람 번호는 appAccountToken.
- 1회 상품은 `AliasNative.storeBuy('wafa_addon')` 처럼 그대로. 애플 상품 번호가 같지 않으면 끝에 `_nr` 을 붙여도 됩니다.
- 영수증은 wafa-verify 가 애플에 직접 확인합니다. `AliasNative.storeManage()` = 애플 구독 관리 창.

## 저장소에 넣어야 할 것
- `GoogleService-Info.plist` — Firebase(alias-nextgen) → iOS 앱 com.weaveapp.wafa (채팅에 붙이지 말고 GitHub 에 직접 올림)

## App Store Connect 에 만들 상품
- 구독 그룹 「와파 요금제」: `wafa_1m` 1,500 · `wafa_3m` 3,300 · `wafa_6m` 5,500 · `wafa_12m` 9,900 (자동 갱신)
- 소모품: `wafa_addon` 1,100 · `wafa_number_5` 110,000 · `wafa_number_4` 55,000 · `wafa_number_3` 11,000 · `wafa_number_extra` 3,300

## 서버 (부름 프로젝트)
- 전화 알림(alias-push-call)이 `com.weaveapp.wafa` 앱 번호로도 보내도록 한 줄 추가가 필요합니다.
