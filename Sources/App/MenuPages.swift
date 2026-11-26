import SwiftUI
import PhotosUI

// ☰ on My Car and My Home opens the same Menu (Tesla app style): profile, My Products, Connection,
// the car's buttons and alerts, Backup, and the app version at the bottom.

// MARK: - Profile (photo, name, email), kept on the phone and in backups

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    nonisolated static let nameKey = "profile.name"
    nonisolated static let emailKey = "profile.email"
    nonisolated static let photoName = "profile.jpg"
    nonisolated static var photoURL: URL { CarArt.folder.appendingPathComponent(photoName) }

    @Published var name: String { didSet { UserDefaults.standard.set(name, forKey: Self.nameKey) } }
    @Published var email: String { didSet { UserDefaults.standard.set(email, forKey: Self.emailKey) } }
    @Published private(set) var photo: UIImage?

    private init() {
        name = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        photo = UIImage(contentsOfFile: Self.photoURL.path)
    }

    /// After a restore: pick up what came back.
    func reload() {
        let n = UserDefaults.standard.string(forKey: Self.nameKey) ?? ""
        let e = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
        if n != name { name = n }
        if e != email { email = e }
        photo = UIImage(contentsOfFile: Self.photoURL.path)
    }

    /// Square, 600 px, JPEG: small enough to sit in every backup.
    func setPhoto(_ data: Data) {
        guard let img = UIImage(data: data) else { return }
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2, y: (img.size.height - side) / 2, width: side, height: side)
        let out = 600.0
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        let r = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: fmt)
        let square = r.image { _ in
            let k = out / side
            img.draw(in: CGRect(x: -crop.minX * k, y: -crop.minY * k, width: img.size.width * k, height: img.size.height * k))
        }
        guard let jpg = square.jpegData(compressionQuality: 0.85) else { return }
        try? jpg.write(to: Self.photoURL, options: .atomic)
        photo = square
    }
}

struct ProfilePhoto: View {
    let image: UIImage?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(TSurface.field)
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Menu row (Tesla app: filled grey icon, big white title, optional grey line, chevron)

struct MenuRow<Icon: View>: View {
    let title: String
    var subtitle: String? = nil
    var dot: Color? = nil
    var compact = false   // the Menu page: Tesla app sizes (15.5 pt title, 12 pt line, 64 pt row, smaller icon)
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 0) {
            icon()
                .frame(width: 26, height: 26)
                .scaleEffect(compact ? 0.77 : 1, anchor: .leading)
                .frame(width: 49, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.app(size: compact ? 15.5 : 17, weight: .semibold)).foregroundStyle(.white)
                if let subtitle {
                    HStack(spacing: 6) {
                        if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                        Text(subtitle).font(.app(size: compact ? 12 : 12.5, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .regular)).foregroundStyle(TeslaDark.dim)
        }
        .padding(.leading, 37)
        .padding(.trailing, 33)
        .frame(height: compact ? 64 : 70)
        .contentShape(Rectangle())
    }
}

/// SF Symbol in the menu's filled grey.
struct MenuSymbol: View {
    let name: String
    var size: CGFloat = 20
    var body: some View {
        Image(systemName: name).font(.system(size: size, weight: .medium)).foregroundStyle(TeslaDark.rowIcon)
    }
}

// MARK: - Menu

struct MenuPage: View {
    @ObservedObject var car: CarModel
    @ObservedObject var energy: EnergyStore
    @ObservedObject var home: HomeModel
    /// Closes the menu and shows that tab (0 My Car, 1 My Home).
    let select: (Int) -> Void
    @ObservedObject private var profile = ProfileStore.shared
    @ObservedObject private var backup = BackupManager.shared
    @ObservedObject private var s3xy = S3XYLink.shared
    @AppStorage("car.gate.ask") private var gateAsk = true

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink { ProfilePage() } label: { profileHeader }
                    .buttonStyle(.plain)
                    .padding(.top, 32)
                    .padding(.bottom, 16)

