import SwiftUI
import UniformTypeIdentifiers

// Backup / restore of the energy history as CSV, plus the daily-totals file for spreadsheets.
// Auto backup: each time the app opens (after the energy refresh) the full backup is written into a folder the user
// picked once (e.g. iCloud Drive › VoltTime Backups). One file per day, the latest 3 kept.

enum EnergyCSV {
    static let header = "start,step_min,solar_kwh,grid_import_kwh,grid_export_kwh,model3_kwh"

    /// Every slot the app has, in kWh. All-zero slots are skipped (restore fills them with 0);
    /// the first slot of each day is always written so the day and its step survive.
    static func backup(_ curves: [String: DayCurve]) -> String {
        var out = header + "\n"
        for k in curves.keys.sorted() {
            guard let c = curves[k] else { continue }
            for i in 0..<c.count {
                let s = c.solar[i], im = c.imp[i], ex = c.exp[i], ca = c.car[i]
                if i > 0 && s == 0 && im == 0 && ex == 0 && ca == 0 { continue }
                let t = i * c.minutes
                out += String(format: "%@ %02d:%02d,%d,%.3f,%.3f,%.3f,%.3f\n", k, t / 60, t % 60, c.minutes, s, im, ex, ca)
            }
        }
        return out
    }

    /// One row per day, the same figures as the Energy tiles.
    static func daily(_ curves: [String: DayCurve]) -> String {
        var out = "date,solar_kwh,grid_import_kwh,grid_export_kwh,home_kwh,model3_kwh,model3_solar_kwh,self_powered_pct\n"
        for k in curves.keys.sorted() {
            guard let c = curves[k] else { continue }
            let f = c.total
            let sp = DaySummary(f).selfPowered.map { String(Int(($0 * 100).rounded())) } ?? ""
            out += String(format: "%@,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%@\n", k, f.solar, f.imp, f.exp, f.house, f.car, f.carSolar, sp)
        }
        return out
    }

    struct BadFile: LocalizedError {
        var errorDescription: String? { "This isn't a VoltTime backup file." }
    }

    static func parse(_ text: String) throws -> [String: DayCurve] {
        var lines = text.split(whereSeparator: \.isNewline).makeIterator()
        guard let head = lines.next(), head.replacingOccurrences(of: "\u{FEFF}", with: "").hasPrefix("start,step_min") else { throw BadFile() }
        var out: [String: DayCurve] = [:]
        while let line = lines.next() {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 6, f[0].count == 16, let step = Int(f[1]), step > 0, 1440 % step == 0 else { continue }
            let key = String(f[0].prefix(10))
            let hm = f[0].suffix(5).split(separator: ":")
            guard hm.count == 2, let h = Int(hm[0]), let m = Int(hm[1]) else { continue }
            var c = out[key] ?? DayCurve(minutes: step)
            guard c.minutes == step else { continue }
            let slot = (h * 60 + m) / step
            guard slot >= 0 && slot < c.count else { continue }
            c.solar[slot] = Float(f[2]) ?? 0
            c.imp[slot] = Float(f[3]) ?? 0
            c.exp[slot] = Float(f[4]) ?? 0
            c.car[slot] = Float(f[5]) ?? 0
            out[key] = c
        }
        guard !out.isEmpty else { throw BadFile() }
        return out
    }
}

@MainActor
final class BackupManager: ObservableObject {
    static let shared = BackupManager()

    @Published var auto: Bool { didSet { defaults.set(auto, forKey: "backup.auto") } }
    @Published private(set) var folderName: String?
    @Published private(set) var lastDate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var kept = 0
    @Published private(set) var working = false

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "backup.folderBookmark"
    static let keep = 3
    static let prefix = "VoltTime_backup_"

    private init() {
        auto = defaults.object(forKey: "backup.auto") as? Bool ?? true
        folderName = defaults.string(forKey: "backup.folderName")
        if defaults.object(forKey: "backup.lastDate") != nil {
            lastDate = Date(timeIntervalSince1970: defaults.double(forKey: "backup.lastDate"))
        }
        kept = defaults.integer(forKey: "backup.kept")
    }

