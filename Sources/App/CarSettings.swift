import SwiftUI
import PhotosUI
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// Settings → Car: one page of groups, each opening its own page.

struct CarSettingsPage: View {
    @ObservedObject var car: CarModel
    @AppStorage("car.layout") private var layout = 2
    @AppStorage(CarArt.sourceKey) private var source = "illustration"
    @AppStorage("car.gate.entity") private var gate = "switch.porch_rf_controller_switch_1"

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Connection")
                NavigationLink { TessiePage(car: car) } label: {
                    nav("Tessie", "bolt.car", car.configured ? (car.error == nil ? "Connected · \(car.car.name)" : "Can't reach Tessie") : "Not set up",
                        dot: car.configured ? (car.error == nil ? TSurface.green : CarColors.amber) : nil, last: true)
                }.buttonStyle(.plain)

                TCaption(text: "Look")
                NavigationLink { LayoutPage() } label: {
                    nav("Layout", "rectangle.split.1x2", layout == 1 ? "View 1 · ring and cards" : "View 2 · list")
                }.buttonStyle(.plain)
                NavigationLink { CarPhotoPage() } label: {
                    nav("Car photo", "photo", source == "photo" ? "My photo" : "Illustration", last: true)
                }.buttonStyle(.plain)

                TCaption(text: "Buttons")
                NavigationLink { QuickControlsPage(car: car) } label: {
                    nav("Quick controls", "square.grid.3x2", car.controls.map(\.short).joined(separator: " · "))
                }.buttonStyle(.plain)
                NavigationLink { AutogatePage() } label: {
                    nav("Autogate", "door.garage.open", gate, last: true)
                }.buttonStyle(.plain)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
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
                    .font(.system(size: 14)).frame(width: 190, alignment: .trailing)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                Button { Task { await saveAndFind() } } label: {
                    HStack(spacing: 8) {
                        if working { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text("Save & find my car").font(.system(size: 15, weight: .medium))
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
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
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

// MARK: Layout

struct LayoutPage: View {
    @AppStorage("car.layout") private var layout = 2

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Car page")
                TSegment(items: ["View 1", "View 2"], subs: ["Ring and cards", "List"], selected: layout - 1) { layout = $0 + 1 }
                    .padding(.horizontal, 20)
                TFootnote(text: layout == 1
                          ? "View 1: your script title, the car pinned behind the page, battery ring with a draggable limit, and Temperature, Tyres, Security and Battery health cards."
                          : "View 2: calm list like the rest of VoltTime — charging panel at the top, one row per topic, details a tap away.")
            }
        }
        .teslaPage("Layout", black: true)
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
                                Text(c.short).font(.system(size: 9)).lineLimit(1)
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
                .font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
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
                                        Toggle("", isOn: askBinding(c)).labelsHidden().scaleEffect(0.75)
                                    }
                                    Image(systemName: car.controls.contains(c) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(car.controls.contains(c) ? Color.white : TeslaDark.dim)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                TFootnote(text: "The switch on each row = ask before doing it. On by default for unlock, trunks, windows, keyless driving and valet. The autogate's own setting is in Settings → Car → Autogate.")
                Button("Reset to default") { CarControl.save(CarControl.defaults); car.reloadControls() }
                    .font(.system(size: 14)).foregroundStyle(CarColors.red).padding(.top, 16)
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
    @AppStorage("car.gate.entity") private var entity = "switch.porch_rf_controller_switch_1"
    @AppStorage("car.gate.ask") private var ask = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Home Assistant")
                TRow("RF switch", icon: "dot.radiowaves.left.and.right") {
                    TextField("switch.…", text: $entity)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .multilineTextAlignment(.trailing).font(.system(size: 13)).foregroundStyle(.white)
                        .frame(width: 220)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                TRow("Ask before sending", icon: "questionmark.bubble", last: true) {
                    Toggle("", isOn: $ask).labelsHidden()
                }
                TFootnote(text: "The Gate button turns this switch on for 1 second, then off — one RF pulse, the same as your autogate script. Nothing is checked first. Uses the Home Assistant address and token from Settings → Home Assistant.")
            }
        }
        .teslaPage("Autogate", black: true)
    }
}

// MARK: Car photo

