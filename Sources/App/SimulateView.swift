import SwiftUI

/// What-if calculator: "if I want X % by the time I leave, when does charging have to start?"
/// Uses the charger settings from Charge details. Nothing here is sent to the car or Home Assistant.
/// Laid out like Public charging: answer + cost on top, battery bar, quick picks, a few rows, Charger ›.
struct SimulateView: View {
    @ObservedObject var model: HomeModel
    @AppStorage("sim.leave") private var leaveMinutes = 7 * 60
    @AppStorage("sim.target") private var target = 100.0
    @AppStorage("sim.buffer") private var bufferMinutes = 15

    private var startSoc: Double { model.simStartSoc ?? min(99, (model.liveSoc ?? model.startSoc).rounded()) }

    private static let targets = [63, 73, 80, 90, 100]

    static func result(_ model: HomeModel, start: Double, target: Double) -> HomeResult {
        HomeMath.calculate(HomeInputs(startSoc: start, endSoc: target, amps: model.amps, volts: model.volts,
                                      efficiencyPct: model.efficiency, capacityKWh: model.capacity, tariff: model.tariff))
    }

    var body: some View {
        let r = Self.result(model, start: startSoc, target: target)
        let sim = HomeMath.simulatedStart(leaveMinutes: leaveMinutes, chargeMinutes: r.minutes, bufferMinutes: bufferMinutes)
        ScrollView {
            VStack(spacing: 0) {
                hero(r, sim)

                TBatteryBar(now: startSoc, limit: max(target, startSoc), range: 1...100) { target = $0 }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                HStack {
                    (Text("\(Int(startSoc))%").foregroundStyle(.white) + Text(isLive ? " now" : " start"))
                    Spacer()
                    (Text("Charge to ") + Text("\(Int(target))%").foregroundStyle(.white))
                }
                .font(.app(size: 13))
                .foregroundStyle(TeslaDark.rowLabel)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                TSegment(items: Self.targets.map { "\($0)%" }, selected: Self.targets.firstIndex(of: Int(target))) {
                    target = Double(Self.targets[$0])
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 18)

                TRow("Starting with", icon: "battery.25percent", badge: socBadge) {
                    HStack(spacing: 10) {
                        TValue(value: "\(Int(startSoc))%")
                        TStepper(value: startBinding, range: 0...99, step: 1)
                    }
                }
                TRow("I leave at", icon: "clock") {
                    DatePicker("", selection: leaveBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                NavigationLink {
                    SimChargerPage(model: model, startSoc: startSoc, target: target, bufferMinutes: $bufferMinutes)
                } label: {
                    TRow("Charger", icon: "bolt", last: true) {
                        HStack(spacing: 8) {
                            Text("\(Int(model.amps))A · RM \(String(format: "%.4f", model.tariff))/kWh")
                                .font(.app(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(TeslaDark.dim)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 60)
        }
        // See-through: the page background is drawn behind the pager (so the house can fade behind it).
    }

    private var isLive: Bool {
        guard let live = model.liveSoc else { return false }
        return abs(live - startSoc) < 0.5
    }

    private var startBinding: Binding<Int> {
        Binding(get: { Int(startSoc) }, set: { model.simStartSoc = Double($0) })
    }

    private var socBadge: AnyView? {
        guard let live = model.liveSoc else { return nil }
        if abs(live - startSoc) < 0.5 { return AnyView(Badge(text: "LIVE", color: TSurface.green)) }
        return AnyView(
            Button { model.simStartSoc = nil } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold))
                    Text("Use car \(Int(live.rounded()))%").font(.app(size: 12, weight: .semibold))
                }
                .foregroundStyle(TeslaDark.labelGrey)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Color(white: 0.19)))
                .overlay(Capsule().strokeBorder(Color(white: 0.3), lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        )
    }

    // MARK: Result

    private func hero(_ r: HomeResult, _ sim: (minutes: Int, daysBefore: Int)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("START CHARGING AT").kerning(0.8)
                Spacer()
                Text("TOTAL COST").kerning(0.8)
            }
            .font(.app(size: 11, weight: .medium))
            .foregroundStyle(TeslaDark.rowLabel)
            .padding(.top, 26)
            .padding(.bottom, 6)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if r.minutes == 0 {
                    Text("—").font(.app(size: 50, weight: .bold))
                } else {
                    let c = splitClock(Fmt.clock(minutes: sim.minutes))
                    Text(c.time).font(.app(size: 50, weight: .bold))
                    Text(c.suffix).font(.app(size: 17, weight: .light)).foregroundStyle(TeslaDark.rowLabel)
                }
                Spacer()
                Text(Fmt.rm(r.cost)).font(.app(size: 32, weight: .bold)).foregroundStyle(TSurface.green)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            .foregroundStyle(.white)

            Text(r.minutes == 0 ? "Pick a target above the start level"
                 : "\(dayLabel(sim)) · full by \(Fmt.clock(minutes: finishMinutes)) · \(Fmt.longDuration(r.minutes))")
                .font(.app(size: 13))
                .foregroundStyle(TeslaDark.rowLabel)
                .lineLimit(1).minimumScaleFactor(0.8)
            if r.minutes > 0 && inPeak(sim.minutes) {
                Label("Starts in TNB peak (2pm–10pm, Mon–Fri)", systemImage: "exclamationmark.triangle")
                    .font(.app(size: 12))
                    .foregroundStyle(Theme.orange)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
    }

    private var finishMinutes: Int { ((leaveMinutes - bufferMinutes) % 1440 + 1440) % 1440 }

    private func dayLabel(_ sim: (minutes: Int, daysBefore: Int)) -> String {
        if sim.daysBefore == 0 { return "Same day" }
        if sim.daysBefore == 1 { return sim.minutes >= 17 * 60 ? "The night before" : "The day before" }
        return "\(sim.daysBefore) days before"
    }

    private func inPeak(_ minutes: Int) -> Bool { minutes >= 14 * 60 && minutes < 22 * 60 }

    private var leaveBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: leaveMinutes / 60, minute: leaveMinutes % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                leaveMinutes = (c.hour ?? 7) * 60 + (c.minute ?? 0)
            }
        )
    }
}

/// Home charging → Charger: finish-early buffer, the charger settings in use, and the detailed numbers.
struct SimChargerPage: View {
    @ObservedObject var model: HomeModel
    let startSoc: Double
    let target: Double
    @Binding var bufferMinutes: Int

