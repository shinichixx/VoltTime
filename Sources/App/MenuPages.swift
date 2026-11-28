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
    var product = false   // a product's page: the Tesla app's smaller text and chevron
    var large = false     // Connection page: the Tesla app's User Access text sizes (15.2 pt title, 12.3 pt line)
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: 0) {
            icon()
                .frame(width: 26, height: 26)
                .scaleEffect(large ? 0.85 : product ? 0.83 : compact ? 0.77 : 1, anchor: large ? .center : .leading)
                .frame(width: large ? 41.3 : 49, alignment: large ? .leading : .leading)
            VStack(alignment: .leading, spacing: large ? 4 : 3) {
                Text(title).font(.app(size: large ? 15.2 : product ? 11.8 : compact ? 15 : 17, weight: product ? .medium : .semibold)).foregroundStyle(.white)
                if let subtitle {
                    HStack(spacing: 6) {
                        if let dot { Circle().fill(dot).frame(width: large ? 5.3 : 6, height: large ? 5.3 : 6).padding(.leading, large ? 0.7 : 0) }
                        Text(subtitle).font(.app(size: large ? 12.3 : compact ? 12 : 12.5, weight: .semibold)).foregroundStyle(TeslaDark.rowLabel)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            if subtitle == nil, let dot { Circle().fill(dot).frame(width: 7, height: 7).padding(.trailing, 20) }
            Image(systemName: "chevron.right").font(.system(size: product ? 11 : 14, weight: .regular)).foregroundStyle(TeslaDark.dim)
        }
        .padding(.leading, large ? 28.7 : 37)
        .padding(.trailing, 33)
        .frame(height: large ? 66.7 : compact ? 54 : 70)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink { ProfilePage() } label: { profileHeader }
                    .buttonStyle(.plain)
                    .padding(.top, 32)
                    .padding(.bottom, 25)

                NavigationLink { MyProductsPage(car: car, select: select) } label: {
                    MenuRow(title: "My Products", compact: true) { MenuSymbol(name: "car.fill") }
                }.buttonStyle(.plain)
                NavigationLink { ConnectionPage(car: car, home: home) } label: {
                    MenuRow(title: "Connection", compact: true) { ConnectionGlyph(size: 26, color: TeslaDark.rowIcon) }
                }.buttonStyle(.plain)
                NavigationLink { NotificationsPage() } label: {
                    MenuRow(title: "Notifications", compact: true) { MenuSymbol(name: "bell.fill") }
                }.buttonStyle(.plain)
                NavigationLink { BackupPage(energy: energy, home: home) } label: {
                    MenuRow(title: "Backup", dot: backup.summaryColor, compact: true) {
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

/// Names typed in My Products > Edit, kept on the phone and in backups ("car." and "home." settings).
enum ProductNames {
    static let carKey = "car.customName"
    static let homeKey = "home.customName"
    static let homeDefault = "Home IM2 Kuantan"
    static func shown(_ custom: String, or fallback: String) -> String {
        custom.isEmpty ? (fallback.isEmpty ? "My Vehicle" : fallback) : custom
    }
    static func car(_ fromTesla: String) -> String { shown(UserDefaults.standard.string(forKey: carKey) ?? "", or: fromTesla) }
}

/// Page titles on My Car, My Home and Simulation: the Tesla app's size and place.
enum PageTitle {
    static let size: CGFloat = 20.3
    static let kerning: CGFloat = -0.2
    static let inset: CGFloat = 2      // past the 7% margin
    static let top: CGFloat = 22.7     // above the 32 pt title line
}

struct MyProductsPage: View {
    @ObservedObject var car: CarModel
    let select: (Int) -> Void
    @AppStorage(ProductNames.carKey) private var carName = ""
    @AppStorage(ProductNames.homeKey) private var homeName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink { ProductPage(car: car, product: .car, select: select) } label: {
                    row(image: "product_car.png", title: ProductNames.shown(carName, or: car.car.name),
                        subtitle: UserDefaults.standard.string(forKey: TessieClient.vinKey) ?? "")
                }.buttonStyle(.plain)
                Rectangle().fill(TSurface.line).frame(height: 0.7).padding(.horizontal, 30)
                NavigationLink { ProductPage(car: car, product: .home, select: select) } label: {
                    row(image: "product_home.png", title: ProductNames.shown(homeName, or: ProductNames.homeDefault), subtitle: "Home")
                }.buttonStyle(.plain)
            }
            .padding(.top, 1)
        }
        .teslaPage("My Products", black: true, lowered: true)
    }

    private func row(image: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 0) {
            Group {
                if let img = UIImage(named: image) { Image(uiImage: img).resizable().scaledToFit() }
            }
            .frame(width: 106, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.app(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
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

/// One product (Tesla app): name with the VIN or "Home" under it, Edit at the top right, its picture,
/// Go To Product, and the settings that belong to it.
struct ProductPage: View {
    enum Product { case car, home }
    @ObservedObject var car: CarModel
    let product: Product
    let select: (Int) -> Void
    @AppStorage(ProductNames.carKey) private var carName = ""
    @AppStorage(ProductNames.homeKey) private var homeName = ""
    @State private var editing = false

    private var isCar: Bool { product == .car }
    private var name: String {
        isCar ? ProductNames.shown(carName, or: car.car.name) : ProductNames.shown(homeName, or: ProductNames.homeDefault)
    }
    private var detail: String {
        guard isCar else { return "Home" }
        let vin = UserDefaults.standard.string(forKey: TessieClient.vinKey) ?? ""
        return vin.isEmpty ? "" : "VIN " + vin
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    if let img = UIImage(named: isCar ? "product_car_page.jpg" : "product_home_page.jpg") {
                        Image(uiImage: img).resizable().scaledToFit()
                    }
                }
                .frame(height: 210)
                .padding(.top, 7)

                Button { select(isCar ? 0 : 1) } label: {
                    MenuRow(title: "Go To Product", compact: true, product: true) { MenuSymbol(name: "rectangle.portrait.and.arrow.right", size: 19) }
                }.buttonStyle(.plain)
                if isCar {
                    NavigationLink { QuickControlsPage(car: car) } label: {
                        MenuRow(title: "Quick Controls", compact: true, product: true) { MenuSymbol(name: "square.grid.2x2.fill", size: 19) }
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink { AutogatePage(car: car) } label: {
                        MenuRow(title: "Autogate", compact: true, product: true) { GateGlyph(size: 22, color: TeslaDark.rowIcon) }
                    }.buttonStyle(.plain)
                    NavigationLink { EnergyGraphPage() } label: {
                        MenuRow(title: "Energy Graph", compact: true, product: true) { MenuSymbol(name: "chart.xyaxis.line", size: 19) }
                    }.buttonStyle(.plain)
                }
            }
        }
        .teslaPage(name, subtitle: detail, black: true, lowered: true, product: true, trailing: AnyView(
            Button { editing = true } label: {
                Text("Edit").font(.app(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.4, blue: 0.96))
                    .frame(minWidth: 44, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        ))
        .navigationDestination(isPresented: $editing) {
            if isCar {
                EditNamePage(key: ProductNames.carKey, fallback: car.car.name)
            } else {
                EditNamePage(key: ProductNames.homeKey, fallback: ProductNames.homeDefault)
            }
        }
    }
}

enum EnergyGraphSetting { static let key = "energy.dayStep" }

/// Home › Energy Graph: the Day graph's interval.
struct EnergyGraphPage: View {
    @AppStorage(EnergyGraphSetting.key) private var step = 5

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TRow("Interval", icon: "clock", last: true) {
                    TSegment(items: ["5 min", "15 min"], selected: step == 15 ? 1 : 0) { step = $0 == 1 ? 15 : 5 }
                        .frame(width: 170)
                }
                TFootnote(text: "Used by the Day graph in every Energy view. 15 min shows the average of each 15 minutes; kWh totals stay the same. Days saved hourly stay hourly.")
            }
        }
        .teslaPage("Energy Graph", black: true)
    }
}

/// A product's name as Teslar shows it. Saving it empty (or unchanged from the original) goes back to the original.
struct EditNamePage: View {
    let key: String
    let fallback: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("NAME").font(.app(size: 11, weight: .medium)).kerning(0.6).foregroundStyle(TeslaDark.rowLabel)
                    .padding(.bottom, 8)
                TextField(fallback, text: $text)
                    .font(.app(size: 15))
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit(save)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(TSurface.field))
                Button(action: save) {
                    Text("Save").font(.app(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(red: 0.2, green: 0.4, blue: 0.96)))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                Text("Changes the name in Teslar only. Save it empty to go back to the original.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 30)
            .padding(.top, 24)
        }
        .teslaPage("Edit Name", black: true, lowered: true)
        .onAppear {
            text = ProductNames.shown(UserDefaults.standard.string(forKey: key) ?? "", or: fallback)
            focused = true
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Always written (empty = the original), so a restore can bring either back.
        UserDefaults.standard.set(t == fallback ? "" : t, forKey: key)
        dismiss()
    }
}

// MARK: - Connection (Tessie, Home Assistant, S3XY)

struct ConnectionPage: View {
    @ObservedObject var car: CarModel
    @ObservedObject var home: HomeModel
    @ObservedObject private var s3xy = S3XYLink.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var haRoute: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink { TessiePage(car: car) } label: {
                    MenuRow(title: "Tessie",
                            subtitle: car.configured ? (car.error == nil ? "Connected · \(ProductNames.car(car.car.name))" : "Can't reach Tessie · tap to check") : "Not set up · add your token",
                            dot: car.configured ? (car.error == nil ? TSurface.green : CarColors.amber) : Color(white: 0.55), large: true) {
                        MenuSymbol(name: "bolt.car.fill", size: 19)
                    }
                }.buttonStyle(.plain)
                NavigationLink { HomeAssistantPage() } label: {
                    MenuRow(title: "Home Assistant",
                            subtitle: home.haConfigured ? (home.message == nil ? haRoute.map { "Connected · \($0)" } ?? "Connected" : "Can't connect") : "Not set up",
                            dot: home.haConfigured ? (home.message == nil ? TSurface.green : TeslaDark.importing) : Color(white: 0.55), large: true) {
                        MenuSymbol(name: "house.fill", size: 19)
                    }
                }.buttonStyle(.plain)
                NavigationLink { S3XYPage() } label: {
                    MenuRow(title: "S3XY Commander", subtitle: s3xyLine, dot: s3xy.statusDot, large: true) {
                        MenuSymbol(name: "waveform.path.ecg", size: 19)
                    }
                }.buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .teslaPage("Connection", black: true, drop: 13)
        .task { await refreshHome() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await HARoute.shared.reset(); await refreshHome() } }
        }
    }

    private func refreshHome() async {
        await home.refresh()
        haRoute = await HAClient.routeName()
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
