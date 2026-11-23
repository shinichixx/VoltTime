import SwiftUI
import MapKit

/// The car page (Tesla-app style list). `active` is false while another page is showing.
struct CarPage: View {
    @ObservedObject var car: CarModel
    @ObservedObject var home: HomeModel
    @Binding var path: [Route]
    var active = true
    @Environment(\.scenePhase) private var phase

    var body: some View {
        CarView2(model: car, home: home, path: $path, active: active)
            .task(id: phase) {
                guard phase == .active else { return }
                while !Task.isCancelled {
                    await car.refresh()
                    try? await Task.sleep(for: .seconds(car.pollInterval))
                }
            }
            .modifier(CarConfirm(model: car))
    }
}

/// Centred question for buttons that ask first: title and line centred, Cancel and the action side by side
/// (drawn by VoltTime, like the iOS alert, so the title can be centred and set in Albert Sans).
struct CarConfirm: ViewModifier {
    @ObservedObject var model: CarModel

    func body(content: Content) -> some View {
        content
            .overlay {
                if let c = model.confirming {
                    let q = model.question(c)
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                            .onTapGesture { cancel() }
                        VStack(spacing: 0) {
                            Text(q.title)
                                .font(.app(size: 19, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            if !q.message.isEmpty {
                                Text(q.message)
                                    .font(.app(size: 15))
                                    .foregroundStyle(Color(white: 0.6))
                                    .multilineTextAlignment(.center)
                                    // one-line messages stay on one line (shrinking a little if needed)
                                    .lineLimit(q.message.contains("\n") ? 3 : 1).minimumScaleFactor(0.75)
                                    .padding(.top, 8)
                            }
                            HStack(spacing: 10) {
                                button("Cancel", color: .white) { cancel() }
                                button(q.action, color: q.destructive ? CarColors.red : .white) { Task { await model.run(c) } }
                            }
                            .padding(.top, 22)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 26)
                        .padding(.bottom, 16)
                        .frame(width: 310)
                        .background(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .fill(Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255))
                                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: model.confirming)
    }

    private func cancel() { model.confirming = nil; model.gateAway = nil }

    private func button(_ t: String, color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.app(size: 17, weight: .semibold)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(Color(white: 0.3)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ScrollY: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// How far the page has scrolled (0 at rest). iOS 18+ reads it from the scroll view itself;
/// iOS 17 falls back to the preference read from the top of the content.
private struct TrackScroll: ViewModifier {
    @Binding var y: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { g in
                g.contentOffset.y + g.contentInsets.top
            } action: { _, v in
                y = v
            }
        } else {
            content.onPreferenceChange(ScrollY.self) { y = $0 }
        }
    }
}

// MARK: - View 2 (Tesla-app style list)

/// Sizes, colours and spacing measured from the Tesla app (iPhone, 393 pt wide).
enum TeslaApp {
    static let bg = Color(red: 22 / 255, green: 23 / 255, blue: 24 / 255)
    static let panel = Color(red: 33 / 255, green: 34 / 255, blue: 35 / 255)
    static let amps = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
    static let track = Color(red: 44 / 255, green: 45 / 255, blue: 47 / 255)
    static let green = Color(red: 0, green: 226 / 255, blue: 134 / 255)          // battery %
    static let sliderGreen = Color(red: 1 / 255, green: 215 / 255, blue: 128 / 255)
    static let batteryBody = Color(red: 45 / 255, green: 47 / 255, blue: 52 / 255)
    static let title = Color(white: 0.953)        // #F3F3F3
    static let boxText = Color(white: 0.91)       // #E8E8E8
    static let grey = Color(white: 0.541)         // #8A8B8B
    static let boxGrey = Color(white: 0.52)       // #858585
    static let buttonText = Color(white: 0.48)    // #7A7B7B
    static let chevron = Color(white: 0.27)       // #454546
    static let icon = Color(red: 205 / 255, green: 206 / 255, blue: 208 / 255)   // top-row buttons, readable on the car
    static let margin: CGFloat = 30
}

struct CarView2: View {
    @ObservedObject var model: CarModel
    @ObservedObject var home: HomeModel
    @Binding var path: [Route]
    var active = true
    @State private var sliderLimit: Double?
    @State private var scroll: CGFloat = 0
    @State private var portAsk: PortAsk?
    @State private var onScreen = true       // live copy of `active` for the delayed scroll reset
    @ObservedObject private var history = BatteryHistory.shared
    private var c: CarSnapshot { model.car }
    typealias K = TeslaApp

    enum PortAsk: Identifiable { case open, unlock; var id: Self { self } }

    // Layout (points from the top of the page, the same reference as My Home's title):
    private let headerBottom: CGFloat = 108      // title, battery line, "remaining…" line
    private let carTop: CGFloat = 92             // car area, pinned, just under the "remaining…" line
    private let carHeight: CGFloat = 180
    private let buttonsTop: CGFloat = 250        // first thing that scrolls (icon row right under the car)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .top) {
                K.bg.ignoresSafeArea()

                // Car: stays put, fades as the page scrolls over it (8% at the end, like the Tesla app).
                CarScene(car: c)
                    .frame(width: w * 0.92)
                    .frame(width: w, height: carHeight)
                    .clipped()
                    .opacity(max(0.08, 1 - Double(max(scroll, 0)) / 150))
                    .padding(.top, carTop)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        GeometryReader { g in
                            Color.clear.preference(key: ScrollY.self, value: -g.frame(in: .named("v2")).minY)
                        }
                        .frame(height: 0)
                        .id("top")
                        Color.clear.frame(height: buttonsTop)
                        ControlStrip(model: model, count: 5, plain: true)
                            .padding(.horizontal, 20)
                        if c.onAC {   // only while plugged into an AC charger (hidden unplugged and on DC fast chargers)
                            chargingPanel
                                .padding(.horizontal, 10)
                                .padding(.top, 19)
                        }
                        rows.padding(.top, 22)
                        carInfo.padding(.top, 20)
                        Text(model.error ?? model.updatedText + " · pull to refresh")
                            .font(.app(size: 11)).foregroundStyle(model.error == nil ? K.grey : CarColors.amber)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        Color.clear.frame(height: 66)   // the last line stops clear of the page dots
                    }
                }
                .coordinateSpace(name: "v2")
                .modifier(TrackScroll(y: $scroll))
                .scrollIndicators(.hidden)
                .refreshable { await model.refresh() }
                .alert(portAsk == .unlock ? "Unlock the charge cable?" : "Open the charge port?",
                       isPresented: Binding(get: { portAsk != nil }, set: { if !$0 { portAsk = nil } }),
                       presenting: portAsk) { a in
                    Button(a == .unlock ? "Unlock" : "Open") {
                        Task {
                            // Tessie open_charge_port opens the door, or unlocks the cable if the door is already open.
                            await model.send("open_charge_port", done: a == .unlock ? "Charge port unlocked" : "Charge port open") { $0.portOpen = true }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { a in
                    Text(a == .unlock ? "The cable is released so you can unplug it." : "The port door opens, ready for the cable.")
                }
                .ignoresSafeArea(.container, edges: .bottom)   // rows run to the very bottom edge, no fade
                // Swiped away to My Home: back to the top, so the car page always opens at the top.
                .onChange(of: active) { _, on in
                    // Back to the top only once the swipe has settled on another page (out of sight),
                    // and not if you've swiped back to My Car in the meantime.
                    onScreen = on
                    guard !on else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(650))
                        guard !onScreen else { return }
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { proxy.scrollTo("top", anchor: .top) }
                    }
                }
                }

                // Header: pinned; fades out as the content comes up to it (Tesla app), back in on the way down.
                let headerOpacity = Double(min(1, max(0, ((buttonsTop - scroll) - (headerBottom + 10)) / 50)))
                header(w)
                    .opacity(headerOpacity)
                    .allowsHitTesting(false)
                // ☰ (Tesla app, top right): My Car settings and backup.
                HStack {
                    Spacer()
                    Button { path.append(.carSettings) } label: { MenuGlyph() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("My Car settings")
                }
                .padding(.top, 24 + 16 - 23)
                .padding(.trailing, 20.5)   // lines end 34 pt from the edge, where the Tesla app's ☰ ends
                .opacity(headerOpacity)
                .allowsHitTesting(headerOpacity > 0.5)
            }
        }
    }