                NavigationLink { MyProductsPage(car: car, select: select) } label: {
                    MenuRow(title: "My Products", compact: true) { MenuSymbol(name: "car.fill") }
                }.buttonStyle(.plain)
                NavigationLink { ConnectionPage(car: car, home: home) } label: {
                    MenuRow(title: "Connection", subtitle: connectionLine, compact: true) { ConnectionGlyph(size: 26, color: TeslaDark.rowIcon) }
                }.buttonStyle(.plain)
                NavigationLink { QuickControlsPage(car: car) } label: {
                    MenuRow(title: "Quick Controls",
                            subtitle: car.controls.prefix(QuickControlsPage.slots).map(\.short).joined(separator: " · "), compact: true) {
                        MenuSymbol(name: "square.grid.3x2.fill", size: 18)
                    }
                }.buttonStyle(.plain)
                NavigationLink { AutogatePage(car: car) } label: {
                    MenuRow(title: "Autogate", subtitle: gateAsk ? "Asks before sending" : "Sends straight away · asks when away", compact: true) {
                        GateGlyph(size: 22, color: TeslaDark.rowIcon)
                    }
                }.buttonStyle(.plain)
                NavigationLink { NotificationsPage() } label: {
                    MenuRow(title: "Notifications", subtitle: alertsLine, compact: true) { MenuSymbol(name: "bell.fill") }
                }.buttonStyle(.plain)
                NavigationLink { BackupPage(energy: energy, home: home) } label: {
                    MenuRow(title: "Backup", subtitle: (backup.lastDate == nil ? "Not saved yet" : backup.lastText) + " · iCloud Drive",
                            dot: backup.summaryColor, compact: true) {
                        MenuSymbol(name: "arrow.triangle.2.circlepath", size: 19)
                    }
                }.buttonStyle(.plain)

                versionPanel.padding(.top, 34)
            }
        }
        .teslaPage("Menu", black: true, lowered: true)
        .onAppear { profile.reload() }
    }

    private var profileHeader: some View {
        HStack(spacing: 0) {
            ProfilePhoto(image: profile.photo, size: 80)
                .padding(.trailing, 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(profile.name.isEmpty ? "Add your name" : profile.name)
                    .font(.app(size: 16, weight: .semibold))
                    .foregroundStyle(profile.name.isEmpty ? TeslaDark.rowLabel : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !profile.email.isEmpty {
                    Text(profile.email).font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .regular)).foregroundStyle(TeslaDark.dim)
        }
        .padding(.leading, 30)
        .padding(.trailing, 33)
        .contentShape(Rectangle())
    }

    /// App Version in a dark panel at the bottom (Tesla app).
    private var versionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App Version").font(.app(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(CarModel.versionLine.replacingOccurrences(of: "Version ", with: ""))
                    .font(.app(size: 12.5, weight: .semibold)).foregroundStyle(TeslaDark.dim)
            }
            if !CarModel.releaseLine.isEmpty {
                Text(CarModel.releaseLine).font(.app(size: 12.5)).foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 30)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
                .fill(Color(white: 0.105))
                .padding(.bottom, -400)   // runs on past the bottom edge
        )
    }

    private var alertsLine: String {
        let d = UserDefaults.standard
        let on = [d.bool(forKey: BatteryAlerts.cellKey) ? "Cell gap" : nil, d.bool(forKey: BatteryAlerts.healthKey) ? "Battery health" : nil].compactMap { $0 }
        return on.isEmpty ? "Off" : on.joined(separator: " · ")
    }

    /// "Tessie · Home Assistant · S3XY off", or what needs attention first.
    private var connectionLine: String {
        if !car.configured { return "Tessie not set up" }
        if car.error != nil { return "Can't reach Tessie" }
        if !home.haConfigured { return "Home Assistant not set up" }
        if home.message != nil { return "Home Assistant can't connect" }
        let s3 = s3xy.state == .receiving ? "S3XY" : "S3XY off"
        return "Tessie · Home Assistant · " + s3
    }
}

// MARK: - Profile

