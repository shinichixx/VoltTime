import SwiftUI
import MapKit

/// The car page: View 1 (ring and cards) or View 2 (list style), switched in Settings → Car → Layout.
struct CarPage: View {
    @ObservedObject var car: CarModel
    @Binding var path: [Route]
    @AppStorage("car.layout") private var layout = 2
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if layout == 1 { CarView1(model: car, path: $path) } else { CarView2(model: car, path: $path) }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await car.refresh()
                try? await Task.sleep(for: .seconds(car.car.charging ? 20 : 60))
            }
        }
        .overlay(alignment: .bottom) {
            if let t = car.toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Color(white: 0.17)).clipShape(Capsule())
                    .padding(.bottom, 64)
                    .transition(.opacity)
            }
        }
        .confirmationDialog(car.confirming.map { "\($0.title)?" } ?? "",
                            isPresented: Binding(get: { car.confirming != nil }, set: { if !$0 { car.confirming = nil } }),
                            titleVisibility: .visible) {
            if let c = car.confirming {
                Button(c.short, role: c == .lock && car.car.locked != false ? .destructive : nil) { Task { await car.run(c) } }
            }
            Button("Cancel", role: .cancel) { car.confirming = nil }
        }
    }
}

// MARK: - View 1

struct CarView1: View {
    @ObservedObject var model: CarModel
    @Binding var path: [Route]
    @State private var scroll: CGFloat = 0
    private var c: CarSnapshot { model.car }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let heroH = w * 0.63
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()
                // Car stays put and dims as the page scrolls over it (to 18%).
                FadedCar(image: CarArt.image(charging: c.charging))
                    .frame(width: w * CGFloat(UserDefaults.standard.object(forKey: CarArt.scaleKey) as? Double ?? 1))
                    .offset(y: header + CGFloat(UserDefaults.standard.double(forKey: CarArt.offsetKey)))
                    .opacity(max(0.18, 1 - Double(scroll) / Double(heroH) * 0.82))
                    .scaleEffect(1 - min(max(scroll, 0), heroH) / heroH * 0.04)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 12) {
                        GeometryReader { g in
                            Color.clear.preference(key: ScrollY.self, value: -g.frame(in: .named("v1")).minY)
                        }
                        .frame(height: 0)
                        Color.clear.frame(height: header + heroH - 26)
                        BatteryRing(soc: c.soc ?? 0, limit: model.pendingLimit ?? c.limit ?? 80, rangeKm: c.rangeKm,
                                    kmPerPercent: c.kmPerPercent) { model.setLimit($0) }
                            .frame(width: min(w - 80, 290))
                        ControlStrip(model: model)
                            .padding(.horizontal, 16)
                        grid(w)
                        locationCard.padding(.horizontal, 16)
                        odometerCard.padding(.horizontal, 16)
                        footer
                        Spacer(minLength: 40)
                    }
                }
                .coordinateSpace(name: "v1")
                .onPreferenceChange(ScrollY.self) { scroll = $0 }
                .scrollIndicators(.hidden)
                .refreshable { await model.refresh() }

                headerView
            }
        }
    }

    private var header: CGFloat { 140 }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                if let t = CarArt.title {
                    Image(uiImage: t).resizable().scaledToFit().frame(width: 200)
                } else {
                    Text(c.name).font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                }
                Spacer()
                Button { path.append(.carSettings) } label: {
                    Image(systemName: "gearshape").font(.system(size: 22, weight: .light)).foregroundStyle(CarColors.muted)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            HStack(spacing: 6) {
                pill { Circle().fill(model.statusColor).frame(width: 7, height: 7); Text(model.statusWord).foregroundStyle(model.statusColor) }
                pill { Text(c.gear).fontWeight(.semibold); Text(gearWord) }
                pill {
                    Image(systemName: c.atHome ? "house" : "location").font(.system(size: 11))
                    Text(model.placeWord).lineLimit(1)
                    Rectangle().fill(Color(white: 0.23)).frame(width: 1, height: 12)
                    Image(systemName: c.charging ? "bolt.fill" : (c.cableConnected ? "powerplug" : "powerplug.portrait"))
                        .font(.system(size: 11)).foregroundStyle(c.charging ? TSurface.green : CarColors.muted)
                    Text(model.chargeWord).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(stops: [.init(color: .black, location: 0.8), .init(color: .black.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(min(1, scroll / 40))
                .ignoresSafeArea(edges: .top)
        )
    }

    private var gearWord: String {
        switch c.gear { case "D": return "Drive"; case "R": return "Reverse"; case "N": return "Neutral"; default: return "Park" }
    }

    private func pill<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        HStack(spacing: 5) { content() }
            .font(.system(size: 12))
            .foregroundStyle(Color(white: 0.78))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(CarColors.line, lineWidth: 1))
    }

    // 2×2: Temperature | Tyres, Security | Battery health
    private func grid(_ w: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                temperatureCard
                tyresCard
            }
            .frame(height: 196)
            HStack(spacing: 10) {
                securityCard
                healthCard
            }
            .frame(height: 200)
        }
        .padding(.horizontal, 16)
    }

    private var temperatureCard: some View {
        OutlineCard {
            VStack(alignment: .leading, spacing: 0) {
                CardBadge(icon: "thermometer.medium", title: "Temperature")
                Text("Cabin").font(.system(size: 11)).foregroundStyle(CarColors.muted).padding(.top, 14)
                Text(deg(c.insideC)).font(.system(size: 28, weight: .light)).foregroundStyle(.white)
                Text("Outside \(deg(c.outsideC)) · AC \(c.climateOn ? "on" : "off")").font(.system(size: 11)).foregroundStyle(CarColors.muted)
                Rectangle().fill(CarColors.line).frame(height: 1).padding(.vertical, 9)
                Text("Battery").font(.system(size: 11)).foregroundStyle(CarColors.muted)
                Text(deg(c.packTempC)).font(.system(size: 28, weight: .light)).foregroundStyle(.white)
                Text(c.batteryHeater ? "Warming" : "Not warming").font(.system(size: 11))
                    .foregroundStyle(c.batteryHeater ? CarColors.orange : CarColors.muted)
            }
        }
    }

    private var tyresCard: some View {
        let cols = (0..<4).map { model.tyreLow($0) ? CarColors.amber : Color.white }
        let d = TyreDiagram(colors: cols)
        return OutlineCard {
            VStack(spacing: 0) {
                CardBadge(icon: "circle.circle", title: "Tyres")
                ZStack(alignment: .top) {
                    d
                    HStack(spacing: 0) {
                        VStack(alignment: .trailing, spacing: 0) {
                            tyre(0).offset(y: d.frontAxle - 11)
                            Spacer()
                            tyre(2).offset(y: d.rearAxle - 97)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        Color.clear.frame(width: 60)
                        VStack(alignment: .leading, spacing: 0) {
                            tyre(1).offset(y: d.frontAxle - 11)
                            Spacer()
                            tyre(3).offset(y: d.rearAxle - 97)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 108)
                }
                .padding(.top, 12)
                Spacer(minLength: 4)
                Text("bar · \(model.tyreNote)").font(.system(size: 11))
                    .foregroundStyle(model.tyreNote.hasSuffix("low") ? CarColors.amber : CarColors.muted)
            }
        }
    }

    private func tyre(_ i: Int) -> some View {
        Text(c.tyres[i].map { String(format: "%.1f", $0) } ?? "–")
            .font(.system(size: 17)).foregroundStyle(model.tyreLow(i) ? CarColors.amber : .white)
            .frame(height: 22)
    }

    private var securityCard: some View {
        OutlineCard {
            VStack(alignment: .leading, spacing: 0) {
                CardBadge(icon: "lock.shield", title: "Security")
                let secure = c.locked == true && !c.anyWindowOpen && !c.doorsOpen && !c.trunkOpen && !c.frunkOpen
                Label(secure ? "All secure" : "Check the car", systemImage: secure ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(secure ? TSurface.green : CarColors.amber)
                    .padding(.top, 8).padding(.bottom, 4)
                secRow("Doors", c.locked == true ? (c.doorsOpen ? "Open" : "Locked") : "Unlocked", c.locked == true && !c.doorsOpen)
                HStack {
                    Text("Windows").font(.system(size: 11)).foregroundStyle(CarColors.muted)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2).fill(c.windowsOpen[i] ? CarColors.amber : TSurface.green).frame(width: 6, height: 10)
                        }
                    }
                    Text(c.anyWindowOpen ? openWindows : "Closed").font(.system(size: 13))
                        .foregroundStyle(c.anyWindowOpen ? CarColors.amber : TSurface.green)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .top) { Rectangle().fill(CarColors.line).frame(height: 1) }
                secRow("Sentry", c.sentry ? "On" : "Off", nil)
                secRow("Valet", c.valet ? "On" : "Off", nil)
            }
        }
    }

    private var openWindows: String {
        let n = ["FL", "FR", "RL", "RR"]
        return (0..<4).filter { c.windowsOpen[$0] }.map { n[$0] }.joined(separator: " ") + " open"
    }

    private func secRow(_ k: String, _ v: String, _ good: Bool?) -> some View {
        HStack {
            Text(k).font(.system(size: 11)).foregroundStyle(CarColors.muted)
            Spacer()
            Text(v).font(.system(size: 13)).foregroundStyle(good == nil ? .white : (good! ? TSurface.green : CarColors.amber))
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(CarColors.line).frame(height: 1) }
    }

    private var healthCard: some View {
        let h = model.health
        return OutlineCard {
            VStack(alignment: .leading, spacing: 0) {
                CardBadge(icon: "heart.text.square", title: "Battery health")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(h.healthPercent.map { String(format: "%.1f", $0) } ?? "–").font(.system(size: 26, weight: .light))
                    Text("% SoH").font(.system(size: 11)).foregroundStyle(CarColors.muted)
                }
                .foregroundStyle(.white)
                .padding(.top, 10)
                HealthCells(health: h.healthPercent).padding(.vertical, 8)
                kv("Max", h.maxRangeKm.map { "\(Int($0.rounded())) km" } ?? "–")
                kv("Capacity", h.capacityKWh.map { String(format: "%.1f kWh", $0) } ?? "–")
                kv("Cycles", h.cycles(lifetimeKWh: c.lifetimeKWh).map { "≈ \(Int($0.rounded()))" } ?? "–")
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 11)).foregroundStyle(CarColors.muted)
            Spacer()
            Text(v).font(.system(size: 13)).foregroundStyle(.white)
        }
        .padding(.vertical, 4)
        .overlay(alignment: .top) { Rectangle().fill(CarColors.line).frame(height: 1) }
    }

    private var locationCard: some View {
        VStack(spacing: 0) {
            CarMap(lat: c.lat, lon: c.lon).frame(height: 90)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.placeWord).font(.system(size: 14)).foregroundStyle(.white)
                    Text(c.address ?? "—").font(.system(size: 12)).foregroundStyle(CarColors.muted).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CarColors.faint)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CarColors.line, lineWidth: 1))
        .onTapGesture { openMaps() }
    }

    private func openMaps() {
        guard let la = c.lat, let lo = c.lon else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: la, longitude: lo)))
        item.name = c.name
        item.openInMaps()
    }

    private var odometerCard: some View {
        HStack {
            CardBadge(icon: "road.lanes", title: "Odometer")
            Spacer()
            Text(c.odometerKm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–")
                .font(.system(size: 24, weight: .light)).foregroundStyle(.white)
            Text("km").font(.system(size: 12)).foregroundStyle(CarColors.muted)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(CarColors.line, lineWidth: 1))
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(model.error ?? model.updatedText + " · pull to refresh").font(.system(size: 11))
                .foregroundStyle(model.error == nil ? CarColors.muted : CarColors.amber)
                .multilineTextAlignment(.center)
            Rectangle().fill(CarColors.line).frame(width: 24, height: 1).padding(.vertical, 6)
            Text(CarModel.versionLine).font(.system(size: 11)).foregroundStyle(CarColors.faint)
            if !CarModel.releaseLine.isEmpty { Text(CarModel.releaseLine).font(.system(size: 11)).foregroundStyle(CarColors.faint) }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private func deg(_ v: Double?) -> String { v.map { String(format: "%.1f°", $0) } ?? "–" }
}

private struct ScrollY: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct CarMap: View {
    let lat: Double?
    let lon: Double?
    var body: some View {
        if let lat, let lon {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 600, longitudinalMeters: 600)),
                interactionModes: []) {
                Annotation("", coordinate: coord) {
                    Circle().fill(CarColors.red).frame(width: 14, height: 14).overlay(Circle().stroke(.black, lineWidth: 3))
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, .dark)
            .id("\(lat),\(lon)")
        } else {
            Color(red: 0.06, green: 0.08, blue: 0.07)
        }
    }
}