    // MARK: Header: "Ultra Rouge" exactly like "Home IM2 Kuantan" (27 pt, 24 pt from the top, 7% from the left),
    // then the battery line and the "remaining" line with the Tesla app's gaps (12 pt and 11.3 pt).

    private func header(_ w: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(c.name)
                    .font(.app(size: 27, weight: .semibold))
                    .kerning(-0.3)
                    .foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 32)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5).fill(K.batteryBody).frame(width: 35, height: 15.5)
                    RoundedRectangle(cornerRadius: 2).fill(socColor).frame(width: max(2, 31 * (c.soc ?? 0) / 100), height: 11.5).padding(.leading, 2)
                }
                .overlay(alignment: .trailing) { RoundedRectangle(cornerRadius: 1).fill(K.batteryBody).frame(width: 1.5, height: 5.5).offset(x: 2.5) }
                HStack(spacing: 6) {
                    Text("\(Int(c.soc ?? 0))%").font(.app(size: 13, weight: .semibold)).foregroundStyle(socColor)
                    if c.charging { Image(systemName: "bolt.fill").font(.system(size: 14)).foregroundStyle(K.green) }
                    Text("· \(c.rangeKm.map { "\(Int($0.rounded())) km" } ?? "—")").font(.app(size: 13, weight: .medium)).foregroundStyle(K.grey)
                }
                .padding(.leading, 4)
            }
            .frame(height: 15.5)
            .padding(.top, 6)
            Text(subline).font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey).lineLimit(1)
                .padding(.top, 8.5)
        }
        .padding(.leading, w * 0.07)
        .padding(.trailing, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let hhmm: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"; return f
    }()

    private var socColor: Color {
        if c.charging { return K.green }
        return (c.soc ?? 0) < 20 ? CarColors.amber : K.title
    }

    private var subline: String {
        if c.charging, let m = c.minutesToLimit, m > 0 {
            let mm = Int(m.rounded())
            let done = (c.updated ?? Date()).addingTimeInterval(m * 60)
            return (mm >= 60 ? "\(mm / 60)h \(mm % 60)m" : "\(mm)m") + " remaining to charge limit (" + Self.hhmm.string(from: done) + ")"
        }
        if c.chargingState == "Complete" { return "Charge complete" }
        let place = model.whereLine
        // "Driving · Kemaman" already says it: don't repeat "Driving" from the status word
        return (model.statusWord == "Driving" ? [place] : [model.statusWord, place]).joined(separator: " · ")
    }

    // MARK: Charging box (Tesla app: 10 pt margins, 4 pt corners, 178 + 1 + 46 pt)

    private var chargingPanel: some View {
        let limit = sliderLimit ?? model.pendingLimit ?? c.limit ?? 80
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Charge limit: \(Int(limit))%").font(.app(size: 13, weight: .semibold)).foregroundStyle(K.boxText)
                    Text("  ·  " + boxState).font(.app(size: 13, weight: .medium)).foregroundStyle(K.boxGrey).lineLimit(1)
                }
                .frame(height: 16)
                if c.charging {   // like the Tesla app: kW / amps / volts only while charging
                    Text(chargeLine).font(.app(size: 12, weight: .medium)).foregroundStyle(K.boxGrey).lineLimit(1)
                        .frame(height: 15)
                        .padding(.top, 6)
                }
                GeometryReader { g in
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(K.track).frame(height: 4.4)
                        Capsule().fill(c.charging ? K.sliderGreen : (c.soc ?? 0) < 20 ? CarColors.amber : K.sliderGreen)
                            .frame(width: max(4, w * (c.soc ?? 0) / 100), height: 4.4)
                        Circle().fill(K.boxText).frame(width: 15, height: 15).offset(x: w * limit / 100 - 7.5)
                    }
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in sliderLimit = min(max((v.location.x / w * 100).rounded(), 50), 100) }
                        .onEnded { _ in if let s = sliderLimit { model.setLimit(s) }; sliderLimit = nil })
                }
                .frame(height: 30)
                .padding(.top, 12.7)
                let amps = Int(c.chargeAmps ?? Double(c.ampsCap))
                HStack {
                    // 5–32 A: no left arrow at 5 A, no right arrow at 32 A.
                    Button { Task { await model.setAmps(amps - 1) } } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 45)
                    }
                    .opacity(amps <= 5 ? 0 : 1).disabled(amps <= 5)
                    Spacer()
                    Text("\(amps) A").font(.app(size: 13, weight: .semibold)).foregroundStyle(K.boxText)
                    Spacer()
                    Button { Task { await model.setAmps(amps + 1) } } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 45)
                    }
                    .opacity(amps >= c.ampsCap ? 0 : 1).disabled(amps >= c.ampsCap)
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(K.grey)
                .padding(.horizontal, 2)
                .frame(height: 45)
                .background(RoundedRectangle(cornerRadius: 7).fill(K.amps))
                .buttonStyle(.plain)
                .padding(.top, 14.6)
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 25)
            .frame(height: c.charging ? 178.3 : 158.3, alignment: .top)   // shorter when the kW / amps line is hidden
            let full = (c.soc ?? 0) >= limit
            // Left: stop while charging; start only with the cable in and room below the limit.
            let left: String? = c.charging ? "Stop Charging" : (c.cableConnected && !full ? "Start Charging" : nil)
            // Right: unlock when the port is open / cable in; open otherwise (hidden once full with no cable).
            let unlock = c.portOpen || c.cableConnected
            let right: String? = full && !c.cableConnected ? nil : (unlock ? "Unlock Charge Port" : "Open Charge Port")
            if left != nil || right != nil {
                Rectangle().fill(K.bg).frame(height: 1)
                HStack(spacing: 0) {
                    if let left { panelButton(left) { Task { await model.run(.charge) } } }
                    if left != nil && right != nil { Rectangle().fill(K.bg).frame(width: 1) }
                    if let right { panelButton(right) { portAsk = unlock ? .unlock : .open } }
                }
                .frame(height: 46)
            }
        }
        .background(RoundedRectangle(cornerRadius: 4).fill(K.panel))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var boxState: String {
        switch c.chargingState {
        case "Charging": return "Charging"
        case "Complete": return "Complete"
        case "NoPower": return "No power"
        default: return c.cableConnected ? "Plugged in" : "Not plugged in"
        }
    }

    private var chargeLine: String {
        var parts: [String] = []
        if let p = c.chargerPowerKW, c.charging { parts.append("\(Int(p.rounded())) kW") }
        if let e = c.energyAddedKWh, e > 0 { parts.append(String(format: "+%.0f kWh", e)) }
        if let a = c.chargeAmps { parts.append("\(Int(a))/\(Int(c.chargeAmpsMax ?? a))A") }
        if let v = c.chargerVoltage, v > 0 { parts.append("\(Int(v))V") }
        if parts.isEmpty { parts.append(c.cableConnected ? "Plugged in" : "Unplugged") }
        return parts.joined(separator: "  ·  ")
    }

    private func panelButton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.app(size: 13, weight: .medium)).foregroundStyle(K.buttonText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Rows (title ≈17 pt, grey line 12 pt, text at 64 pt, one-line 60 pt, two-line 76 pt)

    private var rows: some View {
        let h = model.health
        let health = [h.healthPercent.map { String(format: "Health %.1f%%", $0) },
                      h.maxRangeKm.map { "Max \(Int($0.rounded())) km" },
                      h.cycles(lifetimeKWh: c.lifetimeKWh).map { "\(Int($0.rounded())) cycles" }].compactMap { $0 }
        let tyres = c.tyres.map { $0.map { String(format: "%.1f", $0) } ?? "–" }.joined(separator: " · ") + " bar"
        let street = c.address?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        return VStack(spacing: 0) {
            row("car.side", "Controls", nil) { path.append(.carDetail(.controls)) }
            row("fanblades", "Climate", "Interior \(deg(c.insideC)) · Exterior \(deg(c.outsideC)) · \(c.climateOn ? "On" : "Off")") { path.append(.carDetail(.climate)) }
            row("bolt", "Charging", chargingSub) { path.append(.settings) }
            row("minus.plus.batteryblock", "Battery", health.isEmpty ? "—" : health.joined(separator: " · "), rich: batteryLine) { path.append(.carDetail(.battery)) }
            row("circle.circle", "Tyres", tyres, rich: tyreLine) { path.append(.carDetail(.tyres)) }
            row("lock.shield", "Security", [c.locked == true ? "Locked" : "Unlocked", c.anyWindowOpen ? "Window open" : "Windows closed",
                                            "Sentry \(c.sentry ? "on" : "off")"].joined(separator: " · ")) { path.append(.carDetail(.security)) }
            row("location.north.fill", "Location", locationLine(street)) { path.append(.carDetail(.location)) }
        }
    }

    // MARK: Bottom block (Tesla app: divider, model name, trim, km / VIN / software, two pill buttons)

    private var carInfo: some View {
        let vin = c.vin ?? model.vin
        let lines = [c.odometerKm.map { "\($0.formatted(.number.precision(.fractionLength(0)))) km" },
                     vin.map { "VIN: " + $0 },
                     c.software.map { "Software: " + $0 }].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Color(white: 0.133)).frame(height: 1)
            Text(c.modelName).font(.app(size: 14, weight: .semibold)).kerning(4.5).foregroundStyle(K.title)
                .padding(.top, 29)
            if let t = c.trimName {
                Text(t).font(.app(size: 13, weight: .semibold)).foregroundStyle(K.grey).padding(.top, 10)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines, id: \.self) {
                    Text($0).font(.app(size: 10.5, weight: .semibold)).foregroundStyle(K.grey).frame(height: 13, alignment: .leading)
                }
            }
            .padding(.top, 22)
            HStack(spacing: 10) {
                pill("Copy VIN") {
                    UIPasteboard.general.string = vin
                    model.show("VIN copied")
                }
                pill("Open Tessie") {
                    if let u = URL(string: "https://dash.tessie.com") { UIApplication.shared.open(u) }
                }
            }
            .padding(.top, 26)
        }
        .padding(.horizontal, K.margin)
        .padding(.bottom, 18)
    }

    private func pill(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.app(size: 13, weight: .medium)).foregroundStyle(Color(white: 0.59))
                .padding(.horizontal, 10).frame(height: 25)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 42 / 255, green: 43 / 255, blue: 45 / 255)))
        }
        .buttonStyle(.plain)
    }

    /// Under "Charging": the Home Assistant charging mode; Routine shows tonight's start and ready time.
    private var chargingSub: String? {
        guard let m = home.chargingMode else { return nil }
        if m == "Routine" {
            let start = (home.active ? home.scheduledStart : nil) ?? home.plannedStart()
            let r = home.readyMinutes
            return "Starts " + Self.hhmm.string(from: start) + " · Ready by " + String(format: "%02d:%02d", r / 60, r % 60)
        }
        return ChargingMode.named(m).title
    }

    private var planLine: String {
        let ready = "ready by " + Fmt.clock(minutes: home.readyMinutes)
        let start = (home.active ? home.scheduledStart : nil) ?? home.plannedStart()
        return "Starts " + Fmt.clock(start, calendar: .current) + " · " + ready
    }

    /// "Health 99.5% · Max 615 km · 31 cycles · 12 mV": health amber below 80 %, red below 70 %;
    /// the cell gap amber or red only when the latest parked reading needs attention.
    private var batteryLine: Text? {
        let h = model.health
        guard let hp = h.healthPercent else { return nil }
        let healthCol: Color = hp < 70 ? CarColors.red : (hp < 80 ? CarColors.amber : K.grey)
        var t = Text(String(format: "Health %.1f%%", hp)).foregroundColor(healthCol)
        if let r = h.maxRangeKm { t = t + Text(" · Max \(Int(r.rounded())) km").foregroundColor(K.grey) }
        if let cy = h.cycles(lifetimeKWh: c.lifetimeKWh) { t = t + Text(" · \(Int(cy.rounded())) cycles").foregroundColor(K.grey) }
        if let cell = history.latestParked {
            t = t + Text(" · ").foregroundColor(K.grey)
                + Text("\(Int(cell.mv.rounded())) mV").foregroundColor(CellStatus(cell).rowColor ?? K.grey)
        }
        return t
    }

    /// Each tyre in its own colour: grey normal, orange low or high, red very low.
    private var tyreLine: Text {
        var t = Text("")
        for i in 0..<4 {
            let v = c.tyres[i]
            t = t + Text(v.map { String(format: "%.1f", $0) } ?? "–").foregroundColor(CarModel.tyreColor(v, normal: K.grey))
            t = t + Text(i < 3 ? " · " : " bar").foregroundColor(K.grey)
        }
        return t
    }

    /// "Kuantan · Home", "Kemaman · PGB TSET"; when the place is just the town again, the state instead ("Cukai · Terengganu").
    private func locationLine(_ town: String?) -> String {
        let parts = (c.address ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var second = model.placeWord
        if let town, second.caseInsensitiveCompare(town) == .orderedSame {
            second = parts.count > 1 ? parts[1] : ""
        }
        return [town, second.isEmpty ? nil : second].compactMap { $0 }.joined(separator: " · ")
    }

    private func row(_ icon: String, _ title: String, _ sub: String?, tag: String? = nil, rich: Text? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(K.grey)
                    .frame(width: 44)
                    .padding(.leading, 15)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.app(size: 16, weight: .semibold)).foregroundStyle(K.title)
                    if let rich {
                        rich.font(.app(size: 12, weight: .semibold)).lineLimit(1)
                    } else if let sub {
                        (Text(sub).foregroundColor(K.grey) + Text(tag.map { "  · \($0)" } ?? "").foregroundColor(CarColors.amber))
                            .font(.app(size: 12, weight: .semibold)).lineLimit(1)
                    }
                }
                .padding(.leading, 5)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(K.chevron)
                    .padding(.trailing, 34)
            }
            .frame(minHeight: sub == nil ? 60 : 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deg(_ v: Double?) -> String { v.map { String(format: "%.1f°C", $0) } ?? "—" }
}

