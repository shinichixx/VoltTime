import SwiftUI
import UniformTypeIdentifiers
import AppleArchive
import System
import UserNotifications

// Backup the Pinggan way: ONE file (Apple Archive, lzfse) with the energy days and the settings, saved where you
// choose with iOS's "save a file" screen (iCloud Drive › VoltTime). A weekly reminder nudges you to save one.
// On the iPhone: a compressed copy each day (last 3) and one before every restore, in Application Support/Snapshots,
// left out of iCloud backups. Restore also reads the CSV backups of builds 24–29.

/// Where the app keeps its own data.
enum AppData {
    static var support: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var energy: URL { support.appendingPathComponent("energy.plist") }

    /// Settings that go into a backup (the Home Assistant token stays in the Keychain, never in a file).
    private static let settingPrefixes = ["home.", "sim.", "pub.", "energy.period", "impact.period", "backupReminder", HAClient.urlKey]

    static func settingsData() -> Data? {
        let all = UserDefaults.standard.dictionaryRepresentation()
        let mine = all.filter { k, _ in settingPrefixes.contains { k.hasPrefix($0) } }
        return try? PropertyListSerialization.data(fromPropertyList: mine, format: .binary, options: 0)
    }

    @discardableResult
    static func applySettings(_ data: Data) -> Int {
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return 0 }
        var n = 0
        for (k, v) in dict where settingPrefixes.contains(where: { k.hasPrefix($0) }) {
            UserDefaults.standard.set(v, forKey: k)
            n += 1
        }
        return n
    }
}

/// What a backup or snapshot file holds once unpacked.
struct BackupContents {
    var curves: [String: DayCurve]
    var settings: Data?
}

enum VoltArchive {
    static let ext = "aar"
    static let type = UTType(filenameExtension: "aar") ?? .data

    struct BadFile: LocalizedError {
        var errorDescription: String? { "That isn't a VoltTime backup." }
    }

    /// Packs energy.plist and settings.plist into one compressed file at `out`.
    static func make(at out: URL) throws {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        if fm.fileExists(atPath: AppData.energy.path) {
            try fm.copyItem(at: AppData.energy, to: stage.appendingPathComponent("energy.plist"))
        }
        if let s = AppData.settingsData() { try s.write(to: stage.appendingPathComponent("settings.plist")) }

        try? fm.removeItem(at: out)
        guard let fileStream = ArchiveByteStream.fileStream(path: FilePath(out.path), mode: .writeOnly,
                                                            options: [.create], permissions: FilePermissions(rawValue: 0o644)),
              let compressStream = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: fileStream),
              let encodeStream = ArchiveStream.encodeStream(writingTo: compressStream),
              let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MTM") else {
            throw CocoaError(.fileWriteUnknown)
        }
        var failure: Error?
        do { try encodeStream.writeDirectoryContents(archiveFrom: FilePath(stage.path), keySet: keySet) } catch { failure = error }
        try? encodeStream.close()
        try? compressStream.close()
        try? fileStream.close()
        if let failure { throw failure }
    }

    /// Unpacks a backup or snapshot (security-scoped URLs are handled here).
    static func read(_ file: URL) throws -> BackupContents {
        let fm = FileManager.default
        let ok = file.startAccessingSecurityScopedResource()
        defer { if ok { file.stopAccessingSecurityScopedResource() } }
        let dest = fm.temporaryDirectory.appendingPathComponent("unpack-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dest) }
        guard let readStream = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .readOnly,
                                                            options: [], permissions: FilePermissions(rawValue: 0o644)),
              let decompressStream = ArchiveByteStream.decompressionStream(readingFrom: readStream),
              let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressStream),
              let extractStream = ArchiveStream.extractStream(extractingTo: FilePath(dest.path),
                                                              flags: [.ignoreOperationNotPermitted]) else {
            throw BadFile()
        }
        var failure: Error?
        do { _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream) } catch { failure = error }
        try? extractStream.close()
        try? decodeStream.close()
        try? decompressStream.close()
        try? readStream.close()
        if failure != nil { throw BadFile() }

        let energy = (try? Data(contentsOf: dest.appendingPathComponent("energy.plist"))).flatMap { StoreFile.curves(from: $0) }
        let settings = try? Data(contentsOf: dest.appendingPathComponent("settings.plist"))
        guard energy != nil || settings != nil else { throw BadFile() }
        return BackupContents(curves: energy ?? [:], settings: settings)
    }

    /// A VoltTime backup of either kind: .aar (build 30 on) or the older CSV.
    static func readAny(_ file: URL) throws -> BackupContents {
        if file.pathExtension.lowercased() == "csv" || file.pathExtension.lowercased() == "txt" {
            let ok = file.startAccessingSecurityScopedResource()
            defer { if ok { file.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: file, encoding: .utf8)
            return BackupContents(curves: try EnergyCSV.parse(text), settings: nil)
        }
        return try read(file)
    }

    static func stamp(_ d: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: d)
    }
}

