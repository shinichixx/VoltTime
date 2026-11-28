import SwiftUI

/// Pages pushed from My Home.
enum Route: Hashable {
    case energy, settings, vehicleCharging, ratePlan, chargeDetails, homeAssistant, charge, impact, energyGraph
    case menu, carDetail(CarDetail), energyView(EnergyComponent)
}

// MARK: - Shared dark building blocks

extension View {
    /// Dark page with our own slim top bar (Tesla app): thin grey back arrow, small centred title, optional
    /// item on the right. Replaces the system bar, which is much taller on iOS 26.
    func teslaPage(_ title: String, subtitle: String? = nil, black: Bool = false, lowered: Bool = false, product: Bool = false, trailing: AnyView? = nil, drop: CGFloat? = nil, tesla: Bool = false) -> some View {
        let bg = black ? TSurface.page : TeslaDark.bg
        return self
            .background(bg.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TeslaTopBar(title: title, subtitle: subtitle, trailing: trailing, background: bg, lowered: lowered, product: product, drop: drop, tesla: tesla)
            }
    }

}

/// The slim top bar: 32 pt under the status bar; content starts right below it.
struct TeslaTopBar: View {
    let title: String
    var subtitle: String? = nil
    let trailing: AnyView?
    let background: Color
    var lowered = false   // Menu and My Products: title 22 pt lower, back arrow 11 pt further in (Tesla app)
    var product = false   // a product's page: the Tesla app's smaller header
    var drop: CGFloat? = nil   // Connection: title and arrow placed as on the Tesla app's User Access page
    var tesla = false   // Settings: lower, larger title and a white back arrow (Tesla app)

    var body: some View {
        ZStack {
            VStack(spacing: product ? 6 : 4) {
                Text(title).font(.app(size: tesla ? 15.5 : product || drop != nil ? 14.5 : 15, weight: .semibold)).foregroundStyle(.white)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.app(size: product ? 10.4 : 11, weight: product ? .semibold : .medium)).foregroundStyle(TeslaDark.rowLabel)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 64)
            HStack(spacing: 0) {
                PlainBackButton(small: product, tesla: tesla).padding(.leading, tesla ? 30 : product ? 26 : lowered || drop != nil ? 25 : 14)
                Spacer()
                if let trailing { trailing.padding(.trailing, product ? 9 : 18) }
            }
        }
        .frame(height: 32)
        .padding(.top, drop ?? (lowered || tesla ? 22 : 0))
        .frame(maxWidth: .infinity)
        .background(background.ignoresSafeArea(edges: .top))
    }
}

/// 7 × 13 pt chevron in mid grey, like the Tesla app; the tap area stays 44 pt.
struct PlainBackButton: View {
    var small = false
    var tesla = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            BackChevron()
                .stroke(tesla ? Color(white: 0.95) : Color(white: 0.54), style: StrokeStyle(lineWidth: tesla ? 2.3 : small ? 1.5 : 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: tesla || small ? 6 : 7.5, height: tesla ? 12 : small ? 11 : 13.5)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

struct BackChevron: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// Keeps the swipe-from-the-edge back gesture working with the system back button hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: - How tonight's charge works (the (i) beside Sat–Wed)

private struct ChargeHowSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How tonight's charge works").font(.app(size: 17, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(white: 0.24)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 14)
            ScrollView {
                VStack(spacing: 0) {
                    row("bell", "Plugged in after 7pm, Sat–Wed", "Asked at your reminder times and when you plug in")
                    row("mappin.and.ellipse", "GPS 73% · TSET 63% · Others", "No answer by 10pm means GPS 73%")
                    row("clock", "The vehicle's schedule is set for you", "Mon–Wed never before 10:15pm. Backup start after 5 min")
                    row("slider.horizontal.3", "Routine mode only", "Change it with the mode buttons above", last: true)
                }
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationBackground(Color(red: 0.133, green: 0.137, blue: 0.149))
        .preferredColorScheme(.dark)
    }

    private func row(_ icon: String, _ title: String, _ detail: String, last: Bool = false) -> some View {
        TRow(title, icon: icon, subtitle: detail, last: last) { EmptyView() }
    }
}

// MARK: - Settings (level 1)

/// My Home → Settings, laid out like the Tesla app.
struct SettingsPage: View {
    @ObservedObject var energy: EnergyStore
    @Binding var path: [Route]
    @AppStorage(Tariff.revKey) private var tariffRev = 0
    @AppStorage(EnergyGraphSetting.key) private var graphStep = 5