    var body: some View {
        let r = SimulateView.result(model, start: startSoc, target: target)
        ScrollView {
            VStack(spacing: 0) {
                TCaption(text: "Timing")
                TRow("Finish early by", icon: "shield", last: true) {
                    HStack(spacing: 10) {
                        TValue(value: "\(bufferMinutes)", unit: "min")
                        TStepper(value: $bufferMinutes, range: 0...60, step: 5)
                    }
                }

                TCaption(text: "Charger")
                TRow("Current", icon: "bolt") { TValue(value: "\(Int(model.amps))", unit: "A") }
                TRow("Voltage") { TValue(value: "\(Int(model.volts))", unit: "V") }
                TRow("Efficiency") { TValue(value: model.efficiency.plain, unit: "%") }
                TRow("Battery capacity", last: true) { TValue(value: model.capacity.plain, unit: "kWh") }

                TCaption(text: "Numbers")
                TRow("Duration") { TValue(value: Fmt.longDuration(r.minutes)) }
                TRow("Added") { TValue(value: "+\(Int(r.deltaPct.rounded()))%", color: TSurface.green) }
                TRow("Into battery") { TValue(value: String(format: "%.1f", r.packKWh), unit: "kWh") }
                TRow("From the wall") { TValue(value: String(format: "%.2f", r.wallKWh), unit: "kWh") }
                TRow("Tariff") { TValue(value: String(format: "%.4f", model.tariff), unit: "RM/kWh") }
                TRow("Cost", last: true) { TValue(value: Fmt.rm(r.cost), color: TSurface.green) }

                Text("Charger settings come from Charging → Charge details. Charging to 100% adds about 25 min for the slow last 1%.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                Spacer(minLength: 40)
            }
        }
        .teslaPage("Charger", black: true)
    }
}