// MARK: - Local snapshots (on this iPhone, left out of iCloud backups)

struct Snapshot: Identifiable {
    let url: URL
    let date: Date
    let beforeRestore: Bool
    let bytes: Int64
    var id: String { url.lastPathComponent }
}

/// One compressed copy a day (last 3) plus one taken before every restore (last 1).
/// Each is a few hundred KB at most, so together they stay well under 4× the data.
enum Snapshots {
    static let keepDaily = 3
    static let keepSafety = 1
    private static let dailyPrefix = "daily-"
    private static let safetyPrefix = "before-restore-"

    static var folder: URL {
        var u = AppData.support.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
        return u
    }

    static func takeDailyIfNeeded() {
        guard FileManager.default.fileExists(atPath: AppData.energy.path) else { return }
        let today = String(VoltArchive.stamp().prefix(10))
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard !names.contains(where: { $0.hasPrefix(dailyPrefix + today) }) else { return }
        take(dailyPrefix, keep: keepDaily)
    }

    static func safetyCopy() {
        take(safetyPrefix, keep: keepSafety)
    }

    private static func take(_ prefix: String, keep: Int) {
        let dir = folder
        try? VoltArchive.make(at: dir.appendingPathComponent(prefix + VoltArchive.stamp() + "." + VoltArchive.ext))
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .sorted(by: >)
        for n in names.dropFirst(keep) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
    }

    static func list() -> [Snapshot] {
        let dir = folder
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.compactMap { u -> Snapshot? in
            var n = u.deletingPathExtension().lastPathComponent
            let safety = n.hasPrefix(safetyPrefix)
            if safety { n.removeFirst(safetyPrefix.count) } else if n.hasPrefix(dailyPrefix) { n.removeFirst(dailyPrefix.count) } else { return nil }
            guard let d = f.date(from: n) else { return nil }
            let size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return Snapshot(url: u, date: d, beforeRestore: safety, bytes: size)
        }
        .sorted { $0.date > $1.date }
    }
}

// MARK: - Weekly reminder

