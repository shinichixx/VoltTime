import SwiftUI
import ImageIO

// The "Home IM2 Kuantan" page, rebuilt from the Home Assistant Tesla dashboard (My Home view).
// Same photo scenarios, same live labels, same Energy / Impact / Settings rows and charging modes.
// The charging logic itself stays in Home Assistant (Tesla Charging – Controller automation);
// this page only reads the sensors and sets input_select.tesla_charging_mode.

enum TeslaDark {
    static let bg = Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255)          // #161718, Tesla app
    static let labelGrey = Color(red: 209 / 255, green: 209 / 255, blue: 214 / 255) // #d1d1d6
    static let rowIcon = Color(red: 154 / 255, green: 154 / 255, blue: 159 / 255)   // #9a9a9f
    static let rowLabel = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)  // #8e8e93
    static let dim = Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255)       // #6e6e73
    static let exporting = Color(red: 63 / 255, green: 185 / 255, blue: 80 / 255)  // #3fb950
    static let importing = Color(red: 1, green: 214 / 255, blue: 10 / 255)         // #ffd60a
    static let selfPowered = Color(red: 106 / 255, green: 169 / 255, blue: 1)      // #6aa9ff
    static let chargingGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255) // #34c759
    static let card = Color(white: 0.145)
}

/// Charging modes and the wording from the HA page.
struct ChargingMode: Identifiable {
    let option: String
    let title: String
    let detail: String
    var id: String { option }

    static let all: [ChargingMode] = [
        ChargingMode(option: "Off", title: "Off ⛔️", detail: "No charging at all, until you change it"),
        ChargingMode(option: "Routine", title: "Routine 🕐", detail: "Weekday nights at 32A, plus solar by day"),
        ChargingMode(option: "Excess Solar", title: "Excess Solar ☀️", detail: "Solar surplus only, never from the grid"),
        ChargingMode(option: "Fast", title: "Fast ⚡️", detail: "32A now, then back to Routine at the limit"),
    ]

    static func named(_ option: String) -> ChargingMode {
        all.first { $0.option == option } ?? ChargingMode(option: option, title: option, detail: "")
    }
}

// MARK: - Scenario photos

/// The 9 scenario photos are built into the app (Sources/Photos, ~1 MB in total).
/// Backup only: if one is missing, it is downloaded once from Home Assistant /local/ and kept on the iPhone.
enum ScenarioPhotos {
    static let numbers = Array(1...9)

    static func fileName(_ n: Int) -> String {
        numbers.contains(n) ? "tesla_home_scenario\(n).png" : "tesla_home.png"
    }

