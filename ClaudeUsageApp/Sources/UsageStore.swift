import AppKit
import Combine
import Foundation
import Network

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot = .empty
    @Published private(set) var lastRefreshDate: Date?
    @Published var refreshInterval: RefreshInterval {
        didSet {
            guard oldValue != refreshInterval else { return }
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: Self.refreshDefaultsKey)
            scheduleTimer()
        }
    }

    private var timer: Timer?
    private var httpListener: NWListener?

    private static let refreshDefaultsKey = "refreshIntervalMinutes"
    private static nonisolated(unsafe) let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClaudeUsageMonitor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage_cache.json")
    }()
    private static nonisolated(unsafe) let httpPort: UInt16 = 4480

    init() {
        let storedValue = UserDefaults.standard.integer(forKey: Self.refreshDefaultsKey)
        refreshInterval = RefreshInterval(rawValue: storedValue) ?? .fiveMinutes
        // Migrate old Dropbox cache if it exists
        migrateOldCache()
        refresh()
        scheduleTimer()
        startHTTPServer()
    }

    func refresh() {
        do {
            let data = try Data(contentsOf: Self.cacheURL)
            let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)
            snapshot = decoded
            lastRefreshDate = Date()
        } catch {
            lastRefreshDate = Date()
        }
    }

    func openUsagePage() {
        NSWorkspace.shared.open(UsageFormatters.usageURL)
    }

    private func migrateOldCache() {
        let oldPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Dropbox/claude-menu-bar-app/usage_cache.json")
        if FileManager.default.fileExists(atPath: oldPath.path),
           !FileManager.default.fileExists(atPath: Self.cacheURL.path) {
            try? FileManager.default.copyItem(at: oldPath, to: Self.cacheURL)
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval.seconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    // ── Local HTTP server on localhost:4480 ─────────────────────────────────────
    // Chrome extension POSTs usage JSON here; we validate, write cache, update UI.

    private func startHTTPServer() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // Bind to localhost only — not accessible from LAN
        let localhost = NWEndpoint.Host("127.0.0.1")

        do {
            httpListener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.httpPort)!)
        } catch {
            print("[UsageStore] Failed to create listener: \(error)")
            return
        }

        // Restrict to localhost connections only
        httpListener?.parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: localhost, port: NWEndpoint.Port(rawValue: Self.httpPort)!)

        httpListener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        httpListener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[UsageStore] HTTP server listening on 127.0.0.1:\(Self.httpPort)")
            case .failed(let err):
                print("[UsageStore] Listener failed: \(err)")
            default:
                break
            }
        }

        httpListener?.start(queue: .global(qos: .utility))
    }

    private nonisolated func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        // Read once — HTTP requests from localhost extensions fit in one read
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            self.processRequest(data ?? Data(), connection: connection)
        }
    }

    private nonisolated func processRequest(_ data: Data, connection: NWConnection) {
        let responseBody = #"{"ok":true}"#
        let http = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: http://127.0.0.1\r\nAccess-Control-Allow-Methods: GET,POST,OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Length: \(responseBody.count)\r\nConnection: close\r\n\r\n\(responseBody)"

        defer {
            connection.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }

        guard !data.isEmpty else { return }
        let raw = String(data: data, encoding: .utf8) ?? ""

        if raw.hasPrefix("OPTIONS") || raw.hasPrefix("GET") { return }

        guard let bodyRange = raw.range(of: "\r\n\r\n") else { return }
        let bodyStr = String(raw[bodyRange.upperBound...])
        guard let bodyData = bodyStr.data(using: .utf8) else { return }

        guard let decoded = try? JSONDecoder().decode(UsageSnapshot.self, from: bodyData) else { return }

        // Write validated data to cache
        do {
            try bodyData.write(to: Self.cacheURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.cacheURL.path)
        } catch {
            print("[UsageStore] Cache write error: \(error)")
        }

        Task { @MainActor in
            // Use a local to avoid capturing self in a non-sendable way
            let snapshot = decoded
            Task { @MainActor [weak self] in
                self?.snapshot = snapshot
                self?.lastRefreshDate = Date()
            }
        }
    }
}

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute:
            return "1 min"
        case .fiveMinutes:
            return "5 min"
        case .fifteenMinutes:
            return "15 min"
        case .thirtyMinutes:
            return "30 min"
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }
}