// MARK: - Detail pages (opened from View 2's rows)

enum CarDetail: String, Hashable { case controls, climate, modes, tyres, battery, security, location, odometer }

struct CarDetailPage: View {
    @ObservedObject var model: CarModel
    let detail: CarDetail
    @ObservedObject private var history = BatteryHistory.shared
    @State private var healthRange = 2
    @State private var cellRange = 3
    private var c: CarSnapshot { model.car }

    var body: some View {
        Group {
            switch detail {
            case .controls: ControlsPage(model: model)
            case .climate: ClimateControlsPage(model: model)
            case .modes: SecurityModesPage(model: model)
            case .tyres: TyresPage(model: model)
            case .security: CarSecurityPage(model: model)
            case .location: CarLocationPage(model: model)
            default:
                ScrollView {
                    VStack(spacing: 0) {
                        switch detail {
                        case .battery: battery
                        default: odometer
                        }
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .teslaPage(title, black: true)
        .modifier(CarConfirm(model: model))
    }

    private var title: String {
        switch detail {
        case .controls: return "Controls"
        case .climate: return "Climate"
        case .modes: return "Security & modes"
        case .tyres: return "Tyres"
        case .battery: return "Battery"
        case .security: return "Security"
        case .location: return "Location"
        case .odometer: return "Odometer"
        }
    }

    private var battery: some View {
        let h = model.health
        let K = TeslaApp.self
        let soc = c.soc ?? 0
        let limit = c.limit ?? 80
        let power: Double? = { guard let v = c.packVoltage, let a = c.packCurrent else { return nil }; return abs(v * a) / 1000 }()
        return VStack(alignment: .leading, spacing: 0) {
            // Charge now, range and limit, with a bar marked at the limit
            HStack(alignment: .lastTextBaseline) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(Int(soc))").font(.app(size: 46, weight: .light)).foregroundStyle(K.title)
                    Text("%").font(.app(size: 17, weight: .medium)).foregroundStyle(K.grey)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(c.rangeKm.map { "\(Int($0.rounded())) km" } ?? "–").font(.app(size: 17)).foregroundStyle(K.title)
                    Text("Limit \(Int(limit))%").font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey)
                }
                .padding(.bottom, 6)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(K.track)
                    Capsule().fill(K.sliderGreen).frame(width: g.size.width * soc / 100)
                    Rectangle().fill(K.title).frame(width: 2, height: 16).offset(x: g.size.width * limit / 100 - 1)
                }
            }
            .frame(height: 10)
            Text(batteryStatus).font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey).padding(.top, 10)

            // Precondition: A/C on at 19°C, asks first. Red while it's on.
            Button { model.confirming = .precondition } label: {
                HStack(spacing: 10) {
                    if model.busy == .precondition {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        PreconditionGlyph(on: c.preconditioning, size: 22, color: K.grey)
                    }
                    Text(c.preconditioning ? "Stop preconditioning" : "Precondition battery")
                        .font(.app(size: 14, weight: .medium))
                        .foregroundStyle(c.preconditioning ? CarColors.red : K.title)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10).fill(K.panel))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busy == .precondition)
            .padding(.top, 12)

