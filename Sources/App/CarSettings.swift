import SwiftUI

// ☰ on My Car: the car's settings and backup, one page of groups, each opening its own page.

struct CarSettingsPage: View {
    @ObservedObject var car: CarModel
    @ObservedObject var energy: EnergyStore
    @ObservedObject var home: HomeModel
    @ObservedObject private var backup = BackupManager.shared
    @AppStorage("car.gate.ask") private var gateAsk = true
    @ObservedObject private var s3xy = S3XYLink.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Connection")
                NavigationLink { TessiePage(car: car) } label: {
                    nav("Tessie", "bolt.car", car.configured ? (car.error == nil ? "Connected · \(car.car.name)" : "Can't reach Tessie · tap to check") : "Not set up · add your token",
                        dot: car.configured ? (car.error == nil ? TSurface.green : CarColors.amber) : Color(white: 0.55))
                }.buttonStyle(.plain)
                NavigationLink { S3XYPage() } label: {
                    nav("S3XY Commander", "waveform.path.ecg", s3xyLine, dot: s3xy.statusDot, last: true)
                }.buttonStyle(.plain)

                TCaption(text: "Buttons")
                NavigationLink { QuickControlsPage(car: car) } label: {
                    nav("Quick controls", "square.grid.3x2", car.controls.prefix(QuickControlsPage.slots).map(\.short).joined(separator: " · "))
                }.buttonStyle(.plain)
                NavigationLink { AutogatePage(car: car) } label: {
                    nav("Autogate", "door.garage.open", iconView: AnyView(GateGlyph(size: 20, color: TSurface.icon)), gateAsk ? "Asks before sending" : "Sends straight away · asks when away", last: true)
                }.buttonStyle(.plain)

                TCaption(text: "Data")
                NavigationLink { BackupPage(energy: energy, home: home) } label: {
                    nav("Backup", "arrow.triangle.2.circlepath", (backup.lastDate == nil ? "Not saved yet" : backup.lastText) + " · iCloud Drive",
                        dot: backup.summaryColor, last: true)
                }.buttonStyle(.plain)

                AppVersionFooter()
            }
        }
        .teslaPage("My Car", black: true)
    }

    private var s3xyLine: String {
        let wifi = "Wi-Fi " + (UserDefaults.standard.string(forKey: S3XYLink.ssidKey).flatMap { $0.isEmpty ? nil : $0 } ?? "S3XY_OBD")
        if s3xy.state == .receiving, let r = s3xy.current { return "Connected · \(Int(r.mv.rounded())) mV now" }
        return s3xy.statusWord + " · " + wifi
    }

    private func nav(_ t: String, _ icon: String, iconView: AnyView? = nil, _ sub: String, dot: Color? = nil, last: Bool = false) -> some View {
        TRow(t, icon: icon, iconView: iconView, subtitle: sub, dot: dot, last: last) {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
        }
    }
}

// MARK: Tessie

