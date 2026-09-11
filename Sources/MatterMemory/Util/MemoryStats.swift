import Foundation
import Darwin

@_silgen_name("proc_listallpids") private func mm_proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ size: Int32) -> Int32
@_silgen_name("proc_pidpath") private func mm_proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutablePointer<CChar>, _ size: UInt32) -> Int32
@_silgen_name("proc_pid_rusage") private func mm_proc_pid_rusage(_ pid: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32

/// Physical footprint of this process plus the WebKit helper processes
/// launchd spawned on our behalf — the same grouping Activity Monitor shows.
enum MemoryStats {
    struct Snapshot { var own: UInt64; var helpers: UInt64; var helperCount: Int; var details: [(pid: pid_t, name: String, bytes: UInt64)] = []; var total: UInt64 { own + helpers } }

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFor: ResponsibleFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private static func rusage(of pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) { mm_proc_pid_rusage(pid, 4 /* RUSAGE_INFO_V4 */, UnsafeMutableRawPointer($0)) }
        return ok == 0 ? info : nil
    }

    static func footprint(of pid: pid_t) -> UInt64 { rusage(of: pid)?.ri_phys_footprint ?? 0 }

    static func snapshot() -> Snapshot {
        let me = getpid()
        var snap = Snapshot(own: footprint(of: me), helpers: 0, helperCount: 0)
        guard let responsibleFor else { return snap }
        let count = Int(mm_proc_listallpids(nil, 0))
        guard count > 0 else { return snap }
        var pids = [pid_t](repeating: 0, count: count + 64)
        let n = Int(mm_proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        // Launched from Finder/Dock we are our own responsible process and WebKit's
        // XPC helpers are attributed to us. Launched from a terminal the terminal is
        // responsible for everyone, so fall back to "WebKit helpers started after us".
        let myResponsible = responsibleFor(me)
        let myStart = rusage(of: me)?.ri_proc_start_abstime ?? 0
        for pid in pids.prefix(n) where pid > 0 && pid != me {
            let r = responsibleFor(pid)
            var mine = r == me
            if !mine, myResponsible != me, r == myResponsible, let ru = rusage(of: pid), ru.ri_proc_start_abstime >= myStart {
                mine = isWebKitHelper(pid)
            }
            guard mine else { continue }
            let f = footprint(of: pid)
            if f > 0 { snap.helpers += f; snap.helperCount += 1; snap.details.append((pid, helperName(pid), f)) }
        }
        return snap
    }

    private static func helperName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        guard mm_proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return "?" }
        return (String(cString: buf) as NSString).lastPathComponent
    }

    private static func isWebKitHelper(_ pid: pid_t) -> Bool {
        var buf = [CChar](repeating: 0, count: 4096)
        let len = mm_proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else { return false }
        return String(cString: buf).contains("com.apple.WebKit")
    }

    static func format(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1000 ? String(format: "%.2f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }
}
