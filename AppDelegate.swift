import UIKit
import WebKit
import PushKit
import CallKit
import AVFoundation
import StoreKit
import WidgetKit
import Capacitor
import FirebaseCore
import FirebaseMessaging

/* =====================================================================
   부름 iOS — 앱의 뿌리

   ① 알림(일반)  : 애플 기기 번호 → Firebase 번호로 바꿔 화면에 넘깁니다(안드로이드와 같은 서버 길).
   ② 전화(VoIP)  : 2026-10-10 신설. 앱이 꺼져 있거나 잠겨 있어도 아이폰 기본 전화 화면(CallKit)으로 울립니다.
                   서버(alias-push-call)가 애플로 직접 "전화 알림"을 보냅니다.

   ⚠ 애플 규칙: 전화 알림(VoIP)을 받으면 **반드시 곧바로** CallKit 에 전화를 알려야 합니다.
     안 하면 iOS 가 앱을 강제로 끄고, 여러 번 어기면 전화 알림 자체를 끊어 버립니다.
     그래서 "이미 끝난 전화 · 상대가 끊음" 알림이 와도 일단 알리고 바로 끝냅니다.

   화면(웹)과 주고받는 창구
     웹 → 앱 : window.webkit.messageHandlers.aliasIOS.postMessage({ act: 'stopRing' | 'endCall', id: '…' })
               stopRing — 웹이 받았거나 벨을 끕니다: **아직 안 받은** 전화 화면만 닫습니다
               endCall  — 통화가 끝났습니다: 받은 전화까지 모두 닫습니다
     앱 → 웹 : window.ALIAS_VOIP_TOKEN (전화용 기기 번호) · 'alias-voip-token' 이벤트
               받기를 누르면 alias_call.html?…&answered=1 로 보냅니다(안드로이드와 같은 주소).
   ===================================================================== */

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 와파는 위젯 · 제어 센터 단추가 없어 NureumShared.swift 를 넣지 않습니다(바로너의 nureumOpenHandler 줄을 뺌)
        // 🔴 1.8b — 앱이 화면에 올라올 때 제어 센터 단추가 남긴 쪽지 확인
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            for d in [0.3, 1.0, 2.5] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { AliasNureum.claimPending() } }
        }
        // 🔴 Firebase 켜기 — 값은 빌드 때 GoogleService-Info.plist 에서 채워 넣습니다(ios_setup.py)
        let o = FirebaseOptions(googleAppID: "__GOOGLE_APP_ID__", gcmSenderID: "__GCM_SENDER_ID__")
        o.apiKey = "__API_KEY__"
        o.projectID = "__PROJECT_ID__"
        o.bundleID = "__BUNDLE_ID__"
        o.storageBucket = "__STORAGE_BUCKET__"
        FirebaseApp.configure(options: o)

        // 🔴 전화 알림(VoIP) 받기 시작 — 앱이 꺼져 있다가 전화 알림으로 깨어나도 여기부터 지납니다
        AliasCalls.shared.start()
        // 🔴 2026-10-11 애플 결제 — 앱이 꺼진 사이 끝난 결제도 여기서 받습니다
        AliasStore.shared.start()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // 화면이 준비됐을 수 있으니 창구를 다시 확인하고 전화용 번호를 알려 둡니다
        AliasCalls.shared.attachWeb()
        // 잠금 화면에서 받고 이제 앱을 열었다면, 못 연 통화 화면을 마저 엽니다
        AliasCalls.shared.resumePending()
    }

    // 🔴 애플이 준 기기 번호(APNs)를 Firebase 기기 번호(FCM)로 바꿔서 화면에 넘깁니다.
    //    서버는 안드로이드와 똑같이 Firebase 로 보내므로 서버를 고치지 않아도 됩니다.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, error in
            if let error = error {
                NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
            } else if let token = token {
                NotificationCenter.default.post(name: .capacitorDidRegisterForRemoteNotifications, object: token)
            }
        }
    }

    /* 🔴 2026-10-10 저녁 — 상대가 끊었다는 일반 알림(부재중)이 오면, 울리던 아이폰 전화 화면을 닫습니다.
       (전에는 이걸 VoIP 로 받아서, 이미 닫힌 뒤에 오면 잠깐 다시 울렸습니다) */
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if (userInfo["kind"] as? String) == "missed", let callId = userInfo["call_id"] as? String {
            AliasCalls.shared.remoteEnded(callId)
        }
        completionHandler(.noData)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .capacitorDidFailToRegisterForRemoteNotifications, object: error)
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default Configuration",
                                          sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self   // 아이콘 "걸기" 받는 곳은 ios_setup.py 가 SceneDelegate 안에 직접 넣습니다
        return config
    }
}

/* =====================================================================
   AliasCalls — 전화 알림(PushKit) + 아이폰 기본 전화 화면(CallKit)
   ===================================================================== */
final class AliasCalls: NSObject, PKPushRegistryDelegate, CXProviderDelegate, WKScriptMessageHandler {

    static let shared = AliasCalls()

    /* 🔴 2026-10-11 — 같은 파일을 부름 · 에일리어스콜 두 앱이 함께 씁니다. 앱 번호로 가릅니다. */
    static let isAliascall = (Bundle.main.bundleIdentifier ?? "").hasSuffix(".aliascall")
    /* 🔴 2026-11-19 와파 WAFA — 바로너(부름) 앱 껍데기를 그대로 쓰되, 전화 화면 이름 · 주소는 와파 것으로 (위젯 없음) */
    static let appName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "WAFA"
    static let site = "https://wafa.kr/"

    private var registry: PKPushRegistry?
    private let provider: CXProvider
    private let controller = CXCallController()

    /* 지금 울리거나 통화 중인 전화: 통화 번호(callId) ↔ CallKit 번호(UUID) */
    private var uuidOf: [String: UUID] = [:]
    private var infoOf: [UUID: [String: String]] = [:]
    private var answered: Set<UUID> = []
    private var endingByApp: Set<UUID> = []     // 앱이 스스로 끈 것(거절로 치지 않음)
    private var ringTimers: [UUID: Timer] = [:]
    private var attachedWeb: WKWebView?
    private var urlWatch: NSKeyValueObservation?
    private var xWatch: NSKeyValueObservation?
    private var pageIsCall = false
    private var liveCall = false
    private func applyBackGesture() {
        attachedWeb?.allowsBackForwardNavigationGestures = !(pageIsCall || liveCall)
    }
    private var pendingPath: String?          // 받았는데 아직 통화 화면을 못 연 것

    /* 화면 쪽 alias_call.html 의 벨 시간과 맞춥니다 */
    private let ringSeconds: TimeInterval = 45

    private override init() {
        let cfg = CXProviderConfiguration()
        cfg.supportsVideo = false   // 아이폰 통화 화면의 "영상" 단추를 숨깁니다(영상은 부름 화면이 맡음)
        cfg.maximumCallGroups = 1
        cfg.maximumCallsPerCallGroup = 1
        cfg.supportedHandleTypes = [.generic]
        // 🔒 번호 없는 앱입니다. 아이폰 "최근 통화" 목록에 남기지 않습니다.
        cfg.includesCallsInRecents = false
        provider = CXProvider(configuration: cfg)
        super.init()
        provider.setDelegate(self, queue: DispatchQueue.main)
    }

