import SwiftUI

/// Pages pushed from My Home.
enum Route: Hashable {
    case energy, settings, chargeDetails, homeAssistant, charge, impact
}

// MARK: - Shared dark building blocks

extension View {
    /// Dark page with a small centred title and the system back button (white).
    func teslaPage(_ title: String, black: Bool = false) -> some View {
        self
            .background((black ? TSurface.page : TeslaDark.bg).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(black ? TSurface.page : TeslaDark.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
        .font(.system(size: 11, weight: .semibold))
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
                    Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 11)).foregroundStyle(TeslaDark.rowLabel)
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
                    Text(mode.title).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(selected ? Color.white : TeslaDark.rowLabel)
                    Text(mode.detail).font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
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
    @Binding var path: [Route]
    @ObservedObject private var backup = BackupManager.shared

    private var routine: Bool { (myHome.mode ?? "Routine") == "Routine" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Charging mode")
                modeTiles
                    .padding(.horizontal, 20)
                Text(ChargingMode.named(myHome.pendingMode ?? myHome.mode ?? "Routine").detail)
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.horizontal, 20)
                if let msg = myHome.message ?? home.message {
                    Text(msg).font(.system(size: 12)).foregroundStyle(TeslaDark.importing)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }

                TCaption(text: "Tonight's charge", trailing: routine ? "Sat–Wed" : "Routine only")
                tonight
                    .opacity(routine ? 1 : 0.55)

                TCaption(text: "System")
                TNavRow(title: "Home Assistant", icon: "house",
                        subtitle: home.haConfigured ? (home.message == nil ? "Connected" : "Can't reach Home Assistant") : "Not set up",
                        dot: home.haConfigured ? (home.message == nil ? TSurface.green : TeslaDark.importing) : nil) {
                    path.append(.homeAssistant)
                }
                NavigationLink { BackupPage(energy: energy) } label: {
                    TRow("Backup & restore", icon: "arrow.triangle.2.circlepath", subtitle: backup.summary,
                         dot: backup.summaryColor, last: true) {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                    }
                }
                .buttonStyle(.plain)
                Spacer(minLength: 12)
            }
        }
        .scrollBounceBehavior(.basedOnSize)   // fixed when it fits; scrolls only if something makes it taller
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
                            Text(emoji).font(.system(size: 22)).opacity(myHome.pendingMode == option ? 0.25 : 1)
                            if myHome.pendingMode == option { ProgressView().tint(.white).scaleEffect(0.7) }
                        }
                        Text(option == "Excess Solar" ? "Solar" : option)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
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

    private var nowSoc: Double { home.liveSoc ?? home.startSoc }

    private var tonight: some View {
        let r = home.result
        return VStack(spacing: 0) {
            if !routine {
                Label("Used in Routine mode only. Now on \(myHome.mode ?? "another mode"), so no night schedule is set.",
                      systemImage: "pause.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(nowSoc.rounded()))%").font(.system(size: 28, weight: .light)).foregroundStyle(.white)
                    Text("now").font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                    Spacer()
                    if home.settingLimit { ProgressView().tint(.white).scaleEffect(0.7) }
                    Text("Limit").font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                    Text("\(Int(home.limit.rounded()))%").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                }
                TBatteryBar(now: nowSoc, limit: home.limit)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            TSegment(items: ["GPS", "TSET", "Others"],
                     subs: ["\(Int(HomeModel.gpsLimit))%", "\(Int(HomeModel.tsetLimit))%", "Slider"],
                     selected: tripIndex, disabled: home.settingLimit) { i in
                switch i {
                case 0: Task { await home.chooseTrip("GPS", limit: HomeModel.gpsLimit) }
                case 1: Task { await home.chooseTrip("TSET", limit: HomeModel.tsetLimit) }
                default: home.showLimitSheet = true
                }
            }
            .padding(.horizontal, 20)
            Text("Where you're going tomorrow")
                .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
                .padding(.top, 7)
                .padding(.bottom, 14)

            TRow("Ready by", icon: "clock") {
                DatePicker("", selection: readyBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            TRow("Starts charging", icon: "powerplug", subtitle: statusText) {
                startTime(r)
            }
            TNavRow(title: "Charge details", icon: "list.bullet.rectangle",
                    subtitle: r.minutes == 0 ? "Reminders, safety buffer, charger settings"
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
                Text("Charging").font(.system(size: 22, weight: .light)).foregroundStyle(TSurface.green)
                if let a = myHome.currentNow ?? myHome.chargeAmps {
                    Text("\(Int(a.rounded())) A").font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
            }
        } else if r.minutes == 0 {
            Text("Not needed").font(.system(size: 17, weight: .light)).foregroundStyle(TeslaDark.labelGrey)
        } else {
            // The time actually set in the car wins over the app's own estimate.
            let start = (home.active ? home.scheduledStart : nil) ?? home.plannedStart()
            let c = splitClock(Fmt.clock(start, calendar: .current))
            VStack(alignment: .trailing, spacing: 1) {
                Text(c.time).font(.system(size: 28, weight: .light)).foregroundStyle(.white)
                if !c.suffix.isEmpty {
                    Text(c.suffix).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
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
        if home.active, let st = home.scheduledStart {
            return "\(dayLabel(st)) · set in the car"
        }
        return "\(dayLabel(home.plannedStart())). Set in the car when you plug in after 7pm"
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TeslaDark.rowLabel)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                    HStack(alignment: .firstTextBaseline) {
                        Text(r.minutes == 0 ? "Not needed" : Fmt.longDuration(r.minutes))
                            .font(.system(size: r.minutes == 0 ? 30 : 42, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Spacer()
                        Text(Fmt.rm(r.cost)).font(.system(size: 28, weight: .bold)).foregroundStyle(TSurface.green)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text(r.minutes == 0
                         ? "Already at \(Int(model.startSoc))%, limit \(Int(model.limit.rounded()))%"
                         : "+\(Int(r.deltaPct.rounded()))% (\(Int(model.startSoc))% → \(Int(model.limit.rounded()))%) · \(String(format: "%.1f", r.packKWh)) kWh into battery")
                        .font(.system(size: 13))
                        .foregroundStyle(TeslaDark.rowLabel)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                NavigationLink { RemindersPage(model: model) } label: {
                    TRow("Reminders", icon: "bell") {
                        HStack(spacing: 8) {
                            Text(reminderSummary).font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
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
                                .font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                        }
                    }
                }
                .buttonStyle(.plain)

                Text("Finishes \(model.bufferMinutes) min before your ready time. Saved to Home Assistant, which re-plans tonight's start when these change.")
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
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
                    Toggle("", isOn: Binding(get: { model.remindersOn }, set: { model.setRemindersOn($0) }))
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
                    .font(.system(size: 14)).foregroundStyle(Theme.rouge)
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
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(TeslaDark.labelGrey)
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
            Text("Charge limit for tomorrow").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .padding(.top, 28)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(value))").font(.system(size: 60, weight: .light))
                Text("%").font(.system(size: 24, weight: .light)).foregroundStyle(TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
            .padding(.top, 8)
            Text("Drag the battery to set").font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.bottom, 20)

            TBatteryBar(now: now, limit: max(value, now), range: 50...100) { value = $0 }
                .padding(.horizontal, 20)
            HStack {
                (Text("\(Int(now.rounded()))%").foregroundStyle(.white) + Text(" now"))
                Spacer()
                Text(value > now ? "+\(Int((value - now).rounded()))%" : "No charge needed")
            }
            .font(.system(size: 13))
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
                Text("Set limit").font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
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
