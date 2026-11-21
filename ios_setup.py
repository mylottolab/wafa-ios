# 와파 WAFA iOS (2026-11-19 · 바로너 껍데기에서) — Codemagic 이 "npx cap add ios" 로 만든 아이폰 폴더에 우리 설정을 끼워 넣습니다.
# (GitHub 에 폴더를 올리기 어려워서, 폴더는 빌드 때 만들고 파일만 저장소에 둡니다)
import plistlib, shutil, os, re, sys, json
A = 'ios/App/App/'
CFG = json.load(open('capacitor.config.json', encoding='utf-8'))
APP_ID = CFG['appId']            # com.weaveapp.alias · com.weaveapp.aliascall
APP_NAME = CFG.get('appName', '')
# ── Firebase(알림) ─────────────────────────────────────────────
if not os.path.exists('GoogleService-Info.plist'):
    sys.exit('🔴 GoogleService-Info.plist 가 저장소에 없습니다. Firebase(alias-nextgen) 에서 이 앱(와파 com.weaveapp.wafa) iOS 설정 파일을 받아 올려 주세요.')
g = plistlib.load(open('GoogleService-Info.plist', 'rb'))
if g.get('BUNDLE_ID') != APP_ID:
    sys.exit('🔴 GoogleService-Info.plist 가 이 앱(' + APP_ID + ') 것이 아닙니다: ' + str(g.get('BUNDLE_ID')))
ad = open('AppDelegate.swift').read()
for k, v in {'__GOOGLE_APP_ID__': 'GOOGLE_APP_ID', '__GCM_SENDER_ID__': 'GCM_SENDER_ID', '__API_KEY__': 'API_KEY',
             '__PROJECT_ID__': 'PROJECT_ID', '__BUNDLE_ID__': 'BUNDLE_ID', '__STORAGE_BUCKET__': 'STORAGE_BUCKET'}.items():
    ad = ad.replace(k, str(g.get(v, '')).replace('"', ''))
open(A + 'AppDelegate.swift', 'w').write(ad)

# Firebase 부품을 앱에 넣습니다 (Capacitor 가 만든 부품 목록에 한 줄 더)
pk = 'ios/App/CapApp-SPM/Package.swift'
ps = open(pk).read()
if 'firebase-ios-sdk' not in ps:
    ps = ps.replace('    dependencies: [\n',
        '    dependencies: [\n        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "12.0.0"),\n', 1)
    ps = ps.replace('            dependencies: [\n',
        '            dependencies: [\n                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),\n', 1)
    assert 'FirebaseMessaging' in ps, 'Package.swift 모양이 예상과 다릅니다'
    open(pk, 'w').write(ps)
shutil.copy('App.entitlements', A + 'App.entitlements')
shutil.copy('AppIcon.png', A + 'Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png')
for n in ['splash-2732x2732.png', 'splash-2732x2732-1.png', 'splash-2732x2732-2.png']:
    shutil.copy('Splash.png', A + 'Assets.xcassets/Splash.imageset/' + n)

p = A + 'Info.plist'
d = plistlib.load(open(p, 'rb'))
d['CFBundleDevelopmentRegion'] = 'ko'
d['CFBundleDisplayName'] = APP_NAME or '부름'
d['UIRequiredDeviceCapabilities'] = ['arm64']
d['UISupportedInterfaceOrientations'] = ['UIInterfaceOrientationPortrait']
d.pop('UISupportedInterfaceOrientations~ipad', None)
d['UIBackgroundModes'] = ['audio', 'remote-notification', 'voip']   # 🔴 2026-10-10 voip — 전화 알림(PushKit)
d['NSCameraUsageDescription'] = '영상통화와 사진 · 동영상 보내기에 카메라를 씁니다. (Camera is used for video calls and sending photos.)'
d['NSMicrophoneUsageDescription'] = '음성 · 영상통화와 음성 메시지에 마이크를 씁니다. (Microphone is used for calls and voice messages.)'
d['NSPhotoLibraryUsageDescription'] = '대화방에 사진을 보내려면 사진 보관함을 엽니다.'
d['NSLocationWhenInUseUsageDescription'] = '안심 긴급 버튼을 눌렀을 때에만, 연결한 보호자에게 지금 위치를 알리려고 위치를 씁니다.'   # 🔴 2026-11-14 안심 긴급
d['NSPhotoLibraryAddUsageDescription'] = '받은 사진과 녹음 파일을 휴대폰에 저장합니다.'
# 와파 주소(wafa://) — 안드로이드와 같은 이름
d['CFBundleURLTypes'] = [{'CFBundleURLName': 'kr.wafa.app', 'CFBundleURLSchemes': ['wafa']}]
d['CFBundleLocalizations'] = ['ko', 'en']   # 와파는 영어가 꼭 필요합니다
# 🔴 2026-11-07 — 표준 암호화(HTTPS)만 씁니다 → TestFlight 의 '수출 규정 준수 정보 누락' 질문이 안 나오게
d['ITSAppUsesNonExemptEncryption'] = False
plistlib.dump(d, open(p, 'wb'))