struct CarPhotoPage: View {
    @AppStorage(CarArt.sourceKey) private var source = "illustration"
    @AppStorage(CarArt.fadeKey) private var fade = 0.55
    @AppStorage(CarArt.brightKey) private var bright = 0.0
    @AppStorage(CarArt.scaleKey) private var scale = 1.0
    @AppStorage(CarArt.offsetKey) private var offsetY = 0.0
    @AppStorage(CarArt.blurPlateKey) private var blurPlate = false
    @AppStorage("car.photo.removeBG") private var removeBG = true
    @State private var item: PhotosPickerItem?
    @State private var chargingItem: PhotosPickerItem?
    @State private var working = false
    @State private var note: String?
    @State private var version = 0
    @State private var camera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Color.black
                    FadedCar(image: CarArt.image(charging: false), fade: fade, bright: bright)
                        .scaleEffect(scale)
                        .offset(y: offsetY)
                        .id(version)
                    if working { ProgressView().tint(.white) }
                }
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(CarColors.line))
                .padding(.horizontal, 16).padding(.top, 12)

                TSegment(items: ["Illustration", "My photo"], selected: source == "photo" ? 1 : 0) { i in
                    if i == 1 && !FileManager.default.fileExists(atPath: CarArt.photoURL.path) { note = "Choose a photo first."; return }
                    source = i == 1 ? "photo" : "illustration"; version += 1
                }
                .padding(.horizontal, 20).padding(.top, 14)
                if let note { TFootnote(text: note, color: TeslaDark.rowLabel) }

                TCaption(text: "Source")
                PhotosPicker(selection: $item, matching: .images) {
                    TRow("Choose from Photos", icon: "photo.on.rectangle") { chevron }
                }.buttonStyle(.plain)
                Button { camera = true } label: {
                    TRow("Take a photo", icon: "camera") { chevron }
                }.buttonStyle(.plain)
                PhotosPicker(selection: $chargingItem, matching: .images) {
                    TRow("Charging photo", icon: "bolt", subtitle: FileManager.default.fileExists(atPath: CarArt.chargingURL.path) ? "Set · shown while charging" : "Optional · shown while charging", last: true) { chevron }
                }.buttonStyle(.plain)

                TCaption(text: "Adjust")
                TRow("Remove background", icon: "person.crop.rectangle.badge.plus") { Toggle("", isOn: $removeBG).labelsHidden() }
                slider("Edge fade", fade < 0.05 ? "None" : (fade < 0.4 ? "Light" : (fade < 0.75 ? "Soft" : "Strong")), $fade, 0...1)
                slider("Brightness", String(format: "%+.0f%%", bright * 100), $bright, -0.3...0.3)
                slider("Size", String(format: "%.0f%%", scale * 100), $scale, 0.7...1.4)
                slider("Position", String(format: "%+.0f pt", offsetY), $offsetY, -60...60, last: true)

                TCaption(text: "Privacy")
                TRow("Blur number plate", icon: "eye.slash", subtitle: "Applied when a photo is chosen", last: true) {
                    Toggle("", isOn: $blurPlate).labelsHidden()
                }

                Button {
                    source = "illustration"
                    try? FileManager.default.removeItem(at: CarArt.photoURL)
                    try? FileManager.default.removeItem(at: CarArt.chargingURL)
                    fade = 0.55; bright = 0; scale = 1; offsetY = 0; version += 1
                } label: {
                    TRow("Reset to illustration", icon: "arrow.counterclockwise", last: true) { EmptyView() }
                        .foregroundStyle(CarColors.red)
                }.buttonStyle(.plain).padding(.top, 18)
                TFootnote(text: "Your photo is kept in VoltTime's private storage and goes into your iCloud backup.")
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Car photo", black: true)
        .onChange(of: item) { _, v in if let v { Task { await load(v, to: CarArt.photoURL) } } }
        .onChange(of: chargingItem) { _, v in if let v { Task { await load(v, to: CarArt.chargingURL) } } }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                camera = false
                if let img { Task { await process(img, to: CarArt.photoURL) } }
            }
            .ignoresSafeArea()
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
    }

    private func slider(_ t: String, _ v: String, _ b: Binding<Double>, _ r: ClosedRange<Double>, last: Bool = false) -> some View {
        TRow(t, icon: nil, last: last, trailing: { Text(v).font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel) }) {
            Slider(value: b, in: r).tint(CarColors.red)
        }
    }

    private func load(_ item: PhotosPickerItem, to url: URL) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
            note = "That photo couldn't be opened."; return
        }
        await process(img, to: url)
    }

    private func process(_ img: UIImage, to url: URL) async {
        working = true; defer { working = false }
        let removeBG = removeBG, blur = blurPlate
        let out = await Task.detached(priority: .userInitiated) { CarPhotoProcessor.make(img, removeBackground: removeBG, blurPlate: blur) }.value
        guard let out, let png = out.pngData() else { note = "That photo couldn't be processed."; return }
        do {
            try png.write(to: url, options: .atomic)
            if url == CarArt.photoURL { source = "photo" }
            note = removeBG && !CarPhotoProcessor.lastCutWorked ? "Background couldn't be removed from this one — shown as is." : nil
            version += 1
        } catch { note = error.localizedDescription }
    }
}

