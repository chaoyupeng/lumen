import Cmpv
import Foundation

/// C wakeup trampoline: libmpv calls this (on an arbitrary thread) whenever new
/// events are available. We hop to the client's serial event queue to drain them.
private func mpvWakeup(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx = ctx else { return }
    Unmanaged<MPVClient>.fromOpaque(ctx).takeUnretainedValue().handleWakeup()
}

/// Thin, idiomatic Swift wrapper over the libmpv C client API. This is the ONLY
/// type that touches Cmpv symbols (besides the renderer). One `mpv_handle` for
/// the whole app — no subprocess, no second mpv.
final class MPVClient {
    private(set) var handle: OpaquePointer?

    /// Invoked once per event on the event queue (a background thread). The
    /// handler MUST copy anything it needs out of the event synchronously — the
    /// pointer is only valid until the next `mpv_wait_event` call.
    var onEvent: ((UnsafePointer<mpv_event>) -> Void)?

    private let eventQueue = DispatchQueue(label: "haizea.lumen.mpv", qos: .userInitiated)

    init() {
        handle = mpv_create()
    }

    // MARK: - Event loop

    fileprivate func handleWakeup() {
        eventQueue.async { [weak self] in self?.drainEvents() }
    }

    private func drainEvents() {
        guard let h = handle else { return }
        while true {
            guard let ev = mpv_wait_event(h, 0) else { break }
            if ev.pointee.event_id == MPV_EVENT_NONE { break }
            onEvent?(ev)
        }
    }

    // MARK: - Pre-init configuration

    func setOptionString(_ name: String, _ value: String) {
        guard let h = handle else { return }
        mpv_set_option_string(h, name, value)
    }

    func observe(_ name: String, _ format: mpv_format) {
        guard let h = handle else { return }
        mpv_observe_property(h, 0, name, format)
    }

    func requestLogMessages(_ level: String) {
        guard let h = handle else { return }
        mpv_request_log_messages(h, level)
    }

    func setWakeupCallback() {
        guard let h = handle else { return }
        mpv_set_wakeup_callback(h, mpvWakeup, Unmanaged.passUnretained(self).toOpaque())
    }

    @discardableResult
    func initialize() -> Bool {
        guard let h = handle else { return false }
        return mpv_initialize(h) >= 0
    }

    // MARK: - Commands

    /// Issue a command as a NULL-terminated argv (e.g. ["loadfile", path]).
    func command(_ args: [String]) {
        guard let h = handle else { return }
        var argv: [UnsafePointer<CChar>?] = args.map { UnsafePointer(strdup($0)) }
        argv.append(nil)
        defer { for p in argv where p != nil { free(UnsafeMutablePointer(mutating: p)) } }
        argv.withUnsafeMutableBufferPointer { buf in
            _ = mpv_command(h, buf.baseAddress)
        }
    }

    // MARK: - Typed properties

    func setFlag(_ name: String, _ value: Bool) {
        guard let h = handle else { return }
        var v: Int32 = value ? 1 : 0
        mpv_set_property(h, name, MPV_FORMAT_FLAG, &v)
    }

    func setInt(_ name: String, _ value: Int64) {
        guard let h = handle else { return }
        var v = value
        mpv_set_property(h, name, MPV_FORMAT_INT64, &v)
    }

    func setDouble(_ name: String, _ value: Double) {
        guard let h = handle else { return }
        var v = value
        mpv_set_property(h, name, MPV_FORMAT_DOUBLE, &v)
    }

    func setString(_ name: String, _ value: String) {
        guard let h = handle else { return }
        mpv_set_property_string(h, name, value)
    }

    func getDouble(_ name: String) -> Double? {
        guard let h = handle else { return nil }
        var v: Double = 0
        return mpv_get_property(h, name, MPV_FORMAT_DOUBLE, &v) >= 0 ? v : nil
    }

    func getInt(_ name: String) -> Int64? {
        guard let h = handle else { return nil }
        var v: Int64 = 0
        return mpv_get_property(h, name, MPV_FORMAT_INT64, &v) >= 0 ? v : nil
    }

    func getFlag(_ name: String) -> Bool? {
        guard let h = handle else { return nil }
        var v: Int32 = 0
        return mpv_get_property(h, name, MPV_FORMAT_FLAG, &v) >= 0 ? (v != 0) : nil
    }

    func getString(_ name: String) -> String? {
        guard let h = handle, let c = mpv_get_property_string(h, name) else { return nil }
        defer { mpv_free(c) }
        return String(cString: c)
    }

    // MARK: - Teardown

    /// Tear down the core. The render context must already be freed (see
    /// MPVRenderer.destroy) before calling this.
    func terminate() {
        guard let h = handle else { return }
        mpv_set_wakeup_callback(h, nil, nil)
        mpv_terminate_destroy(h)
        handle = nil
    }
}