    private var rateSubtitle: String {
        Tariff.recordedAFA(Date()) != nil ? "TOU" : "TOU · Record \(Date().formatted(.dateTime.month(.wide).locale(Num.en))) AFA"
    }

    var body: some View {
        let _ = tariffRev   // redraw when a rate changes
        ScrollView {
            VStack(spacing: 0) {
                caption("HOME SETTINGS").padding(.top, 38.7)
                SettingsRow(title: "Utility Rate Plan", icon: AnyView(PylonGlyph()), subtitle: rateSubtitle) { path.append(.ratePlan) }
                    .padding(.top, 11.3)
                SettingsRow(title: "Energy Graph",
                            icon: AnyView(Image(systemName: "chart.xyaxis.line").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(SettingsRow.grey)),
                            subtitle: EnergyGraphSetting.label(graphStep)) { path.append(.energyGraph) }
                caption("YOUR PRODUCTS").padding(.top, 30.3)
                SettingsRow(title: "Vehicle Charging", icon: AnyView(VehicleFrontGlyph())) { path.append(.vehicleCharging) }
                    .padding(.top, 10.7)
            }
        }
        .teslaPage("Settings", black: true, tesla: true)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.app(size: 12.5, weight: .semibold)).foregroundStyle(SettingsRow.grey)
            .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20, alignment: .leading)
            .padding(.leading, 20.3)
    }
}

/// A Settings row placed as in the Tesla app: no lines, icon centred at 34 pt, text from 63 pt.
private struct SettingsRow: View {
    static let grey = Color(red: 138 / 255, green: 140 / 255, blue: 140 / 255)

    let title: String
    let icon: AnyView
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                icon.frame(width: 28).padding(.leading, 20)
                ZStack(alignment: .leading) {
                    Text(title).font(.app(size: 15.0, weight: .semibold)).foregroundStyle(Color(white: 0.95))
                        .offset(y: subtitle == nil ? 0 : -9.3)
                    if let subtitle {
                        Text(subtitle).font(.app(size: 12.0, weight: .semibold)).foregroundStyle(Self.grey)
                            .offset(y: 10.7)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.leading, 15)
                Spacer(minLength: 12)
                BackChevron()
                    .stroke(Color(white: 0.23), style: StrokeStyle(lineWidth: 2.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 6.7, height: 12.7)
                    .scaleEffect(x: -1)
                    .padding(.trailing, 34.3)
            }
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Front of a vehicle (drawn on a 76 × 56 px grid taken from the mockup).
struct VehicleFrontGlyph: View {
    var body: some View {
        Canvas { c, s in
            let k = s.width / 76
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 62) * k, y: (y - 973) * k) }
            func box(_ a: CGFloat, _ b: CGFloat, _ d: CGFloat, _ e: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(origin: pt(a, b), size: CGSize(width: (d - a) * k, height: (e - b) * k)), cornerRadius: r * k)
            }
            let grey = GraphicsContext.Shading.color(SettingsRow.grey)
            let hole = GraphicsContext.Shading.color(TSurface.page)
            var roof = Path()
            roof.addLines([pt(72, 998), pt(80, 979), pt(88, 975), pt(113, 975), pt(121, 979), pt(129, 998)])
            c.stroke(roof, with: grey, style: StrokeStyle(lineWidth: 4 * k, lineJoin: .round))
            for p in [box(66, 992, 135, 1017, 10), box(66, 1010, 76, 1027, 3), box(125, 1010, 135, 1027, 3),
                      box(63, 986, 74, 992, 3), box(127, 986, 138, 992, 3)] { c.fill(p, with: grey) }
            for (x, d) in [(CGFloat(70), CGFloat(1)), (131, -1)] {
                var lamp = Path()
                lamp.addLines([pt(x, 996), pt(x + d * 14, 1000), pt(x + d * 12, 1005), pt(x + d * 2, 1002)])
                lamp.closeSubpath()
                c.fill(lamp, with: hole)
            }
            c.fill(box(84, 1012, 117, 1015, 1), with: hole)
        }
        .frame(width: 25.3, height: 18.7)
    }
}

