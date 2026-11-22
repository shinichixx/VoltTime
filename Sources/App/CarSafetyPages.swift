import SwiftUI
import MapKit
import CoreLocation

// Security and Location pages (opened from the car page rows).

// MARK: - Security

struct CarSecurityPage: View {
    @ObservedObject var model: CarModel
    private var c: CarSnapshot { model.car }
    typealias K = TeslaApp

    private static let corners = ["Front left", "Front right", "Rear left", "Rear right"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statusCard
                caption("Doors & windows")
                carCard
                caption("Modes")
                modesCard
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    // Everything that's open, in plain words.
    private var issues: [String] {
        var out: [String] = []
        for i in 0..<4 where c.doorOpen(i) { out.append(Self.corners[i] + " door open") }
        if c.doors == nil && c.doorsOpen { out.append("A door is open") }
        for i in 0..<4 where c.windowsOpen[i] { out.append(Self.corners[i] + " window open") }
        if c.frunkOpen { out.append("Front trunk open") }
        if c.trunkOpen { out.append("Rear trunk open") }
        return out
    }

    private var statusCard: some View {
        let locked = c.locked == true
        let secure = locked && issues.isEmpty
        let title = secure ? "Secure" : (locked ? "Check the car" : "Unlocked")
        let line = secure ? "Locked · everything closed"
            : (issues.isEmpty ? "Everything closed" : issues.prefix(2).joined(separator: " · ") + (issues.count > 2 ? " · +\(issues.count - 2)" : ""))
        return HStack(spacing: 14) {
            Image(systemName: secure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.system(size: 30))
                .foregroundStyle(secure ? TSurface.green : CarColors.amber)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.app(size: 22, weight: .semibold)).foregroundStyle(K.title)
                Text(line).font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button { model.tap(.lock) } label: {
                Group {
                    if model.busy == .lock { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Text(locked ? "Unlock" : "Lock").font(.app(size: 13, weight: .medium)).foregroundStyle(K.title) }
                }
                .frame(width: 84, height: 32)
                .background(Capsule().fill(K.track))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))
    }

    private func caption(_ t: String) -> some View {
        Text(t.uppercased()).font(.app(size: 11, weight: .semibold)).kerning(0.8).foregroundStyle(Color(white: 0.4))
            .padding(.top, 24).padding(.bottom, 8).padding(.leading, 4)
    }

