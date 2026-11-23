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
                    nav("Tessie", "bolt.car", car.configured ? (car.error == nil ? "Connected · \(car.car.name)" : "Can't reach Tessie") : "Not set up",
                        dot: car.configured ? (car.error == nil ? TSurface.green : CarColors.amber) : nil, last: true)
                }.buttonStyle(.plain)

                TCaption(text: "Car data")
                NavigationLink { S3XYPage() } label: {
                    nav("S3XY Commander", "waveform.path.ecg",
                        s3xy.state == .receiving ? "Connected · reading the cells" : "Cell balance · join S3XY_OBD in the car",
                        dot: s3xy.state == .receiving ? TSurface.green : nil, last: true)
                }.buttonStyle(.plain)

                TCaption(text: "Buttons")
                NavigationLink { QuickControlsPage(car: car) } label: {
                    nav("Quick controls", "square.grid.3x2", car.controls.map(\.short).joined(separator: " · "))
                }.buttonStyle(.plain)
                NavigationLink { AutogatePage(car: car) } label: {
                    nav("Autogate", "door.garage.open", gateAsk ? "Asks before sending" : "Sends straight away · asks when away", last: true)
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

    private func nav(_ t: String, _ icon: String, _ sub: String, dot: Color? = nil, last: Bool = false) -> some View {
        TRow(t, icon: icon, subtitle: sub, dot: dot, last: last) {
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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Your 6 buttons", trailing: "View 2 shows the first 5")
                HStack(spacing: 6) {
                    ForEach(car.controls.indices, id: \.self) { i in
                        let c = car.controls[i]
                        Button { slot = i } label: {
                            VStack(spacing: 3) {
                                Image(systemName: c.icon(car.car)).font(.system(size: 18, weight: .light))
                                Text(c.short).font(.app(size: 9)).lineLimit(1)
                            }
                            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 12).fill(slot == i ? TSurface.selected : TSurface.field))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(slot == i ? CarColors.red : .clear, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                HStack {
                    Button { move(-1) } label: { Label("Move left", systemImage: "arrow.left") }.disabled(slot == 0)
                    Spacer()
                    Button { move(1) } label: { Label("Move right", systemImage: "arrow.right") }.disabled(slot == 5)
                }
                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.horizontal, 20).padding(.top, 10)
                TFootnote(text: "Tap a slot, then pick a button below for it.")

                ForEach(CarControl.Group.allCases, id: \.self) { g in
                    TCaption(text: g.rawValue)
                    let items = CarControl.allCases.filter { $0.group == g }
                    ForEach(items) { c in
                        Button { pick(c) } label: {
                            TRow(c.title, icon: c.icon(car.car), last: c == items.last) {
                                HStack(spacing: 12) {
                                    if c != .gate {
                                        Toggle("", isOn: askBinding(c)).labelsHidden().tint(TSurface.green).scaleEffect(0.75)
                                    }
                                    Image(systemName: car.controls.contains(c) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(car.controls.contains(c) ? Color.white : TeslaDark.dim)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                TFootnote(text: "The switch on each row = ask before doing it. On by default for unlock, trunks, windows, keyless driving, valet and preconditioning. The autogate's own setting is in My Car ☰ › Autogate.")
                Button("Reset to default") { CarControl.save(CarControl.defaults); car.reloadControls() }
                    .font(.app(size: 14)).foregroundStyle(CarColors.red).padding(.top, 16)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Quick controls", black: true)
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

    private func move(_ d: Int) {
        var list = car.controls
        let j = slot + d
        guard list.indices.contains(j) else { return }
        list.swapAt(slot, j); slot = j
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
    @AppStorage(S3XYLink.ssidKey) private var ssid = "S3XY_OBD"
    @AppStorage(S3XYLink.enabledKey) private var enabled = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Status")
                TRow(statusTitle, icon: "waveform.path.ecg", subtitle: statusLine,
                     dot: link.state == .receiving ? TSurface.green : nil, last: true) { EmptyView() }
                TFootnote(text: diagnostics, color: TeslaDark.rowLabel)
                Button { link.reconnect() } label: {
                    Text("Connect now").font(.app(size: 15, weight: .medium))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.selected))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.top, 10)

                TCaption(text: "Wi-Fi")
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

                TCaption(text: "How to connect")
                steps([
                    "In the S3XY app › Commander, turn on ScanMyTesla support.",
                    "In the car, join \(ssid) in iPhone Settings › Wi-Fi (password 12345678 unless you changed it).",
                    "Open TesLah. Cell balance updates by itself while it's open.",
                ])
                TFootnote(text: "Only one app can use the Commander's Wi-Fi at a time. While TesLah reads it, some S3XY gadgets may drop out of the S3XY app.", color: TeslaDark.rowLabel)

                TCaption(text: "Open TesLah in the car, every day")
                steps([
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
                TFootnote(text: "Getting in the car then opens TesLah, which takes the day's parked reading by itself.", color: TeslaDark.rowLabel)
            }
            .padding(.bottom, 30)
        }
        .teslaPage("S3XY Commander", black: true)
    }

    /// For screenshots when it doesn't connect: Wi-Fi, link state, requests sent, last error.
    private var diagnostics: String {
        var s = "Wi-Fi \(link.onWifi ? "on" : "off") · link \(link.link) · \(link.sent) requests sent · \(link.frames) messages"
        if let e = link.lastError { s += " · " + e }
        return s
    }

    private var statusTitle: String {
        switch link.state {
        case .receiving: return "Connected"
        case .waiting: return "Not connected"
        case .off: return "Off"
        }
    }

    private var statusLine: String {
        switch link.state {
        case .receiving:
            if let r = link.current { return "\(link.frames) frames · cells \(Int(r.mv.rounded())) mV apart" }
            return "\(link.frames) frames · waiting for battery data"
        case .waiting: return "Join \(ssid) in the car"
        case .off: return "Turn on Read cell balance"
        }
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(i + 1)").font(.app(size: 14, weight: .semibold)).foregroundStyle(TSurface.green)
                    Text(items[i]).font(.app(size: 14)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.13)))
        .padding(.horizontal, 20)
    }
}