            // Low Power Mode and Accessory Power, side by side. Green outline while on.
            HStack(spacing: 10) {
                modeButton(.lowPower, "Low Power Mode", on: c.lowPower == true)
                modeButton(.accessoryPower, "Accessory Power", on: c.accessoryPower == true)
            }
            .padding(.top, 8)

            caption("Live")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                tile("Voltage", c.packVoltage.map { "\(Int($0.rounded()))" }, "V")
                tile("Current", c.packCurrent.map { "\(Int(abs($0).rounded()))" }, "A")
                tile("Power", power.map { String(format: "%.1f", $0) }, "kW")
                tile("Energy left", c.energyLeftKWh.map { String(format: "%.1f", $0) }, "kWh")
                tile("Pack temp", c.packTempC.map { "\(Int($0.rounded()))" }, "°C")
                tile("Added", c.energyAddedKWh.map { String(format: "+%.0f", $0) }, "kWh")
            }

            caption("Health")
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(h.healthPercent.map { String(format: "%.1f", $0) } ?? "–").font(.app(size: 28, weight: .light)).foregroundStyle(K.title)
                        Text("%").font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let now = h.capacityKWh, let new = h.originalCapacityKWh {
                            Text(String(format: "%.1f of %.1f kWh", now, new)).font(.app(size: 12, weight: .medium)).foregroundStyle(K.title)
                            Text(String(format: "%.1f%% lost", max(0, (1 - now / new) * 100))).font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey)
                        }
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(K.track)
                        Capsule().fill(K.sliderGreen).frame(width: g.size.width * min(1, (h.healthPercent ?? 0) / 100))
                    }
                }
                .frame(height: 6)
                .padding(.top, 10)
                .padding(.bottom, 6)
                healthRow("Max range at 100%", h.maxRangeKm.map { "\(Int($0.rounded()))" } ?? "–", "km")
                healthRow("Cycles", h.cycles(lifetimeKWh: c.lifetimeKWh).map { "\(Int($0.rounded()))" } ?? "–", "")
                Rectangle().fill(TeslaApp.track).frame(height: 1)
                healthGraph
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))

            cellBalance
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    /// Half-width toggle box: icon, name, and On / Off under it. Goes through the same send path as the quick controls.
    private func modeButton(_ ctl: CarControl, _ title: String, on: Bool) -> some View {
        let K = TeslaApp.self
        let green = TSurface.green
        return Button { Task { await model.run(ctl) } } label: {
            HStack(spacing: 10) {
                if model.busy == ctl {
                    ProgressView().tint(.white).scaleEffect(0.75).frame(width: 22)
                } else {
                    Image(systemName: ctl.icon(c))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(on ? green : K.grey)
                        .frame(width: 22)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(size: 13, weight: .medium)).foregroundStyle(K.title)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(on ? "On" : "Off").font(.app(size: 12, weight: .medium)).foregroundStyle(on ? green : K.grey)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(K.panel)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? green.opacity(0.8) : .clear, lineWidth: 1.2))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy != nil)
    }

    private var batteryStatus: String {
        if c.charging, let m = c.minutesToLimit, m > 0 {
            let mm = Int(m.rounded())
            let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "HH:mm"
            return "Charging · " + (mm >= 60 ? "\(mm / 60)h \(mm % 60)m" : "\(mm)m") + " to limit (" + f.string(from: (c.updated ?? Date()).addingTimeInterval(m * 60)) + ")"
        }
        if c.chargingState == "Complete" { return "Charge complete" }
        return c.cableConnected ? "Plugged in · not charging" : "Not plugged in"
    }

    private func caption(_ t: String) -> some View {
        Text(t.uppercased()).font(.app(size: 11, weight: .semibold)).kerning(0.8).foregroundStyle(Color(white: 0.4))
            .padding(.top, 20).padding(.bottom, 8).padding(.leading, 4)
    }

    private func tile(_ k: String, _ v: String?, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(k).font(.app(size: 11, weight: .medium)).foregroundStyle(TeslaApp.grey).lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(v ?? "–").font(.app(size: 21, weight: .light)).foregroundStyle(TeslaApp.title)
                Text(u).font(.app(size: 11, weight: .medium)).foregroundStyle(TeslaApp.grey)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .padding(.horizontal, 11)
        .background(RoundedRectangle(cornerRadius: 12).fill(TeslaApp.panel))
    }

    // MARK: Battery history (build 47)

    private var healthGraph: some View {
        let opts: [(String, Int?)] = [("6 M", 183), ("1 Y", 365), ("All", nil)]
        let cut = RangePicker.cutoff(opts[healthRange].1)
        let pts = history.health.filter { cut == nil || $0.date >= cut! }.map { HistoryGraph.Point(date: $0.date, value: $0.percent) }
        let vals = pts.map(\.value)
        let lo = min(vals.min() ?? 99, 99) - 0.2, hi = max(vals.max() ?? 100, 100) + 0.2
        let guides = Array(Set([floor(lo + 0.2), ceil(hi - 0.2)])).sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Health over time").font(.app(size: 12, weight: .medium)).foregroundStyle(TeslaApp.grey).padding(.top, 12)
            RangePicker(options: opts, selected: $healthRange)
            if pts.count >= 2 {
                HistoryGraph(points: pts, lo: lo, hi: hi, guides: guides, color: Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255),
                             startLabel: cut == nil ? "Delivery" : "",
                             format: { String(format: "%.1f%%", $0) }, guideLabel: { String(format: "%g%%", $0) })
                    .frame(height: 96)
            } else {
                Text("Fills in day by day: one reading a day from Tessie.")
                    .font(.app(size: 12)).foregroundStyle(TeslaApp.grey).frame(height: 40)
            }
        }
    }

    private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM, HH:mm"; return f }()

    private var cellBalance: some View {
        let K = TeslaApp.self
        let opts: [(String, Int?)] = [("6 W", 42), ("6 M", 183), ("1 Y", 365), ("All", nil)]
        let cut = RangePicker.cutoff(opts[cellRange].1)
        let hist = history.parked.filter { cut == nil || $0.date >= cut! }
        let pts = hist.map { HistoryGraph.Point(date: $0.date, value: $0.mv) }
        let last = history.latestParked
        let live = S3XYLink.shared
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                caption("Cell balance")
                Spacer()
                Text("via S3XY Commander").font(.app(size: 11, weight: .medium)).foregroundStyle(K.grey).padding(.top, 12)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let r = last {
                    let st = CellStatus(r)
                    HStack {
                        Circle().fill(st.color).frame(width: 7, height: 7)
                        Text(st == .notJudged ? "Below 20% · not judged" : st.word)
                            .font(.app(size: 14, weight: .medium)).foregroundStyle(st == .notJudged ? K.grey : K.title)
                        Spacer()
                        Text("Parked · " + (r.soc.map { "\(Int($0.rounded()))% · " } ?? "") + Self.stamp.string(from: r.date))
                            .font(.app(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.78))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color(white: 0.19)))
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(Int(r.mv.rounded()))").font(.app(size: 40, weight: .light)).foregroundStyle(K.title)
                        Text("mV apart").font(.app(size: 13, weight: .medium)).foregroundStyle(K.grey)
                    }
                    .padding(.top, 6)
                    cellBar(r.mv, dim: st == .notJudged)
                    healthRow("Highest cell", String(format: "%.3f V", r.maxV), "")
                    healthRow("Lowest cell", String(format: "%.3f V", r.minV), "")
                } else {
                    Text(live.state == .receiving ? "Reading the cells…" : "No reading yet")
                        .font(.app(size: 15, weight: .medium)).foregroundStyle(K.title)
                    Text("In the car, join the S3XY_OBD Wi-Fi and open TesLah. My Car ☰ › S3XY Commander shows how.")
                        .font(.app(size: 12)).foregroundStyle(K.grey).padding(.top, 4).padding(.bottom, 6)
                }
                if let road = history.road {
                    Rectangle().fill(TeslaApp.track).frame(height: 1)
                    Text("On the road: up to \(Int(road.mv.rounded())) mV · " + Self.stamp.string(from: road.date))
                        .font(.app(size: 13)).foregroundStyle(K.grey).frame(height: 36)
                }
                if !history.parked.isEmpty {
                    Rectangle().fill(TeslaApp.track).frame(height: 1)
                    let avg = history.parked.map(\.mv).reduce(0, +) / Double(history.parked.count)
                    Text("Parked readings · average \(Int(avg.rounded())) mV")
                        .font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey).padding(.top, 12).padding(.bottom, 10)
                    RangePicker(options: opts, selected: $cellRange)
                    if pts.count >= 2 {
                        HistoryGraph(points: pts, lo: 0, hi: max(25, (pts.map(\.value).max() ?? 0) + 5), guides: [10, 20],
                                     color: TSurface.green, startLabel: cut == nil ? "First reading" : "",
                                     format: { "\(Int($0.rounded())) mV" })
                            .frame(height: 90).padding(.top, 10)
                    } else {
                        Text("The trend shows from the second day.").font(.app(size: 12)).foregroundStyle(K.grey).frame(height: 36)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))
        }
    }

    /// 0–60 mV: green under 10, darker green to 20, amber to 50, red beyond; white dot at the reading.
    private func cellBar(_ mv: Double, dim: Bool) -> some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(TSurface.green).frame(width: w * 10 / 60)
                        Rectangle().fill(Color(red: 40 / 255, green: 150 / 255, blue: 70 / 255)).frame(width: w * 10 / 60)
                        Rectangle().fill(CarColors.amber).frame(width: w * 30 / 60)
                        Rectangle().fill(CarColors.red)
                    }
                    .opacity(dim ? 0.3 : 0.6)
                    .frame(height: 6)
                    Circle().fill(.white).frame(width: 10, height: 10).offset(x: w * min(mv, 60) / 60 - 5)
                }
                .frame(height: 10)
            }
            .frame(height: 10)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    ForEach([0, 10, 20, 50], id: \.self) { v in
                        Text("\(v)").offset(x: v == 0 ? 0 : w * Double(v) / 60 - 6)
                    }
                    Text("mV").frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.app(size: 10)).foregroundStyle(TeslaApp.grey)
            .frame(height: 12)
        }
        .padding(.top, 12).padding(.bottom, 10)
    }

    private func healthRow(_ k: String, _ v: String, _ u: String) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(TeslaApp.track).frame(height: 1)
            HStack(alignment: .lastTextBaseline) {
                Text(k).font(.app(size: 14)).foregroundStyle(TeslaApp.title)
                Spacer()
                Text(v).font(.app(size: 14)).foregroundStyle(TeslaApp.title)
                if !u.isEmpty { Text(u).font(.app(size: 11)).foregroundStyle(TeslaApp.grey) }
            }
            .frame(height: 37)
        }
    }

    private var odometer: some View {
        TStats(items: [TStat(value: c.odometerKm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–", unit: "km", caption: "Odometer")])
            .padding(.top, 40)
    }

    private func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }
}
