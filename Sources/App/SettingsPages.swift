import SwiftUI

/// Pages pushed from My Home.
enum Route: Hashable {
    case energy, settings, chargeDetails, homeAssistant, charge, impact
    case menu, carDetail(CarDetail), energyView(EnergyComponent)
}

// MARK: - Shared dark building blocks

/// One of the three System tiles at the bottom of Settings (My Car, My Home, Backup).
struct SystemTile: View {
    let icon: String
    let title: String
    let status: String
    let dot: Color?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(TSurface.icon)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(TeslaDark.dim)
            }
            .frame(height: 22)
            Text(title).font(.app(size: 15, weight: .medium)).foregroundStyle(.white)
                .padding(.top, 8)
            HStack(spacing: 4) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(status).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel).lineLimit(1)
            }
            .padding(.top, 3)
            Text(detail).font(.app(size: 10)).foregroundStyle(TeslaDark.dim).lineLimit(1)
                .padding(.top, 1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(TSurface.field))
        .contentShape(Rectangle())
    }
}

extension View {
    /// Dark page with our own slim top bar (Tesla app): thin grey back arrow, small centred title, optional
    /// item on the right. Replaces the system bar, which is much taller on iOS 26.
    func teslaPage(_ title: String, black: Bool = false, trailing: AnyView? = nil) -> some View {
        let bg = black ? TSurface.page : TeslaDark.bg
        return self
            .background(bg.ignoresSafeArea())
            .navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                TeslaTopBar(title: title, trailing: trailing, background: bg)
            }
    }

    /// Tesla app back button: a thin grey arrow, no circle behind it (iOS 26 would put the system one in glass).
    @ViewBuilder func plainBackButton() -> some View {
        if #available(iOS 26.0, *) {
            self.navigationBarBackButtonHidden(true)
                .toolbar { ToolbarItem(placement: .topBarLeading) { PlainBackButton() }.sharedBackgroundVisibility(.hidden) }
        } else {
            self.navigationBarBackButtonHidden(true)
                .toolbar { ToolbarItem(placement: .topBarLeading) { PlainBackButton() } }
        }
    }
}

/// The slim top bar: 32 pt under the status bar; content starts right below it.
struct TeslaTopBar: View {
    let title: String
    let trailing: AnyView?
    let background: Color

    var body: some View {
        ZStack {
            Text(title).font(.app(size: 15, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 80)
            HStack(spacing: 0) {
                PlainBackButton().padding(.leading, 14)
                Spacer()
                if let trailing { trailing.padding(.trailing, 18) }
            }
        }
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(background.ignoresSafeArea(edges: .top))
    }
}

/// 7 × 13 pt chevron in mid grey, like the Tesla app; the tap area stays 44 pt.
struct PlainBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            BackChevron()
                .stroke(Color(white: 0.54), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 7.5, height: 13.5)
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

/// Label whose icon has its own colour.
struct TintedIconLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(color)
            configuration.title
        }
    }
}

struct SectionCaption: View {
    let text: String
    var trailing: String = ""

    var body: some View {
        HStack {
            Text(text.uppercased())
            Spacer()
            if !trailing.isEmpty { Text(trailing) }
        }
        .font(.app(size: 11, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(TeslaDark.dim)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

/// Row that opens another page: icon, title over detail, chevron.
struct NavRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(TeslaDark.rowIcon)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(size: 15, weight: .medium)).foregroundStyle(.white)
                    if !detail.isEmpty {
                        Text(detail).font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Radio row for one charging mode.
struct ModeRow: View {
    @ObservedObject var model: MyHomeModel
    let mode: ChargingMode
    var inset: CGFloat = 24

    var body: some View {
        let selected = (model.pendingMode ?? model.mode) == mode.option
        Button {
            Task { await model.setMode(mode.option) }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? Color.white : TeslaDark.dim)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title).font(.app(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Color.white : TeslaDark.rowLabel)
                    Text(mode.detail).font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                }
                Spacer()
                if model.pendingMode == mode.option { ProgressView().tint(.white).scaleEffect(0.8) }
            }
            .padding(.horizontal, inset)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.pendingMode != nil)
    }
}

// MARK: - Settings (level 1)

struct SettingsPage: View {
    @ObservedObject var home: HomeModel
    @ObservedObject var myHome: MyHomeModel
    @ObservedObject var energy: EnergyStore
    @ObservedObject var car: CarModel
    @Binding var path: [Route]
    private var routine: Bool { (myHome.mode ?? "Routine") == "Routine" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Car charging mode")
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
                    TCaption(text: "Tonight's charge", trailing: "Sat–Wed")
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
        .teslaPage("Settings", black: true)
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
            Text(unsent ? "Tap tomorrow's trip to send \(Fmt.clock(home.plannedStart(), calendar: .current)) to the car"
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
            return "\(dayLabel(st)) · set in the car"
        }
        return "\(dayLabel(home.plannedStart())). Set in the car when you plug in after 7pm"
    }

    private var unsent: Bool {
        home.startSync == .pending && routine && !noNight && home.charging != true && home.result.minutes > 0
    }

    /// Not sent yet → Checking in car… → Live, under the Starts charging line.
    @ViewBuilder private var syncTag: some View {
        if routine && home.active && home.charging != true && home.result.minutes > 0 {
            let (text, col): (String, Color) = switch home.startSync {
                case .pending: ("Not sent yet", CarColors.amber)
                case .checking: ("Checking in car…", TeslaDark.labelGrey)
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
                          : "Update the VoltTime package in Home Assistant to use reminders.",
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
                TRow("Tariff", last: true) { TValueField(value: $model.tariff, unit: "RM", focus: $focus, key: "tariff") }

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
                Button("Use car \(Int(live.rounded()))%") { model.startSoc = live.rounded() }
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