enum BackupReminder {
    static let enabledKey = "backupReminder.on"
    static let weekdayKey = "backupReminder.weekday"    // 1 = Sunday … 7 = Saturday
    static let minutesKey = "backupReminder.minutes"    // minutes after midnight
    private static let id = "volttime-weekly-backup"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [enabledKey: true, weekdayKey: 1, minutesKey: 21 * 60])
    }

    static func apply() async {
        let d = UserDefaults.standard
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard d.bool(forKey: enabledKey) else { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Back up VoltTime"
        content.body = "Save this week's energy data to iCloud Drive."
        content.sound = .default
        var when = DateComponents()
        when.weekday = max(1, min(7, d.integer(forKey: weekdayKey)))
        when.hour = d.integer(forKey: minutesKey) / 60
        when.minute = d.integer(forKey: minutesKey) % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

enum EnergyCSV {
    static let header = "start,step_min,solar_kwh,grid_import_kwh,grid_export_kwh,model3_kwh"

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

    @Published private(set) var lastDate: Date?
    @Published private(set) var lastBytes: Int64 = 0
    @Published private(set) var working = false
    @Published var status: String?

    private let defaults = UserDefaults.standard

    private init() {
        if defaults.object(forKey: "backup.savedDate") != nil {
            lastDate = Date(timeIntervalSince1970: defaults.double(forKey: "backup.savedDate"))
            lastBytes = Int64(defaults.integer(forKey: "backup.savedBytes"))
        }
    }

    /// Due when nothing was saved in the last 7 days.
    var isDue: Bool {
        guard let d = lastDate else { return true }
        return Date().timeIntervalSince(d) > 7 * 86_400
    }

    var lastText: String {
        guard let d = lastDate else { return "Not saved yet" }
        if Calendar.current.isDateInToday(d) { return "Today " + d.formatted(date: .omitted, time: .shortened) }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d),
                                                    to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return days == 1 ? "Yesterday" : "\(days) days ago"
    }

    /// One line for the Settings row.
    var summary: String { lastDate == nil ? "Not saved yet" : "Saved to iCloud · " + lastText.lowercased() }
    var summaryColor: Color { isDue ? Theme.orange : TSurface.green }

    // MARK: Save

    func save() {
        guard !working else { return }
        working = true
        status = "Packing…"
        Task {
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("VoltTime-backup-" + VoltArchive.stamp() + "." + VoltArchive.ext)
            let made: Result<Int64, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    try VoltArchive.make(at: out)
                    return .success(Int64((try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
                } catch { return .failure(error) }
            }.value
            switch made {
            case .failure(let e):
                working = false
                status = "The backup file couldn't be made: \(e.localizedDescription)"
            case .success(let bytes):
                status = nil
                SystemSheets.shared.export(out) { [weak self] saved in
                    guard let self else { return }
                    self.working = false
                    try? FileManager.default.removeItem(at: out)
                    guard saved != nil else { self.status = "Not saved."; return }
                    let now = Date()
                    self.lastDate = now
                    self.lastBytes = bytes
                    self.defaults.set(now.timeIntervalSince1970, forKey: "backup.savedDate")
                    self.defaults.set(Int(bytes), forKey: "backup.savedBytes")
                    self.status = "Backup saved."
                    Self.removeOldCSVBackups()
                }
            }
        }
    }

    /// Builds 24–29 wrote CSV backups into On My iPhone › VoltTime. Once a real backup is saved they go.
    static func removeOldCSVBackups() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for u in (try? fm.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
        where u.lastPathComponent.hasPrefix("VoltTime_backup_") && u.pathExtension == "csv" {
            try? fm.removeItem(at: u)
        }
        for k in ["backup.auto", "backup.folderBookmark", "backup.folderName", "backup.kept", "backup.lastDate"] {
            UserDefaults.standard.removeObject(forKey: k)
        }
    }

    // MARK: Files to share

    func dailyTotalsFile(_ store: EnergyStore) async -> URL? {
        let curves = store.curves
        let text = await Task.detached(priority: .utility) { EnergyCSV.daily(curves) }.value
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoltTime_daily_" + EnergyStore.keyFormatter.string(from: Date()) + ".csv")
        do { try Data(text.utf8).write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}

struct PendingRestore: Identifiable {
    let contents: BackupContents
    let name: String
    var id: String { name }
}

// MARK: - Save screen, file picker and share sheet, opened straight from UIKit

@MainActor
final class SystemSheets: NSObject, UIDocumentPickerDelegate {
    static let shared = SystemSheets()
    private var onPick: ((URL?) -> Void)?

    private static func top() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }

    /// iOS "save a file" screen. `done(nil)` = cancelled.
    func export(_ url: URL, done: @escaping (URL?) -> Void) {
        present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), done)
    }

    /// Picks one file, copied into the app first.
    func pickFile(_ types: [UTType], done: @escaping (URL?) -> Void) {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = false
        vc.shouldShowFileExtensions = true
        present(vc, done)
    }

    private func present(_ vc: UIDocumentPickerViewController, _ done: @escaping (URL?) -> Void) {
        guard let top = Self.top() else { done(nil); return }
        vc.delegate = self
        onPick = done
        top.present(vc, animated: true)
    }

    func share(_ url: URL) {
        guard let top = Self.top() else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }

    nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let first = urls.first
        Task { @MainActor in self.finish(first) }
    }

    nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ url: URL?) {
        let f = onPick
        onPick = nil
        f?(url)
    }
}

// MARK: - Backup & restore page (Settings → System)

struct BackupPage: View {
    @ObservedObject var energy: EnergyStore
    @ObservedObject var home: HomeModel
    @ObservedObject private var backup = BackupManager.shared
    @AppStorage(BackupReminder.enabledKey) private var remindOn = true
    @AppStorage(BackupReminder.weekdayKey) private var remindDay = 1
    @AppStorage(BackupReminder.minutesKey) private var remindMinutes = 21 * 60
    @State private var pending: PendingRestore?
    @State private var note: String?
    @State private var snapshots: [Snapshot] = []