    func start() {
        if registry != nil { return }
        let r = PKPushRegistry(queue: .main)
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r
    }

    // MARK: - 전화용 기기 번호

    private var voipToken: String {
        get { UserDefaults.standard.string(forKey: "alias_voip_token") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "alias_voip_token") }
    }

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        voipToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        NSLog("[AliasCalls] 전화용 기기 번호를 받았습니다 (%@…)", String(voipToken.prefix(10)))
        attachWeb()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        voipToken = ""
    }

    // MARK: - 전화 알림이 왔을 때

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        let d = payload.dictionaryPayload
        func s(_ k: String) -> String { (d[k] as? String) ?? "" }

        let kind = s("kind").isEmpty ? "call" : s("kind")
        let callId = s("call_id")
        NSLog("[AliasCalls] 전화 알림: %@ %@", kind, callId)

        /* ── 상대가 끊었습니다 ── */
        if kind == "missed" {
            if let u = uuidOf[callId] {
                // 규칙상 "알리기"를 먼저 합니다(같은 번호라 새로 울리지 않습니다) → 그리고 끝냅니다
                provider.reportNewIncomingCall(with: u, update: CXCallUpdate()) { _ in
                    DispatchQueue.main.async {
                        self.finish(u, reason: .remoteEnded)
                        completion()
                    }
                }
            } else {
                reportAndEnd(callId: callId, completion: completion)
            }
            markDone(callId)
            return
        }

        /* ── 이미 끝난 전화(늦게 온 알림) ── */
        if callId.isEmpty || isDone(callId) || uuidOf[callId] != nil {
            if let u = uuidOf[callId] {
                provider.reportNewIncomingCall(with: u, update: CXCallUpdate()) { _ in completion() }
            } else {
                reportAndEnd(callId: callId, completion: completion)
            }
            return
        }

        /* ── 새 전화: 아이폰 기본 전화 화면으로 울립니다 ── */
        let who = s("who").isEmpty ? AliasCalls.appName : s("who")
        let u = UUID()
        let upd = CXCallUpdate()
        upd.remoteHandle = CXHandle(type: .generic, value: who)
        upd.localizedCallerName = who
        upd.hasVideo = false
        upd.supportsHolding = false
        upd.supportsGrouping = false
        upd.supportsUngrouping = false
        upd.supportsDTMF = false

        uuidOf[callId] = u
        infoOf[u] = ["call": callId, "who": who, "token": s("session_token"), "link": s("link_id"),
                     "type": s("call_type").isEmpty ? "voice" : s("call_type")]

        provider.reportNewIncomingCall(with: u, update: upd) { err in
          DispatchQueue.main.async {
            if let err = err {
                NSLog("[AliasCalls] 🔴 전화 화면을 못 띄웠습니다: %@", err.localizedDescription)
                self.forget(u)
            } else {
                // 안 받으면 45초 뒤 저절로 멎습니다
                let t = Timer.scheduledTimer(withTimeInterval: self.ringSeconds, repeats: false) { _ in
                    if !self.answered.contains(u) { self.finish(u, reason: .unanswered) }
                }
                self.ringTimers[u] = t
            }
            completion()
          }
        }
    }

    /* 규칙을 지키려고 잠깐 알리고 곧바로 끝냅니다 */
    private func reportAndEnd(callId: String, completion: @escaping () -> Void) {
        let u = UUID()
        let upd = CXCallUpdate()
        upd.remoteHandle = CXHandle(type: .generic, value: AliasCalls.appName)
        upd.localizedCallerName = AliasCalls.appName
        provider.reportNewIncomingCall(with: u, update: upd) { _ in
            self.provider.reportCall(with: u, endedAt: nil, reason: .remoteEnded)
            completion()
        }
    }

    // MARK: - CallKit 단추

    func providerDidReset(_ provider: CXProvider) {
        for (_, u) in uuidOf { forget(u) }
        uuidOf.removeAll()
    }

    /* [받기] */
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let u = action.callUUID
        answered.insert(u)
        ringTimers[u]?.invalidate(); ringTimers[u] = nil
        action.fulfill()

        guard let i = infoOf[u], let callId = i["call"] else { return }
        markDone(callId)

        /* 🔴 2026-10-10 저녁 — 잠긴 채 받으면 부름(웹 화면)이 마이크를 못 씁니다.
           아이폰 통화 화면의 이름 자리에 "부름 아이콘을 눌러 연결" 을 띄워 알려 드립니다. */
        if UIApplication.shared.applicationState != .active {
            let hint = CXCallUpdate()
            hint.localizedCallerName = (i["who"] ?? AliasCalls.appName) + " · ··· 누르면 연결"
            provider.reportCall(with: u, updated: hint)
        }
        let path = AliasCalls.isAliascall
            ? "aliascall_incoming_calls.html?autoaccept=" + enc(callId) + "&answered=1"
            : "alias_call.html?call=" + enc(callId) +
              "&token=" + enc(i["token"] ?? "") +
              "&link=" + enc(i["link"] ?? "") +
              "&type=" + enc(i["type"] ?? "voice") +
              "&once=" + enc(callId) + "&answered=1"
        pendingPath = path
        openPage(path, tries: 60)
    }

    /* [거절] 또는 [끊기] */
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let u = action.callUUID
        action.fulfill()
        let byApp = endingByApp.contains(u)
        let wasAnswered = answered.contains(u)
        if let callId = infoOf[u]?["call"] { markDone(callId) }
        forget(u)

        if byApp { return }
        if wasAnswered {
            // 통화 중 아이폰 전화 화면에서 [끊기] — 화면(웹)에게 끊으라고 알립니다
            runJS("try{ if (window.ALIAS_HANGUP_NOW) ALIAS_HANGUP_NOW(); }catch(e){}")
        }
        // 받기 전 [거절] 은 안드로이드와 같이 조용히 닫습니다(거는 쪽은 45초 뒤 부재중)
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
        runJS("try{ if (window.ALIAS_SET_MUTE) ALIAS_SET_MUTE(" + (action.isMuted ? "true" : "false") + "); }catch(e){}")
    }

    // MARK: - 정리

    /* 앱이 스스로 끝냅니다(웹이 받았거나 · 통화가 끝났거나 · 상대가 끊음) */
    private func finish(_ u: UUID, reason: CXCallEndedReason) {
        if answered.contains(u) || reason == .remoteEnded || reason == .unanswered {
            provider.reportCall(with: u, endedAt: nil, reason: reason)
            if let callId = infoOf[u]?["call"] { markDone(callId) }
            forget(u)
        }
    }

    /* 상대가 받기 전에 끊었습니다 — 아직 울리는 중이면 닫습니다(이미 닫혔으면 아무 일도 안 함) */
    func remoteEnded(_ callId: String) {
        DispatchQueue.main.async {
            self.markDone(callId)
            if let u = self.uuidOf[callId], !self.answered.contains(u) {
                self.finish(u, reason: .remoteEnded)
            }
        }
    }

    /* 웹이 "벨 꺼요 / 통화 끝났어요" 라고 할 때 — 거절로 치지 않고 조용히 닫습니다
       ⚠ 아이폰 전화 화면에서 [받기]를 누르면 웹도 곧바로 "벨 꺼요(stopRing)" 를 보냅니다.
         그때 받은 전화까지 닫으면 통화가 끊기므로, stopRing 은 안 받은 것만 닫습니다. */
    private func endFromWeb(_ callId: String, includeAnswered: Bool) {
        var targets: [UUID] = callId.isEmpty ? Array(uuidOf.values) : (uuidOf[callId].map { [$0] } ?? [])
        if !includeAnswered { targets = targets.filter { !answered.contains($0) } }
        for u in targets {
            endingByApp.insert(u)
            let tx = CXTransaction(action: CXEndCallAction(call: u))
            controller.request(tx) { err in
                if err != nil {
                    // 이미 끝난 전화면 요청이 거절됩니다 — 그냥 장부에서 지웁니다
                    DispatchQueue.main.async {
                        self.provider.reportCall(with: u, endedAt: nil, reason: .answeredElsewhere)
                        self.forget(u)
                    }
                }
            }
        }
        if !callId.isEmpty && includeAnswered { markDone(callId) }
    }

    private func forget(_ u: UUID) {
        ringTimers[u]?.invalidate(); ringTimers[u] = nil
        if let callId = infoOf[u]?["call"] {
            uuidOf[callId] = nil
            if let p = pendingPath, p.contains("call=" + enc(callId) + "&") { pendingPath = nil }   // 끝난 전화는 다시 열지 않습니다
        }
        infoOf[u] = nil
        answered.remove(u)
        endingByApp.remove(u)
    }

    /* 이미 끝난 전화 명단(스무 개) — 늦게 온 알림으로 다시 울리지 않게 */
    private func isDone(_ id: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: "alias_done_calls") ?? []).contains(id)
    }
    private func markDone(_ id: String) {
        if id.isEmpty { return }
        var a = UserDefaults.standard.stringArray(forKey: "alias_done_calls") ?? []
        if a.contains(id) { return }
        a.append(id)
        if a.count > 20 { a.removeFirst(a.count - 20) }
        UserDefaults.standard.set(a, forKey: "alias_done_calls")
    }

    // MARK: - 화면(웹)과 잇기

    func currentWebView() -> WKWebView? {
        for sc in UIApplication.shared.connectedScenes {
            guard let ws = sc as? UIWindowScene else { continue }
            for w in ws.windows {
                if let vc = w.rootViewController as? CAPBridgeViewController, let wv = vc.bridge?.webView {
                    return wv
                }
            }
        }
        return nil
    }

    /* 🔴 화면마다 심는 작은 도우미 — burum.kr 파일은 하나도 고치지 않습니다(안드로이드에 영향 없음)
         ① 전화용 번호를 devices 표에 저장(claim_device · 하루 한 번 · 계정이 바뀌면 다시)
         ② AL.clearCallNotices(벨 끄기)  → 앱에 stopRing
         ③ ongoingStop(통화 끝) · 통화 화면 떠남 → 앱에 endCall */
    private static let helperJS = #"""
    (function(){
      if (window.__aliasIOS) return; window.__aliasIOS = true;
      function post(m){ try { window.webkit.messageHandlers.aliasIOS.postMessage(m); } catch (e) {} }
      var busy = false;
      /* 에일리어스콜 — 로그인 정보는 브라우저 저장소에서 읽어 서버 함수로 보냅니다 */
      function saveVoipAliascall(){
        var tok = window.ALIAS_VOIP_TOKEN;
        if (busy || !tok) return;
        var ses = null;
        try { ses = JSON.parse(localStorage.getItem('sb-qmwaraittiurkynszjts-auth-token') || 'null'); } catch (e) {}
        if (!ses || !ses.access_token || !ses.user) return;
        var key = 'alias_voip_saved_' + ses.user.id, last = '';
        try { last = localStorage.getItem(key) || ''; } catch (e) {}
        if (last.indexOf(tok + '|') === 0 && Date.now() - Number(last.split('|')[1] || 0) < 86400000) return;
        busy = true;
        fetch('https://qmwaraittiurkynszjts.supabase.co/functions/v1/aliascall-push-subscribe', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + ses.access_token },
          body: JSON.stringify({ platform: 'android_fcm', token: tok, user_agent: navigator.userAgent,
                                 lang: (localStorage.getItem('aliascall_lang') === 'en' ? 'en' : 'ko') })
        }).then(function(r){
          if (r.ok) { try { localStorage.setItem(key, tok + '|' + Date.now()); } catch (e) {} console.log('[voip] 전화용 번호를 저장했습니다'); }
          else { busy = false; console.warn('[voip] 전화용 번호 저장 실패', r.status); }
        }).catch(function(){ busy = false; });
      }
      function saveVoip(){
        if (window.ALIAS_APP === 'aliascall') { saveVoipAliascall(); return; }
        var AL = window.AL, tok = window.ALIAS_VOIP_TOKEN;
        if (busy || !tok || !AL || !AL.sb) return;
        busy = true;
        AL.sb.auth.getSession().then(function(r){
          var ses = r && r.data && r.data.session;
          if (!ses) { busy = false; return; }
          var key = 'alias_voip_saved_' + ses.user.id, last = '';
          try { last = localStorage.getItem(key) || ''; } catch (e) {}
          if (last.indexOf(tok + '|') === 0 && Date.now() - Number(last.split('|')[1] || 0) < 86400000) { return; }
          AL.sb.rpc('claim_device', { p_token: tok, p_platform: 'ios' }).then(function(res){
            if (res.error) { console.warn('[voip] 전화용 번호 저장 실패', res.error.message); busy = false; return; }
            try { localStorage.setItem(key, tok + '|' + Date.now()); } catch (e) {}
            console.log('[voip] 전화용 번호를 저장했습니다');
          });
        }).catch(function(){ busy = false; });
      }
      function hook(){
        var AL = window.AL;
        if (AL && typeof AL.clearCallNotices === 'function' && !AL.clearCallNotices.__ios) {
          var o = AL.clearCallNotices;
          AL.clearCallNotices = function(id){
            post({ act: 'stopRing', id: String(id || (AL.call && AL.call.callId) || '') });
            return o.apply(this, arguments);
          };
          AL.clearCallNotices.__ios = true;
        }
        if (typeof window.ongoingStop === 'function' && !window.ongoingStop.__ios) {
          var g = window.ongoingStop;
          window.ongoingStop = function(){ post({ act: 'endCall', id: '' }); return g.apply(this, arguments); };
          window.ongoingStop.__ios = true;
        }
        saveVoip();
      }
      /* 🔴 2026-10-11 — 애플 심사: 아이폰 앱 화면에 다른 스토어(구글 플레이) 이름이 보이면 떨어집니다.
         웹 파일은 그대로 두고(안드로이드 영향 없음), 아이폰에서만 글자를 바꿔 보여 줍니다. */
      var SWAP = [
        [/Google Play\s*(로|으로)?\s*결제/g, 'App Store로 결제'],
        [/Google Play\s*로/g, 'App Store로'],
        [/Pay with Google Play/g, 'Pay with the App Store'],
        [/Google Play|구글 플레이|구글플레이/g, 'App Store'],
        [/Play\s*스토어|플레이\s*스토어|Play Store/g, 'App Store'],
        [/구글\s*결제/g, 'App Store 결제'],
        [/\bapp_store\b/g, 'App Store']
      ];
      function swapText(root){
        try {
          var w = document.createTreeWalker(root || document.body, NodeFilter.SHOW_TEXT, null);
          var nd;
          while ((nd = w.nextNode())) {
            var v = nd.nodeValue;
            if (!v || !/Google|Play|구글|플레이|app_store/.test(v)) continue;
            var nv = v;
            for (var i = 0; i < SWAP.length; i++) nv = nv.replace(SWAP[i][0], SWAP[i][1]);
            if (nv !== v) nd.nodeValue = nv;
          }
        } catch (e) {}
      }
      var swapTimer = null;
      function swapSoon(){ if (swapTimer) return; swapTimer = setTimeout(function(){ swapTimer = null; swapText(); }, 120); }
      try {
        if (document.body) {
          swapText();
          new MutationObserver(swapSoon).observe(document.body, { childList: true, subtree: true, characterData: true });
        }
      } catch (e) {}
      var n = 0, t = setInterval(function(){ hook(); if (++n > 40) clearInterval(t); }, 500);
      hook();
      window.addEventListener('alias-voip-token', function(){ busy = false; saveVoip(); });
      window.addEventListener('pagehide', function(){
        if (/alias_call\.html/.test(location.pathname)) post({ act: 'endCall', id: '' });
      });
    })();
    """#

    /* 🔴 안드로이드 창구 흉내 — 결제(storeBuy · storeConsume · storeFlush · storeRecover) ·
         전화 알림 끄기(cancelCall · cancelAllCalls) · 알림 설정 열기
       ⚠ 아이폰에서 못 하는 것(인쇄 등)은 만들지 않습니다. 스피커 바꾸기는 2026-10-18(1.3)부터 있습니다 — 화면이 typeof 로 확인하고 건너뜁니다. */
    static let shimJS = #"""
    /* 🔴 2026-10-12 — 통화(RTCPeerConnection)가 열리고 닫히는 것을 앱에 알립니다(통화 중에는 밀어서 뒤로 가기를 막기 위해) */
    (function(){
      var O = window.RTCPeerConnection;
      if (!O || O.__ios) return;
      var live = 0;
      function tell(){ try { window.webkit.messageHandlers.aliasIOS.postMessage({ act: 'inCall', on: live > 0 }); } catch (e) {} }
      function W(a, b){
        var pc = (b === undefined) ? new O(a) : new O(a, b);
        var counted = true; live++; tell();
        function drop(){ if (counted) { counted = false; live = Math.max(0, live - 1); tell(); } }
        function check(){ if (pc.connectionState === 'closed' || pc.connectionState === 'failed' || pc.signalingState === 'closed') drop(); }
        try { pc.addEventListener('connectionstatechange', check); pc.addEventListener('signalingstatechange', check); } catch (e) {}
        var c = pc.close;
        pc.close = function(){ var r = c.apply(pc, arguments); drop(); return r; };
        return pc;
      }
      W.prototype = O.prototype; W.__ios = true;
      try { W.generateCertificate = O.generateCertificate; } catch (e) {}
      window.RTCPeerConnection = W;
    })();
    (function(){
      if (window.AliasNative) return;
      function post(m){ try { window.webkit.messageHandlers.aliasIOS.postMessage(m); } catch (e) {} }
      function account(){
        try {
          for (var i = 0; i < localStorage.length; i++) {
            var k = localStorage.key(i);
            if (/^sb-.*-auth-token$/.test(k)) {
              var v = JSON.parse(localStorage.getItem(k) || 'null');
              var u = v && (v.user || (v.currentSession && v.currentSession.user));
              if (u && u.id) return String(u.id);
            }
          }
        } catch (e) {}
        return '';
      }
      window.AliasNative = {
        isIOS: function(){ return true; },
        storeBuy: function(sku){ post({ act: 'storeBuy', sku: String(sku || ''), account: account() }); },
        storeConsume: function(token){ post({ act: 'storeConsume', token: String(token || '') }); },
        storeFlush: function(){ post({ act: 'storeFlush' }); },
        storeRecover: function(){ post({ act: 'storeFlush' }); },
        cancelCall: function(id){ post({ act: 'stopRing', id: String(id || '') }); },
        cancelAllCalls: function(){ post({ act: 'stopRing', id: '' }); },
        callEnded: function(){ post({ act: 'endCall', id: '' }); },
        /* 🔴 2026-10-18 (1.3) — 스피커 ↔ 수화기. 통화가 붙으면 영상은 스피커, 음성은 수화기로 시작 */
        setSpeaker: function(on){ post({ act: 'setSpeaker', on: !!on }); },
        /* 🔴 2026-10-20 (1.5) — 음성 통화를 시작할 때는 소리 설정을 건드리지 않습니다(아이폰 마이크가 무음이 되던 원인).
           영상 통화만 스피커로 시작합니다. audioV2 = 화면이 "1.5 이상" 임을 알아보는 표시 */
        audioV2: true,
        callOngoing: function(name, video){ if (video) post({ act: 'setSpeaker', on: true }); },
        openNotificationSettings: function(){ post({ act: 'openSettings' }); },
        /* 🔴 2026-10-31 (1.7) — 누름 위젯: 라인 목록(이름 · 그림)을 위젯이 읽는 상자에 넣습니다 */
        /* 🔴 2026-11-19 와파 — 자동결제 구독. 안드로이드와 같은 부름말: storeSubscribe('wafa_plan', 'wafa-1m', 사람번호)
           애플 상품 번호는 기본 요금제 이름의 - 를 _ 로 (wafa-1m → wafa_1m). 사람 번호는 appAccountToken 으로 붙습니다 */
        storeSubscribe: function(productId, basePlanId, accountId){
          post({ act: 'storeBuy', sku: String(basePlanId || productId || '').replace(/-/g, '_'), account: String(accountId || account()) });
        },
        storeManage: function(){ post({ act: 'storeManage' }); }
      };
    })();
    """#

    /* 창구를 달고, 도우미와 전화용 번호를 화면에 심어 둡니다 */
    func attachWeb() {
        guard let wv = currentWebView() else { return }
        let ucc = wv.configuration.userContentController
        let first = (attachedWeb !== wv)
        if first {
            ucc.removeScriptMessageHandler(forName: "aliasIOS")
            ucc.add(self, name: "aliasIOS")
            // 🔴 2026-10-11 — 안드로이드와 같은 이름의 창구(AliasNative)를 아이폰에도 엽니다.
            //    화면(웹)은 고치지 않고, 안에서는 애플 결제 · 아이폰 전화 화면으로 처리합니다.
            ucc.addUserScript(WKUserScript(source: "window.ALIAS_APP='" + (AliasCalls.isAliascall ? "aliascall" : "burum") + "';" + AliasCalls.shimJS,
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
            // 다음에 열리는 화면마다 도우미가 들어갑니다
            ucc.addUserScript(WKUserScript(source: AliasCalls.helperJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            if !AliasCalls.isAliascall {
                ucc.addUserScript(WKUserScript(source: AliasShortcuts.publishJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }
            attachedWeb = wv
            // 🔴 2026-10-11 — 화면 왼쪽 끝에서 오른쪽으로 밀면 직전 화면으로 (아이폰식 뒤로 가기).
            //    통화 화면에서는 실수로 밀어 전화가 끊기지 않게 막습니다.
            wv.allowsBackForwardNavigationGestures = true
            // 🔴 2026-10-12 — 화면이 좌우로 흔들리지 않게: 옆으로 튕기기를 끄고, 옆으로 밀린 화면은 바로 제자리로
            wv.scrollView.alwaysBounceHorizontal = false
            wv.scrollView.showsHorizontalScrollIndicator = false
            xWatch = wv.scrollView.observe(\.contentOffset, options: [.new]) { sv, _ in
                let left = -sv.adjustedContentInset.left
                if abs(sv.contentOffset.x - left) > 0.5 { sv.contentOffset = CGPoint(x: left, y: sv.contentOffset.y) }
            }
            ucc.addUserScript(WKUserScript(source: "(function(){var s=document.createElement('style');s.textContent='html,body{overflow-x:clip!important;max-width:100vw}';(document.head||document.documentElement).appendChild(s);})();",
                                           injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            // 🔴 2026-10-12 — 통화 전용 화면 주소이거나, 화면 안에서 실제 통화(RTCPeerConnection)가 열려 있을 때만 막습니다
            urlWatch = wv.observe(\.url, options: [.initial, .new]) { [weak self] w, _ in
                let u = (w.url?.absoluteString ?? "").lowercased()
                let callPage = u.contains("alias_call.html") || u.contains("autoaccept=")
                DispatchQueue.main.async {
                    self?.pageIsCall = callPage
                    self?.liveCall = false          // 새 화면 — 통화 표시를 처음부터 다시 셉니다
                    self?.applyBackGesture()
                }
            }
        }
        let tok = voipToken
        if !tok.isEmpty && !ucc.userScripts.contains(where: { $0.source.hasPrefix("window.ALIAS_VOIP_TOKEN=") }) {
            ucc.addUserScript(WKUserScript(source: "window.ALIAS_VOIP_TOKEN='" + tok + "';",
                                           injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        // 지금 떠 있는 화면에도 바로 넣습니다
        var js = tok.isEmpty ? "" : "window.ALIAS_VOIP_TOKEN='" + tok + "';"
        if first { js += "window.ALIAS_APP='" + (AliasCalls.isAliascall ? "aliascall" : "burum") + "';" + AliasCalls.shimJS + AliasCalls.helperJS }
        if first && !AliasCalls.isAliascall { js += AliasShortcuts.publishJS }
        js += "try{ window.dispatchEvent(new Event('alias-voip-token')); }catch(e){}"
        runJS(js)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let act = m["act"] as? String else { return }
        let id = (m["id"] as? String) ?? ""
        switch act {
        case "storeBuy": AliasStore.shared.buy(sku: (m["sku"] as? String) ?? "", account: (m["account"] as? String) ?? "")
        case "storeConsume": AliasStore.shared.consume(token: (m["token"] as? String) ?? "")
        case "storeFlush": AliasStore.shared.flush()
        case "openSettings":
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        case "stopRing": endFromWeb(id, includeAnswered: false)
        case "endCall": endFromWeb(id, includeAnswered: true); AliasSpeaker.reset()
        case "hello": attachWeb()
        case "inCall": liveCall = (m["on"] as? Bool) ?? false; applyBackGesture(); if !liveCall { AliasSpeaker.reset() }
        case "setSpeaker": AliasSpeaker.set((m["on"] as? Bool) ?? false)
        case "shortcuts": AliasShortcuts.set(m["items"] as? [[String: Any]] ?? [])
        case "storeManage": AliasStore.shared.manage()   // 🔴 2026-11-19 와파 — 구독 관리(애플 화면)
        default: break
        }
    }

    private func runJS(_ js: String) {
        DispatchQueue.main.async {
            self.currentWebView()?.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func resumePending() {
        if let p = pendingPath { openPage(p, tries: 60) }
        // 부름이 열렸으니 이름 자리를 원래대로 돌립니다
        for u in answered {
            let back = CXCallUpdate()
            back.localizedCallerName = infoOf[u]?["who"] ?? AliasCalls.appName
            provider.reportCall(with: u, updated: back)
        }
    }

    /* 🔴 2026-10-31 — 누름 위젯을 눌러 들어왔을 때 그 라인 화면으로 */
    func openNureum(_ url: String) { openPage(url, tries: 60, exact: true) }   // 🔴 1.8d — 라인 번호까지 같아야 '이미 열림'

    /* 받기 → 통화 화면으로(안드로이드 MainActivity.openPageLater 와 같은 일) */
    private func openPage(_ path: String, tries: Int, exact: Bool = false) {
        if tries <= 0 { NSLog("[AliasCalls] 🔴 화면이 끝내 준비되지 않았습니다"); return }
        guard let wv = currentWebView() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openPage(path, tries: tries - 1, exact: exact) }
            return
        }
        let page = path.components(separatedBy: "?").first ?? path
        let safe = path.replacingOccurrences(of: "'", with: "\\'")
        // 에일리어스콜은 같은 화면(받은 전화 목록)에 있어도 그 전화(autoaccept=번호)가 아니면 다시 엽니다
        let marker = exact ? path : (AliasCalls.isAliascall ? (path.components(separatedBy: "&").first ?? path) : page)
        let js = "(function(){" +
            "if ((location.pathname + location.search).indexOf('" + marker + "') >= 0) {" +
            "  try { if (window.ALIAS_ANSWER_NOW) ALIAS_ANSWER_NOW(); } catch (e) {}" +
            "  return 'done'; }" +
            "if (document.readyState !== 'complete') return 'wait';" +
            "if (!window.AL || !AL.sb) return 'wait';" +
            "location.replace('" + safe + "');" +
            "return 'go';" +
            "})()"
        wv.evaluateJavaScript(js) { v, _ in
            if let r = v as? String, r == "go" || r == "done" {
                self.pendingPath = nil
            } else if let r = v as? String, r == "wait" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openPage(path, tries: tries - 1, exact: exact) }
            } else if v == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openPage(path, tries: tries - 1, exact: exact) }
            }
        }
    }

    /* 🔴 2026-10-16 — 홈 화면 아이콘을 길게 눌러 고른 사람에게 바로 음성 전화
       (연락처 ⋯ → "지금 걸기" 와 똑같이: 이용권 확인 → alias_call.html?link=…&type=voice&once=새 표) */
    func dial(_ linkId: String, tries: Int = 240) {
        if tries <= 0 { return }
        if pageIsCall || liveCall { return }                 // 통화 중에는 새로 걸지 않습니다
        guard let wv = currentWebView() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.dial(linkId, tries: tries - 1) }
            return
        }
        let link = linkId.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\\", with: "")
        let ticket = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 100000...999999), radix: 36)
        let js = "(function(){" +
            "try { if (document.body && !document.getElementById('brDialToast')) { var d = document.createElement('div'); d.id = 'brDialToast';" +
            "  d.textContent = '📞 전화 거는 중…';" +
            "  d.style.cssText = 'position:fixed;left:50%;top:18%;transform:translateX(-50%);z-index:2147483647;background:rgba(20,20,30,.92);color:#fff;padding:12px 20px;border-radius:999px;font:600 15px -apple-system,sans-serif;box-shadow:0 6px 20px rgba(0,0,0,.35)';" +
            "  document.body.appendChild(d); setTimeout(function(){ try { d.remove(); } catch (e) {} }, 6000); } } catch (e) {}" +
            "if (document.readyState !== 'complete' || !window.AL || !AL.sb) return 'wait';" +
            // 로그인 화면은 로그인 확인 뒤 스스로 연락처로 넘어가므로, 그게 끝난 뒤에 겁니다(안 그러면 덮어써짐)
            "if (/alias_auth\\.html/.test(location.pathname) || location.pathname === '/') return 'wait';" +
            "var on = false; try { for (var i = 0; i < localStorage.length; i++) { if (/^sb-.*-auth-token$/.test(localStorage.key(i) || '')) on = true; } } catch (e) {}" +
            "if (!on) return 'wait';" +
            "(async function(){" +
            "  try { if (AL.requirePlan && !(await AL.requirePlan())) return; } catch (e) {}" +
            "  location.href = '" + AliasCalls.site + "alias_call.html?link=' + encodeURIComponent('" + link + "') + '&type=voice&once=" + ticket + "';" +
            "})();" +
            "return 'go';" +
            "})()"
        wv.evaluateJavaScript(js) { v, _ in
            if (v as? String) != "go" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.dial(linkId, tries: tries - 1) }
            }
        }
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }
}

/* =====================================================================
   AliasStore — 애플 결제 (StoreKit 2)        2026-10-11 신설

   흐름 (안드로이드 BillingBridge 와 같은 모양)
     화면 AliasNative.storeBuy(sku) → 여기서 애플 결제창
     → 결제 끝 → 화면에 storePurchase { sku, a: 'apple:<거래번호>' }
     → 화면이 서버(…-google-verify)로 보냄 → 서버가 **애플에 직접** 확인하고 이용권을 줌
     → 화면 AliasNative.storeConsume(token) → 여기서 finish (정리)
   ⚠ 서버 확인 전에는 finish 하지 않습니다. 실패하면 다음에 앱을 켤 때 다시 보냅니다.
   ⚠ 결제에 "누가 샀는지"(appAccountToken = 로그인한 사람 번호)를 붙입니다.
     서버는 그 번호가 영수증을 보낸 사람과 같을 때만 이용권을 줍니다.
   ===================================================================== */
final class AliasStore {
    static let shared = AliasStore()
    private var updates: Task<Void, Never>?
    private var waiting: [String: Transaction] = [:]     // 'apple:<id>' → 아직 정리 안 한 거래 (메인에서만 만짐)
    private var outbox: [[String: Any]] = []             // 화면이 준비되기 전에 생긴 소식 (메인에서만 만짐)
    private var sending = false                          // 같은 소식을 두 번 보내지 않게

    func start() {
        if updates != nil { return }
        updates = Task.detached { [weak self] in
            for await r in Transaction.updates { await self?.handle(r) }
        }
    }

    func buy(sku: String, account: String) {
        if sku.isEmpty { toWeb("storeError", sku, "상품 번호가 없습니다"); return }
        Task {
            do {
                /* 🔴 애플 상품 번호 = 안드로이드 번호 + "_nr"(비갱신 구독). 다시 만든 것은 _nr2 · _nr3 … 큰 번호를 먼저 씁니다 */
                let ids = [sku + "_nr5", sku + "_nr4", sku + "_nr3", sku + "_nr2", sku + "_nr", sku]
                let found = try await Product.products(for: ids)
                guard let p = ids.compactMap({ id in found.first(where: { $0.id == id }) }).first else {
                    self.toWeb("storeError", sku, "상품을 찾지 못했습니다 (" + sku + ")")
                    return
                }
                var opts: Set<Product.PurchaseOption> = []
                if let u = UUID(uuidString: account) { opts.insert(.appAccountToken(u)) }
                let r = try await p.purchase(options: opts)
                switch r {
                case .success(let v): await self.handle(v)
                case .userCancelled: self.toWeb("storeCanceled", sku, "")
                case .pending: self.toWeb("storePending", sku, "")
                @unknown default: self.toWeb("storeError", sku, "결제가 끝나지 않았습니다")
                }
            } catch {
                self.toWeb("storeError", sku, "결제를 시작하지 못했습니다 (" + error.localizedDescription + ")")
            }
        }
    }

    private func handle(_ v: VerificationResult<Transaction>) async {
        guard case .verified(let t) = v else {
            toWeb("storeError", "", "애플이 확인하지 못한 결제입니다")
            return
        }
        if t.revocationDate != nil {           // 환불 · 취소된 것은 정리만
            await t.finish()
            return
        }
        let token = "apple:" + String(t.id)
        DispatchQueue.main.async {
            self.waiting[token] = t
            let plain = t.productID.replacingOccurrences(of: "_nr[0-9]*$", with: "", options: .regularExpression)
            self.toWeb("storePurchase", plain, token, String(t.originalID))
        }
    }

    /* 🔴 2026-11-19 와파 — 구독 바꾸기 · 해지: 애플 구독 관리 창을 앱 안에서 엽니다 */
    func manage() {
        Task { @MainActor in
            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
                if let u = URL(string: "https://apps.apple.com/account/subscriptions") { UIApplication.shared.open(u) }
                return
            }
            do { try await AppStore.showManageSubscriptions(in: scene) }
            catch { if let u = URL(string: "https://apps.apple.com/account/subscriptions") { UIApplication.shared.open(u) } }
        }
    }

    /* 서버가 확인을 마쳤습니다 → 정리 */
    func consume(token: String) {
        DispatchQueue.main.async {
            if let t = self.waiting[token] {
                self.waiting[token] = nil
                Task { await t.finish() }
                return
            }
            Task {
                for await r in Transaction.unfinished {
                    if case .verified(let t) = r, "apple:" + String(t.id) == token { await t.finish() }
                }
            }
        }
    }

    /* 화면이 준비됐습니다 → 못 끝낸 결제를 다시 보냅니다 */
    func flush() {
        DispatchQueue.main.async { self.drain() }
        Task {
            for await r in Transaction.unfinished { await self.handle(r) }
        }
    }

    private func toWeb(_ kind: String, _ sku: String, _ a: String, _ b: String = "") {
        let ev: [String: Any] = ["kind": kind, "sku": sku, "a": a, "b": b, "code": 0]
        DispatchQueue.main.async {
            self.outbox.append(ev)
            self.drain()
        }
    }

    /* 화면(공용 파일)이 준비돼야 받을 수 있습니다. 준비 전이면 0.5초마다 다시. (메인에서만 부름) */
    private func drain(tries: Int = 40, retry: Bool = false) {
        if sending && !retry { return }
        guard let first = outbox.first else { sending = false; return }
        sending = true
        guard let wv = AliasCalls.shared.currentWebView(),
              let data = try? JSONSerialization.data(withJSONObject: first),
              let json = String(data: data, encoding: .utf8) else {
            if tries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.drain(tries: tries - 1, retry: true) }
            } else { sending = false }
            return
        }
        let js = "(function(){try{var ev=" + json + ";" +
            "if(typeof window.acStoreEvent==='function'){window.acStoreEvent(ev);return 'ok';}" +
            "if(window.AL&&typeof AL.onStoreEvent==='function'&&AL.sb){AL.onStoreEvent(ev);return 'ok';}" +
            "}catch(e){}return 'wait';})()"
        wv.evaluateJavaScript(js) { v, _ in
            DispatchQueue.main.async {
                if let r = v as? String, r == "ok" {
                    if !self.outbox.isEmpty { self.outbox.removeFirst() }
                    self.drain(retry: true)
                } else if tries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.drain(tries: tries - 1, retry: true) }
                } else {
                    self.sending = false
                }
            }
        }
    }
}


/* =====================================================================
   AliasNureum — 누름 위젯(아이폰 바탕화면)   2026-10-31 (1.7)
   · sync: 화면이 보낸 라인 목록을 App Group 상자에 저장 → 위젯이 읽어 사람을 고르게 함
   · open: 위젯을 누르면 burumnureum://line/<라인번호> → 그 라인 화면을 엶
   ===================================================================== */
enum AliasNureum {
    static let group = "group.com.weaveapp.wafa"   // 와파는 위젯이 없어 상자를 쓰지 않습니다(못 열면 그냥 넘어감)
    static let scheme = "wafa"
    static let idRx = "^[0-9a-f-]{36}$"

    static func sync(_ items: [[String: Any]]) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            NSLog("[AliasNureum] 🔴 App Group 상자를 못 엽니다(엔타이틀먼트 확인)"); return
        }
        var out: [[String: String]] = []
        for it in items.prefix(40) {
            guard let id = it["id"] as? String, id.range(of: idRx, options: .regularExpression) != nil,
                  let name = it["name"] as? String, !name.isEmpty else { continue }
            if let b64 = it["icon"] as? String, let data = Data(base64Encoded: b64), data.count < 400_000 {
                try? data.write(to: dir.appendingPathComponent("nureum_\(id).png"))
            }
            var row = ["id": id, "name": String(name.prefix(20))]
            if let c = it["color"] as? String, c.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil { row["color"] = c }   // 1.8 색 바탕
            out.append(row)
        }
        if let d = try? JSONSerialization.data(withJSONObject: out) {
            UserDefaults(suiteName: group)?.set(d, forKey: "nureum_lines")
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /* 🔴 1.8b — 제어 센터 "누름 걸기" 쪽지(20초 안에 남긴 것만) */
    static func claimPending() {
        guard let ud = UserDefaults(suiteName: group),
              let d = ud.dictionary(forKey: "nureum_open"),
              let s = d["url"] as? String, let t = d["t"] as? Double,
              Date().timeIntervalSince1970 - t < 20,
              let u = URL(string: s) else { return }
        ud.removeObject(forKey: "nureum_open")
        _ = open(u)
    }

    @discardableResult
    static func open(_ url: URL?) -> Bool {
        guard let u = url, u.scheme == scheme else { return false }
        let id = u.lastPathComponent
        /* 🔴 2026-11-14 안심 긴급 위젯 · 잠금 화면 · 동작 버튼 → 긴급 화면(5초 뒤 보냄) */
        if u.host == "sos" { AliasCalls.shared.openNureum("sos.html?go=1"); return true }
        if u.host == "line", id.range(of: idRx, options: .regularExpression) != nil {
            AliasCalls.shared.openNureum("nureum_line.html?line=" + id)
        } else {
            AliasCalls.shared.openNureum("wafa_start.html")
        }
        return true
    }
}

/* =====================================================================
   AliasShortcuts — 홈 화면 아이콘 길게 누르기 → "○○에게 걸기"   2026-10-16 신설 (부름만)

   안드로이드의 단축번호 "걸기" 아이콘과 같은 일을 아이폰 방식으로 합니다.
   (아이폰은 앱이 홈 화면에 사람별 아이콘을 직접 만들 수 없어서, 아이콘 메뉴에 최대 4명을 올립니다)
     · 고르는 기준: ① 단축번호가 있는 사람(번호 순) → ② 모자라면 최근 연락한 사람(문자 · 통화)
     · 그룹방 · 떠난 사람은 넣지 않습니다
     · 로그아웃하면 메뉴를 비웁니다
   ⚠ burum.kr 파일은 고치지 않습니다. 화면에 작은 도우미를 심어 목록만 받아 옵니다.
   ===================================================================== */
enum AliasShortcuts {
    static let type = "kr.burum.call"

    static func set(_ items: [[String: Any]]) {
        let list: [UIApplicationShortcutItem] = items.prefix(4).compactMap { it in
            guard let id = it["id"] as? String, !id.isEmpty,
                  let name = it["name"] as? String, !name.isEmpty else { return nil }
            var sub = "음성 통화"
            if let n = it["sd"] as? Int { sub = "단축 \(n) · 음성 통화" }
            else if let n = it["sd"] as? Double { sub = "단축 \(Int(n)) · 음성 통화" }
            return UIApplicationShortcutItem(type: type, localizedTitle: name, localizedSubtitle: sub,
                                             icon: UIApplicationShortcutIcon(systemImageName: "phone.fill"),
                                             userInfo: ["link": id as NSString])
        }
        DispatchQueue.main.async { UIApplication.shared.shortcutItems = list }
    }

    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == type, let id = item.userInfo?["link"] as? String, !id.isEmpty else { return false }
        AliasCalls.shared.dial(id)
        return true
    }

    /* 화면에 심는 도우미 — 로그인한 사람의 연락처에서 4명을 골라 앱에 알려 줍니다(3분에 한 번까지) */
    static let publishJS = #"""
    (function(){
      if (window.__burumSC) return; window.__burumSC = true;
      function post(items){ try { window.webkit.messageHandlers.aliasIOS.postMessage({ act: 'shortcuts', items: items }); } catch (e) {} }
      async function run(force){
        if (!window.AL || !AL.sb) return false;
        try {
          var KEY = 'burum_sc_at', now = Date.now();
          if (!force) { var t = +(sessionStorage.getItem(KEY) || 0); if (now - t < 180000) return true; }
          sessionStorage.setItem(KEY, String(now));
          var ss = await AL.sb.auth.getSession();
          if (!ss || !ss.data || !ss.data.session) { post([]); return true; }
          var r = await AL.sb.rpc('my_contacts');
          if (r.error) return true;
          var sp = {};
          try {
            var e2 = await AL.sb.from('link_sides').select('id, speed_dial');
            (e2.data || []).forEach(function(x){ if (x.speed_dial) sp[x.id] = Number(x.speed_dial); });
          } catch (e) {}
          var list = (r.data || []).filter(function(x){
            return x.kind !== 'group' && x.link_id && (x.peer_label || x.peer_display);
          });
          list.sort(function(a, b){
            var na = sp[a.my_side_id] || 0, nb = sp[b.my_side_id] || 0;
            if (na && nb) return na - nb;
            if (na) return -1;
            if (nb) return 1;
            return String(b.last_activity_at || '').localeCompare(String(a.last_activity_at || ''));
          });
          post(list.slice(0, 4).map(function(x){
            return { id: String(x.link_id), name: String(x.peer_label || x.peer_display).slice(0, 40), sd: sp[x.my_side_id] || null };
          }));
        } catch (e) {}
        return true;
      }
      var force = /alias_contacts\.html/.test(location.pathname);   // 연락처 화면을 열면 바로 새로
      var n = 0;
      (function tick(){ run(force).then(function(ok){ if (!ok && ++n < 40) setTimeout(tick, 500); }); })();
    })();
    """#
}

/* =====================================================================
   AliasSpeaker — 통화 중 스피커 ↔ 수화기        2026-10-18 신설 (1.3)

   왜   아이폰 부름에는 스피커 단추가 없었습니다(화면이 setSpeaker 가 있을 때만 단추를 보임).
   어떻게  overrideOutputAudioPort(.speaker / .none). 블루투스 · 유선 이어폰이 있으면
          "수화기" 쪽은 이어폰으로 나갑니다(아이폰이 알아서 고름).
   ⚠ 웹 통화(WebKit)가 소리 설정을 다시 만들면 스피커가 풀릴 수 있어,
     설정이 바뀌었다는 소식(categoryChange)이 오면 스피커를 다시 겁니다.
   ⚠ 무엇이 실패해도 통화는 그대로 갑니다.
   ===================================================================== */
enum AliasSpeaker {
    static var on = false
    static var watching: NSObjectProtocol?

    static func set(_ v: Bool) {
        on = v
        apply()
        if watching == nil {
            watching = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                              object: nil, queue: .main) { n in
                AliasSpeaker.report()
                guard AliasSpeaker.on else { return }
                let why = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
                if why == .categoryChange || why == .routeConfigurationChange {
                    let outs = AVAudioSession.sharedInstance().currentRoute.outputs
                    if !outs.contains(where: { $0.portType == .builtInSpeaker }) { AliasSpeaker.apply() }
                }
            }
        }
    }

    static var changedCategory = false
    static var saved: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    /* 🔴🔴 2026-10-19 (1.5) — 1.4 에서 "통화가 끝난 뒤 걸려오는 전화의 벨이 안 울림".
         원인: 스피커를 바꿀 때 앱이 소리 설정을 직접 켜고(setActive) 끝나도 끄지 않았고,
               끝날 때 soloAmbient(무음 스위치를 따르는 설정)로 바꿔 두었습니다.
               켜진 채 남은 앱 소리 설정이 다음 전화의 벨(CallKit)을 막았습니다.
         고침: ① 스피커를 "켤" 때만 설정을 바꾸고 켭니다(수화기로 받는 보통 통화는 손대지 않음)
               ② 통화가 끝나면 원래 설정으로 되돌리고 앱 소리 설정을 반드시 끕니다 */
    static func reset() {
        if !on && watching == nil && !changedCategory { return }
        on = false
        DispatchQueue.main.async {
            let s = AVAudioSession.sharedInstance()
            try? s.overrideOutputAudioPort(.none)
            if changedCategory {
                changedCategory = false
                if let o = saved { try? s.setCategory(o.0, mode: o.1, options: o.2) }
                saved = nil
                try? s.setActive(false, options: .notifyOthersOnDeactivation)
            }
            print("[speaker] 통화 끝 — 소리 설정 원래대로")
        }
    }

    static func apply() {
        DispatchQueue.main.async {
            let s = AVAudioSession.sharedInstance()
            do {
                if on {
                    let opts: AVAudioSession.CategoryOptions = [.allowBluetooth, .defaultToSpeaker]
                    if s.category != .playAndRecord || !s.categoryOptions.contains(.defaultToSpeaker) {
                        if saved == nil { saved = (s.category, s.mode, s.categoryOptions) }
                        let mode: AVAudioSession.Mode = (s.category == .playAndRecord) ? s.mode : .voiceChat
                        try s.setCategory(.playAndRecord, mode: mode, options: opts)
                        changedCategory = true
                    }
                    try? s.setActive(true)   // 빌드 14 에서 스피커가 된 그대로. 통화가 끝나면 reset() 이 끕니다
                    try s.overrideOutputAudioPort(.speaker)
                } else {
                    if changedCategory, s.category == .playAndRecord {
                        try? s.setCategory(.playAndRecord, mode: s.mode, options: [.allowBluetooth])
                    }
                    try? s.overrideOutputAudioPort(.none)
                }
                print("[speaker] " + (on ? "스피커" : "수화기 · 이어폰"))
            } catch {
                print("[speaker] 바꾸기 실패: \(error)")
            }
            report()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { report() }
        }
    }

    /* 지금 소리가 실제로 나가는 곳: speaker · receiver · bt · headset · other */
    static func report() {
        let outs = AVAudioSession.sharedInstance().currentRoute.outputs
        var r = "other"
        if let p = outs.first?.portType {
            switch p {
            case .builtInSpeaker: r = "speaker"
            case .builtInReceiver: r = "receiver"
            case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE: r = "bt"
            case .headphones, .usbAudio: r = "headset"
            default: r = "other"
            }
        }
        AliasCalls.shared.currentWebView()?.evaluateJavaScript(
            "try{ window.AL && AL.onAudioRoute && AL.onAudioRoute('" + r + "'); }catch(e){}", completionHandler: nil)
    }
}


/* =====================================================================
   🔴 2026-10-20 (1.5) — 영상이 저절로 재생되게(유튜브 "같이 보기")
   아이폰 웹 화면은 기본으로 "손으로 눌러야 소리 나는 영상이 재생" 됩니다.
   그래서 같이 보기를 눌러도 아이폰만 ▶ 를 한 번 더 눌러야 했습니다.
   부름의 화면 틀(CAPBridgeViewController)을 이어받아 그 제한만 풉니다.
   (ios_setup.py 가 Main.storyboard 의 화면 틀을 이것으로 바꿉니다)
   ===================================================================== */
class BurumBridgeViewController: CAPBridgeViewController {
    override func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let c = super.webViewConfiguration(for: instanceConfiguration)
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        return c
    }
}