# 🔴 2026-11-07 (1.1) — 부름과 같은 받는 자리: 홈 아이콘 길게 누르기 "걸기" · 위젯 주소(baronu://)
sd = A + 'SceneDelegate.swift'
t = open(sd).read()
hook = 'SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)\n'
if 'AliasShortcuts' not in t:
    assert t.count(hook) == 1, 'SceneDelegate.swift 모양이 예상과 다릅니다'
    t = t.replace(hook, hook +
        '        if let item = connectionOptions.shortcutItem {\n'
        '            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { AliasShortcuts.handle(item) }\n'
        '        }\n')
    i = t.rstrip().rfind('}')
    t = t[:i] + ('\n    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,\n'
                 '                     completionHandler: @escaping (Bool) -> Void) {\n'
                 '        completionHandler(AliasShortcuts.handle(shortcutItem))\n'
                 '    }\n}\n')
if 'AliasNureum' not in t:
    assert t.count(hook) == 1, 'SceneDelegate.swift 모양이 예상과 다릅니다(위젯)'
    t = t.replace(hook, hook +
        '        if let u = connectionOptions.urlContexts.first?.url, u.scheme == AliasNureum.scheme {\n'
        '            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { AliasNureum.open(u) }\n'
        '        }\n')
    hook2 = 'SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)\n'
    assert t.count(hook2) == 1, 'SceneDelegate.swift 모양이 예상과 다릅니다(위젯 2)'
    t = t.replace(hook2, 'if AliasNureum.open(URLContexts.first?.url) { return }\n        ' + hook2)
open(sd, 'w').write(t)

p = 'ios/App/App.xcodeproj/project.pbxproj'
s = open(p).read()
key = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n'
if 'CODE_SIGN_ENTITLEMENTS' not in s:
    assert s.count(key) == 2, 'pbxproj 모양이 예상과 다릅니다'
    s = s.replace(key, key + '\t\t\t\tCODE_SIGN_ENTITLEMENTS = App/App.entitlements;\n')
s = s.replace('TARGETED_DEVICE_FAMILY = "1,2";', 'TARGETED_DEVICE_FAMILY = 1;')
# 🔴 2026-10-18 — 앱 버전(App Store 에 보이는 번호). 1.0 심사 통과 뒤 첫 업데이트 = 1.1
APP_VERSION = '1.1'   # 🔴 2026-11-21 와파 1.1 — 벨 · 진동 · 무음, 아래위 흰 띠, 음성 안내 등
s = re.sub(r'MARKETING_VERSION = [^;]+;', 'MARKETING_VERSION = ' + APP_VERSION + ';', s)
# 🔴 2026-11-21 소리 없는 벨소리(silence.caf) — 「진동만 · 소리 없음」 때 CallKit 이 씀. 앱 묶음(Resources)에 넣습니다.
#    capacitor.config.json 이 들어간 자리 네 곳을 본떠 한 줄씩 더합니다. 못 찾으면 건너뜀(그때는 기본 벨소리로 울림).
if os.path.exists('silence.caf') and 'silence.caf' not in s:
    shutil.copy('silence.caf', A + 'silence.caf')
    BF, FR = 'A1B2C3D4E5F6071829304A5B', 'A1B2C3D4E5F6071829304A5C'
    lines = s.split('\n'); out = []; hits = 0
    for ln in lines:
        out.append(ln)
        t = ln.strip()
        ind = ln[:len(ln) - len(ln.lstrip())]
        if '/* capacitor.config.json in Resources */ = {isa = PBXBuildFile;' in t:
            out.append(ind + BF + ' /* silence.caf in Resources */ = {isa = PBXBuildFile; fileRef = ' + FR + ' /* silence.caf */; };'); hits += 1
        elif '/* capacitor.config.json */ = {isa = PBXFileReference;' in t:
            out.append(ind + FR + ' /* silence.caf */ = {isa = PBXFileReference; lastKnownFileType = file; path = silence.caf; sourceTree = "<group>"; };'); hits += 1
        elif re.match(r'^[0-9A-F]{24} /\* capacitor\.config\.json \*/,$', t):
            out.append(ind + FR + ' /* silence.caf */,'); hits += 1
        elif re.match(r'^[0-9A-F]{24} /\* capacitor\.config\.json in Resources \*/,$', t):
            out.append(ind + BF + ' /* silence.caf in Resources */,'); hits += 1
    if hits == 4:
        s = '\n'.join(out); print('silence.caf 를 앱에 넣었습니다')
    else:
        print('⚠ silence.caf 를 넣을 자리를 다 못 찾았습니다(' + str(hits) + '/4) — 기본 벨소리로 울립니다')
open(p, 'w').write(s)
print(APP_NAME + ' iOS 설정을 넣었습니다 (' + APP_ID + ')')

# 🔴 2026-11-07 (1.1) — 화면 틀을 BurumBridgeViewController 로(영상 자동 재생 허용 — 부름과 같게). 못 찾으면 그냥 넘어갑니다.
for sb in ['ios/App/App/Base.lproj/Main.storyboard']:
    if os.path.exists(sb):
        t = open(sb).read()
        if 'BurumBridgeViewController' not in t:
            t2 = re.sub(r'customClass="CAPBridgeViewController" customModule="Capacitor"( customModuleProvider="[^"]*")?',
                        'customClass="BurumBridgeViewController" customModule="App" customModuleProvider="target"', t)
            if t2 != t:
                open(sb, 'w').write(t2); print('화면 틀을 BurumBridgeViewController 로 바꿨습니다')
            else:
                print('⚠ Main.storyboard 에서 CAPBridgeViewController 를 못 찾았습니다')

