import Foundation
import AppKit
import Security

/// Your Oatmeal account: which site this copy of the app belongs to, who's signed in there, and what
/// their plan unlocks. One signed app serves every site deployed from the blueprint: a site's
/// download page opens `oatmeal://connect?site=…`, sign-in comes back as `oatmeal://signed-in?token=…`,
/// and the plan is checked with that site (which asks Whop). With no site, the app is the free,
/// fully local open-source build and nothing is locked.
@MainActor
final class OatmealAccount: ObservableObject {
    static let shared = OatmealAccount()

    struct SiteInfo: Decodable, Equatable {
        var brand: String
        var signIn: Bool
        var oatmealAI: Bool
        var signInUrl: String
        var pricingUrl: String
        var accountUrl: String
    }

    struct Me: Codable, Equatable {
        var name: String?
        var email: String?
        var plan: String
        var planName: String
        /// Days of meetings the plan shows; nil for all of them.
        var historyDays: Int?
        var oatmealAI: Bool
    }

    /// The site's address, e.g. https://oatmeal.whop.site. From `oatmeal://connect`, else the build's default.
    @Published private(set) var site: URL?
    @Published private(set) var info: SiteInfo?
    @Published private(set) var me: Me?
    @Published private(set) var busy = false
    @Published private(set) var error: String?

    private static let siteKey = "account.site"
    private static let meKey = "account.me"

    var signedIn: Bool { token != nil }
    var isPaid: Bool { me.map { $0.plan != "free" } ?? false }
    var brand: String { info?.brand ?? "Oatmeal" }

    /// Meetings older than this are kept but locked until Pro. Nil when nothing is locked: no site
    /// (the open-source build), or a plan with full history.
    var historyCutoff: Date? {
        guard site != nil, !isPaid else { return nil }
        let days = me?.historyDays ?? 30
        return Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date()))
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.siteKey) ?? (Bundle.main.object(forInfoDictionaryKey: "OatmealSite") as? String) ?? ""
        site = URL(string: saved).flatMap { $0.scheme == "https" || $0.host == "localhost" ? $0 : nil }
        // The last plan we saw, so Pro stays unlocked offline.
        if let data = UserDefaults.standard.data(forKey: Self.meKey) { me = try? JSONDecoder().decode(Me.self, from: data) }
        if site != nil { Task { await refresh() } }
    }

    // MARK: Links into the app

    /// Handles `oatmeal://connect?site=…` and `oatmeal://signed-in?token=…&site=…`. True if it was ours.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "oatmeal", let host = url.host else { return false }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in query.first { $0.name == name }?.value }
        switch host {
        case "connect":
            guard let s = value("site").flatMap(Self.siteURL) else { error = "That link didn\u{2019}t include a valid site."; return true }
            if s != site { signOut() }
            setSite(s)
            Task { await refresh() }
            open()
        case "signed-in":
            guard let token = value("token"), !token.isEmpty else { error = "Sign-in didn\u{2019}t finish. Try again."; return true }
            if let s = value("site").flatMap(Self.siteURL) { setSite(s) }
            Keychain.set(token, for: tokenAccount)
            error = nil
            Task { await refresh() }
            open()
        default:
            return false
        }
        return true
    }

    private func open() {
        AppModel.shared.settingsTab = "General"
        AppModel.shared.open(.settings)
    }

    private static func siteURL(_ raw: String) -> URL? {
        guard let u = URL(string: raw), let host = u.host, u.scheme == "https" || host == "localhost" || host == "127.0.0.1" else { return nil }
        var c = URLComponents()
        c.scheme = u.scheme; c.host = host; c.port = u.port
        return c.url
    }

    private func setSite(_ s: URL) {
        site = s
        UserDefaults.standard.set(s.absoluteString, forKey: Self.siteKey)
    }

    // MARK: Signing in

    func signIn() {
        guard let info, info.signIn, let url = URL(string: info.signInUrl) else {
            error = info == nil ? "Can\u{2019}t reach \(site?.host ?? "the site") right now." : "Sign-in isn\u{2019}t switched on for \(brand) yet."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func signOut() {
        Keychain.delete(tokenAccount)
        me = nil
        UserDefaults.standard.removeObject(forKey: Self.meKey)
    }

    func openPricing() {
        if let s = info?.pricingUrl, let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    func openAccountPage() {
        if let s = info?.accountUrl, let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    /// Reads the site's details and, when signed in, the plan.
    func refresh() async {
        guard let site else { return }
        busy = true
        defer { busy = false }
        do {
            info = try await get("api/app/config", from: site, as: SiteInfo.self)
            if signedIn {
                let fresh = try await get("api/app/me", from: site, as: Me.self, auth: true)
                me = fresh
                UserDefaults.standard.set(try? JSONEncoder().encode(fresh), forKey: Self.meKey)
            }
            error = nil
        } catch AccountError.signedOut {
            signOut()
            error = "You were signed out. Sign in again."
        } catch {
            // Offline or the site is down: keep the last plan we saw.
            self.error = (error as? AccountError)?.message ?? "Can\u{2019}t reach \(site.host ?? "the site") right now."
        }
    }

    // MARK: Oatmeal AI

    struct WrittenNotes: Decodable {
        var title: String
        var notes: String
        var summary: [String]
    }

    /// Has the site's Oatmeal AI write this meeting's notes (Pro).
    func writeNotes(title: String, startedAt: Date, attendees: [String], transcript: String, myNotes: String) async throws -> WrittenNotes {
        guard let site else { throw AccountError.message("Connect Oatmeal to your account first.") }
        let body: [String: Any] = [
            "title": title, "startedAt": startedAt.formatted(date: .abbreviated, time: .shortened),
            "attendees": attendees, "transcript": transcript, "myNotes": myNotes,
        ]
        var request = try authorized(site.appendingPathComponent("api/app/notes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300
        return try await send(request, as: WrittenNotes.self)
    }

    // MARK: HTTP

    enum AccountError: Error {
        case signedOut
        case message(String)
        var message: String? { if case .message(let m) = self { return m }; return nil }
    }

    private var tokenAccount: String { "token:" + (site?.host ?? "none") }
    private var token: String? { Keychain.get(tokenAccount) }

    private func authorized(_ url: URL) throws -> URLRequest {
        guard let token else { throw AccountError.signedOut }
        var r = URLRequest(url: url)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    private func get<T: Decodable>(_ path: String, from site: URL, as type: T.Type, auth: Bool = false) async throws -> T {
        let url = site.appendingPathComponent(path)
        var request = auth ? try authorized(url) : URLRequest(url: url)
        request.timeoutInterval = 20
        return try await send(request, as: T.self)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AccountError.signedOut }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw AccountError.message(message ?? "The site answered \(status).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// The sign-in token, kept in the login Keychain.
private enum Keychain {
    static let service = "com.oatmeal.app.account"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        delete(account)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecValueData as String: Data(value.utf8),
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