struct TessiePage: View {
    @ObservedObject var car: CarModel
    @State private var token = ""
    @State private var editing = false
    @State private var vehicles: [TessieVehicle] = []
    @State private var note: String?
    @State private var working = false
    @AppStorage(TessieClient.vinKey) private var vin = ""
    @FocusState private var focus: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Access token")
                TRow("Token", icon: "key", last: true) {
                    Group {
                        if editing || token.isEmpty {
                            SecureField("Tessie access token", text: $token)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .multilineTextAlignment(.trailing).focused($focus)
                        } else {
                            Button { editing = true; focus = true } label: {
                                HStack(spacing: 5) { Text("••••••••••").foregroundStyle(.white); Text("saved").foregroundStyle(TeslaDark.rowLabel) }
                            }.buttonStyle(.plain)
                        }
                    }
                    .font(.app(size: 14)).frame(width: 190, alignment: .trailing)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                Button { Task { await saveAndFind() } } label: {
                    HStack(spacing: 8) {
                        if working { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text("Save & find my car").font(.app(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.selected))
                }
                .buttonStyle(.plain).disabled(working)
                .padding(.horizontal, 20).padding(.top, 16)
                if let note { TFootnote(text: note, color: TeslaDark.rowLabel) }

                if !vehicles.isEmpty {
                    TCaption(text: "Car")
                    ForEach(vehicles) { v in
                        Button { vin = v.vin; Task { await car.refresh() } } label: {
                            TRow(v.name, icon: "car", subtitle: v.vin, last: v.vin == vehicles.last?.vin) {
                                if vin == v.vin { Image(systemName: "checkmark").foregroundStyle(.white) }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Text("Create a token at dash.tessie.com → Settings → Developer API → Generate Access Token. It's kept in the iPhone Keychain and never goes into backups. Reading the car uses Tessie's saved state, so opening VoltTime doesn't wake the car; only the buttons do.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20).padding(.top, 14)
            }
        }
        .teslaPage("Tessie", black: true)
        .onAppear { token = Keychain.get(TessieClient.tokenKey) ?? "" }
    }

    private func saveAndFind() async {
        focus = false; editing = false
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(t, for: TessieClient.tokenKey)
        guard !t.isEmpty else { note = "Paste your Tessie token first."; return }
        working = true; defer { working = false }
        do {
            vehicles = try await TessieClient(token: t).vehicles()
            if vin.isEmpty || !vehicles.contains(where: { $0.vin == vin }), let first = vehicles.first { vin = first.vin }
            note = vehicles.isEmpty ? "Connected, but no cars on this Tessie account." : "Connected."
            await car.refresh()
        } catch {
            note = error.localizedDescription
        }
    }
}

// MARK: Quick controls

struct QuickControlsPage: View {
    @ObservedObject var car: CarModel
    @State private var slot = 0
    @State private var askToggles: [String: Bool] = [:]
    @State private var dragging: Int?
    @State private var dragX: CGFloat = 0
    static let slots = 5
    /// These always ask (unlock, A/C on, frunk) or have their own setting (gate), so no switch.
    private let fixedAsk: Set<CarControl> = [.lock, .climate, .frunk, .gate]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Shortcut row", trailing: "\(Self.slots) buttons")
                strip
                    .padding(.horizontal, 20)
                Text("Tap a button, then pick its replacement below. Hold and drag to reorder.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 30).padding(.top, 10)

                ForEach(CarControl.Group.allCases, id: \.self) { g in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(g.rawValue.uppercased()).font(.app(size: 11, weight: .medium)).kerning(0.8)
                        Spacer()
                        Text("ASK FIRST").frame(width: 60)
                        Text("ROW").frame(width: 26)
                    }
                    .font(.app(size: 9, weight: .medium))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 6)
                    let items = CarControl.allCases.filter { $0.group == g }
                    ForEach(items) { c in
                        Button { pick(c) } label: {
                            TRow(c.title, iconView: AnyView(ControlIcon(control: c, car: car.car, size: 18, color: TSurface.icon)),
                                 subtitle: askLine(c), last: c == items.last) {
                                HStack(spacing: 0) {
                                    Group {
                                        if c == .gate {
                                            Text("Own").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                                        } else if fixedAsk.contains(c) {
                                            Text("Always").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                                        } else {
                                            Toggle("", isOn: askBinding(c)).labelsHidden().tint(TSurface.green).scaleEffect(0.75)
                                        }
                                    }
                                    .frame(width: 60)
                                    slotBadge(c).frame(width: 26)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                TFootnote(text: "Green = TesLah asks \"Are you sure?\" first. Number = slot in the row. The autogate's own setting is in My Car ☰ › Autogate.")
                Button("Reset to default") { CarControl.save(CarControl.defaults); car.reloadControls() }
                    .font(.app(size: 14)).foregroundStyle(CarColors.red).padding(.top, 16)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Quick controls", black: true)
    }

    private var row: [CarControl] { Array(car.controls.prefix(Self.slots)) }

    private var strip: some View {
        GeometryReader { geo in
            let w = geo.size.width / CGFloat(Self.slots)
            HStack(spacing: 0) {
                ForEach(row.indices, id: \.self) { i in
                    let c = row[i]
                    VStack(spacing: 4) {
                        ControlIcon(control: c, car: car.car, size: 20, color: .white).frame(height: 24)
                        Text(c.short).font(.app(size: 10)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: w - 8, height: 62)
                    .background(RoundedRectangle(cornerRadius: 12).fill(slot == i ? TSurface.selected : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(slot == i ? Color(red: 62/255, green: 106/255, blue: 225/255) : .clear, lineWidth: 1.6))
                    .scaleEffect(dragging == i ? 1.08 : 1)
                    .offset(x: dragging == i ? dragX : 0)
                    .zIndex(dragging == i ? 1 : 0)
                    .frame(width: w)
                    .contentShape(Rectangle())
                    .onTapGesture { slot = i }
                    .gesture(LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { v in
                            guard case .second(true, let drag) = v else { return }
                            if dragging == nil { dragging = i; slot = i; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                            guard let from = dragging else { return }
                            dragX = drag?.translation.width ?? 0
                            let to = min(max(from + Int((dragX / w).rounded()), 0), Self.slots - 1)
                            if to != from {
                                var list = car.controls
                                list.swapAt(from, to)
                                CarControl.save(list); car.reloadControls()
                                dragX -= CGFloat(to - from) * w
                                dragging = to; slot = to
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                        .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { dragging = nil; dragX = 0 } })
                }
            }
            .frame(maxHeight: .infinity)
            .animation(.easeOut(duration: 0.15), value: car.controls)
        }
        .frame(height: 76)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 16).fill(TSurface.field))
    }

    private func askLine(_ c: CarControl) -> String? {
        switch c {
        case .lock: return "Asks before unlocking"
        case .climate: return "Asks before turning on"
        case .frunk: return "Always asks"
        case .gate: return "Ask setting in My Car ☰ › Autogate"
        default: return nil
        }
    }

    @ViewBuilder private func slotBadge(_ c: CarControl) -> some View {
        if let i = row.firstIndex(of: c) {
            Text("\(i + 1)").font(.app(size: 12, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color(red: 62/255, green: 106/255, blue: 225/255)))
        } else {
            Circle().strokeBorder(TeslaDark.dim, lineWidth: 1.2).frame(width: 22, height: 22)
        }
    }

    private func askBinding(_ c: CarControl) -> Binding<Bool> {
        Binding(get: { askToggles[c.rawValue] ?? CarControl.asks(c) },
                set: { askToggles[c.rawValue] = $0; UserDefaults.standard.set($0, forKey: "car.confirm." + c.rawValue) })
    }

    private func pick(_ c: CarControl) {
        var list = car.controls
        if let existing = list.firstIndex(of: c) { list.swapAt(existing, slot) } else { list[slot] = c }
        CarControl.save(list); car.reloadControls()
    }
}

// MARK: Autogate

struct AutogatePage: View {
    @ObservedObject var car: CarModel
    @AppStorage("car.gate.entity") private var entity = "switch.porch_rf_controller_switch_1"
    @AppStorage("car.gate.ask") private var ask = true
    @AppStorage(CarModel.zoneKey) private var zone = "zone.home_outer"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Home Assistant")
                TRow("RF switch", icon: "dot.radiowaves.left.and.right") {
                    TextField("switch.…", text: $entity)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing).font(.app(size: 13)).foregroundStyle(.white)
                        .frame(width: 220)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                TRow("Ask before sending", icon: "questionmark.bubble") {
                    Toggle("", isOn: $ask).labelsHidden().tint(TSurface.green)
                }
                TRow("Home zone", icon: "scope",
                     subtitle: car.homeZone.map { "\($0.name) · \(Int($0.radius.rounded())) m radius" } ?? "Reading from Home Assistant…",
                     last: true) {
                    TextField("zone.…", text: $zone)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing).font(.app(size: 13)).foregroundStyle(.white)
                        .frame(width: 150)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                TFootnote(text: "The Gate button turns this switch on for 1 second, then off: one RF pulse, the same as your autogate script. With Ask before sending on, you confirm it first. If the car is outside the home zone, it always asks, and says how far away the car is. Uses the Home Assistant address and token from My Home ☰ › Home Assistant.")
            }
        }
        .teslaPage("Autogate", black: true)
        .task(id: zone) { _ = await car.loadZone() }
    }
}

/// "VoltTime · Version 1.0 (36)" and the release date, at the foot of the ☰ pages.
struct AppVersionFooter: View {
    var body: some View {
        VStack(spacing: 3) {
            Text("TesLah · " + CarModel.versionLine).foregroundStyle(TeslaDark.rowLabel)
            if !CarModel.releaseLine.isEmpty { Text(CarModel.releaseLine).foregroundStyle(TeslaDark.dim) }
        }
        .font(.app(size: 11))
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }
}

// ☰ on My Home: Home Assistant and backup.

struct HomeSettingsPage: View {
    @ObservedObject var home: HomeModel
    @ObservedObject var energy: EnergyStore
    @ObservedObject private var backup = BackupManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Connection")
                NavigationLink { HomeAssistantPage() } label: {
                    TRow("Home Assistant", icon: "house",
                         subtitle: home.haConfigured ? (home.message == nil ? "Connected" : "Can't connect") : "Not set up",
                         dot: home.haConfigured ? (home.message == nil ? TSurface.green : TeslaDark.importing) : nil, last: true) {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                    }
                }.buttonStyle(.plain)

                TCaption(text: "Data")
                NavigationLink { BackupPage(energy: energy, home: home) } label: {
                    TRow("Backup", icon: "arrow.triangle.2.circlepath",
                         subtitle: (backup.lastDate == nil ? "Not saved yet" : backup.lastText) + " · iCloud Drive",
                         dot: backup.summaryColor, last: true) {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                    }
                }.buttonStyle(.plain)

                AppVersionFooter()
            }
        }
        .teslaPage("My Home", black: true)
        .task { await home.refresh() }
    }
}


// MARK: S3XY Commander (cell balance)

struct S3XYPage: View {
    @ObservedObject private var link = S3XYLink.shared
    @ObservedObject private var history = BatteryHistory.shared
    @AppStorage(S3XYLink.ssidKey) private var ssid = "S3XY_OBD"
    @AppStorage(S3XYLink.enabledKey) private var enabled = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                statusCard
                    .padding(.horizontal, 20).padding(.top, 8)

                TCaption(text: "Reading")
                TRow("Read cell balance", icon: "battery.100percent") {
                    Toggle("", isOn: $enabled).labelsHidden().tint(TSurface.green)
                        .onChange(of: enabled) { _, on in on ? link.start() : link.stop() }
                }
                TRow("Wi-Fi name", icon: "wifi") {
                    TextField("S3XY_OBD", text: $ssid)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.app(size: 14)).foregroundStyle(TeslaDark.rowLabel).frame(width: 160)
                }
                TRow("Address", icon: "network", last: true) {
                    Text("192.168.4.1 · Panda").font(.app(size: 14)).foregroundStyle(TeslaDark.rowLabel)
                }

                TCaption(text: "Set up")
                NavigationLink { S3XYConnectHelp(ssid: ssid) } label: {
                    navRow("How to connect", "list.number", "ScanMyTesla support, join \(ssid)")
                }.buttonStyle(.plain)
                NavigationLink { S3XYDailyHelp(ssid: ssid) } label: {
                    navRow("Daily reading", "arrow.clockwise", "Shortcuts opens TesLah in the car")
                }.buttonStyle(.plain)
                NavigationLink { S3XYDetailsPage() } label: {
                    navRow("Connection details", "info.circle",
                           "Wi-Fi \(link.onWifi ? "on" : "off") · \(link.sent) sent · \(link.frames) received", last: true)
                }.buttonStyle(.plain)

                TFootnote(text: "Only one app can use the Commander's Wi-Fi at a time. While TesLah reads it, the S3XY app may lose its gadgets.")
            }
            .padding(.bottom, 30)
        }
        .teslaPage("S3XY Commander", black: true)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(link.statusDot).frame(width: 9, height: 9)
                Text(link.statusWord).font(.app(size: 20, weight: .semibold)).foregroundStyle(.white)
            }
            Text(hint).font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Rectangle().fill(TSurface.line).frame(height: 0.5).padding(.vertical, 14)
            HStack {
                Text(link.state == .receiving ? "NOW" : "LAST READING").kerning(0.6)
                Spacer()
                if link.state != .receiving, let r = shown { Text(r.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())) }
            }
            .font(.app(size: 10, weight: .medium)).foregroundStyle(TeslaDark.dim)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let r = shown {
                    Text("\(Int(r.mv.rounded())) mV").font(.app(size: 26, weight: .light)).foregroundStyle(.white)
                    Text([r.parked ? "parked" : "driving", r.soc.map { "\(Int($0.rounded()))%" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                } else {
                    Text("No reading yet").font(.app(size: 17, weight: .light)).foregroundStyle(TeslaDark.labelGrey)
                }
            }
            .padding(.top, 4)
            if link.state != .receiving {
                Button { link.reconnect() } label: {
                    Text("Connect now").font(.app(size: 15, weight: .medium))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(TSurface.selected))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.125)))
    }

    private var shown: CellReading? { link.current ?? history.latestParked }

    private var hint: String {
        switch link.state {
        case .receiving: return "Reading the cells over \(ssid)."
        case .waiting: return "Join \(ssid) in the car, then tap Connect now."
        case .off: return "Turn on Read cell balance below."
        }
    }

    private func navRow(_ t: String, _ icon: String, _ sub: String, last: Bool = false) -> some View {
        TRow(t, icon: icon, subtitle: sub, last: last) {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
        }
    }
}