    // Top-down car: a coloured bar on each side for each door/window, labels beside it.
    private var carCard: some View {
        VStack(spacing: 8) {
            Text("Frunk · " + (c.frunkOpen ? "Open" : "Closed"))
                .font(.app(size: 12, weight: .medium)).foregroundStyle(c.frunkOpen ? CarColors.amber : K.grey)
            let car = TopDownCar(open: (0..<4).map { c.doorOpen($0) || c.windowsOpen[$0] },
                                 doorOpen: (0..<4).map { c.doorOpen($0) },
                                 frunk: c.frunkOpen, trunk: c.trunkOpen, lengthPt: 250)
            HStack(spacing: 0) {
                // labels centred on the middle of each door
                ZStack(alignment: .topLeading) {
                    cornerLabel(0).offset(y: car.frontMid - 17)
                    cornerLabel(2).offset(y: car.rearMid - 17)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                car
                ZStack(alignment: .topTrailing) {
                    cornerLabel(1).offset(y: car.frontMid - 17)
                    cornerLabel(3).offset(y: car.rearMid - 17)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .frame(height: car.lengthPt)
            Text("Trunk · " + (c.trunkOpen ? "Open" : "Closed"))
                .font(.app(size: 12, weight: .medium)).foregroundStyle(c.trunkOpen ? CarColors.amber : K.grey)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))
    }

    private func cornerLabel(_ i: Int) -> some View {
        let state = c.doorOpen(i) ? "Door open" : (c.windowsOpen[i] ? "Window open" : "Closed")
        let open = state != "Closed"
        return VStack(alignment: i % 2 == 0 ? .leading : .trailing, spacing: 2) {
            Text(Self.corners[i]).font(.app(size: 12, weight: .medium)).foregroundStyle(K.grey)
            Text(state).font(.app(size: 15, weight: .medium)).foregroundStyle(open ? CarColors.amber : K.title)
        }
    }

    private var modesCard: some View {
        VStack(spacing: 0) {
            modeRow(icon: AnyView(SentryGlyph(on: c.sentry, size: 22, color: K.grey)),
                    title: "Sentry", sub: "Cameras watch the car when parked", on: c.sentry, control: .sentry)
            Rectangle().fill(K.track).frame(height: 1).padding(.leading, 52)
            modeRow(icon: AnyView(Image(systemName: "person.badge.key").font(.system(size: 19)).foregroundStyle(K.grey)),
                    title: "Valet", sub: "Limits speed, locks the glovebox", on: c.valet, control: .valet)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))
    }

    private func modeRow(icon: AnyView, title: String, sub: String, on: Bool, control: CarControl) -> some View {
        HStack(spacing: 14) {
            icon.frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(size: 16, weight: .medium)).foregroundStyle(K.title)
                Text(sub).font(.app(size: 12)).foregroundStyle(K.grey)
            }
            Spacer()
            if model.busy == control {
                ProgressView().tint(.white)
            } else {
                // Valet asks first (Quick controls setting); Sentry goes straight away.
                Toggle("", isOn: Binding(get: { on }, set: { _ in model.tap(control) }))
                    .labelsHidden()
                    .tint(TSurface.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Model 3 from above, with a bar along each side for each door (amber when open).
struct TopDownCar: View {
    let open: [Bool]        // FL FR RL RR: door or window open
    let doorOpen: [Bool]
    let frunk: Bool
    let trunk: Bool
    var lengthPt: CGFloat = 236

    // Model 3 to scale (same outline as the Tyres page): 4720 × 1848 mm, 2089 mm across the mirrors.
    static let frontDoor: (CGFloat, CGFloat) = (0.275, 0.50)   // fraction of the length from the nose
    static let rearDoor: (CGFloat, CGFloat) = (0.515, 0.70)
    var width: CGFloat { TyreDiagram.Wm * lengthPt / TyreDiagram.L + 6 }
    /// Middle of the front and rear doors, for lining up the labels.
    var frontMid: CGFloat { (Self.frontDoor.0 + Self.frontDoor.1) / 2 * lengthPt }
    var rearMid: CGFloat { (Self.rearDoor.0 + Self.rearDoor.1) / 2 * lengthPt }

    var body: some View {
        let L = TyreDiagram.L, Wb = TyreDiagram.Wb, Wm = TyreDiagram.Wm
        let k = lengthPt / L
        Canvas { ctx, sz in
            let mx = sz.width / 2
            let hw = Wb / 2 * k, hm = Wm / 2 * k, Lp = L * k
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mx + x, y: y) }
            var shell = Path()
            shell.move(to: P(-hw * 0.80, Lp * 0.035))
            shell.addCurve(to: P(hw * 0.80, Lp * 0.035), control1: P(-hw * 0.55, 0), control2: P(hw * 0.55, 0))
            shell.addCurve(to: P(hw, Lp * 0.22), control1: P(hw * 0.97, Lp * 0.07), control2: P(hw, Lp * 0.14))
            shell.addLine(to: P(hw, Lp * 0.86))
            shell.addCurve(to: P(0, Lp), control1: P(hw, Lp * 0.95), control2: P(hw * 0.85, Lp))
            shell.addCurve(to: P(-hw, Lp * 0.86), control1: P(-hw * 0.85, Lp), control2: P(-hw, Lp * 0.95))
            shell.addLine(to: P(-hw, Lp * 0.22))
            shell.addCurve(to: P(-hw * 0.80, Lp * 0.035), control1: P(-hw, Lp * 0.14), control2: P(-hw * 0.97, Lp * 0.07))
            ctx.fill(shell, with: .color(Color(white: 0.10)))
            ctx.stroke(shell, with: .color(Color(white: 0.42)), lineWidth: 1.6)
            // windscreen, glass roof, rear glass
            let glass = Color(red: 0.17, green: 0.20, blue: 0.25)
            func quad(_ y0: CGFloat, _ c0: CGFloat, _ y1: CGFloat, _ c1: CGFloat, _ w0: CGFloat, _ w1: CGFloat, _ col: Color) {
                var p = Path()
                p.move(to: P(-hw * w0, Lp * y0)); p.addQuadCurve(to: P(hw * w0, Lp * y0), control: P(0, Lp * c0))
                p.addLine(to: P(hw * w1, Lp * y1)); p.addQuadCurve(to: P(-hw * w1, Lp * y1), control: P(0, Lp * c1))
                p.closeSubpath(); ctx.fill(p, with: .color(col))
            }
            quad(0.30, 0.25, 0.42, 0.40, 0.82, 0.76, glass)
            quad(0.43, 0.41, 0.64, 0.655, 0.76, 0.76, Color(red: 0.12, green: 0.14, blue: 0.17))
            quad(0.65, 0.665, 0.78, 0.81, 0.76, 0.80, glass)
            // mirrors
            let my = Lp * 0.31
            for s in [-1.0, 1.0] as [CGFloat] {
                var m = Path()
                m.move(to: P(s * hw, my)); m.addLine(to: P(s * hm, my + 1)); m.addLine(to: P(s * hm, my + 3.5)); m.addLine(to: P(s * hw, my + 3.5)); m.closeSubpath()
                ctx.fill(m, with: .color(Color(white: 0.29)))
            }
            // frunk and trunk lid edges (amber when open)
            for (y, bow, isOpen) in [(Lp * 0.27, -Lp * 0.012, frunk), (Lp * 0.80, Lp * 0.012, trunk)] {
                var p = Path(); p.move(to: P(-hw * 0.82, y)); p.addQuadCurve(to: P(hw * 0.82, y), control: P(0, y + bow * 2))
                ctx.stroke(p, with: .color(isOpen ? CarColors.amber : Color(white: 0.35)), lineWidth: isOpen ? 3 : 1.4)
            }
            // doors where the real ones are: green closed, amber open (door or window)
            let spans = [Self.frontDoor, Self.rearDoor]
            for i in 0..<4 {
                let s: CGFloat = i % 2 == 0 ? -1 : 1
                let (f0, f1) = spans[i / 2]
                let y0 = Lp * f0 + 2, y1 = Lp * f1 - 2
                var p = Path(); p.move(to: P(s * hw, y0)); p.addLine(to: P(s * hw, y1))
                ctx.stroke(p, with: .color(open[i] ? CarColors.amber : TSurface.green), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                if doorOpen[i] {   // the door swung out
                    var d = Path(); d.move(to: P(s * hw, y0)); d.addLine(to: P(s * (hw + 8), y1 - 4))
                    ctx.stroke(d, with: .color(CarColors.amber), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
        }
        .frame(width: width, height: lengthPt)
    }
}

// MARK: - Location

struct CarLocationPage: View {
    @ObservedObject var model: CarModel
    @State private var camera: MapCameraPosition = .automatic
    @State private var lines: [String] = []
    @State private var geocodedFor = ""
    private var c: CarSnapshot { model.car }
    typealias K = TeslaApp

    private var coord: CLLocationCoordinate2D? {
        guard let la = c.lat, let lo = c.lon else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }

    private func carRegion(_ co: CLLocationCoordinate2D) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: co, latitudinalMeters: 450, longitudinalMeters: 450))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                map
                HStack(alignment: .center, spacing: 10) {
                    Text(model.placeWord).font(.app(size: 26, weight: .semibold)).foregroundStyle(K.title).lineLimit(1)
                    Text(tag.0).font(.app(size: 12, weight: .medium)).foregroundStyle(tag.1)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(K.track))
                }
                .padding(.top, 18)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(addressLines, id: \.self) { Text($0) }
                }
                .font(.app(size: 15)).foregroundStyle(Color(white: 0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .textSelection(.enabled)

                // Exact position, 5 decimals (about 1 m)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GPS").font(.app(size: 11, weight: .semibold)).kerning(0.6).foregroundStyle(K.grey)
                        Text(gpsText).font(.app(size: 17, weight: .regular).monospacedDigit()).foregroundStyle(K.title)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = gpsText
                        model.show(Banner(title: "Coordinates copied", detail: gpsText, icon: "doc.on.doc", tint: TSurface.green))
                    } label: {
                        Text("Copy").font(.app(size: 13, weight: .medium)).foregroundStyle(K.title)
                            .frame(width: 66, height: 32).background(Capsule().fill(K.track))
                    }
                    .buttonStyle(.plain)
                    .disabled(coord == nil)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))
                .padding(.top, 18)

                HStack(spacing: 10) {
                    Button(action: openMaps) { big("Open in Maps") }.buttonStyle(.plain).disabled(coord == nil)
                    ShareLink(item: shareText) { big("Share") }.disabled(coord == nil)
                }
                .padding(.top, 12)

                Text(updated).font(.app(size: 12)).foregroundStyle(K.grey).padding(.top, 14)
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task(id: "\(c.lat ?? 0),\(c.lon ?? 0)") {
            if let co = coord { camera = carRegion(co) }
            await geocode()
        }
    }