/// Transmission tower (drawn on a 60 × 72 px grid taken from the mockup).
struct PylonGlyph: View {
    var body: some View {
        Canvas { c, s in
            let k = s.width / 60
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 72) * k, y: (y - 601) * k) }
            var p = Path()
            for line in [[pt(94, 605), pt(110, 605)], [pt(94, 605), pt(94, 635), pt(75, 669)], [pt(110, 605), pt(110, 635), pt(129, 669)],
                         [pt(76, 626), pt(76, 616), pt(128, 616), pt(128, 626)], [pt(76, 647), pt(76, 637), pt(128, 637), pt(128, 647)],
                         [pt(94, 637), pt(122, 659)], [pt(110, 637), pt(82, 659)]] {
                p.addLines(line)
            }
            c.stroke(p, with: .color(Color(red: 138 / 255, green: 140 / 255, blue: 140 / 255)),
                     style: StrokeStyle(lineWidth: 7 * k, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 20, height: 24)
    }
}

/// Settings → Utility Rate Plan: this month's rates and each month's AFA.
struct UtilityRatePlanPage: View {
    let firstDay: Date?
    @AppStorage(Tariff.revKey) private var tariffRev = 0
    @State private var editing: Date?
    @State private var text = ""
    @State private var limit = ""

    /// This month back to the first month with energy data (or the earliest AFA seed).
    private var months: [Date] {
        let cal = Calendar.current
        let now = cal.dateInterval(of: .month, for: Date())?.start ?? Date()
        let first = firstDay.flatMap { cal.dateInterval(of: .month, for: $0)?.start } ?? now
        var out: [Date] = [], m = now
        while m >= first, out.count < 240 {
            out.append(m)
            guard let p = cal.date(byAdding: .month, value: -1, to: m) else { break }
            m = p
        }
        return out.isEmpty ? [now] : out
    }

