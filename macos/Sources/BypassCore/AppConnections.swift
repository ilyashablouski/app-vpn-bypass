import Foundation
import Darwin

/// IP-адреса текущих соединений приложений через libproc (без запуска `lsof`).
public enum AppConnections {
    /// Сопоставление процесса с записью приложения: по пути к .app (охватывает helper-процессы)
    /// либо по имени исполняемого файла.
    public static func matches(entry: Entry, processPath: String) -> Bool {
        if let bundle = entry.path, !bundle.isEmpty, processPath.hasPrefix(bundle + "/") { return true }
        return (processPath as NSString).lastPathComponent == entry.value
    }

    public static func remoteAddresses(for apps: [Entry]) -> Set<IPv4Target> {
        guard !apps.isEmpty else { return [] }
        var result = Set<IPv4Target>()
        for pid in allPIDs() {
            guard let path = processPath(pid), apps.contains(where: { matches(entry: $0, processPath: path) })
            else { continue }
            result.formUnion(remoteAddresses(pid: pid))
        }
        return result
    }

    private static func allPIDs() -> [pid_t] {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(size) / MemoryLayout<pid_t>.size + 32)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        return pids[0..<Int(bytes) / MemoryLayout<pid_t>.size].filter { $0 > 0 }
    }

    private static func processPath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
    }

    private static func remoteAddresses(pid: pid_t) -> Set<IPv4Target> {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size + 8)
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * MemoryLayout<proc_fdinfo>.size))
        guard bytes > 0 else { return [] }

        var result = Set<IPv4Target>()
        for fd in fds[0..<Int(bytes) / MemoryLayout<proc_fdinfo>.size]
        where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let n = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info,
                                   Int32(MemoryLayout<socket_fdinfo>.size))
            guard n == Int32(MemoryLayout<socket_fdinfo>.size), info.psi.soi_family == AF_INET else { continue }

            let ini: in_sockinfo
            switch Int(info.psi.soi_kind) {
            case 1: ini = info.psi.soi_proto.pri_in            // UDP и прочие IP-сокеты
            case 2: ini = info.psi.soi_proto.pri_tcp.tcpsi_ini  // TCP
            default: continue
            }
            guard ini.insi_fport != 0 else { continue }
            let addr = UInt32(bigEndian: ini.insi_faddr.ina_46.i46a_addr4.s_addr)
            let first = addr >> 24
            if addr == 0 || first == 127 || first >= 224 || (addr >> 16) == 0xA9FE { continue }
            result.insert(IPv4Target(address: addr))
        }
        return result
    }
}
