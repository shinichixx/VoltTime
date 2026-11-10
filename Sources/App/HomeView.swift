import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var model: HomeModel
    @Binding var showSettings: Bool
    @FocusState private var focus: String?
    @State private var showAdvanced = false
    @State private var copied = false

    var body: some View {
        let r = model.result
        let start = model.plannedStart()
        VStack(spacing: 0) {
            AppHeader(icon: "house.fill", title: "Ultra Rouge", subtitle: headerSubtitle) {
                HStack(spacing: 8) {
                    if model.haConfigured {
                        HeaderButton(systemName: "arrow.clockwise", spinning: model.busy) { Task { await model.refresh() } }
                    }
                    HeaderButton(systemName: "gearshape.fill") { showSettings = true }
                }
            }
            ScrollView {
                VStack(spacing: 12) {
                    if let msg = model.message {
                        Text(msg).font(.system(size: 12)).foregroundStyle(Theme.rouge)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Theme.rouge.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    startCard(r, start)
                    tripCard
                    planCard(r)
                    costCard(r)
                    advancedCard(r)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if let soc = model.liveSoc { parts.append("\(Int(soc.rounded()))%") }
        if model.charging == true { parts.append("Charging") }
        else if let p = model.plugged { parts.append(p ? "Plugged in" : "Unplugged") }
        return parts.isEmpty ? "Home charging" : parts.joined(separator: " · ")
    }

    // MARK: Start time

    private func startCard(_ r: HomeResult, _ start: Date) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CHARGE START").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.teal).kerning(0.6)
                        Text(r.minutes == 0 ? "—" : Fmt.clock(start, calendar: .current))
                            .font(.system(size: 40, weight: .heavy)).foregroundStyle(.primary)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        HStack(spacing: 8) {
                            Badge(text: dayLabel(start), color: Theme.green)
                            Text("ready by \(Fmt.clock(minutes: model.readyMinutes))").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = "Tesla Charge Start: \(Fmt.clock(start, calendar: .current)) (\(dayLabel(start))) for ready time \(Fmt.clock(minutes: model.readyMinutes))."
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.field).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 8) {
                    Figure(label: "Duration", value: Fmt.longDuration(r.minutes))
                    Figure(label: "Added", value: "+\(Int(r.deltaPct.rounded()))%", color: Theme.teal)
                    Figure(label: "Energy", value: String(format: "%.1f kWh", r.packKWh))
                }
                scheduleStatus
            }
        }
    }

    @ViewBuilder private var scheduleStatus: some View {
        if model.haConfigured {
            Divider()
            HStack(spacing: 8) {
                if model.charging == true {
                    Image(systemName: "bolt.fill").foregroundStyle(Theme.green)
                    Text("Charging now").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.green)
                } else if model.active, let st = model.scheduledStart {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green)
                    Text("Car schedule: \(Fmt.clock(st, calendar: .current))").font(.system(size: 12, weight: .semibold))
                    Text("set by Home Assistant").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "moon.zzz").foregroundStyle(.secondary)
                    Text("Not scheduled · runs Sat–Wed nights from 7pm").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let h = cal.component(.hour, from: d)
        if cal.isDateInToday(d) { return h >= 17 ? "Tonight" : "Today" }
        if cal.isDateInTomorrow(d) { return h < 12 ? "After midnight" : "Tomorrow" }
        return d.formatted(.dateTime.weekday(.abbreviated))
    }

    // MARK: Trip

    private var tripCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(icon: "mappin.and.ellipse", title: "Where are you going tomorrow?", color: Theme.orange,
                          trailing: model.destination.isEmpty ? "" : model.destination)
                HStack(spacing: 8) {
                    tripButton("GPS", HomeModel.gpsLimit) { Task { await model.chooseTrip("GPS", limit: HomeModel.gpsLimit) } }
                    tripButton("TSET", HomeModel.tsetLimit) { Task { await model.chooseTrip("TSET", limit: HomeModel.tsetLimit) } }
                    tripButton("Others", nil) { model.showLimitSheet = true }
                }
                HStack {
                    Text("Charge limit").font(.system(size: 13))
                    Spacer()
                    if model.settingLimit { ProgressView().scaleEffect(0.8) }
                    Text("\(Int(model.limit.rounded()))%").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.orange)
                }
                if !model.haConfigured {
                    Slider(value: $model.limit, in: 50...100, step: 1).tint(Theme.orange)
                }
            }
        }
    }

    private func tripButton(_ name: String, _ value: Double?, action: @escaping () -> Void) -> some View {
        let selected: Bool = {
            if !model.destination.isEmpty { return model.destination.hasPrefix(name) }
            if let value { return abs(model.limit - value) < 0.5 }
            return false
        }()
        return Button(action: action) {
            VStack(spacing: 2) {
                Text(name).font(.system(size: 14, weight: .bold))
                Text(value.map { "\(Int($0))%" } ?? "Slider").font(.system(size: 11))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? .white : Theme.orange)
            .background(selected ? Theme.orange : Theme.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(model.settingLimit)
    }

    // MARK: Plan inputs

    private func planCard(_ r: HomeResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(icon: "clock.fill", title: "Plan", color: Theme.teal, trailing: "End of charge")
                HStack {
                    Text("Target ready time").font(.system(size: 13))
                    Spacer()
                    DatePicker("", selection: readyBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Stepper(value: $model.bufferMinutes, in: 0...60, step: 5) {
                    HStack {
                        Text("Safety buffer").font(.system(size: 13))
                        Spacer()
                        Text("\(model.bufferMinutes) min").font(.system(size: 13, weight: .semibold))
                    }
                }
                VStack(spacing: 4) {
                    HStack {
                        Text("Start state of charge").font(.system(size: 13))
                        if model.socIsLive { Badge(text: "LIVE", color: Theme.green) }
                        else if let live = model.liveSoc {
                            Button("Use car \(Int(live.rounded()))%") { model.startSoc = live.rounded() }
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.teal)
                        }
                        Spacer()
                        Text("\(Int(model.startSoc))%").font(.system(size: 15, weight: .bold))
                    }
                    Slider(value: $model.startSoc, in: 0...99, step: 1).tint(Theme.teal)
                }
                batteryBar(r)
            }
        }
    }

    private var readyBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: model.readyMinutes / 60, minute: model.readyMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                model.readyMinutes = (c.hour ?? 5) * 60 + (c.minute ?? 45)
            }
        )
    }

    private func batteryBar(_ r: HomeResult) -> some View {
        VStack(spacing: 5) {
            GeometryReader { g in
                let w = g.size.width
                let startW = w * min(1, model.startSoc / 100)
                let addW = w * min(1, r.deltaPct / 100)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.field)
                    HStack(spacing: 0) {
                        Rectangle().fill(Color(white: 0.62)).frame(width: startW)
                        Rectangle().fill(Theme.teal).frame(width: addW)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: 10)
            HStack {
                Text("0%")
                Spacer()
                Text("+\(Int(r.deltaPct.rounded()))% added to battery").fontWeight(.semibold)
                Spacer()
                Text("100%")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Cost

    private func costCard(_ r: HomeResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wall power consumption").font(.system(size: 13, weight: .semibold))
                        Text("Drawn before AC–DC loss").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.2f kWh", r.wallKWh)).font(.system(size: 16, weight: .bold))
                        Text("@ \(model.efficiency.plain)% efficiency").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.green).frame(width: 30, height: 30)
                        .overlay(Text("RM").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimated cost").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                        Text("RM \(String(format: "%.4f", model.tariff)) / kWh").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.rm(r.cost)).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.green)
                }
                .padding(10)
                .background(Theme.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: Advanced

    private func advancedCard(_ r: HomeResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "gearshape.2.fill").foregroundStyle(Theme.blue)
                        Text("Advanced parameters").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(Int(model.amps))A · \(Int(model.volts))V · \(model.capacity.plain)kWh")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)
                if showAdvanced {
                    Divider()
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
                    Button("Reset to defaults") { model.resetDefaults() }
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.rouge)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
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
            Text("Charge limit for tomorrow").font(.headline).padding(.top, 26)
            Text("\(Int(value))%").font(.system(size: 52, weight: .heavy)).foregroundStyle(Theme.orange)
            Slider(value: $value, in: 50...100, step: 1).tint(Theme.orange).padding(.horizontal, 24)
            HStack(spacing: 8) {
                ForEach([60, 70, 80, 90, 100], id: \.self) { p in
                    Button("\(p)%") { value = Double(p) }
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .foregroundStyle(Int(value) == p ? .white : Theme.orange)
                        .background(Int(value) == p ? Theme.orange : Theme.orange.opacity(0.10))
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
                Text("Set limit").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.teal).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
        .onAppear { value = (model.liveLimit ?? model.limit).rounded() }
        .preferredColorScheme(.light)
    }
}
