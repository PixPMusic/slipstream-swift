import SwiftUI
import WebKit

struct LoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var browser = LoginBrowser()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign in to Floatplane").font(.headline)
                    Text("Sign in on Floatplane’s website.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { browser.retry() }.tint(.primary)
                Button("Cancel") { dismiss() }.tint(.primary)
            }.padding()
            Divider()
            LoginWebView(browser: browser)
                .overlay { if browser.loading { ProgressView().padding().background(.regularMaterial, in: Capsule()) } }
            if let error = browser.error {
                HStack {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { browser.retry() }.tint(.primary)
                }.padding()
            }
        }
        #if os(macOS)
        .frame(width: 660, height: 740)
        #endif
        .onAppear {
            browser.onSession = { cookie in try await model.authenticate(cookie) }
        }
        .onDisappear { browser.stop() }
    }
}

@MainActor @Observable final class LoginBrowser: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    var loading = true
    var error: String?
    @ObservationIgnored var onSession: ((SessionCookie) async throws -> Void)?
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var finished = false
    @ObservationIgnored private var lastValue: String?
    @ObservationIgnored let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.websiteDataStore.httpCookieStore.add(self)
        webView.load(URLRequest(url: URL(string: "https://www.floatplane.com/login")!))
        polling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.checkSession()
            }
        }
    }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { checkSession() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false
        checkSession()
    }
    private func checkSession() {
        guard !finished, checking == nil else { return }
        checking = Task { [weak self] in
            guard let self else { return }
            defer { checking = nil }
            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            guard !Task.isCancelled,
                  let cookie = cookies.compactMap(SessionCookie.init(cookie:)).first,
                  cookie.value != lastValue, let onSession else { return }
            lastValue = cookie.value
            do {
                // Anonymous sessions also have a cookie; only /user/self proves login.
                try await onSession(cookie)
                finished = true
            } catch APIError.signedOut { lastValue = nil }
            catch APIError.forbidden { lastValue = nil }
            catch { self.error = error.localizedDescription; lastValue = nil }
        }
    }
    func retry() {
        error = nil
        lastValue = nil
        checkSession()
        webView.reload()
    }
    func stop() {
        polling?.cancel()
        polling = nil
        checking?.cancel()
        checking = nil
        webView.stopLoading()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loading = false
        if (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loading = false
        if (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        return LoginNavigationPolicy.allows(url, isSubframe: navigationAction.targetFrame?.isMainFrame == false) ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.scheme == "https", let host = url.host, LoginNavigationPolicy.allowsTopLevelHost(host) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

#if os(macOS)
struct LoginWebView: NSViewRepresentable {
    let browser: LoginBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else
struct LoginWebView: UIViewRepresentable {
    let browser: LoginBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