// MARK: - View 2 (Tesla-app style list)

struct CarView2: View {
    @ObservedObject var model: CarModel
    @Binding var path: [Route]
    @State private var sliderLimit: Double?
    private var c: CarSnapshot { model.car }
    static let bg = Color(red: 23 / 255, green: 24 / 255, blue: 26 / 255)
    static let panel = Color(red: 33 / 255, green: 34 / 255, blue: 37 / 255)
    static let btn = Color(red: 44 / 255, green: 45 / 255, blue: 48 / 255)
    private var bg: Color { Self.bg }
    private var panel: Color { Self.panel }
    private var btn: Color { Self.btn }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                FadedCar(image: CarArt.image(charging: c.charging))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                ControlStrip(model: model, count: 5, plain: true)
                    .padding(.horizontal, 12)
                    .padding(.top, -6)
                chargingPanel
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                rows.padding(.top, 10)
                VStack(spacing: 3) {
                    Text(model.error ?? model.updatedText).foregroundStyle(model.error == nil ? CarColors.muted : CarColors.amber)
                    Text("VoltTime · " + CarModel.versionLine + (CarModel.releaseLine.isEmpty ? "" : " · " + CarModel.releaseLine.replacingOccurrences(of: "Released ", with: "")))
                        .foregroundStyle(CarColors.faint)
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                Spacer(minLength: 50)
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
        .background(bg.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text(c.name).font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { path.append(.carSettings) } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 21)).foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Color(white: 0.24), lineWidth: 1.5).frame(width: 34, height: 15)
                    RoundedRectangle(cornerRadius: 2).fill(socColor).frame(width: max(2, 29 * (c.soc ?? 0) / 100), height: 10).padding(.leading, 2.5)
                }
                Text("\(Int(c.soc ?? 0))%").font(.system(size: 15, weight: .semibold)).foregroundStyle(socColor)
                if c.charging { Image(systemName: "bolt.fill").foregroundStyle(TSurface.green) }
                Text("· \(c.rangeKm.map { "\(Int($0.rounded())) km" } ?? "—")").font(.system(size: 15, weight: .medium)).foregroundStyle(CarColors.muted)
            }
            Text([model.statusWord, c.atHome ? "Parked at home" : model.placeWord, c.gear].joined(separator: " · "))
                .font(.system(size: 14, weight: .medium)).foregroundStyle(CarColors.muted)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var socColor: Color { c.charging ? TSurface.green : ((c.soc ?? 0) < 20 ? CarColors.amber : .white) }

    private var chargingPanel: some View {
        let limit = sliderLimit ?? model.pendingLimit ?? c.limit ?? 80
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Charge limit: \(Int(limit))%").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text("·  " + model.chargeWord).font(.system(size: 15, weight: .medium)).foregroundStyle(CarColors.muted).lineLimit(1)
                }
                Text(chargeLine).font(.system(size: 13)).foregroundStyle(CarColors.muted)
                GeometryReader { g in
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(white: 0.2)).frame(height: 6)
                        Capsule().fill(c.charging ? TSurface.green : CarColors.amber).frame(width: w * (c.soc ?? 0) / 100, height: 6)
                        Circle().fill(Color(white: 0.92)).frame(width: 22, height: 22).offset(x: w * limit / 100 - 11)
                    }
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in sliderLimit = min(max((v.location.x / w * 100).rounded(), 50), 100) }
                        .onEnded { _ in if let s = sliderLimit { model.setLimit(s) }; sliderLimit = nil })
                }
                .frame(height: 30)
                .padding(.vertical, 6)
                HStack {
                    Button { Task { await model.setAmps(Int(c.chargeAmps ?? 32) - 1) } } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text("\(Int(c.chargeAmps ?? 32)) A").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button { Task { await model.setAmps(Int(c.chargeAmps ?? 32) + 1) } } label: { Image(systemName: "chevron.right") }
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(white: 0.79))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(btn))
                .buttonStyle(.plain)
            }
            .padding(20)
            Rectangle().fill(Color(white: 0.16)).frame(height: 1)
            HStack(spacing: 0) {
                panelButton(c.charging ? "Stop charging" : "Start charging") { Task { await model.run(.charge) } }
                Rectangle().fill(Color(white: 0.16)).frame(width: 1)
                panelButton(c.portOpen ? "Close charge port" : "Open charge port") { Task { await model.run(.chargePort) } }
            }
            .frame(height: 50)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(panel))
    }

    private var chargeLine: String {
        var parts: [String] = []
        parts.append(c.cableConnected ? "Plugged in" : "Unplugged")
        if let p = c.chargerPowerKW { parts.append("\(Int(p)) kW") }
        if let e = c.energyAddedKWh, e > 0 { parts.append(String(format: "+%.0f kWh", e)) }
        if let a = c.chargeAmpsMax { parts.append("\(Int(a)) A max") }
        if let v = c.chargerVoltage, v > 0 { parts.append("\(Int(v)) V") }
        return parts.joined(separator: " · ")
    }

    private func panelButton(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.79)).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var rows: some View {
        let h = model.health
        let health = [h.healthPercent.map { String(format: "Health %.1f%%", $0) },
                      h.maxRangeKm.map { "Max \(Int($0.rounded())) km" },
                      h.cycles(lifetimeKWh: c.lifetimeKWh).map { "≈\(Int($0.rounded())) cycles" }].compactMap { $0 }
        let tyres = c.tyres.map { $0.map { String(format: "%.1f", $0) } ?? "–" }.joined(separator: " · ") + " bar"
        return VStack(spacing: 0) {
            row("car", "Controls", nil) { path.append(.carDetail(.controls)) }
            row("thermometer.medium", "Climate", "Interior \(deg(c.insideC)) · Exterior \(deg(c.outsideC))") { path.append(.carDetail(.climate)) }
            row("circle.circle", "Tyres", tyres, tag: model.tyreNote.hasSuffix("low") ? model.tyreNote : nil) { path.append(.carDetail(.tyres)) }
            row("minus.plus.batteryblock", "Battery", health.isEmpty ? "—" : health.joined(separator: " · ")) { path.append(.carDetail(.battery)) }
            row("lock.shield", "Security", [c.locked == true ? "Locked" : "Unlocked", c.anyWindowOpen ? "Window open" : "Windows closed",
                                            "Sentry \(c.sentry ? "on" : "off")"].joined(separator: " · ")) { path.append(.carDetail(.security)) }
            row("location.north", "Location", [model.placeWord, c.address?.split(separator: ",").dropFirst().first.map { String($0).trimmingCharacters(in: .whitespaces) }]
                .compactMap { $0 }.joined(separator: " · ")) { path.append(.carDetail(.location)) }
            row("calendar.badge.clock", "Charging plan", "Tonight's start time and ready time") { path.append(.settings) }
            row("road.lanes", "Odometer", c.odometerKm.map { "\($0.formatted(.number.precision(.fractionLength(0)))) km" } ?? "—") { path.append(.carDetail(.odometer)) }
        }
    }

    private func row(_ icon: String, _ title: String, _ sub: String?, tag: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon).font(.system(size: 22, weight: .light)).foregroundStyle(Color(white: 0.79)).frame(width: 46, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    if let sub {
                        (Text(sub).foregroundColor(CarColors.muted) + Text(tag.map { "  · \($0)" } ?? "").foregroundColor(CarColors.amber))
                            .font(.system(size: 13, weight: .medium)).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(CarColors.faint)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, sub == nil ? 16 : 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deg(_ v: Double?) -> String { v.map { String(format: "%.1f°C", $0) } ?? "—" }
}

// MARK: - Detail pages (opened from View 2's rows)

enum CarDetail: String, Hashable { case controls, climate, tyres, battery, security, location, odometer }

struct CarDetailPage: View {
    @ObservedObject var model: CarModel
    let detail: CarDetail
    private var c: CarSnapshot { model.car }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                switch detail {
                case .controls: controls
                case .climate: climate
                case .tyres: tyres
                case .battery: battery
                case .security: security
                case .location: location
                case .odometer: odometer
                }
                Spacer(minLength: 40)
            }
        }
        .teslaPage(title, black: true)
    }

    private var title: String {
        switch detail {
        case .controls: return "Controls"
        case .climate: return "Climate"
        case .tyres: return "Tyres"
        case .battery: return "Battery"
        case .security: return "Security"
        case .location: return "Location"
        case .odometer: return "Odometer"
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ForEach(CarControl.Group.allCases, id: \.self) { g in
                TCaption(text: g.rawValue)
                let items = CarControl.allCases.filter { $0.group == g }
                ForEach(items) { c in
                    Button { model.tap(c) } label: {
                        TRow(c.title, icon: c.icon(model.car), last: c == items.last) {
                            if model.busy == c { ProgressView().tint(.white).scaleEffect(0.8) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var climate: some View {
        VStack(spacing: 0) {
            TStats(items: [TStat(value: f(c.insideC), unit: "°C", caption: "Interior"),
                           TStat(value: f(c.outsideC), unit: "°C", caption: "Exterior"),
                           TStat(value: f(c.setTempC), unit: "°C", caption: "Set to")])
                .padding(.top, 24)
            TCaption(text: "Climate")
            Button { model.tap(.climate) } label: {
                TRow(c.climateOn ? "Turn off" : "Turn on", icon: "fanblades", subtitle: c.climateOn ? "On" : "Off", last: true) { EmptyView() }
            }.buttonStyle(.plain)
            TCaption(text: "Battery")
            TRow("Battery temperature", icon: "thermometer.medium", subtitle: c.batteryHeater ? "Warming" : "Not warming", last: true) {
                TValue(value: f(c.packTempC), unit: "°C")
            }
        }
    }

    private var tyres: some View {
        let cols = (0..<4).map { model.tyreLow($0) ? CarColors.amber : Color.white }
        let d = TyreDiagram(colors: cols, lengthPt: 260)
        return VStack(spacing: 0) {
            ZStack(alignment: .top) {
                d
                HStack {
                    VStack { big(0).offset(y: d.frontAxle - 18); Spacer(); big(2).offset(y: d.rearAxle - 260 + 18) }
                    Spacer().frame(width: d.lengthPt * 0.5)
                    VStack { big(1).offset(y: d.frontAxle - 18); Spacer(); big(3).offset(y: d.rearAxle - 260 + 18) }
                }
                .frame(height: 260)
            }
            .padding(.top, 30)
            Text("bar · recommended \(String(format: "%.1f", CarModel.recommendedBar)) · \(model.tyreNote)")
                .font(.system(size: 13)).foregroundStyle(model.tyreNote.hasSuffix("low") ? CarColors.amber : CarColors.muted)
                .padding(.top, 20)
        }
    }

    private func big(_ i: Int) -> some View {
        Text(c.tyres[i].map { String(format: "%.1f", $0) } ?? "–")
            .font(.system(size: 30, weight: .light)).foregroundStyle(model.tyreLow(i) ? CarColors.amber : .white)
    }

    private var battery: some View {
        let h = model.health
        return VStack(spacing: 0) {
            TStats(items: [TStat(value: "\(Int(c.soc ?? 0))", unit: "%", caption: "Now"),
                           TStat(value: c.rangeKm.map { "\(Int($0.rounded()))" } ?? "–", unit: "km", caption: "Range"),
                           TStat(value: c.limit.map { "\(Int($0))" } ?? "–", unit: "%", caption: "Limit")])
                .padding(.top, 24)
            TCaption(text: "Health")
            HealthCells(health: h.healthPercent).padding(.horizontal, 20).padding(.vertical, 8)
            TRow("Health", icon: "heart.text.square") { TValue(value: h.healthPercent.map { String(format: "%.1f", $0) } ?? "–", unit: "%") }
            TRow("Max range at 100%", icon: "arrow.left.and.right") { TValue(value: h.maxRangeKm.map { "\(Int($0.rounded()))" } ?? "–", unit: "km") }
            TRow("Capacity", icon: "minus.plus.batteryblock") { TValue(value: h.capacityKWh.map { String(format: "%.1f", $0) } ?? "–", unit: "kWh") }
            TRow("When new", icon: "sparkles") { TValue(value: h.originalCapacityKWh.map { String(format: "%.1f", $0) } ?? "–", unit: "kWh") }
            TRow("Cycles", icon: "arrow.triangle.2.circlepath", subtitle: "Lifetime energy ÷ capacity") {
                TValue(value: h.cycles(lifetimeKWh: c.lifetimeKWh).map { "≈ \(Int($0.rounded()))" } ?? "–")
            }
            TRow("Lifetime energy", icon: "bolt", last: true) { TValue(value: c.lifetimeKWh.map { "\(Int($0.rounded()))" } ?? "–", unit: "kWh") }
        }
    }

    private var security: some View {
        let names = ["Front left", "Front right", "Rear left", "Rear right"]
        return VStack(spacing: 0) {
            TCaption(text: "Doors")
            TRow("Doors", icon: "lock", subtitle: c.doorsOpen ? "A door is open" : nil) { TValue(value: c.locked == true ? "Locked" : "Unlocked", color: c.locked == true ? TSurface.green : CarColors.amber) }
            TRow("Front trunk", icon: "car.side.front.open") { TValue(value: c.frunkOpen ? "Open" : "Closed") }
            TRow("Rear trunk", icon: "car.side.rear.open", last: true) { TValue(value: c.trunkOpen ? "Open" : "Closed") }
            TCaption(text: "Windows")
            ForEach(0..<4, id: \.self) { i in
                TRow(names[i], icon: "window.vertical.closed", last: i == 3) {
                    TValue(value: c.windowsOpen[i] ? "Open" : "Closed", color: c.windowsOpen[i] ? CarColors.amber : TSurface.green)
                }
            }
            TCaption(text: "Modes")
            TRow("Sentry", icon: "eye") { TValue(value: c.sentry ? "On" : "Off") }
            TRow("Valet", icon: "person.badge.key", last: true) { TValue(value: c.valet ? "On" : "Off") }
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 10) {
            CarMap(lat: c.lat, lon: c.lon).frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 16))
            Text(model.placeWord).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
            Text(c.address ?? "—").font(.system(size: 13)).foregroundStyle(CarColors.muted)
        }
        .padding(20)
    }

    private var odometer: some View {
        TStats(items: [TStat(value: c.odometerKm.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "–", unit: "km", caption: "Odometer")])
            .padding(.top, 40)
    }

    private func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "–" }
}