    private static let weekdays = Calendar.current.weekdaySymbols   // Sunday first

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "iCloud Drive")
                Button { backup.save() } label: {
                    TRow("Save backup to iCloud Drive…", icon: "icloud.and.arrow.up", subtitle: saveLine,
                         dot: backup.summaryColor) {
                        if backup.working { ProgressView().tint(.white).scaleEffect(0.8) } else { chevron }
                    }
                }
                .buttonStyle(.plain)
                .disabled(backup.working)
                Button(action: chooseRestore) {
                    TRow("Restore from backup…", icon: "icloud.and.arrow.down", subtitle: note ?? "Pick a VoltTime backup file",
                         last: true) { chevron }
                }
                .buttonStyle(.plain)
                TFootnote(text: "One small file with every energy day and your settings. In the save screen pick iCloud Drive › VoltTime. Restore also reads the older CSV backups.")

                TCaption(text: "Reminder")
                TRow("Weekly reminder", icon: "bell") {
                    Toggle("", isOn: $remindOn).labelsHidden().tint(TSurface.green)
                }
                if remindOn {
                    TRow("Day", icon: nil) {
                        Menu {
                            ForEach(1...7, id: \.self) { d in
                                Button(Self.weekdays[d - 1]) { remindDay = d }
                            }
                        } label: {
                            Text(Self.weekdays[max(1, min(7, remindDay)) - 1])
                                .font(.system(size: 15)).foregroundStyle(TSurface.icon)
                        }
                    }
                    TRow("Time", icon: nil, last: true) {
                        DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                } else {
                    Rectangle().fill(TSurface.line).frame(height: 0.5).padding(.leading, 58).padding(.trailing, 20)
                }

                TCaption(text: "On this iPhone", trailing: snapshotTotal)
                if snapshots.isEmpty {
                    TRow("No copies yet", icon: "clock.arrow.circlepath", subtitle: "The first one is made today", last: true) { EmptyView() }
                }
                ForEach(Array(snapshots.enumerated()), id: \.element.id) { i, s in
                    Button { open(s) } label: {
                        TRow(dayText(s.date), icon: i == 0 ? "clock.arrow.circlepath" : nil,
                             subtitle: (s.beforeRestore ? "Before restore" : "Daily") + " · " + size(s.bytes),
                             last: i == snapshots.count - 1) { chevron }
                    }
                    .buttonStyle(.plain)
                }
                TFootnote(text: "A copy each day (last \(Snapshots.keepDaily)) and one before every restore. Kept only on this iPhone, left out of iCloud backups.")

                TCaption(text: "Export")
                Button {
                    Task { if let u = await backup.dailyTotalsFile(energy) { SystemSheets.shared.share(u) } }
                } label: {
                    TRow("Daily totals", icon: "tablecells", subtitle: "One row per day, for Excel or Numbers", last: true) { chevron }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Backup & restore", black: true)
        .onAppear { snapshots = Snapshots.list() }
        .onChange(of: remindOn) { _, _ in Task { await BackupReminder.apply() } }
        .onChange(of: remindDay) { _, _ in Task { await BackupReminder.apply() } }
        .onChange(of: remindMinutes) { _, _ in Task { await BackupReminder.apply() } }
        .alert(item: $pending) { p in
            Alert(title: Text("Restore from \(p.name)?"),
                  message: Text(restoreMessage(p.contents)),
                  primaryButton: .default(Text("Restore")) { restore(p) },
                  secondaryButton: .cancel())
        }
    }

    // MARK: Actions

    private func chooseRestore() {
        SystemSheets.shared.pickFile([VoltArchive.type, .commaSeparatedText, .plainText, .data]) { url in
            guard let url else { return }
            Task {
                do {
                    let c = try await Task.detached(priority: .userInitiated) { try VoltArchive.readAny(url) }.value
                    pending = PendingRestore(contents: c, name: url.lastPathComponent)
                } catch {
                    note = error.localizedDescription
                }
            }
        }
    }

    private func open(_ s: Snapshot) {
        Task {
            do {
                let c = try await Task.detached(priority: .userInitiated) { try VoltArchive.read(s.url) }.value
                pending = PendingRestore(contents: c, name: "the copy of " + dayText(s.date))
            } catch {
                note = error.localizedDescription
            }
        }
    }

    private func restore(_ p: PendingRestore) {
        Snapshots.safetyCopy()
        var parts: [String] = []
        if !p.contents.curves.isEmpty {
            let r = energy.merge(p.contents.curves)
            parts.append("\(r.added) days added, \(r.improved) improved")
        }
        if let s = p.contents.settings, AppData.applySettings(s) > 0 {
            home.reloadSettings()
            parts.append("settings back")
        }
        note = "Restored: " + (parts.isEmpty ? "nothing new" : parts.joined(separator: ", "))
        snapshots = Snapshots.list()
    }

    // MARK: Text

    private func restoreMessage(_ c: BackupContents) -> String {
        var m = "\(c.curves.count) days of energy data"
        if c.settings != nil { m += " and your settings" }
        return m + ". A copy of what's on the iPhone now is kept first. Days already here keep whichever copy has more detail."
    }

    private var saveLine: String {
        if let s = backup.status, s != "Backup saved." { return s }
        guard backup.lastDate != nil else { return "Not saved yet" }
        return backup.lastText + " · " + size(backup.lastBytes)
    }

    private var snapshotTotal: String {
        snapshots.isEmpty ? "" : size(snapshots.reduce(0) { $0 + $1.bytes })
    }

    private func dayText(_ d: Date) -> String {
        let t = d.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(d) { return "Today, " + t }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday, " + t }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + t
    }

    private func size(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(remindMinutes * 60)) },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                remindMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 0)
            })
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
    }
}
