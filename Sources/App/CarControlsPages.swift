import SwiftUI

// Controls (car seen from above + quick tiles), Controls › Climate, Controls › Security & modes, and Tyres.
// Every control shows what the car is doing now and sends the change through Tessie.

// MARK: - Controls

struct ControlsPage: View {
    @ObservedObject var model: CarModel
    private var c: CarSnapshot { model.car }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                carView.padding(.top, 10)
                TCaption(text: "Quick")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    tile("fanblades", "Climate", (c.climateOn ? "On" : "Off") + (c.insideC.map { String(format: " · %.1f°C", $0) } ?? ""),
                         c.climateOn ? CarColors.blue : nil) { model.tap(.climate) }
                    tile("window.vertical.open", "Windows", c.anyWindowOpen ? "Close" : "Vent", nil) { model.tap(.windows) }
                    tile("door.garage.open", "Autogate", "Send signal", nil) { model.tap(.gate) }
                    tile("lightbulb", "Flash", "Lights", nil) { model.tap(.flash) }
                    tile("speaker.wave.2", "Honk", "Horn", nil) { model.tap(.honk) }
                    tile("key", "Keyless", "Drive 2 min", CarColors.amber) { model.tap(.keyless) }
                }
                .padding(.horizontal, 20)
                TCaption(text: "More")
                NavigationLink(value: Route.carDetail(.climate)) {
                    TRow("Climate", icon: "fanblades", subtitle: climateLine) { chevron }
                }
                .buttonStyle(.plain)
                NavigationLink(value: Route.carDetail(.modes)) {
                    TRow("Security & modes", icon: "lock.shield", subtitle: modesLine) { chevron }
                }
                .buttonStyle(.plain)
                TRow("Wake car", icon: "sun.max", subtitle: "Asleep cars take about 30 s to answer", last: true) {
                    pillButton(model.busy == .wake ? "…" : "Wake") { model.tap(.wake) }
                }
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var climateLine: String {
        let set = c.setTempC.map { String(format: "set to %.0f°C", $0) } ?? "set temperature"
        let seats = (c.seatCool ?? [0, 0]).contains { $0 > 0 } ? "seats cooling" : "seats off"
        return [(c.climateOn ? "On" : "Off"), set, seats].joined(separator: " · ")
    }

    private var modesLine: String {
        ["Sentry \(c.sentry ? "on" : "off")", "Valet \(c.valet ? "on" : "off")", "Guest \(c.guest == true ? "on" : "off")"].joined(separator: " · ")
    }

    // Car from above, with the things you can open around it.
    private var carView: some View {
        let d = TyreDiagram(colors: Array(repeating: Color.white, count: 4), lengthPt: 200)
        return VStack(spacing: 10) {
            pill("Front trunk", c.frunkOpen ? "Open" : "Closed · tap to open") { model.tap(.frunk) }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .trailing, spacing: 46) {
                    sideLabel("Windows", c.anyWindowOpen ? "Open" : "All closed", .trailing, c.anyWindowOpen ? CarColors.amber : nil) { model.tap(.windows) }
                    sideLabel("Charge port", (c.cableConnected ? "Cable in · " : "") + (c.portOpen ? "open" : "closed"), .trailing, nil) { model.tap(.chargePort) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                ZStack {
                    d
                    Button { model.tap(.lock) } label: {
                        let locked = c.locked != false
                        Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(locked ? TSurface.green : CarColors.amber)
                            .frame(width: 46, height: 46)
                            .background(Circle().fill((locked ? TSurface.green : CarColors.amber).opacity(0.18)))
                            .overlay(Circle().strokeBorder(locked ? TSurface.green : CarColors.amber, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                sideLabel(c.locked != false ? "Locked" : "Unlocked", c.locked != false ? "tap to unlock" : "tap to lock", .leading,
                          c.locked != false ? TSurface.green : CarColors.amber, titleColored: true) { model.tap(.lock) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            pill("Rear trunk", c.trunkOpen ? "Open" : "Closed · tap to open") { model.tap(.trunk) }
        }
        .padding(.horizontal, 12)
    }

    private func pill(_ t: String, _ sub: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(spacing: 1) {
                Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                Text(sub).font(.system(size: 10)).foregroundStyle(TeslaDark.rowLabel)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(Capsule().fill(TSurface.field))
        }
        .buttonStyle(.plain)
    }

    private func sideLabel(_ t: String, _ sub: String, _ align: HorizontalAlignment, _ color: Color?, titleColored: Bool = false,
                           _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(alignment: align, spacing: 1) {
                Text(t).font(.system(size: 13, weight: .medium)).foregroundStyle(titleColored ? (color ?? .white) : .white)
                Text(sub).font(.system(size: 10)).foregroundStyle(titleColored ? TeslaDark.rowLabel : (color ?? TeslaDark.rowLabel))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tile(_ icon: String, _ t: String, _ sub: String, _ subColor: Color?, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if model.busy.map({ $0.title.hasPrefix(t) || $0.short == t }) == true { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(TSurface.icon) }
                }
                .frame(height: 22)
                Text(t).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).padding(.top, 8)
                Text(sub).font(.system(size: 10)).foregroundStyle(subColor ?? TeslaDark.rowLabel).lineLimit(1).padding(.top, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(TSurface.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
    }
}

/// Small grey pill button used at the end of a row.
func pillButton(_ t: String, _ a: @escaping () -> Void) -> some View {
    Button(action: a) {
        Text(t).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(TSurface.selected))
    }
    .buttonStyle(.plain)
}

// MARK: - Controls › Climate

struct ClimateControlsPage: View {
    @ObservedObject var model: CarModel
    @State private var temp: Double?
    @State private var tempTask: Task<Void, Never>?
    private var c: CarSnapshot { model.car }
    private var shownTemp: Double { temp ?? c.setTempC ?? 22 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Inside \(deg(c.insideC)) · Outside \(deg(c.outsideC))")
                    .font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 14)
                HStack(spacing: 26) {
                    round("minus") { step(-0.5) }
                    HStack(alignment: .top, spacing: 2) {
                        Text(String(format: "%.1f", shownTemp)).font(.system(size: 52, weight: .light)).monospacedDigit()
                        Text("°C").font(.system(size: 15)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 10)
                    }
                    .foregroundStyle(.white)
                    round("plus") { step(0.5) }
                }
                .padding(.top, 10)
                Text("Set temperature").font(.system(size: 11)).foregroundStyle(TeslaDark.rowLabel).padding(.top, 2)
                Button { model.tap(.climate) } label: {
                    HStack(spacing: 10) {
                        if model.busy == .climate { ProgressView().tint(.white).scaleEffect(0.8) }
                        else { Image(systemName: "fanblades").font(.system(size: 17)) }
                        Text(c.climateOn ? "Turn climate off" : "Turn climate on").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(c.climateOn ? Color.white : CarColors.blue)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Capsule().fill(c.climateOn ? TSurface.selected : Color(red: 30 / 255, green: 58 / 255, blue: 92 / 255)))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.top, 18)

                TCaption(text: "Seats")
                seatRow("Driver seat cooling", "carseat.left.fan", seat: "driver", index: 0)
                seatRow("Passenger seat cooling", "carseat.right.fan", seat: "passenger", index: 1, last: true)

                TCaption(text: "Modes")
                TRow("Keep climate on", icon: "fanblades", subtitle: "After you leave the car") { EmptyView() } below: {
                    TSegment(items: ["Off", "Keep", "Pet", "Camp"], selected: keepIndex) { i in
                        Task { await model.send("set_climate_keeper_mode", ["mode": String(i)], done: ["Keep climate off", "Keep climate on", "Pet mode on", "Camp mode on"][i]) {
                            $0.keeperMode = ["off", "on", "dog", "camp"][i] } }
                    }
                }
                TRow("Cabin overheat protection", icon: "sun.max.trianglebadge.exclamationmark", subtitle: "Cools the cabin when it's hot inside") { EmptyView() } below: {
                    TSegment(items: ["Off", "Fan only", "A/C"], selected: overheatIndex) { i in
                        let params = i == 0 ? ["on": "false"] : ["on": "true", "fan_only": i == 1 ? "true" : "false"]
                        Task { await model.send("set_cabin_overheat_protection", params, done: "Overheat protection " + ["off", "fan only", "on"][i]) {
                            $0.overheat = ["Off", "FanOnly", "On"][i] } }
                    }
                }
                TRow("Defrost", icon: "windshield.front.and.heat.waves") {
                    Toggle("", isOn: Binding(get: { c.defrost == true }, set: { on in
                        Task { await model.send(on ? "start_defrost" : "stop_defrost", done: on ? "Defrost on" : "Defrost off") { $0.defrost = on } }
                    })).labelsHidden().tint(TSurface.green)
                }
                TRow("Bioweapon defence", icon: "aqi.medium", last: true) {
                    Toggle("", isOn: Binding(get: { c.bioweapon == true }, set: { on in
                        Task { await model.send("set_bioweapon_mode", ["on": on ? "true" : "false"], done: on ? "Bioweapon defence on" : "Bioweapon defence off") { $0.bioweapon = on } }
                    })).labelsHidden().tint(TSurface.green)
                }
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var keepIndex: Int? { ["off": 0, "on": 1, "dog": 2, "camp": 3][c.keeperMode] ?? 0 }
    private var overheatIndex: Int? {
        switch c.overheat { case "On": return 2; case "FanOnly": return 1; case "Off": return 0; default: return nil }
    }

    private func seatRow(_ t: String, _ icon: String, seat: String, index: Int, last: Bool = false) -> some View {
        TRow(t, icon: icon, last: last) {
            TSegment(items: ["Off", "1", "2", "3"], selected: c.seatCool?[index] ?? 0) { lvl in
                Task { await model.send("set_seat_cool", ["seat": seat, "level": String(lvl)], done: lvl == 0 ? "\(t) off" : "\(t) \(lvl)") {
                    var s = $0.seatCool ?? [0, 0]; s[index] = lvl; $0.seatCool = s } }
            }
            .frame(width: 150)
        }
    }

    private func step(_ d: Double) {
        let v = min(28, max(15, shownTemp + d))
        temp = v
        tempTask?.cancel()
        tempTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await model.send("set_temperatures", ["temperature": String(format: "%.1f", v)], done: String(format: "Set to %.1f°C", v)) { $0.setTempC = v }
            temp = nil
        }
    }

    private func round(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                .frame(width: 48, height: 48).background(Circle().fill(TSurface.field))
        }
        .buttonStyle(.plain)
    }

    private func deg(_ v: Double?) -> String { v.map { String(format: "%.1f°C", $0) } ?? "–" }
}

// MARK: - Controls › Security & modes

struct SecurityModesPage: View {
    @ObservedObject var model: CarModel
    private var c: CarSnapshot { model.car }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Security")
                TRow("Sentry mode", icon: "record.circle", subtitle: "Cameras record if someone comes close") {
                    toggle(c.sentry) { on in Task { await model.send(on ? "enable_sentry" : "disable_sentry", done: on ? "Sentry on" : "Sentry off") { $0.sentry = on } } }
                }
                TRow("Valet mode", icon: "person.badge.key", subtitle: "Limits speed and locks the glovebox", badge: AnyView(askTag)) {
                    toggle(c.valet) { _ in model.tap(.valet) }
                }
                TRow("Guest mode", icon: "person.2", subtitle: "Hides your data for someone else driving") {
                    toggle(c.guest == true) { on in Task { await model.send(on ? "enable_guest" : "disable_guest", done: on ? "Guest mode on" : "Guest mode off") { $0.guest = on } } }
                }
                TRow("Keyless driving", icon: "key", subtitle: "Drive without the phone key for 2 min", badge: AnyView(askTag), last: true) {
                    pillButton(model.busy == .keyless ? "…" : "Start") { model.tap(.keyless) }
                }

                TCaption(text: "Power")
                TRow("Low power mode", icon: "leaf", subtitle: "Saves energy when parked long") {
                    toggle(c.lowPower == true) { _ in Task { await model.run(.lowPower) } }
                }
                TRow("Keep accessory power", icon: "powerplug", subtitle: "USB and 12 V stay on after you leave", last: true) {
                    toggle(c.accessoryPower == true) { _ in Task { await model.run(.accessoryPower) } }
                }

                TCaption(text: "Find the car")
                HStack(spacing: 8) {
                    big("Flash") { model.tap(.flash) }
                    big("Honk") { model.tap(.honk) }
                    big("Boombox") { model.tap(.boombox) }
                }
                .padding(.horizontal, 20)
                TFootnote(text: "Which buttons ask first is set in My Car ☰ › Quick controls.")
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var askTag: some View { Text("asks first").font(.system(size: 10, weight: .medium)).foregroundStyle(CarColors.amber) }

    private func toggle(_ on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { on }, set: set)).labelsHidden().tint(TSurface.green)
    }

    private func big(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 13).fill(TSurface.field))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tyres

struct TyresPage: View {
    @ObservedObject var model: CarModel
    @AppStorage(CarModel.warnKey) private var warn = 2.6
    @AppStorage(CarModel.unitKey) private var unit = "bar"
    private var c: CarSnapshot { model.car }
    private let names = ["FRONT LEFT", "FRONT RIGHT", "REAR LEFT", "REAR RIGHT"]
    private let shortNames = ["Front left", "Front right", "Rear left", "Rear right"]

    var body: some View {
        let cols = (0..<4).map { low($0) ? CarColors.amber : Color.white }
        let d = TyreDiagram(colors: cols, lengthPt: 236)
        return ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Circle().fill(lowOnes.isEmpty ? TSurface.green : CarColors.amber).frame(width: 7, height: 7)
                    Text(statusText).font(.system(size: 14, weight: .medium)).foregroundStyle(lowOnes.isEmpty ? Color.white : CarColors.amber)
                    Spacer()
                    Text(readText).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
                .padding(.horizontal, 20).padding(.top, 14)

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .trailing, spacing: 0) {
                        block(0, .trailing).padding(.top, max(0, d.frontAxle - 34))
                        Spacer(minLength: 0)
                        block(2, .trailing).padding(.bottom, max(0, d.lengthPt - d.rearAxle - 34))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    d
                    VStack(alignment: .leading, spacing: 0) {
                        block(1, .leading).padding(.top, max(0, d.frontAxle - 34))
                        Spacer(minLength: 0)
                        block(3, .leading).padding(.bottom, max(0, d.lengthPt - d.rearAxle - 34))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: d.lengthPt)
                .padding(.horizontal, 12)
                .padding(.top, 22)

                summary.padding(.horizontal, 20).padding(.top, 18)

                TCaption(text: "Settings")
                TRow("Recommended (cold)", icon: "gauge.with.dots.needle.50percent", subtitle: "Model 3 · on the door pillar") {
                    TValue(value: fmt(CarModel.recommendedBar), unit: unit)
                }
                TRow("Warn me below", icon: "bell", subtitle: "That tyre turns amber here and on My Car") {
                    HStack(spacing: 0) {
                        Button { warn = max(2.0, ((warn - 0.1) * 10).rounded() / 10) } label: { Image(systemName: "minus").frame(width: 34, height: 30) }
                        Text(fmt(warn)).font(.system(size: 14, weight: .medium)).monospacedDigit().frame(minWidth: 34)
                        Button { warn = min(3.2, ((warn + 0.1) * 10).rounded() / 10) } label: { Image(systemName: "plus").frame(width: 34, height: 30) }
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                TRow("Unit", icon: "ruler", last: true) {
                    TSegment(items: ["bar", "psi"], selected: unit == "psi" ? 1 : 0) { unit = $0 == 1 ? "psi" : "bar" }
                        .frame(width: 104)
                }
                TFootnote(text: "Readings come from the car through Tessie. Tyres read about 0.2–0.3 bar higher when warm, so compare them in the morning.")
                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var lowOnes: [Int] { (0..<4).filter { low($0) } }
    private func low(_ i: Int) -> Bool { (c.tyres[i] ?? 99) < warn }

    private var statusText: String {
        if c.tyres.allSatisfy({ $0 == nil }) { return "No reading yet" }
        if lowOnes.isEmpty { return "All 4 tyres OK" }
        if lowOnes.count == 1, let v = c.tyres[lowOnes[0]] { return "\(shortNames[lowOnes[0]]) low · \(fmt(v)) \(unit)" }
        return "\(lowOnes.count) tyres low"
    }

    private var readText: String {
        guard let d = c.tyresRead ?? c.updated else { return "" }
        return "Read " + d.formatted(date: .omitted, time: .shortened)
    }

    private func block(_ i: Int, _ align: HorizontalAlignment) -> some View {
        let v = c.tyres[i]
        let diff = v.map { $0 - CarModel.recommendedBar }
        return VStack(alignment: align, spacing: 2) {
            Text(names[i]).font(.system(size: 10, weight: .medium)).kerning(0.5).foregroundStyle(TeslaDark.rowLabel)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v.map { fmt($0) } ?? "–").font(.system(size: 32, weight: .light)).foregroundStyle(low(i) ? CarColors.amber : .white)
                Text(unit).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
            }
            if let diff {
                Text((diff >= 0 ? "+" : "−") + fmt(abs(diff)) + " vs " + fmt(CarModel.recommendedBar))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(low(i) ? CarColors.amber : TSurface.green)
            }
        }
        .frame(height: 68, alignment: .top)
    }

    private var summary: some View {
        let vals = c.tyres.compactMap { $0 }
        let hi = vals.max(), lo = vals.min()
        let spread = (hi != nil && lo != nil) ? hi! - lo! : nil
        let warnSpread = (spread ?? 0) >= 0.3
        return HStack(spacing: 0) {
            stat(hi.map { fmt($0) } ?? "–", "Highest", .white)
            Rectangle().fill(TSurface.line).frame(width: 0.5, height: 28)
            stat(lo.map { fmt($0) } ?? "–", "Lowest", lo.map { $0 < warn } == true ? CarColors.amber : .white)
            Rectangle().fill(TSurface.line).frame(width: 0.5, height: 28)
            stat(spread.map { fmt($0) } ?? "–", "Difference", warnSpread ? CarColors.amber : .white)
        }
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.field))
    }

    private func stat(_ v: String, _ cap: String, _ col: Color) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(size: 17, weight: .light)).foregroundStyle(col)
            Text(cap).font(.system(size: 10)).foregroundStyle(TeslaDark.rowLabel)
        }
        .frame(maxWidth: .infinity)
    }

    /// Pressure in the chosen unit (bar with one decimal, psi whole numbers).
    private func fmt(_ bar: Double) -> String {
        unit == "psi" ? String(format: "%.0f", bar * 14.5038) : String(format: "%.1f", bar)
    }
}