    /// Can be downloaded again, so it lives in Caches (iOS may clear it; left out of iCloud backups).
    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScenarioPhotos", isDirectory: true)
    }

    /// Builds up to 29 kept the downloaded copies in Application Support; move them to Caches.
    static func moveOldFolder() {
        let fm = FileManager.default
        let old = AppData.support.appendingPathComponent("ScenarioPhotos", isDirectory: true)
        guard fm.fileExists(atPath: old.path) else { return }
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.moveItem(at: old, to: folder)) != nil { return }
        }
        try? fm.removeItem(at: old)
    }

    private static func localURL(_ name: String) -> URL? {
        // Built into the app: Sources/Photos/tesla_home_scenarioN.jpg (shrunk to iPhone width).
        let base = (name as NSString).deletingPathExtension
        if let u = Bundle.main.url(forResource: base, withExtension: "jpg") { return u }
        if let u = Bundle.main.url(forResource: name, withExtension: nil) { return u }
        let u = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    static var savedCount: Int { numbers.filter { localURL(fileName($0)) != nil }.count }

    static func load(_ n: Int) -> UIImage? {
        guard let u = localURL(fileName(n)), let d = try? Data(contentsOf: u) else { return nil }
        return decode(d)
    }

    /// Downloads one photo from Home Assistant and keeps it.
    @discardableResult
    static func download(_ n: Int, ha: HAClient) async throws -> Data {
        let name = fileName(n)
        let d = try await ha.data("/local/\(name)")
        guard decode(d, maxPixels: 64) != nil else { throw APIError(message: "\(name) in /config/www isn't a picture") }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try d.write(to: folder.appendingPathComponent(name), options: .atomic)
        return d
    }

    /// Fetches any photo not yet on the phone. Returns how many of the 9 are saved.
    static func fetchMissing(ha: HAClient) async -> Int {
        for n in numbers where localURL(fileName(n)) == nil {
            _ = try? await download(n, ha: ha)
        }
        return savedCount
    }

    static func clear() { try? FileManager.default.removeItem(at: folder) }

    /// Decodes at screen size (the originals are 1792×2400).
    static func decode(_ data: Data, maxPixels: Int = 1800) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Model

@MainActor
final class MyHomeModel: ObservableObject {
    @Published var solarW: Double?
    @Published var gridW: Double?
    @Published var carW: Double?
    @Published var soc: Double?
    @Published var connected = false
    @Published var charging = false
    @Published var chargeAmps: Double?      // setting in the car (Tessie)
    @Published var currentNow: Double?      // what the Wall Connector delivers now
    @Published var chargeLimit: Double?
    @Published var scenario = 0
    @Published var dailyYield: Double?
    @Published var selfPowered: Double?
    @Published var importToday: Double?
    @Published var exportToday: Double?
    @Published var mode: String?
    @Published var modeOptions: [String] = ChargingMode.all.map(\.option)
    @Published var pendingMode: String?
    @Published var message: String?
    @Published var photo: UIImage?
    @Published var photoNumber = -1
    /// The photo being faded out, kept fully visible underneath so the cross-fade never dips to dark.
    @Published var previousPhoto: UIImage?
    static let fadeSeconds = 1.0
    @Published var loaded = false

    private var downloading = Set<Int>()
    private var prefetched = false

    func refresh() async {
        guard let ha = HAClient.configured() else {
            message = "Set up Home Assistant first: Home tab → gear."
            return
        }
        let s = await ha.states([Entity.solarPower, Entity.gridPower, Entity.carPower, Entity.battery, Entity.plugged,
                                 Entity.wallConnectorStatus, Entity.wallConnectorAmps, Entity.scenario, Entity.dailyYield,
                                 Entity.selfPowered, Entity.importToday, Entity.exportToday, Entity.chargingMode,
                                 Entity.chargeCurrent, Entity.limit])
        if s.isEmpty {
            message = "Can't reach Home Assistant. Check Tailscale, or the URL and token in Settings."
            return
        }
        message = nil
        solarW = s[Entity.solarPower]?.number
        gridW = s[Entity.gridPower]?.number
        carW = s[Entity.carPower]?.number
        soc = s[Entity.battery]?.number
        connected = s[Entity.plugged]?.isOn ?? false
        charging = (s[Entity.wallConnectorStatus]?.state.lowercased() ?? "") == "charging"
        chargeAmps = s[Entity.chargeCurrent]?.number
        currentNow = s[Entity.wallConnectorAmps]?.number
        chargeLimit = s[Entity.limit]?.number
        dailyYield = s[Entity.dailyYield]?.number
        importToday = s[Entity.importToday]?.number
        exportToday = s[Entity.exportToday]?.number
        selfPowered = s[Entity.selfPowered]?.number ?? localSelfPowered
        if let m = s[Entity.chargingMode], m.isAvailable {
            mode = m.state
            if let opts = m.attributes["options"] as? [String], !opts.isEmpty { modeOptions = opts }
        }
        let n = Int(s[Entity.scenario]?.number ?? 0)
        scenario = ScenarioPhotos.numbers.contains(n) ? n : localScenario(amps: s[Entity.wallConnectorAmps]?.number ?? 0)
        loaded = true
        await showPhoto(scenario, ha: ha)
    }

    /// Same formula as the "Tesla Home Scenario" template sensor, used only if that sensor is missing.
    private func localScenario(amps: Double) -> Int {
        let solar = solarW ?? 0, grid = gridW ?? 0
        let k = (connected && amps >= 5) ? 1 : (connected ? 2 : 3)
        let export = grid < -100 || (grid <= 100 && [4, 5, 6].contains(scenario))
        return solar > 50 ? k + (export ? 3 : 0) : 6 + k
    }

    /// Same formula as the "Self Powered Today" template sensor.
    private var localSelfPowered: Double? {
        guard let y = dailyYield, let i = importToday, let e = exportToday else { return nil }
        let load = y + i - e
        return load > 0 ? min(100, max(0, 100 * (1 - i / load))).rounded() : 0
    }

    private func showPhoto(_ n: Int, ha: HAClient) async {
        if n != photoNumber || photo == nil {
            if let img = ScenarioPhotos.load(n) {
                crossFade(to: img, number: n)
            } else if !downloading.contains(n) {
                downloading.insert(n)
                defer { downloading.remove(n) }
                if let d = try? await ScenarioPhotos.download(n, ha: ha), let img = ScenarioPhotos.decode(d), n == scenario {
                    crossFade(to: img, number: n)
                }
            }
        }
        if !prefetched {
            prefetched = true
            Task { _ = await ScenarioPhotos.fetchMissing(ha: ha) }
        }
    }

    /// New photo fades in on top of the old one, then the old one is dropped.
    private func crossFade(to img: UIImage, number n: Int) {
        previousPhoto = photo
        withAnimation(.easeInOut(duration: Self.fadeSeconds)) {
            photo = img
            photoNumber = n
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((Self.fadeSeconds + 0.3) * 1_000_000_000))
            guard let self, self.photoNumber == n else { return }
            self.previousPhoto = nil
        }
    }

    func reloadPhoto() {
        photoNumber = -1
        photo = nil
        prefetched = false
    }

    func setMode(_ option: String) async {
        guard let ha = HAClient.configured(), option != mode, pendingMode == nil else { return }
        pendingMode = option
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await ha.call("input_select", "select_option", ["entity_id": Entity.chargingMode, "option": option])
            mode = option
            message = nil
        } catch {
            message = "Couldn't change the charging mode: \(error.localizedDescription)"
        }
        pendingMode = nil
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refresh()
    }

    // MARK: Display text (same rules as the button-card JavaScript)

    static func kw(_ w: Double?) -> String {
        let k = abs(w ?? 0) / 1000
        return k < 0.05 ? "0" : String(format: "%.1f", k)
    }

    var status: (text: String, color: Color) {
        let g = gridW ?? 0
        if g < -100 { return ("Exporting", TeslaDark.exporting) }
        if g > 100 { return ("Importing", TeslaDark.importing) }
        return ("Self-powered", TeslaDark.selfPowered)
    }

    /// House load excluding the car.
    var homeW: Double { max((solarW ?? 0) + (gridW ?? 0) - (carW ?? 0), 0) }
}

