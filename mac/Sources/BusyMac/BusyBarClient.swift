import Foundation

/// Talks to the bar's local HTTP API (`http://<host>/api/...`).
///
/// The bar keeps its timer as a "snapshot": the last state written, plus when
/// it was written. Reading it tells you where the timer was at that moment;
/// the time since has to be added on by the client (see `SessionState`).
/// Changing the timer means writing a new snapshot - there is no pause or
/// stop endpoint. Snapshots are handled as raw JSON so fields this app does
/// not know about are passed back to the bar untouched.
struct BusyBarClient {
    typealias JSON = [String: Any]

    var host: String
    var token: String?

    enum Failure: LocalizedError {
        case badHost
        case http(Int, String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .badHost: return "The bar's address isn't valid."
            case .http(let code, let body): return "The bar answered \(code): \(body)"
            case .malformed: return "The bar sent something unexpected."
            }
        }
    }

    // MARK: Requests

    private func request(_ method: String, _ path: String, body: JSON? = nil) async throws -> Any {
        guard let url = URL(string: "http://\(host)/api\(path)") else { throw Failure.badHost }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = method
        if let token, !token.isEmpty { req.setValue(token, forHTTPHeaderField: "X-API-Token") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(decoding: data.prefix(200), as: UTF8.self))
        }
        if data.isEmpty { return [:] as JSON }
        return try JSONSerialization.jsonObject(with: data)
    }

    func snapshot() async throws -> JSON {
        guard let json = try await request("GET", "/busy/snapshot") as? JSON else { throw Failure.malformed }
        return json
    }

    /// One of the bar's two cards: "busy" or "custom" (the physical switch positions).
    func profile(_ slot: String) async throws -> JSON {
        guard let json = try await request("GET", "/busy/profiles/\(slot)") as? JSON else { throw Failure.malformed }
        return json
    }

    /// Writes `variant` as the newest snapshot, stamped now so the bar takes it as the truth.
    private func apply(_ variant: JSON) async throws {
        let stamped: JSON = ["snapshot": variant, "snapshot_timestamp_ms": nowMs()]
        _ = try await request("PUT", "/busy/snapshot", body: stamped)
    }

    // MARK: Session control

    /// Starts what a card describes - the same thing the bar's own switch + Start would run.
    func start(slot: String) async throws {
        let card = try await profile(slot)
        guard let cardID = card["id"] as? String,
              let timer = card["timer_settings"] as? JSON,
              let settings = card["busy_bar_settings"] as? JSON
        else { throw Failure.malformed }

        var variant: JSON = ["card_id": cardID, "is_paused": false, "busy_bar_settings": settings]
        switch timer["type"] as? String {
        case "SIMPLE":
            variant["type"] = "SIMPLE"
            variant["time_left_ms"] = timer["total_time_ms"] ?? 25 * 60_000
        case "INTERVAL":
            let work = timer["interval_work_ms"] ?? 25 * 60_000
            variant["type"] = "INTERVAL"
            variant["current_interval"] = 0
            variant["current_interval_time_total_ms"] = work
            variant["current_interval_time_left_ms"] = work
            variant["interval_settings"] = timer
        default:
            variant["type"] = "INFINITE"
        }
        try await apply(variant)
    }

    func stop() async throws {
        let live = try await snapshot()
        let settings = (live["snapshot"] as? JSON)?["busy_bar_settings"] ?? [:]
        try await apply(["type": "NOT_STARTED", "busy_bar_settings": settings])
    }

    /// Pausing writes back the time actually left, not the stale figure the
    /// stored snapshot carries - otherwise resuming would hand back time already spent.
    func setPaused(_ paused: Bool) async throws {
        let live = try await snapshot()
        guard var variant = live["snapshot"] as? JSON, variant["type"] as? String != "NOT_STARTED" else { return }
        if paused, let state = SessionState(snapshot: live) {
            switch variant["type"] as? String {
            case "SIMPLE":
                variant["time_left_ms"] = state.timeLeftMs
            case "INTERVAL":
                variant["current_interval"] = state.interval
                variant["current_interval_time_left_ms"] = state.timeLeftMs
                if let settings = variant["interval_settings"] as? JSON {
                    variant["current_interval_time_total_ms"] =
                        SessionState.duration(of: state.interval ?? 0, settings: settings)
                }
            default: break
            }
        }
        variant["is_paused"] = paused
        try await apply(variant)
    }
}

func nowMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