extension S3XYLink {
    var connecting: Bool { state == .waiting && ["starting", "preparing"].contains(link) }
    var statusDot: Color {
        switch state {
        case .receiving: return TSurface.green
        case .waiting: return connecting ? CarColors.amber : Color(white: 0.55)
        case .off: return Color(white: 0.4)
        }
    }
    var statusWord: String {
        switch state {
        case .receiving: return "Connected"
        case .waiting: return connecting ? "Connecting…" : "Not connected"
        case .off: return "Off"
        }
    }
}

private func s3xySteps(_ items: [String]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(items.indices, id: \.self) { i in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(i + 1)").font(.app(size: 14, weight: .semibold)).foregroundStyle(TSurface.green).frame(width: 14)
                Text(items[i]).font(.app(size: 14)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.125)))
    .padding(.horizontal, 20)
}

struct S3XYConnectHelp: View {
    let ssid: String
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Steps")
                s3xySteps([
                    "In the S3XY app › Commander, turn on ScanMyTesla support.",
                    "In the car, join \(ssid) in iPhone Settings › Wi-Fi (password 12345678 unless you changed it).",
                    "Open TesLah. Cell balance updates by itself while it's open.",
                ])
                TFootnote(text: "The first time, iOS asks to let TesLah find devices on your local network. Tap Allow.")
            }
        }
        .teslaPage("How to connect", black: true)
    }
}