    private func name(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year().locale(Num.en)) }
    private func two(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        let _ = tariffRev   // redraw when a rate changes
        let r = Tariff.rates()
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "TNB Domestic ToU · NEM 3.0", trailing: name(Date()))
                HStack {
                    Text("RM/kWh").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Import").frame(width: 72, alignment: .trailing)
                    Text("Export").frame(width: 72, alignment: .trailing)
                }
                .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.horizontal, 20).padding(.vertical, 8)
                rateRow("Peak", "Mon–Fri 2pm–10pm", r.importPeak, r.exportPeak)
                rateRow("Off-peak", "Other hours, weekends and public holidays", r.importOff, r.exportOff)

                TCaption(text: "Monthly AFA and threshold")
                ForEach(months, id: \.self) { m in
                    let saved = Tariff.recordedAFA(m)
                    Button {
                        text = saved.map(two) ?? ""
                        limit = String(Int(Tariff.threshold(m)))
                        editing = m
                    } label: {
                        TRow(name(m), subtitle: "Threshold \(Int(Tariff.threshold(m))) kWh"
                             + (saved == nil ? " · AFA using \(two(Tariff.afa(m)))" : "")) {
                            HStack(spacing: 8) {
                                if let saved {
                                    Text("\(two(saved)) sen").font(.app(size: 15)).foregroundStyle(.white)
                                } else {
                                    Text("Record").font(.app(size: 14)).foregroundStyle(Color(red: 0.24, green: 0.55, blue: 1))
                                }
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                TCaption(text: "Calendar")
                NavigationLink { PublicHolidaysPage() } label: {
                    TRow("Public holidays", last: true) {
                        HStack(spacing: 8) {
                            let y = Calendar(identifier: .gregorian).component(.year, from: Date())
                            Text("\(Holiday.allCases.filter { Tariff.holidayDate($0, y) != nil }.count) of \(Holiday.allCases.count)")
                                .font(.app(size: 15)).foregroundStyle(.white)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                        }
                    }
                }
                .buttonStyle(.plain)

                TCaption(text: "Rates")
                NavigationLink { RateComponentsPage() } label: {
                    TRow("Rate components", last: true) {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                    }
                }
                .buttonStyle(.plain)
                TFootnote(text: "Solar used is valued at the import rate. Export offsets the month's off-peak import at the off-peak export rate, then the rest at the peak export rate. Impact leaves out the energy efficiency incentive; Utility Bill (Energy › Grid) includes it.",
                          color: TeslaDark.dim)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Utility Rate Plan", black: true)
        .alert(editing.map { name($0) } ?? "AFA", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("AFA (sen/kWh)", text: $text).keyboardType(.numbersAndPunctuation)
            TextField("AFA threshold (kWh)", text: $limit).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let m = editing, let v = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) {
                    Tariff.setAFA(v, m)
                }
                if let m = editing {
                    let kWh = Double(limit.trimmingCharacters(in: .whitespaces))
                    Tariff.setThreshold(kWh == Tariff.standardThreshold ? nil : kWh, m)
                }
            }
        } message: {
            Text("AFA in sen/kWh (minus for a rebate), then the threshold in kWh (default 600). At or below it: no AFA, retail charge or service tax.")
        }
    }

    private func rateRow(_ title: String, _ hours: String, _ imp: Double, _ exp: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(size: 15)).foregroundStyle(.white)
                Text(hours).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach([imp, exp].indices, id: \.self) { i in
                Text(String(format: "%.4f", i == 0 ? imp : exp)).font(.app(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 72, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(TSurface.line).frame(height: 0.5).padding(.horizontal, 20) }
    }
}

/// Utility Rate Plan → Public holidays: off-peak all day. Five are fixed; the rest are set each year.
struct PublicHolidaysPage: View {
    @AppStorage(Tariff.revKey) private var tariffRev = 0
    @State private var year = Calendar(identifier: .gregorian).component(.year, from: Date())
    @State private var editing: Holiday?
    @State private var picked = Date()
    private let cal = Calendar(identifier: .gregorian)
    private let blue = Color(red: 0.24, green: 0.55, blue: 1)

    private func short(_ d: Date) -> String { d.formatted(.dateTime.day().month(.abbreviated).locale(Num.en)) }
    private func bounds(_ y: Int) -> ClosedRange<Date> {
        let a = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? Date()
        let b = cal.date(from: DateComponents(year: y, month: 12, day: 31)) ?? a
        return a...b
    }

    var body: some View {
        let _ = tariffRev
        let set = Holiday.allCases.filter { Tariff.holidayDate($0, year) != nil }.count
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button { year -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 32) }
                    Spacer()
                    Text(String(year)).font(.app(size: 16, weight: .semibold))
                    Spacer()
                    Button { year += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 32) }
                }
                .buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 8)
                TFootnote(text: "\(set) of \(Holiday.allCases.count) dates set · off-peak all day", color: TeslaDark.rowLabel)
                ForEach(Holiday.allCases) { h in
                    let d = Tariff.holidayDate(h, year)
                    Button {
                        picked = d ?? (cal.component(.year, from: Date()) == year ? Date() : bounds(year).lowerBound)
                        editing = h
                    } label: {
                        TRow(h.name, last: h == .christmas) {
                            if h.fixed != nil, let d {
                                Text("\(short(d)) · Fixed").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                            } else {
                                HStack(spacing: 8) {
                                    Text(d.map(short) ?? "Set date").font(.app(size: 15)).foregroundStyle(d == nil ? blue : .white)
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(h.fixed != nil)
                }
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Public Holidays", black: true)
        .sheet(item: $editing) { h in
            VStack(spacing: 14) {
                Text("\(h.name) \(String(year))").font(.app(size: 17, weight: .semibold))
                DatePicker("Date", selection: $picked, in: bounds(year), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                HStack(spacing: 12) {
                    if Tariff.holidayDate(h, year) != nil {
                        Button("Remove") { Tariff.setHoliday(h, year, nil); editing = nil }.foregroundStyle(Theme.rouge)
                    } else {
                        Button("Cancel") { editing = nil }.foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Save") { Tariff.setHoliday(h, year, picked); editing = nil }.foregroundStyle(blue)
                }
                .font(.app(size: 16, weight: .semibold))
                .padding(.horizontal, 8)
            }
            .padding(20)
            .presentationDetents([.height(520)])
            .preferredColorScheme(.dark)
        }
    }
}

/// Utility Rate Plan → Rate components.
struct RateComponentsPage: View {
    @FocusState private var focus: String?
    @AppStorage(Tariff.revKey) private var tariffRev = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Energy (RM/kWh)")
                row("Peak", .energyPeak, "RM")
                row("Off-peak", .energyOff, "RM", last: true)
                TCaption(text: "Other charges (RM/kWh)")
                row("Capacity", .capacity, "RM")
                row("Network", .network, "RM", last: true)
                TCaption(text: "Taxes on import")
                row("Service tax", .st, "%")
                row("KWTBB", .kwtbb, "%", last: true)
                Button("Reset to defaults") { focus = nil; Tariff.resetParts() }
                    .font(.app(size: 14)).foregroundStyle(Theme.rouge)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .teslaPage("Rate components", black: true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private func row(_ title: String, _ part: Tariff.Part, _ unit: String, last: Bool = false) -> some View {
        let value = Binding<Double>(get: { _ = tariffRev; return Tariff.part(part) },
                                    set: { if $0 != Tariff.part(part) { Tariff.setPart(part, $0) } })
        return TRow(title, last: last) { TValueField(value: value, unit: unit, focus: $focus, key: part.rawValue) }
    }
}

// MARK: - Vehicle Charging

struct VehicleChargingPage: View {
    @ObservedObject var home: HomeModel
    @ObservedObject var myHome: MyHomeModel
    @ObservedObject var energy: EnergyStore
    @ObservedObject var car: CarModel
    @Binding var path: [Route]
    @State private var showHow = false
    private var routine: Bool { (myHome.mode ?? "Routine") == "Routine" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Vehicle charging mode")
                    .padding(.top, 0)            // close under the slim top bar
                modeTiles
                    .padding(.horizontal, 20)
                Text(ChargingMode.named(myHome.pendingMode ?? myHome.mode ?? "Routine").detail)
                    .font(.app(size: 12))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                if let msg = myHome.message ?? home.message {
                    Text(msg).font(.app(size: 12)).foregroundStyle(TeslaDark.importing)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }

                // Tonight's charge only in Routine; other modes just keep Charge details (charger settings apply to all).
                if routine {
                    TCaption(text: "Tonight's charge", trailing: "Sat–Wed", info: { showHow = true })
                    tonight
                } else {
                    Rectangle().fill(Color.clear).frame(height: 20)
                    TNavRow(title: "Charge details", icon: "list.bullet.rectangle",
                            subtitle: "Reminders, safety buffer, charger settings", last: true) {
                        path.append(.chargeDetails)
                    }
                }

                Spacer(minLength: 12)
            }
        }
        .teslaPage("Vehicle Charging", black: true)
        .sheet(isPresented: $showHow) {
            ChargeHowSheet()
                .presentationDetents([.height(390), .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await home.refresh()
            await myHome.refresh()
        }
    }

    // MARK: Mode tiles

    private var modeTiles: some View {
        HStack(spacing: 8) {
            ForEach(myHome.modeOptions, id: \.self) { option in
                let mode = ChargingMode.named(option)
                let selected = (myHome.pendingMode ?? myHome.mode) == option
                let emoji = mode.title.split(separator: " ").last.map(String.init) ?? ""
                Button {
                    Task { await myHome.setMode(option) }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            Text(emoji).font(.app(size: 22)).opacity(myHome.pendingMode == option ? 0.25 : 1)
                            if myHome.pendingMode == option { ProgressView().tint(.white).scaleEffect(0.7) }
                        }
                        Text(option == "Excess Solar" ? "Solar" : option)
                            .font(.app(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : TeslaDark.rowLabel)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13).fill(selected ? Color(white: 0.17) : TSurface.field))
                    .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(selected ? Color.white : Color.clear, lineWidth: 1.2))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(myHome.pendingMode != nil)
            }
        }
        .animation(.easeOut(duration: 0.15), value: myHome.mode)
    }

    // MARK: Tonight's charge

    /// Routine on a Thursday or Friday night: nothing is scheduled.
    private var noNight: Bool { routine && HomeMath.isNoChargeNight(Date(), calendar: .current) }

    private var nowSoc: Double { home.liveSoc ?? home.startSoc }

    private var tonight: some View {
        let r = home.result
        return VStack(spacing: 0) {
            if !routine {
                Label("Used in Routine mode only. Now on \(myHome.mode ?? "another mode"), so no night schedule is set.",
                      systemImage: "pause.circle")
                    .font(.app(size: 12))
                    .foregroundStyle(Theme.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(nowSoc.rounded()))%").font(.app(size: 28, weight: .light)).foregroundStyle(.white)
                    Text("now").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                    Spacer()
                    Text("Limit").font(.app(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                    Text("\(Int(home.limit.rounded()))%").font(.app(size: 15, weight: .medium)).foregroundStyle(.white)
                }
                TBatteryBar(now: nowSoc, limit: home.limit)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            TSegment(items: ["GPS", "TSET", "Others"],
                     subs: ["\(Int(HomeModel.gpsLimit))%", "\(Int(HomeModel.tsetLimit))%", "Slider"],
                     selected: tripIndex, disabled: home.settingLimit) { i in
                    guard !home.settingLimit else { return }
                switch i {
                case 0: Task { await home.chooseTrip("GPS", limit: HomeModel.gpsLimit) }
                case 1: Task { await home.chooseTrip("TSET", limit: HomeModel.tsetLimit) }
                default: home.showLimitSheet = true
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(CarColors.amber, lineWidth: 1.2)
                .opacity(unsent ? 1 : 0))
            .padding(.horizontal, 20)
            Text(unsent ? "Tap tomorrow's trip to send \(Fmt.clock(home.plannedStart(), calendar: .current)) to the vehicle"
                        : "Where you're going tomorrow")
                .font(.app(size: 11)).foregroundStyle(unsent ? CarColors.amber : TeslaDark.dim)
                .padding(.top, 7)
                .padding(.bottom, 14)

            if noNight && home.charging != true {
                TRow("No night charge tonight", icon: "moon", subtitle: "Charges from excess solar by day") { EmptyView() }
            } else {
                TRow("Ready by", icon: "clock") {
                    DatePicker("", selection: readyBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                TRow("Starts charging", icon: "powerplug", subtitle: statusText) {
                    startTime(r)
                } below: {
                    syncTag.padding(.top, -4)
                }
            }
            TNavRow(title: "Charge details", icon: "list.bullet.rectangle",
                    subtitle: r.minutes == 0 || noNight ? "Reminders, safety buffer, charger settings"
                        : "\(Fmt.longDuration(r.minutes)) · +\(Int(r.deltaPct.rounded()))% · \(String(format: "%.1f kWh", r.packKWh))",
                    last: true) {
                path.append(.chargeDetails)
            }
        }
    }

    @ViewBuilder private func startTime(_ r: HomeResult) -> some View {
        if home.charging == true {
            // Charging now: show that and the current, not a start time that has already passed.
            VStack(alignment: .trailing, spacing: 1) {
                Text("Charging").font(.app(size: 22, weight: .light)).foregroundStyle(TSurface.green)
                if let a = myHome.currentNow ?? myHome.chargeAmps {
                    Text("\(Int(a.rounded())) A").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
            }
        } else if r.minutes == 0 {
            Text("Not needed").font(.app(size: 17, weight: .light)).foregroundStyle(TeslaDark.labelGrey)
        } else {
            // The time actually set in the car wins over the app's own estimate, unless an edit is waiting to be sent.
            let start = (home.active && home.startSync == .live ? home.scheduledStart : nil) ?? home.plannedStart()
            let c = splitClock(Fmt.clock(start, calendar: .current))
            VStack(alignment: .trailing, spacing: 1) {
                Text(c.time).font(.app(size: 28, weight: .light)).foregroundStyle(.white)
                if !c.suffix.isEmpty {
                    Text(c.suffix).font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
            }
        }
    }

    private var statusText: String {
        let r = home.result
        if home.charging == true {
            let mode = myHome.mode ?? "Routine"
            return mode == "Routine" ? "Charging now" : "Charging now in \(mode == "Excess Solar" ? "Solar" : mode) mode"
        }
        if r.minutes == 0 {
            return "Already at \(Int(nowSoc.rounded()))%, limit \(Int(home.limit.rounded()))%. Nothing to add tonight."
        }
        if !routine { return "Night plan paused" }
        if home.active && home.startSync != .live {
            let b = home.bufferMinutes
            return "\(dayLabel(home.plannedStart()))" + (b > 0 ? " · \(b) min buffer" : "")
        }
        if home.active, let st = home.scheduledStart {
            return "\(dayLabel(st)) · set in the vehicle"
        }
        return "\(dayLabel(home.plannedStart())). Set in the vehicle when you plug in after 7pm"
    }

    private var unsent: Bool {
        home.startSync == .pending && routine && !noNight && home.charging != true && home.result.minutes > 0
    }

    /// Not sent yet → Checking in car… → Live, under the Starts charging line.
    @ViewBuilder private var syncTag: some View {
        if routine && home.active && home.charging != true && home.result.minutes > 0 {
            let (text, col): (String, Color) = switch home.startSync {
                case .pending: ("Not sent yet", CarColors.amber)
                case .checking: ("Checking in vehicle…", TeslaDark.labelGrey)
                case .live: ("Live", TSurface.green)
            }
            HStack(spacing: 5) {
                Circle().fill(col).frame(width: 6, height: 6)
                Text(text).font(.app(size: 10.5, weight: .medium)).foregroundStyle(col)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(col.opacity(0.16)))
        }
    }

    private var tripIndex: Int? {
        let names = ["GPS", "TSET", "Others"]
        if !home.destination.isEmpty { return names.firstIndex { home.destination.hasPrefix($0) } }
        if abs(home.limit - HomeModel.gpsLimit) < 0.5 { return 0 }
        if abs(home.limit - HomeModel.tsetLimit) < 0.5 { return 1 }
        return nil
    }

    private var readyBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: home.readyMinutes / 60, minute: home.readyMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                home.readyMinutes = (c.hour ?? 5) * 60 + (c.minute ?? 45)
            }
        )
    }
}

func dayLabel(_ d: Date) -> String {
    let cal = Calendar.current
    let h = cal.component(.hour, from: d)
    if cal.isDateInToday(d) { return h >= 17 ? "Tonight" : "Today" }
    if cal.isDateInTomorrow(d) { return h < 12 ? "After midnight" : "Tomorrow" }
    return d.formatted(.dateTime.weekday(.abbreviated))
}

// MARK: - Charge details (level 2)

struct ChargeDetailsPage: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        let r = model.result
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("CHARGE TIME").kerning(0.8)
                        Spacer()
                        Text("COST").kerning(0.8)
                    }
                    .font(.app(size: 11, weight: .medium))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.minutes == 0 ? "Not needed" : Fmt.longDuration(r.minutes))
                            .font(.app(size: r.minutes == 0 ? 30 : 42, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        Text(Fmt.rm(r.cost)).font(.app(size: 28, weight: .bold)).foregroundStyle(TSurface.green)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text(r.minutes == 0
                         ? "Already at \(Int(model.startSoc))%, limit \(Int(model.limit.rounded()))%"
                         : "+\(Int(r.deltaPct.rounded()))% (\(Int(model.startSoc))% → \(Int(model.limit.rounded()))%) · \(String(format: "%.1f", r.packKWh)) kWh into battery")
                        .font(.app(size: 13))
                        .foregroundStyle(TeslaDark.rowLabel)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                NavigationLink { RemindersPage(model: model) } label: {
                    TRow("Reminders", icon: "bell") {
                        HStack(spacing: 8) {
                            Text(reminderSummary).font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                        }
                    }
                }
                .buttonStyle(.plain)
                TRow("Safety buffer", icon: "shield") {
                    HStack(spacing: 10) {
                        TValue(value: "\(model.bufferMinutes)", unit: "min")
                        TStepper(value: $model.bufferMinutes, range: 0...60, step: 5)
                    }
                }
                NavigationLink { ChargerBatteryPage(model: model) } label: {
                    TRow("Charger & battery", icon: "bolt", last: true) {
                        HStack(spacing: 8) {
                            Text("\(Int(model.amps))A · \(Int(model.volts))V · \(model.efficiency.plain)%")
                                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                        }
                    }
                }
                .buttonStyle(.plain)

                Text("Finishes \(model.bufferMinutes) min before your ready time. Saved to Home Assistant, which re-plans tonight's start when these change.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Charge details", black: true)
    }

    private var reminderSummary: String {
        if !model.remindersAvailable { return "Update HA package" }
        if !model.remindersOn { return "Off" }
        return model.reminderTimes.sorted().map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: " · ")
    }
}

/// Charge details → Reminders.
struct RemindersPage: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer().frame(height: 12)
                TRow("Ask where I'm going", icon: "bell", last: !model.remindersOn) {
                    Toggle("", isOn: Binding(get: { model.remindersOn }, set: { model.setRemindersOn($0) })).tint(TSurface.green)
                        .labelsHidden()
                        .tint(TSurface.green)
                }
                if model.remindersOn {
                    ForEach(Array(model.reminderTimes.enumerated()), id: \.offset) { i, t in
                        TRow(ordinal(i + 1) + " reminder", icon: nil) {
                            DatePicker("", selection: timeBinding(i, t), in: eveningRange, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        .modifier(SwipeToDelete(enabled: model.reminderTimes.count > 1) { model.removeReminder(at: i) })
                    }
                    if model.reminderTimes.count < 6 {
                        Button { model.addReminder() } label: {
                            TRow("Add reminder", icon: "plus", last: true) { EmptyView() }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Rectangle().fill(TSurface.line).frame(height: 0.5).padding(.leading, 58).padding(.trailing, 20)
                    }
                }
                TFootnote(text: model.remindersAvailable
                          ? "Sent by Home Assistant Sat–Wed, only while Ultra Rouge is plugged in at home and you haven't answered. Between 5 pm and 9:59 pm. No answer by 10 pm = GPS 73%."
                            + (model.remindersOn && model.reminderTimes.count > 1 ? " Swipe left on a reminder to delete it." : "")
                          : "Update Teslar's Home Assistant package (volttime.yaml) to use reminders.",
                          color: model.remindersAvailable ? TeslaDark.dim : TeslaDark.importing)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Reminders", black: true)
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    private var eveningRange: ClosedRange<Date> {
        let cal = Calendar.current
        let a = cal.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
        let b = cal.date(bySettingHour: 21, minute: 59, second: 0, of: Date()) ?? Date()
        return a...b
    }

    private func timeBinding(_ i: Int, _ minutes: Int) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                model.setReminder(at: i, minutes: (c.hour ?? 19) * 60 + (c.minute ?? 0))
            }
        )
    }
}

/// Charge details → Charger & battery: start charge, charger settings and the worked-out numbers.
struct ChargerBatteryPage: View {
    @ObservedObject var model: HomeModel
    @FocusState private var focus: String?

    var body: some View {
        let r = model.result
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Battery")
                TRow("Start charge", icon: "battery.50percent", badge: socBadge, last: true) {
                    TValue(value: "\(Int(model.startSoc))%")
                } below: {
                    Slider(value: $model.startSoc, in: 0...99, step: 1).tint(.white)
                }

                TCaption(text: "Settings")
                TRow("Current") { TValueField(value: $model.amps, unit: "A", focus: $focus, key: "amps") }
                TRow("Voltage") { TValueField(value: $model.volts, unit: "V", focus: $focus, key: "volts") }
                TRow("Efficiency") { TValueField(value: $model.efficiency, unit: "%", focus: $focus, key: "eff") }
                TRow("Capacity") { TValueField(value: $model.capacity, unit: "kWh", focus: $focus, key: "cap") }
                TRow("Tariff", subtitle: "Off-peak, from Utility Rate Plan", last: true) {
                    TValue(value: String(format: "%.4f", model.tariff), unit: "RM/kWh")
                }

                TCaption(text: "Numbers")
                TRow("From the wall") { TValue(value: String(format: "%.2f", r.wallKWh), unit: "kWh") }
                TRow("Power", subtitle: "From the wall → into the battery") {
                    TValue(value: String(format: "%.2f → %.2f", r.grossKW, r.netKW), unit: "kW")
                }
                TRow("Pace", last: true) {
                    TValue(value: "\(r.secondsPerPct / 60)m \(String(format: "%02d", r.secondsPerPct % 60))s", unit: "per 1%")
                }

                Button("Reset to defaults") { model.resetDefaults() }
                    .font(.app(size: 14)).foregroundStyle(Theme.rouge)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .teslaPage("Charger & battery", black: true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private var socBadge: AnyView? {
        if model.socIsLive { return AnyView(Badge(text: "LIVE", color: TSurface.green)) }
        if let live = model.liveSoc {
            return AnyView(
                Button("Use vehicle \(Int(live.rounded()))%") { model.startSoc = live.rounded() }
                    .font(.app(size: 12, weight: .medium)).foregroundStyle(TeslaDark.labelGrey)
                    .buttonStyle(.plain)
            )
        }
        return nil
    }
}

// MARK: - "Others" limit sheet

struct LimitSheet: View {
    @ObservedObject var model: HomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 80

    private static let picks = [60, 70, 80, 90, 100]

    var body: some View {
        let now = model.liveSoc ?? model.startSoc
        VStack(spacing: 0) {
            Text("Charge limit for tomorrow").font(.app(size: 16, weight: .semibold)).foregroundStyle(.white)
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))").font(.app(size: 60, weight: .light))
                Text("%").font(.app(size: 24, weight: .light)).foregroundStyle(TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
            Text("Drag the battery to set").font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.bottom, 20)

            TBatteryBar(now: now, limit: max(value, now), range: 50...100) { value = $0 }
                .padding(.horizontal, 20)
            HStack {
                (Text("\(Int(now.rounded()))%").foregroundStyle(.white) + Text(" now"))
                Spacer()
                Text(value > now ? "+\(Int((value - now).rounded()))%" : "No charge needed")
            }
            .font(.app(size: 13))
            .foregroundStyle(TeslaDark.rowLabel)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)

            TSegment(items: Self.picks.map { "\($0)%" }, selected: Self.picks.firstIndex(of: Int(value))) {
                value = Double(Self.picks[$0])
            }
            .padding(.horizontal, 20)

            Button {
                let v = value
                Task { await model.chooseTrip("Others", limit: v) }
                dismiss()
            } label: {
                Text("Set limit").font(.app(size: 16, weight: .medium)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.selected))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 31 / 255, green: 32 / 255, blue: 34 / 255).ignoresSafeArea())
        .onAppear { value = (model.liveLimit ?? model.limit).rounded() }
        .preferredColorScheme(.dark)
    }
}