struct ProfilePage: View {
    @ObservedObject private var profile = ProfileStore.shared
    @State private var pick: PhotosPickerItem?
    @FocusState private var focus: Field?
    enum Field { case name, email }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PhotosPicker(selection: $pick, matching: .images) {
                    VStack(spacing: 14) {
                        ProfilePhoto(image: profile.photo, size: 100)
                        Text(profile.photo == nil ? "Add photo" : "Change photo")
                            .font(.app(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.25, green: 0.45, blue: 0.95))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                .padding(.bottom, 26)

                field("Name", text: $profile.name, kind: .name)
                field("Email", text: $profile.email, kind: .email).padding(.top, 18)
                TFootnote(text: "Kept on this phone only, and in your backup.")
                    .padding(.top, 6)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .teslaPage("Profile", black: true)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { profile.setPhoto(data) }
                pick = nil
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, kind: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.app(size: 11, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
                .padding(.leading, 10)
            TextField(label, text: text)
                .font(.app(size: 15))
                .foregroundStyle(.white)
                .textContentType(kind == .name ? .name : .emailAddress)
                .keyboardType(kind == .name ? .default : .emailAddress)
                .textInputAutocapitalization(kind == .name ? .words : .never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: kind)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(TSurface.field))
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - My Products

struct MyProductsPage: View {
    @ObservedObject var car: CarModel
    let select: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button { select(0) } label: {
                    product(image: "product_car.png", title: car.car.name.isEmpty ? "My Car" : car.car.name,
                            subtitle: UserDefaults.standard.string(forKey: TessieClient.vinKey) ?? "")
                }.buttonStyle(.plain)
                Rectangle().fill(TSurface.line).frame(height: 0.7).padding(.horizontal, 30)
                Button { select(1) } label: {
                    product(image: "product_home.png", title: "IM2 Kuantan", subtitle: "Home")
                }.buttonStyle(.plain)
            }
            .padding(.top, 1)
        }
        .teslaPage("My Products", black: true, lowered: true)
    }

    private func product(image: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 0) {
            Group {
                if let img = UIImage(named: image) { Image(uiImage: img).resizable().scaledToFit() }
            }
            .frame(width: 106, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.app(size: 12.5, weight: .semibold)).foregroundStyle(.white)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.app(size: 10)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
                }
            }
            .padding(.leading, 30)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .regular)).foregroundStyle(TeslaDark.dim)
        }
        .padding(.leading, 34)
        .padding(.trailing, 33)
        .frame(height: 91)
        .contentShape(Rectangle())
    }
}

// MARK: - Connection (Tessie, Home Assistant, S3XY)

struct ConnectionPage: View {
    @ObservedObject var car: CarModel
    @ObservedObject var home: HomeModel
    @ObservedObject private var s3xy = S3XYLink.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink { TessiePage(car: car) } label: {
                    MenuRow(title: "Tessie",
                            subtitle: car.configured ? (car.error == nil ? "Connected · \(car.car.name)" : "Can't reach Tessie · tap to check") : "Not set up · add your token",
                            dot: car.configured ? (car.error == nil ? TSurface.green : CarColors.amber) : Color(white: 0.55)) {
                        MenuSymbol(name: "bolt.car.fill", size: 19)
                    }
                }.buttonStyle(.plain)
                NavigationLink { HomeAssistantPage() } label: {
                    MenuRow(title: "Home Assistant",
                            subtitle: home.haConfigured ? (home.message == nil ? "Connected" : "Can't connect") : "Not set up",
                            dot: home.haConfigured ? (home.message == nil ? TSurface.green : TeslaDark.importing) : Color(white: 0.55)) {
                        MenuSymbol(name: "house.fill", size: 19)
                    }
                }.buttonStyle(.plain)
                NavigationLink { S3XYPage() } label: {
                    MenuRow(title: "S3XY Commander", subtitle: s3xyLine, dot: s3xy.statusDot) {
                        MenuSymbol(name: "waveform.path.ecg", size: 19)
                    }
                }.buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .teslaPage("Connection", black: true)
        .task { await home.refresh() }
    }

    private var s3xyLine: String {
        let wifi = "Wi-Fi " + (UserDefaults.standard.string(forKey: S3XYLink.ssidKey).flatMap { $0.isEmpty ? nil : $0 } ?? "S3XY_OBD")
        if s3xy.state == .receiving, let r = s3xy.current { return "Connected · \(Int(r.mv.rounded())) mV now" }
        return s3xy.statusWord + " · " + wifi
    }
}

// MARK: - Drawn icons (Tesla app style, filled grey)