struct S3XYDailyHelp: View {
    let ssid: String
    @Environment(\.openURL) private var openURL
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Shortcuts automation")
                s3xySteps([
                    "Shortcuts › Automation › New.",
                    "Choose Wi-Fi › \(ssid) › When joining.",
                    "Choose Run Immediately.",
                    "Add the action Open App › TesLah.",
                ])
                Button { if let u = URL(string: "shortcuts://") { openURL(u) } } label: {
                    Text("Open Shortcuts").font(.app(size: 15, weight: .medium))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.selected))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.top, 14)
                TFootnote(text: "Getting in the car then opens TesLah, which takes the day's parked reading by itself.")
            }
        }
        .teslaPage("Daily reading", black: true)
    }
}

struct S3XYDetailsPage: View {
    @ObservedObject private var link = S3XYLink.shared
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Link")
                TRow("Wi-Fi", icon: "wifi") { value(link.onWifi ? "On" : "Off") }
                TRow("Connection", icon: "point.3.connected.trianglepath.dotted") { value(link.link.capitalized) }
                TRow("Requests sent", icon: "arrow.up") { value("\(link.sent)") }
                TRow("Messages received", icon: "arrow.down", last: link.lastError == nil) { value("\(link.frames)") }
                if let e = link.lastError {
                    TRow("Last error", icon: "exclamationmark.triangle", subtitle: e, last: true) { EmptyView() }
                }
                Button { link.reconnect() } label: {
                    Text("Connect now").font(.app(size: 15, weight: .medium))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.selected))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.top, 16)
                TFootnote(text: "Take a screenshot of this page if it won't connect.")
            }
        }
        .teslaPage("Connection details", black: true)
    }
    private func value(_ s: String) -> some View { Text(s).font(.app(size: 14)).foregroundStyle(TeslaDark.rowLabel) }
}