enum CarPhotoProcessor {
    nonisolated(unsafe) static var lastCutWorked = true

    /// Lifts the car off its background (iOS subject lift), blurs a number plate if asked, crops tight, max 1600 px.
    static func make(_ input: UIImage, removeBackground: Bool, blurPlate: Bool) -> UIImage? {
        guard let cg = upright(input).cgImage else { return nil }
        var ci = CIImage(cgImage: cg)
        if blurPlate { ci = blurPlates(ci, cg: cg) }
        var result = ci
        lastCutWorked = true
        if removeBackground {
            let req = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg)
            do {
                try handler.perform([req])
                if let obs = req.results?.first {
                    let mask = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
                    let m = CIImage(cvPixelBuffer: mask)
                    let f = CIFilter.blendWithMask()
                    f.inputImage = ci; f.maskImage = m; f.backgroundImage = CIImage.empty()
                    if let o = f.outputImage { result = o }
                } else { lastCutWorked = false }
            } catch { lastCutWorked = false }
        }
        let ctx = CIContext()
        guard let outCG = ctx.createCGImage(result, from: ci.extent) else { return nil }
        var img = UIImage(cgImage: outCG)
        if removeBackground, lastCutWorked, let cropped = cropToContent(img) { img = cropped }
        return downscale(img, max: 1600)
    }

    private static func blurPlates(_ ci: CIImage, cg: CGImage) -> CIImage {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        var out = ci
        for o in req.results ?? [] {
            guard let s = o.topCandidates(1).first?.string else { continue }
            let t = s.replacingOccurrences(of: " ", with: "")
            // Malaysian-style plates: letters then digits, short.
            guard t.count >= 3, t.count <= 10, t.rangeOfCharacter(from: .decimalDigits) != nil,
                  t.rangeOfCharacter(from: .letters) != nil else { continue }
            let b = o.boundingBox
            let r = CGRect(x: b.minX * W, y: b.minY * H, width: b.width * W, height: b.height * H).insetBy(dx: -b.width * W * 0.15, dy: -b.height * H * 0.5)
            let blurred = out.clampedToExtent().applyingGaussianBlur(sigma: 18).cropped(to: r)
            out = blurred.composited(over: out)
        }
        return out
    }

    private static func upright(_ i: UIImage) -> UIImage {
        guard i.imageOrientation != .up else { return i }
        return UIGraphicsImageRenderer(size: i.size).image { _ in i.draw(at: .zero) }
    }

    private static func cropToContent(_ img: UIImage) -> UIImage? {
        guard let cg = img.cgImage, let data = cg.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
        let w = cg.width, h = cg.height, bpr = cg.bytesPerRow, bpp = cg.bitsPerPixel / 8
        guard bpp >= 4 else { return nil }
        let alphaOffset: Int = (cg.alphaInfo == .premultipliedFirst || cg.alphaInfo == .first) ? 0 : 3
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) where p[y * bpr + x * bpp + alphaOffset] > 20 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX > minX, maxY > minY else { return nil }
        let padX = (maxX - minX) / 20
        let r = CGRect(x: max(0, minX - padX), y: max(0, minY - padX / 2), width: min(w, maxX - minX + padX * 2), height: min(h, maxY - minY + padX))
        return cg.cropping(to: r).map { UIImage(cgImage: $0) }
    }

    private static func downscale(_ i: UIImage, max m: CGFloat) -> UIImage {
        let s = min(1, m / max(i.size.width, i.size.height))
        guard s < 1 else { return i }
        let size = CGSize(width: i.size.width * s, height: i.size.height * s)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = false
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in i.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