/// Two linked rings.
struct ConnectionGlyph: View {
    var size: CGFloat = 26
    var color: Color = TeslaDark.rowIcon
    var body: some View {
        Canvas { ctx, s in
            let u = s.width / 64
            let w = 6.5 * u
            ctx.stroke(Path(ellipseIn: CGRect(x: 5 * u, y: 19 * u, width: 31 * u, height: 26 * u)), with: .color(color), lineWidth: w)
            ctx.stroke(Path(ellipseIn: CGRect(x: 28 * u, y: 19 * u, width: 31 * u, height: 26 * u)), with: .color(color), lineWidth: w)
        }
        .frame(width: size, height: size)
    }
}

/// Energy: a rising zig-zag over a flat bar.
struct EnergyGlyph: View {
    var size: CGFloat = 24
    var color: Color = TeslaDark.rowIcon
    var body: some View {
        Canvas { ctx, s in
            let u = s.width / 64
            var p = Path()
            p.move(to: CGPoint(x: 9 * u, y: 36 * u))
            p.addLine(to: CGPoint(x: 23 * u, y: 23 * u))
            p.addLine(to: CGPoint(x: 33 * u, y: 31 * u))
            p.addLine(to: CGPoint(x: 51 * u, y: 15 * u))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 5 * u, lineCap: .round, lineJoin: .round))
            ctx.fill(Path(roundedRect: CGRect(x: 7 * u, y: 45 * u, width: 52 * u, height: 6 * u), cornerRadius: 3 * u), with: .color(color))
        }
        .frame(width: size, height: size)
    }
}

/// Impact: a filled leaf with a down-left arrow cut into it.
struct ImpactGlyph: View {
    var size: CGFloat = 24
    var color: Color = TeslaDark.rowIcon
    var body: some View {
        Canvas { ctx, s in
            let u = s.width / 64
            var leaf = Path()
            let a = -Double.pi / 4
            for i in 0..<180 {
                let t = Double(i) / 180 * 2 * Double.pi
                let x = cos(t), y = sin(t) * 0.78 * (1 - 0.18 * pow(abs(cos(t)), 3))
                let pt = CGPoint(x: (32 + (x * cos(a) - y * sin(a)) * 30) * u, y: (32 + (x * sin(a) + y * cos(a)) * 30) * u)
                if i == 0 { leaf.move(to: pt) } else { leaf.addLine(to: pt) }
            }
            leaf.closeSubpath()
            ctx.fill(leaf, with: .color(color))
            ctx.blendMode = .destinationOut
            var cut = Path()
            cut.move(to: CGPoint(x: 41 * u, y: 25 * u)); cut.addLine(to: CGPoint(x: 8 * u, y: 58 * u))
            cut.move(to: CGPoint(x: 23 * u, y: 31 * u)); cut.addLine(to: CGPoint(x: 23 * u, y: 43 * u)); cut.addLine(to: CGPoint(x: 35 * u, y: 43 * u))
            ctx.stroke(cut, with: .color(.black), style: StrokeStyle(lineWidth: 4.2 * u, lineCap: .butt, lineJoin: .miter))
        }
        .frame(width: size, height: size)
    }
}

/// Settings: a filled six-tooth gear.
struct GearGlyph: View {
    var size: CGFloat = 24
    var color: Color = TeslaDark.rowIcon
    var body: some View {
        Canvas { ctx, s in
            let u = s.width / 64
            let c = CGPoint(x: 32 * u, y: 32 * u)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 22 * u, y: c.y - 22 * u, width: 44 * u, height: 44 * u)), with: .color(color))
            for i in 0..<6 {
                let ang = Double(i) * Double.pi / 3 + Double.pi / 6
                let ca = cos(ang), sa = sin(ang)
                func p(_ r: Double, _ t: Double) -> CGPoint {
                    CGPoint(x: c.x + CGFloat(ca * r - sa * t) * u, y: c.y + CGFloat(sa * r + ca * t) * u)
                }
                var tooth = Path()
                tooth.move(to: p(18, -9.5)); tooth.addLine(to: p(30, -6.8)); tooth.addLine(to: p(30, 6.8)); tooth.addLine(to: p(18, 9.5))
                tooth.closeSubpath()
                ctx.fill(tooth, with: .color(color))
            }
            ctx.blendMode = .destinationOut
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9 * u, y: c.y - 9 * u, width: 18 * u, height: 18 * u)), with: .color(.black))
        }
        .frame(width: size, height: size)
    }
}
