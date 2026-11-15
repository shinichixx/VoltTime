import SwiftUI

/// Pages pushed from My Home.
enum Route: Hashable {
    case energy, settings, chargeDetails, homeAssistant, charge
}

// MARK: - Shared dark building blocks

extension View {
    /// Dark page with a small centred title and the system back button (white).
    func teslaPage(_ title: String) -> some View {
        self
            .background(TeslaDark.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(TeslaDark.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
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
    @Binding var path: [Route]

    private var routine: Bool { (myHome.mode ?? "Routine") == "Routine" }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionCaption(text: "Charging mode")
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(myHome.modeOptions, id: \.self) { option in
                            ModeRow(model: myHome, mode: ChargingMode.named(option), inset: 0)
                        }
                        if let msg = myHome.message ?? home.message {
                            Text(msg).font(.system(size: 12)).foregroundStyle(TeslaDark.importing)
                                .padding(.top, 6)
                        }
                    }
                    .padding(.vertical, -4)
                }
                .padding(.horizontal, 16)

                SectionCaption(text: "Charging start time", trailing: "Routine")
                startTimeCard
                    .padding(.horizontal, 16)

                SectionCaption(text: "Home Assistant")
                NavRow(icon: "server.rack", title: "Connection",
                       detail: home.haConfigured ? (home.message == nil ? "Connected" : "Can't reach Home Assistant") : "Not set up") {
                    path.append(.homeAssistant)
                }
                Spacer(minLength: 40)
            }
        }
        .refreshable {
            await home.refresh()
            await myHome.refresh()
        }
        .teslaPage("Settings")
        .task {
            await home.refresh()
            await myHome.refresh()
        }
    }

    // MARK: Charging start time

    private var startTimeCard: some View {
        let r = home.result
        let start = home.plannedStart()
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                if !routine {
                    Label("Used in Routine mode only. Now on \(myHome.mode ?? "another mode"), so no night schedule is set.",
                          systemImage: "pause.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Location tomorrow").font(.system(size: 13, weight: .medium)).foregroundStyle(TeslaDark.labelGrey)
                        Spacer()
                        if home.settingLimit { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text("Limit \(Int(home.limit.rounded()))%").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    }
                    HStack(spacing: 8) {
                        tripButton("GPS", HomeModel.gpsLimit) { Task { await home.chooseTrip("GPS", limit: HomeModel.gpsLimit) } }
                        tripButton("TSET", HomeModel.tsetLimit) { Task { await home.chooseTrip("TSET", limit: HomeModel.tsetLimit) } }
                        tripButton("Others", nil) { home.showLimitSheet = true }
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                HStack {
                    Text("Ready by").font(.system(size: 14)).foregroundStyle(.white)
                    Spacer()
                    DatePicker("", selection: readyBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }

                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 6) {
                    Text("START TIME").font(.system(size: 11, weight: .semibold)).kerning(0.5).foregroundStyle(TeslaDark.dim)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(r.minutes == 0 ? "—" : Fmt.clock(start, calendar: .current))
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        if r.minutes > 0 {
                            Text(dayLabel(start)).font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                        }
                    }
                    scheduleStatus
                }

                Divider().overlay(Color.white.opacity(0.08))

                Button { path.append(.chargeDetails) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Charge details").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            Text(r.minutes == 0 ? "Safety buffer, battery, charger settings"
                                 : "\(Fmt.longDuration(r.minutes)) · +\(Int(r.deltaPct.rounded()))% · \(String(format: "%.1f kWh", r.packKWh))")
                                .font(.system(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(routine ? 1 : 0.6)
    }

    @ViewBuilder private var scheduleStatus: some View {
        HStack(spacing: 6) {
            if home.charging == true {
                Image(systemName: "bolt.fill").foregroundStyle(TeslaDark.chargingGreen)
                Text("Charging now").foregroundStyle(TeslaDark.chargingGreen)
            } else if !routine {
                Image(systemName: "moon.zzz").foregroundStyle(TeslaDark.dim)
                Text("Night plan paused").foregroundStyle(TeslaDark.rowLabel)
            } else if home.active, let st = home.scheduledStart {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(TeslaDark.chargingGreen)
                Text("Set in the car for \(Fmt.clock(st, calendar: .current))").foregroundStyle(.white)
            } else {
                Image(systemName: "moon.zzz").foregroundStyle(TeslaDark.dim)
                Text("Sat–Wed nights, set when you plug in after 7pm").foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func tripButton(_ name: String, _ value: Double?, action: @escaping () -> Void) -> some View {
        let selected: Bool = {
            if !home.destination.isEmpty { return home.destination.hasPrefix(name) }
            if let value { return abs(home.limit - value) < 0.5 }
            return false
        }()
        return Button(action: action) {
            VStack(spacing: 2) {
                Text(name).font(.system(size: 14, weight: .semibold))
                Text(value.map { "\(Int($0))%" } ?? "Slider").font(.system(size: 11))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : TeslaDark.rowLabel)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selected ? Theme.teal : Theme.field)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(home.settingLimit)
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
    @FocusState private var focus: String?

    var body: some View {
        let r = model.result
        ScrollView {
            VStack(spacing: 12) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Figure(label: "Duration", value: Fmt.longDuration(r.minutes))
                            Figure(label: "Added", value: "+\(Int(r.deltaPct.rounded()))%", color: Theme.teal)
                            Figure(label: "Energy", value: String(format: "%.1f kWh", r.packKWh))
                        }
                        batteryBar(r)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Stepper(value: $model.bufferMinutes, in: 0...60, step: 5) {
                            HStack {
                                Text("Safety buffer").font(.system(size: 14))
                                Spacer()
                                Text("\(model.bufferMinutes) min").font(.system(size: 14, weight: .semibold))
                            }
                        }
                        Text("Charging finishes this long before the ready time.")
                            .font(.system(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                        Divider().overlay(Color.white.opacity(0.08))
                        VStack(spacing: 6) {
                            HStack {
                                Text("Start state of charge").font(.system(size: 14))
                                if model.socIsLive { Badge(text: "LIVE", color: TeslaDark.chargingGreen) }
                                else if let live = model.liveSoc {
                                    Button("Use car \(Int(live.rounded()))%") { model.startSoc = live.rounded() }
                                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.teal)
                                }
                                Spacer()
                                Text("\(Int(model.startSoc))%").font(.system(size: 15, weight: .semibold))
                            }
                            Slider(value: $model.startSoc, in: 0...99, step: 1).tint(Theme.teal)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wall power").font(.system(size: 14, weight: .medium))
                                Text("Drawn before AC–DC loss @ \(model.efficiency.plain)%").font(.system(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                            }
                            Spacer()
                            Text(String(format: "%.2f kWh", r.wallKWh)).font(.system(size: 16, weight: .semibold))
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Estimated cost").font(.system(size: 14, weight: .medium))
                                Text("RM \(String(format: "%.4f", model.tariff)) / kWh").font(.system(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                            }
                            Spacer()
                            Text(Fmt.rm(r.cost)).font(.system(size: 20, weight: .semibold)).foregroundStyle(TeslaDark.exporting)
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHARGER AND BATTERY").font(.system(size: 11, weight: .semibold)).kerning(0.5).foregroundStyle(TeslaDark.dim)
                        ValueRow(label: "Current", value: $model.amps, unit: "A", focus: $focus, key: "amps")
                        ValueRow(label: "Voltage", value: $model.volts, unit: "V", focus: $focus, key: "volts")
                        ValueRow(label: "Charging efficiency", value: $model.efficiency, unit: "%", focus: $focus, key: "eff")
                        ValueRow(label: "Battery capacity", value: $model.capacity, unit: "kWh", focus: $focus, key: "cap")
                        ValueRow(label: "Tariff", value: $model.tariff, unit: "RM/kWh", focus: $focus, key: "tariff")
                        HStack(spacing: 8) {
                            Figure(label: "Gross power", value: String(format: "%.2f kW", r.grossKW))
                            Figure(label: "Net to battery", value: String(format: "%.3f kW", r.netKW))
                            Figure(label: "Pace", value: "\(r.secondsPerPct / 60)m \(String(format: "%02d", r.secondsPerPct % 60))s/1%")
                        }
                        .padding(.top, 4)
                        Button("Reset to defaults") { model.resetDefaults() }
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.rouge)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                }
                Text("Saved to Home Assistant, which re-plans tonight's start when these change.")
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .teslaPage("Charge details")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private func batteryBar(_ r: HomeResult) -> some View {
        VStack(spacing: 5) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.field)
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(white: 0.45)).frame(width: w * min(1, model.startSoc / 100))
                        Rectangle().fill(Theme.teal).frame(width: w * min(1, r.deltaPct / 100))
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)
            HStack {
                Text("\(Int(model.startSoc))%")
                Spacer()
                Text("+\(Int(r.deltaPct.rounded()))% added").fontWeight(.semibold)
                Spacer()
                Text("\(Int(model.limit.rounded()))%")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(TeslaDark.rowLabel)
        }
    }
}

// MARK: - "Others" slider

struct LimitSheet: View {
    @ObservedObject var model: HomeModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 80

    var body: some View {
        VStack(spacing: 18) {
            Text("Charge limit for tomorrow").font(.headline).foregroundStyle(.white).padding(.top, 26)
            Text("\(Int(value))%").font(.system(size: 52, weight: .semibold)).foregroundStyle(.white)
            Slider(value: $value, in: 50...100, step: 1).tint(Theme.teal).padding(.horizontal, 24)
            HStack(spacing: 8) {
                ForEach([60, 70, 80, 90, 100], id: \.self) { p in
                    Button("\(p)%") { value = Double(p) }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Int(value) == p ? Theme.teal : Theme.field)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            Button {
                let v = value
                Task { await model.chooseTrip("Others", limit: v) }
                dismiss()
            } label: {
                Text("Set limit").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.teal).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.09).ignoresSafeArea())
        .onAppear { value = (model.liveLimit ?? model.limit).rounded() }
        .preferredColorScheme(.dark)
    }
}