// MARK: - View

struct MyHomeView: View {
    @ObservedObject var model: MyHomeModel
    @Binding var path: [Route]
    /// `.page` is the swiped page (title, rows). The house photo (`.backdrop`) and its power figures (`.labels`)
    /// are drawn behind / above the pager by ContentView, so they stay put and fade instead of sliding.
    enum Layer { case page, backdrop, labels }
    var layer: Layer = .page
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var fx: PagerFX
    @State private var scroll: CGFloat = 0
    @AppStorage(ProductNames.homeKey) private var homeName = ""

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let height = w * 2400 / 1792 + 20
            switch layer {
            case .backdrop:
                backdrop(width: w, height: height).compositingGroup()
                    .onAppear { fx.homePhotoTop = geo.frame(in: .global).minY }
                    .onChange(of: geo.frame(in: .global).minY) { _, v in fx.homePhotoTop = v }
            case .labels:
                labels(width: w).compositingGroup()
            case .page:
                page(width: w, height: height, screen: geo.size.height, px: geo.frame(in: .global).minX)
            }
        }
    }

    private func page(width w: CGFloat, height: CGFloat, screen: CGFloat, px: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Color.clear
                .onAppear { if !fx.pagerDriven { fx.homeX = px } }
                .onChange(of: px) { _, v in if !fx.pagerDriven { fx.homeX = v } }
                .onChange(of: scroll) { _, v in fx.homeScroll = v }

            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { g in
                        Color.clear.preference(key: ScrollY.self, value: -g.frame(in: .named("home")).minY)
                    }
                    .frame(height: 0)
                    photoTapAreas(width: w, height: height)
                    rows
                }
                // Exactly one screen tall: the rows only bounce, and always spring back to where they were.
                .frame(height: screen, alignment: .top)
            }
            .coordinateSpace(name: "home")
            .modifier(TrackScroll(y: $scroll))
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always)
            .mask(   // rows fade out softly as they reach the title
                VStack(spacing: 0) {
                    Color.clear.frame(height: 92)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                    Color.black
                }
            )
            .ignoresSafeArea(.container, edges: .bottom)

            header(width: w)
        }
        .task(id: phase) {
            // Live while the page is on screen, like the HA card (every 5 s).
            guard phase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // MARK: Opening Energy / Impact

    /// Every way into Energy and Impact from My Home starts on Day / Today, whatever was last picked there.
    /// (The pages are new each time, so their date is already today.)
    private func openEnergy(_ c: EnergyComponent? = nil) {
        UserDefaults.standard.set(ImpactPeriod.day.rawValue, forKey: "energy.period")
        path.append(c.map { Route.energyView($0) } ?? .energy)
    }

    private func openImpact() {
        UserDefaults.standard.set(ImpactPeriod.day.rawValue, forKey: "impact.period")
        path.append(.impact)
    }

    /// The empty space over the house: a tap on the car, a solar roof, a window or the grid wire opens that
    /// Energy view. It's part of the scrolling page (under the figures), so swiping across it still changes page.
    private func photoTapAreas(width w: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .overlay {
                GeometryReader { g in
                    // The photo is drawn behind the pager and doesn't move, so place the areas by screen position.
                    let top = (fx.homePhotoTop ?? g.frame(in: .global).minY) + Self.photoY - g.frame(in: .global).minY
                    let areas = HouseTapAreas(photo: model.photoNumber, width: w, top: top)
                    Color.clear
                        .contentShape(areas.shape)
                        .onTapGesture(coordinateSpace: .local) { p in
                            if let c = areas.component(at: p) { openEnergy(c) }
                        }
                }
            }
    }

    // MARK: Picture with live labels

    /// Where the house photo (with its figures and flow streaks) sits under the title; the rows don't move.
    /// 17 pt lower than build 79, so Exporting → Wall Connector and GRID → Energy are both 40 pt.
    static let photoY: CGFloat = 12

    private func backdrop(width w: CGFloat, height: CGFloat) -> some View {
        let bg = TeslaDark.bg
        return ZStack(alignment: .topLeading) {
            bg
            photo(width: w)
                // The photo's own top and bottom fade into the page, so it never ends in a hard line.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.07),
                                             .init(color: .black, location: 0.80), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .offset(y: Self.photoY)
            PowerFlowOverlay(model: model, width: w)   // moving pulses along the wires
                .offset(y: Self.photoY)
            // Fade under the title (0–250 pt), then fade the bottom into the rows.
            LinearGradient(stops: [
                .init(color: bg, location: 0),
                .init(color: bg, location: 34.0 / 250),
                .init(color: bg.opacity(0.78), location: 80.0 / 250),
                .init(color: bg.opacity(0.5), location: 130.0 / 250),
                .init(color: bg.opacity(0.2), location: 190.0 / 250),
                .init(color: bg.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(width: w, height: 250)
            LinearGradient(stops: [
                .init(color: bg, location: 0),
                .init(color: bg.opacity(0.75), location: 0.10),
                .init(color: bg.opacity(0.35), location: 0.22),
                .init(color: bg.opacity(0), location: 0.34),
            ], startPoint: .bottom, endPoint: .top)
            .frame(width: w, height: height)
        }
        .frame(width: w, height: height)
        .clipped()
    }

    private func header(width w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text(ProductNames.shown(homeName, or: ProductNames.homeDefault))
                .font(.app(size: PageTitle.size, weight: .semibold))
                .kerning(PageTitle.kerning)
                .foregroundStyle(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 1)
                .frame(height: 32)
                .padding(.leading, w * 0.07 + PageTitle.inset)
                .padding(.trailing, 60)
                .padding(.top, PageTitle.top)

            // ☰ (Tesla app, top right): My Home settings and backup. Same spot as on My Car.
            HStack {
                Spacer()
                Button { path.append(.menu) } label: { MenuGlyph() }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 1)
                    .accessibilityLabel("My Home settings")
            }
            .padding(.trailing, 17.5)
            .frame(width: w, alignment: .trailing)
            .padding(.top, 24 + 16 - 23)

            Text(model.loaded ? model.status.text : " ")
                .font(.app(size: 15))
                .foregroundStyle(model.status.color)
                .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 1)
                .padding(.leading, w * 0.07 + PageTitle.inset)
                .padding(.top, 54)
        }
        .frame(width: w, alignment: .topLeading)
    }

    private func labels(width w: CGFloat) -> some View {
        let labelY = Self.photoY + w * 0.2812
        return ZStack(alignment: .topLeading) {
            Color.clear
            anchored(x: w * 0.2901, y: labelY, bottom: true) {
                // Each figure opens its own graph on the Energy page (Tesla app).
                Button { openEnergy(.vehicle) } label: {
                    carLabel
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, -8)
            }
            anchored(x: w * 0.5064 + 12, y: labelY, bottom: true) {
                Button { openEnergy(.solar) } label: {
                    FlowLabel(title: "SOLAR", value: Text("\(MyHomeModel.kw(model.solarW)) kW"))
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -8)
            }
            anchored(x: w * 0.7863, y: labelY, bottom: true) {
                Button { openEnergy(.home) } label: {
                    FlowLabel(title: "HOME", value: Text("\(MyHomeModel.kw(model.homeW)) kW"))
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -8)
            }
            anchored(x: w * 0.7947, y: Self.photoY + w * 1.20, bottom: false) {
                Button { openEnergy(.grid) } label: {
                    FlowLabel(title: "GRID", value: Text("\(MyHomeModel.kw(model.gridW)) kW"))
                        .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -8)
            }
        }
        .frame(width: w, height: w * 2400 / 1792 + 20, alignment: .topLeading)
    }

    @ViewBuilder private func photo(width w: CGFloat) -> some View {
        if let img = model.photo {
            ZStack(alignment: .top) {
                // Old scenario stays solid underneath while the new one fades in over it.
                if let prev = model.previousPhoto {
                    Image(uiImage: prev)
                        .resizable()
                        .scaledToFit()
                        .frame(width: w)
                }
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w)
                    .id(model.photoNumber)
                    .transition(.opacity)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "house.fill").font(.system(size: 64)).foregroundStyle(Color.white.opacity(0.08))
                if model.loaded {
                    Text("Loading photo from Home Assistant…").font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                }
            }
            .frame(width: w, height: w * 2400 / 1792)
        }
    }

    private var carLabel: some View {
        let value: Text
        if model.connected {
            var t = Text("\(MyHomeModel.kw(model.carW)) kW")
            if let soc = model.soc {
                if model.charging {
                    t = t + Text("  ")
                        + Text(Image(systemName: "arrowtriangle.up.fill")).font(.system(size: 7)).foregroundColor(TeslaDark.chargingGreen).baselineOffset(1)
                        + Text(" \(Int(soc))%")
                } else {
                    t = t + Text(" · \(Int(soc))%")
                }
            }
            value = t
        } else {
            value = Text("Idle")
        }
        return FlowLabel(title: model.connected ? "MODEL 3" : "WALL CONNECTOR", value: value)
    }

    /// Puts a label so its bottom-centre (or top-centre) sits on the point, like translate(-50%, -100%).
    private func anchored<V: View>(x: CGFloat, y: CGFloat, bottom: Bool, @ViewBuilder _ content: () -> V) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .overlay(alignment: bottom ? .bottom : .top) { content().fixedSize() }
            .position(x: x, y: y)
    }

    // MARK: Rows

    private var rows: some View {
        VStack(spacing: 0) {
            TeslaRow(icon: AnyView(EnergyGlyph(size: 24)), name: "Energy",
                     label: model.dailyYield.map { String(format: "%.1f kWh Generated Today", $0) } ?? "Generated Today") {
                openEnergy()
            }
            TeslaRow(icon: AnyView(ImpactGlyph(size: 24)), name: "Impact",
                     label: model.selfPowered.map { "\(Int($0.rounded()))% Self-Powered Today" } ?? "Self-Powered Today") {
                openImpact()
            }
            TeslaRow(icon: AnyView(GearGlyph(size: 24)), name: "Settings", label: nil) {
                path.append(.settings)
            }
            if let msg = model.message {
                Text(msg)
                    .font(.app(size: 12))
                    .foregroundStyle(TeslaDark.importing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
            }
            Spacer(minLength: 44) // room for the page dots
        }
    }
}

/// Small grey caption over a white value, with the photo's text shadow.
struct FlowLabel: View {
    let title: String
    let value: Text

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.app(size: 9))
                .kerning(0.3)
                .foregroundStyle(TeslaDark.labelGrey)
            value
                .font(.app(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white) // view-level, so the green charging arrow keeps its colour
        }
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.65), radius: 3, x: 0, y: 1)
    }
}

/// Icon on the left, white name over a grey label, chevron on the right (Tesla app's Home rows).
struct TeslaRow: View {
    let icon: AnyView
    let name: String
    let label: String?
    var action: (() -> Void)?

    var body: some View {
        GeometryReader { g in
            if let action {
                Button(action: action) { content(g.size.width) }
                    .buttonStyle(.plain)
            } else {
                content(g.size.width)
            }
        }
        .frame(height: 64)
    }

    private func content(_ width: CGFloat) -> some View {
        HStack(spacing: 0) {
            icon
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.app(size: 16, weight: .semibold)).foregroundStyle(.white)
                if let label {
                    Text(label).font(.app(size: 12, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .regular)).foregroundStyle(TeslaDark.dim)
        }
        .padding(.horizontal, width * 0.07)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