    var hasFolder: Bool { defaults.data(forKey: bookmarkKey) != nil }

    // MARK: Folder

    func setFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            lastError = "Couldn't use that folder. Try another one."
            return
        }
        defaults.set(data, forKey: bookmarkKey)
        let name = Self.displayName(url)
        defaults.set(name, forKey: "backup.folderName")
        folderName = name
        lastError = nil
    }

    private func folderURL() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale {
            let ok = url.startAccessingSecurityScopedResource()
            if let fresh = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
            if ok { url.stopAccessingSecurityScopedResource() }
        }
        return url
    }

    private static func displayName(_ url: URL) -> String {
        let path = url.path
        if path.contains("com~apple~CloudDocs") { return "iCloud Drive › " + url.lastPathComponent }
        if path.contains("/File Provider Storage/") || path.contains("/Containers/Shared/AppGroup/") { return "On My iPhone › " + url.lastPathComponent }
        return url.lastPathComponent
    }

    // MARK: Back up

    /// Called each time the app opens, after the energy refresh.
    func autoBackup(_ store: EnergyStore) async {
        guard auto, hasFolder, !store.curves.isEmpty else { return }
        await backUp(store)
    }

    func backUp(_ store: EnergyStore) async {
        guard !working else { return }
        guard let folder = folderURL() else {
            lastError = "Choose a backup folder first."
            return
        }
        working = true
        defer { working = false }
        let curves = store.curves
        let data = await Task.detached(priority: .utility) { Data(EnergyCSV.backup(curves).utf8) }.value
        let name = Self.prefix + EnergyStore.keyFormatter.string(from: Date()) + ".csv"
        let prefix = Self.prefix, keep = Self.keep

        let result: (error: String?, kept: Int) = await Task.detached(priority: .utility) {
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            var writeError: Error?
            coordinator.coordinate(writingItemAt: folder.appendingPathComponent(name), options: .forReplacing, error: &coordError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let e = writeError ?? coordError { return (e.localizedDescription, 0) }

            // Keep the newest 3 (iCloud may list files it hasn't downloaded as ".name.icloud").
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            func plainName(_ u: URL) -> String {
                var n = u.lastPathComponent
                if n.hasPrefix("."), n.hasSuffix(".icloud") { n = String(n.dropFirst().dropLast(7)) }
                return n
            }
            let backups = files.filter { plainName($0).hasPrefix(prefix) && plainName($0).hasSuffix(".csv") }
                .sorted { plainName($0) > plainName($1) }
            for old in backups.dropFirst(keep) {
                coordinator.coordinate(writingItemAt: old, options: .forDeleting, error: nil) { url in
                    try? FileManager.default.removeItem(at: url)
                }
            }
            return (nil, min(backups.count, keep))
        }.value

        if let e = result.error {
            lastError = "Backup failed: \(e)"
        } else {
            lastError = nil
            lastDate = Date()
            kept = result.kept
            defaults.set(lastDate!.timeIntervalSince1970, forKey: "backup.lastDate")
            defaults.set(kept, forKey: "backup.kept")
        }
    }

    // MARK: Daily totals (shared, not kept)

    func dailyTotalsFile(_ store: EnergyStore) async -> URL? {
        let curves = store.curves
        let text = await Task.detached(priority: .utility) { EnergyCSV.daily(curves) }.value
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoltTime_daily_" + EnergyStore.keyFormatter.string(from: Date()) + ".csv")
        do { try Data(text.utf8).write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    // MARK: Restore

    static func read(_ url: URL) async throws -> [String: DayCurve] {
        try await Task.detached(priority: .userInitiated) {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            var coordError: NSError?
            var text: String?
            var readError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
                do { text = try String(contentsOf: u, encoding: .utf8) } catch { readError = error }
            }
            if let e = readError ?? coordError { throw e }
            return try EnergyCSV.parse(text ?? "")
        }.value
    }
}

/// iPhone share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct PendingRestore: Identifiable {
    let curves: [String: DayCurve]
    let fileName: String
    var id: String { fileName }
}
