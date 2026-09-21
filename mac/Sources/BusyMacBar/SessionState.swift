import Foundation

/// What the bar's timer is doing right now, worked out from a snapshot.
///
/// The snapshot is the state as it was *written*; this advances it by the time
/// since, walking over interval boundaries. Mirrors `busylib.features.timer`.
struct SessionState: Equatable {
    enum Kind: String { case infinite, simple, interval }
    enum Phase { case work, rest }

    var kind: Kind
    var cardID: String
    var isPaused: Bool
    var phase: Phase
    var interval: Int?
    /// nil for an infinite session, which has no end.
    var timeLeftMs: Int?

    /// Returns nil when nothing is running (not started, or already finished).
    init?(snapshot: [String: Any], now: Int = nowMs()) {
        guard let inner = snapshot["snapshot"] as? [String: Any],
              let type = inner["type"] as? String,
              let stamp = snapshot["snapshot_timestamp_ms"] as? Int
        else { return nil }
        let elapsed = max(0, now - stamp)
        cardID = inner["card_id"] as? String ?? ""
        isPaused = inner["is_paused"] as? Bool ?? false
        phase = .work
        interval = nil
        timeLeftMs = nil

        switch type {
        case "INFINITE":
            kind = .infinite

        case "SIMPLE":
            kind = .simple
            let stored = inner["time_left_ms"] as? Int ?? 0
            let left = isPaused ? stored : stored - elapsed
            if left <= 0 { return nil }
            timeLeftMs = left

        case "INTERVAL":
            kind = .interval
            guard let settings = inner["interval_settings"] as? [String: Any] else { return nil }
            var index = inner["current_interval"] as? Int ?? 0
            var left = inner["current_interval_time_left_ms"] as? Int ?? 0
            if !isPaused {
                // Even indices are work, odd are rest; the session ends at
                // cycles*2-1 (no rest after the final work).
                let last = (settings["interval_work_cycles_count"] as? Int ?? 1) * 2 - 1
                left -= elapsed
                while left <= 0 {
                    index += 1
                    if index >= last { return nil }
                    let length = Self.duration(of: index, settings: settings)
                    if length <= 0 { break }
                    left += length
                }
            }
            interval = index
            phase = index % 2 == 0 ? .work : .rest
            timeLeftMs = max(0, left)

        default:
            return nil
        }
    }

    static func duration(of index: Int, settings: [String: Any]) -> Int {
        let key = index % 2 == 0 ? "interval_work_ms" : "interval_rest_ms"
        return settings[key] as? Int ?? 0
    }

    /// Whether the Mac should be locked down: running, not paused, and not on a break.
    var isFocusing: Bool { !isPaused && phase == .work }
}
