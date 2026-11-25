import SwiftUI
import UIKit

// Auto-cleanup of old backups in the iCloud Drive folder: after every saved backup only the newest N stay
// (default 3). The app can only touch that folder after you pick it once (iOS keeps a bookmark to it).

struct BackupFile: Identifiable {
    let name: String      // TesLah-backup-2026-11-25_13-22.aar
    let url: URL
    let stamp: String     // 2026-11-25_13-22: same format in TesLah and the older VoltTime backups
    var id: String { name }
    var shortName: String {
        let base = name.replacingOccurrences(of: ".aar", with: "")
        guard let r = base.range(of: "-backup-") else { return base }
        return String(base[..<r.lowerBound]) + " " + String(base[r.upperBound...]).replacingOccurrences(of: "_", with: " ")
    }
}

@MainActor
final class BackupCleanup: ObservableObject {
    static let shared = BackupCleanup()

    static let onKey = "backup.cleanup.on"
    static let keepKey = "backup.cleanup.keep"
    static let oldKey = "backup.cleanup.includeOld"
    private static let bookmarkKey = "backup.cleanup.bookmark"
    private static let nameKey = "backup.cleanup.folderName"

    @Published private(set) var folderName: String?
    @Published private(set) var files: [BackupFile] = []   // newest first
    @Published private(set) var problem: String?

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [Self.onKey: true, Self.keepKey: 3, Self.oldKey: true])
        folderName = defaults.data(forKey: Self.bookmarkKey) == nil ? nil : defaults.string(forKey: Self.nameKey)
    }

    var hasFolder: Bool { defaults.data(forKey: Self.bookmarkKey) != nil }
    var keep: Int { max(1, min(10, defaults.integer(forKey: Self.keepKey))) }
    var includeOld: Bool { defaults.bool(forKey: Self.oldKey) }
    var enabled: Bool { defaults.bool(forKey: Self.onKey) }

    // MARK: Folder

    /// iOS "Open" screen for one folder. `start` is where it opens (the folder the last backup went to).
    func chooseFolder(start: URL? = nil) {
        SystemSheets.shared.pickFolder(start: start) { [weak self] url in
            guard let self, let url else { return }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                self.defaults.set(data, forKey: Self.bookmarkKey)
                self.defaults.set(url.lastPathComponent, forKey: Self.nameKey)
                self.folderName = url.lastPathComponent
                self.problem = nil
            } catch {
                self.problem = "That folder couldn't be kept: \(error.localizedDescription)"
                return
            }
            Task { await self.refresh() }
        }
    }

    private nonisolated static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    // MARK: Listing

    /// Real file name, also for iCloud files that are not downloaded yet (".name.icloud").
    private nonisolated static func realName(_ n: String) -> String {
        if n.hasPrefix("."), n.hasSuffix(".icloud") { return String(n.dropFirst().dropLast(7)) }
        return n
    }

    private nonisolated static func scan(_ folder: URL, includeOld: Bool) throws -> [BackupFile] {
        var urls: [URL] = []
        var inner: Error?
        var coordError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: folder, options: [.withoutChanges], error: &coordError) { u in
            do { urls = try FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: []) }
            catch { inner = error }
        }
        if let e = inner ?? coordError { throw e }
        var out: [BackupFile] = []
        for u in urls {
            let n = realName(u.lastPathComponent)
            guard n.hasSuffix(".aar") else { continue }
            guard n.hasPrefix("TesLah-backup-") || (includeOld && n.hasPrefix("VoltTime-backup-")) else { continue }
            guard let r = n.range(of: "-backup-") else { continue }
            let stamp = String(n[r.upperBound...].dropLast(4))
            guard stamp.count >= 16, stamp.first?.isNumber == true else { continue }   // yyyy-MM-dd_HH-mm, nothing else
            out.append(BackupFile(name: n, url: u, stamp: stamp))
        }
        return out.sorted { $0.stamp == $1.stamp ? $0.name > $1.name : $0.stamp > $1.stamp }
    }

    func refresh() async {
        guard hasFolder else { files = []; return }
        let old = includeOld
        let result: Result<[BackupFile], Error> = await Task.detached(priority: .utility) {
            guard let folder = Self.resolve() else { return .failure(CocoaError(.fileNoSuchFile)) }
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            do { return .success(try Self.scan(folder, includeOld: old)) } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let list): files = list; problem = nil
        case .failure: files = []; problem = "The backup folder can't be opened. Choose it again."
        }
    }

    // MARK: Delete

    /// Deletes everything but the newest `keep`. `justSaved` is the file name iOS just wrote: if the folder listing
    /// doesn't show it yet it still counts as one of the kept files, so a slow iCloud never costs you an extra backup.
    @discardableResult
    func cleanUp(justSaved: String? = nil) async -> Int {
        guard hasFolder else { return 0 }
        let keepN = keep
        let old = includeOld
        let saved = justSaved.map { Self.realName($0) }
        let result: Result<Int, Error> = await Task.detached(priority: .utility) {
            guard let folder = Self.resolve() else { return .failure(CocoaError(.fileNoSuchFile)) }
            let ok = folder.startAccessingSecurityScopedResource()
            defer { if ok { folder.stopAccessingSecurityScopedResource() } }
            do {
                let list = try Self.scan(folder, includeOld: old)
                var allowed = keepN
                if let saved, !list.contains(where: { $0.name == saved }) { allowed = max(0, keepN - 1) }
                var removed = 0
                for f in list.dropFirst(allowed) {
                    var err: NSError?
                    var done = false
                    NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: f.url, options: .forDeleting, error: &err) { u in
                        do { try FileManager.default.removeItem(at: u); done = true } catch {}
                    }
                    if done { removed += 1 }
                }
                return .success(removed)
            } catch { return .failure(error) }
        }.value
        await refresh()
        switch result {
        case .success(let n): return n
        case .failure: problem = "The backup folder can't be opened. Choose it again."; return 0
        }
    }

    /// After a backup was saved from the iOS Save screen.
    func afterSave(_ saved: URL?) async -> Int {
        guard enabled, hasFolder else { return 0 }
        return await cleanUp(justSaved: saved?.lastPathComponent)
    }
}
