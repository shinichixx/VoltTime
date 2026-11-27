import Foundation
import Network

/// Picks the Home Assistant address for each request: the home Wi-Fi one when it answers,
/// otherwise the Tailscale one. The token is never sent to the home address before it has
/// answered like Home Assistant.
actor HARoute {
    static let shared = HARoute()

    static let homeKey = "haHomeURL"
    static let autoKey = "haAutoSwitch"
    static let defaultHome = "http://192.168.0.211:8123"

    private let monitor = NWPathMonitor()
    private var started = false
    private var onWiFi: Bool?
    private var cached: (home: URL, ok: Bool, at: Date)?
    private var probing: (home: URL, task: Task<Bool, Never>)?
    private var generation = 0
    /// The address that answered the latest request (shown in Menu › Connection).
    private(set) var lastUsed: URL?

    func used(_ base: URL) { lastUsed = base }

    /// Forget the last answer (network changed, app reopened, a request failed).
    func reset() {
        generation += 1
        cached = nil
        probing = nil
    }

    private func networkChanged(wifi: Bool) {
        onWiFi = wifi
        reset()
    }

    private func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            let wifi = path.availableInterfaces.contains { $0.type == .wifi }
            Task { await HARoute.shared.networkChanged(wifi: wifi) }
        }
        monitor.start(queue: DispatchQueue(label: "ha.route"))
    }

    func base(home: URL?, away: URL) async -> URL {
        guard let home, home != away else { return away }
        start()
        if onWiFi == false { return away }   // mobile data only: don't wait for the home address
        if let c = cached, c.home == home, Date().timeIntervalSince(c.at) < 30 { return c.ok ? home : away }
        let task: Task<Bool, Never>
        if let p = probing, p.home == home {
            task = p.task
        } else {
            task = Task { await HARoute.looksLikeHomeAssistant(home) }
            probing = (home, task)
        }
        let g = generation
        let ok = await task.value
        if g == generation {
            cached = (home, ok, Date())
            probing = nil
        }
        return ok ? home : away
    }

    /// Asks for the public web manifest (no token), waiting 2 seconds at most.
    static func looksLikeHomeAssistant(_ base: URL) async -> Bool {
        guard let url = URL(string: base.absoluteString + "/manifest.json") else { return false }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        req.httpMethod = "GET"
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (obj["name"] as? String) == "Home Assistant"
    }
}
