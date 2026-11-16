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
    @Published private(set) var customFolderName: String?
    @Published private(set) var lastDate: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var kept = 0
    @Published private(set) var working = false

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "backup.folderBookmark"
    static let keep = 3
    static let prefix = "VoltTime_backup_"
    static let defaultName = "On My iPhone › VoltTime"

    /// The app's own folder, shown in the Files app as On My iPhone › VoltTime.
    static var appFolder: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    private init() {
        auto = defaults.object(forKey: "backup.auto") as? Bool ?? true
        customFolderName = defaults.data(forKey: "backup.folderBookmark") == nil ? nil : defaults.string(forKey: "backup.folderName")
        if defaults.object(forKey: "backup.lastDate") != nil {
            lastDate = Date(timeIntervalSince1970: defaults.double(forKey: "backup.lastDate"))
        }
        kept = defaults.integer(forKey: "backup.kept")
    }

    var usesCustomFolder: Bool { defaults.data(forKey: bookmarkKey) != nil }
    var folderName: String { customFolderName ?? Self.defaultName }

    /// One line for the Settings row.
    var summary: String {
        if let lastError { return lastError }
        guard auto else { return "Auto backup off" }
        return "Auto · " + lastText
    }
    var summaryColor: Color? {
        if lastError != nil { return Theme.orange }
        return auto ? TSurface.green : nil
    }
    var lastText: String {
        guard let d = lastDate else { return "not yet" }
        return Calendar.current.isDateInToday(d)
            ? "today " + d.formatted(date: .omitted, time: .shortened)
            : d.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Folder

    func setFolder(_ url: URL) {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            do { data = try url.bookmarkData() } catch {
                lastError = "Couldn't use that folder: \(error.localizedDescription)"
                return
            }
        }
        defaults.set(data, forKey: bookmarkKey)
        let name = Self.displayName(url)
        defaults.set(name, forKey: "backup.folderName")
        customFolderName = name
        lastError = nil
    }

    func useAppFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: "backup.folderName")
        customFolderName = nil
        lastError = nil
    }

    func reportNoFolder() {
        lastError = "The picker didn't return a folder. Backups stay in \(Self.defaultName)."
    }

    private func customFolderURL() -> URL? {
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
        guard auto, !store.curves.isEmpty else { return }
        await backUp(store)
    }

    func backUp(_ store: EnergyStore) async {
        guard !working else { return }
        working = true
        defer { working = false }
        let curves = store.curves
        let data = await Task.detached(priority: .utility) { Data(EnergyCSV.backup(curves).utf8) }.value
        let name = Self.prefix + EnergyStore.keyFormatter.string(from: Date()) + ".csv"
        let prefix = Self.prefix, keep = Self.keep

        var target = customFolderURL() ?? Self.appFolder
        var result = await Self.write(data, name: name, to: target, prefix: prefix, keep: keep)
        var fellBack = false
        if result.error != nil, target != Self.appFolder {
            target = Self.appFolder
            result = await Self.write(data, name: name, to: target, prefix: prefix, keep: keep)
            fellBack = true
        }
        if let e = result.error {
            lastError = "Backup failed: \(e)"
        } else {
            lastError = fellBack ? "Couldn't write to \(folderName); saved in \(Self.defaultName)" : nil
            lastDate = Date()
            kept = result.kept
            defaults.set(lastDate!.timeIntervalSince1970, forKey: "backup.lastDate")
            defaults.set(kept, forKey: "backup.kept")
        }
    }

    private static func write(_ data: Data, name: String, to folder: URL, prefix: String, keep: Int) async -> (error: String?, kept: Int) {
        await Task.detached(priority: .utility) {
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let coordinator = NSFileCoordinator()
            var coordError: NSError?
            var writeError: Error?
            coordinator.coordinate(writingItemAt: folder.appendingPathComponent(name), options: .forReplacing, error: &coordError) { url in
                do { try data.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let e = writeError ?? coordError { return (e.localizedDescription, 0) }

            // Keep the newest few (iCloud may list files it hasn't downloaded as ".name.icloud").
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
    }

    // MARK: Files to share

    /// A fresh backup file in the temporary folder, for "Save a copy…".
    func backupCopyFile(_ store: EnergyStore) async -> URL? {
        let curves = store.curves
        let text = await Task.detached(priority: .utility) { EnergyCSV.backup(curves) }.value
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.prefix + EnergyStore.keyFormatter.string(from: Date()) + ".csv")
        do { try Data(text.utf8).write(to: url, options: .atomic) } catch { return nil }
        return url
    }

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

struct PendingRestore: Identifiable {
    let curves: [String: DayCurve]
    let fileName: String
    var id: String { fileName }
}

// MARK: - Pickers and share sheet, opened straight from UIKit (not inside a SwiftUI pop-up)

@MainActor
final class SystemSheets: NSObject, UIDocumentPickerDelegate {
    static let shared = SystemSheets()
    private var onPick: ((URL?) -> Void)?

    private static func top() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }

    /// Picks one folder or file. `onPick(nil)` = cancelled.
    func pick(_ types: [UTType], asCopy: Bool, onPick: @escaping (URL?) -> Void) {
        guard let top = Self.top() else { onPick(nil); return }
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
        vc.allowsMultipleSelection = false
        vc.shouldShowFileExtensions = true
        vc.delegate = self
        self.onPick = onPick
        top.present(vc, animated: true)
    }

    func share(_ url: URL) {
        guard let top = Self.top() else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let f = onPick
        onPick = nil
        f?(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let f = onPick
        onPick = nil
        f?(nil)
    }
}

// MARK: - Backup & restore page (Settings → Data)

struct BackupPage: View {
    @ObservedObject var energy: EnergyStore
    @ObservedObject private var backup = BackupManager.shared
    @State private var pendingRestore: PendingRestore?
    @State private var note: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Automatic")
                TRow("Auto backup", icon: "arrow.triangle.2.circlepath") {
                    Toggle("", isOn: $backup.auto).labelsHidden().tint(TSurface.green)
                }
                Button(action: chooseFolder) {
                    TRow("Backup folder", icon: "folder", subtitle: backup.folderName) { chevron }
                }
                .buttonStyle(.plain)
                if backup.usesCustomFolder {
                    Button { backup.useAppFolder() } label: {
                        TRow("Use \(BackupManager.defaultName) instead", icon: nil) { EmptyView() }
                    }
                    .buttonStyle(.plain)
                }
                TRow("Last backup", icon: nil, subtitle: lastLine,
                     dot: backup.lastError != nil ? Theme.orange : (backup.lastDate == nil ? nil : TSurface.green), last: true) {
                    if backup.working { ProgressView().tint(.white).scaleEffect(0.8) }
                }
                TFootnote(text: "To pick a folder: open it (go inside), then tap Open. Without one, backups go to \(BackupManager.defaultName) in the Files app.")

                TCaption(text: "Manual")
                Button { Task { await backup.backUp(energy) } } label: {
                    TRow("Back up now", icon: "arrow.clockwise", subtitle: "To \(backup.folderName)") { chevron }
                }
                .buttonStyle(.plain)
                .disabled(backup.working)
                Button {
                    Task { if let u = await backup.backupCopyFile(energy) { SystemSheets.shared.share(u) } }
                } label: {
                    TRow("Save a copy…", icon: "square.and.arrow.up", subtitle: "Share sheet › Save to Files › iCloud Drive") { chevron }
                }
                .buttonStyle(.plain)
                Button {
                    Task { if let u = await backup.dailyTotalsFile(energy) { SystemSheets.shared.share(u) } }
                } label: {
                    TRow("Daily totals", icon: "tablecells", subtitle: "One row per day, for Excel or Numbers") { chevron }
                }
                .buttonStyle(.plain)
                Button(action: chooseRestore) {
                    TRow("Restore from backup", icon: "square.and.arrow.down", subtitle: note, last: true) { chevron }
                }
                .buttonStyle(.plain)

                TFootnote(text: "Backs up each time the app opens, after the data refreshes. One file per day, the latest \(BackupManager.keep) days kept. After a reset: Restore from backup, then pick the newest file.")
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Backup & restore", black: true)
        .alert(item: $pendingRestore) { p in
            Alert(title: Text("Restore \(p.curves.count) days?"),
                  message: Text("From \(p.fileName). Days already on the iPhone keep whichever copy has more detail."),
                  primaryButton: .default(Text("Restore")) {
                      let r = energy.merge(p.curves)
                      note = "Restored: \(r.added) days added, \(r.improved) improved"
                  },
                  secondaryButton: .cancel())
        }
    }

    private func chooseFolder() {
        SystemSheets.shared.pick([.folder], asCopy: false) { url in
            guard let url else { return }
            backup.setFolder(url)
            Task { await backup.backUp(energy) }
        }
    }

    private func chooseRestore() {
        SystemSheets.shared.pick([.commaSeparatedText, .plainText, .text], asCopy: true) { url in
            guard let url else { return }
            Task {
                do {
                    let curves = try await BackupManager.read(url)
                    pendingRestore = PendingRestore(curves: curves, fileName: url.lastPathComponent)
                } catch {
                    note = error.localizedDescription
                }
            }
        }
    }

    private var lastLine: String {
        if let e = backup.lastError { return e }
        guard backup.lastDate != nil else { return "Not yet" }
        let t = backup.lastText
        return t.prefix(1).uppercased() + String(t.dropFirst()) + " · \(backup.kept) kept"
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
    }
}