    private var map: some View {
        ZStack(alignment: .bottomTrailing) {
            if let co = coord {
                Map(position: $camera, interactionModes: [.pan, .zoom]) {
                    Annotation("", coordinate: co, anchor: .center) {
                        ZStack {
                            Circle().fill(CarColors.red).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white, lineWidth: 3))
                                .shadow(color: .black.opacity(0.5), radius: 4)
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(c.heading ?? 0))   // points the way the car faces
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { }
                .environment(\.colorScheme, .dark)
                Button { withAnimation { camera = carRegion(co) } } label: {
                    Image(systemName: "location.fill").font(.system(size: 15)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(12)
            } else {
                Color(red: 0.06, green: 0.08, blue: 0.07)
                Text("No position yet").font(.app(size: 13)).foregroundStyle(K.grey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func big(_ t: String) -> some View {
        Text(t).font(.app(size: 15, weight: .medium)).foregroundStyle(K.title)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 12).fill(K.panel))
    }

    private var tag: (String, Color) {
        if c.charging { return ("Charging", TSurface.green) }
        if ["D", "R", "N"].contains(c.gear) || (c.speedKmh ?? 0) > 0 { return ("Driving", K.title) }
        return ("Parked", K.grey)
    }

    private var gpsText: String {
        guard let la = c.lat, let lo = c.lon else { return "—" }
        return String(format: "%.5f, %.5f", la, lo)
    }

    private var addressLines: [String] {
        if !lines.isEmpty { return lines }
        if let a = c.address, !a.isEmpty { return [a] }
        return ["Address not available"]
    }

    private var shareText: String {
        var t = c.name + " · " + model.placeWord + "\n" + addressLines.joined(separator: "\n")
        if let la = c.lat, let lo = c.lon {
            t += "\n" + gpsText + "\nhttps://maps.apple.com/?ll=\(String(format: "%.5f,%.5f", la, lo))&q=\(c.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Car")"
        }
        return t
    }

    private var updated: String {
        guard let u = c.located ?? c.updated else { return "" }
        return "Updated " + u.formatted(date: .omitted, time: .shortened)
    }

    private func openMaps() {
        guard let co = coord else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: co))
        item.name = c.name
        item.openInMaps()
    }

    /// Full street address from the exact position (Apple's lookup); Tessie's address if that fails.
    private func geocode() async {
        guard let la = c.lat, let lo = c.lon else { return }
        let key = String(format: "%.5f,%.5f", la, lo)
        guard key != geocodedFor else { return }
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: la, longitude: lo),
                                                                       preferredLocale: Locale(identifier: "en_MY")).first else { return }
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let first = [street.isEmpty ? p.name : street, p.subLocality].compactMap { $0 }.filter { !$0.isEmpty }
        let town = [p.postalCode, p.locality].compactMap { $0 }.joined(separator: " ")
        let second = [town, p.administrativeArea, p.country].compactMap { $0 }.filter { !$0.isEmpty }
        let out = [first.joined(separator: ", "), second.joined(separator: ", ")].filter { !$0.isEmpty }
        if !out.isEmpty { lines = out; geocodedFor = key }
    }
}
