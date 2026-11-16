import SwiftUI

/// What-if calculator: "if I want X % by the time I leave, when does charging have to start?"
/// Uses the charger settings from Charge details. Nothing here is sent to the car or Home Assistant.
struct SimulateView: View {
    @ObservedObject var model: HomeModel
    @AppStorage("sim.leave") private var leaveMinutes = 7 * 60
    @AppStorage("sim.target") private var target = 100.0
    @AppStorage("sim.buffer") private var bufferMinutes = 15
    @State private var startSoc = 20.0
    @State private var seeded = false

    private static let targets = [63, 73, 80, 90, 100]

    private var result: HomeResult {
        HomeMath.calculate(HomeInputs(startSoc: startSoc, endSoc: target, amps: model.amps, volts: model.volts,
                                      efficiencyPct: model.efficiency, capacityKWh: model.capacity, tariff: model.tariff))
    }

    var body: some View {
        let r = result
        let sim = HomeMath.simulatedStart(leaveMinutes: leaveMinutes, chargeMinutes: r.minutes, bufferMinutes: bufferMinutes)
        ScrollView {
            VStack(spacing: 0) {
                hero(r, sim)
                whatIf
                TCaption(text: "Cost")
                TRow("Estimated cost", icon: "banknote",
                     subtitle: String(format: "%.2f kWh from the wall · RM %.4f/kWh", r.wallKWh, model.tariff), last: true) {
                    TValue(value: Fmt.rm(r.cost), color: TSurface.green, size: 22)
                }
                Text("Uses the charger settings from Settings → Charge details (\(Int(model.amps))A · \(Int(model.volts))V · \(model.efficiency.plain)% · \(model.capacity.plain) kWh). Charging to 100% adds about 25 min for the slow last 1%.")
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }
            .padding(.bottom, 90)   // room to scroll the last row above the page dots
        }
        .background(TSurface.page)
        .onAppear {
            if !seeded {
                startSoc = min(99, (model.liveSoc ?? model.startSoc).rounded())
                seeded = true
            }
        }
    }

    // MARK: Result

    private func hero(_ r: HomeResult, _ sim: (minutes: Int, daysBefore: Int)) -> some View {
        VStack(spacing: 0) {
            TCaption(text: "Start charging at", trailing: r.minutes > 0 ? dayLabel(sim) : "")
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if r.minutes == 0 {
                    Text("—").font(.system(size: 54, weight: .thin))
                    Text("Target must be above the start level").font(.system(size: 13)).foregroundStyle(TeslaDark.rowLabel)
                } else {
                    let c = splitClock(Fmt.clock(minutes: sim.minutes))
                    Text(c.time).font(.system(size: 54, weight: .thin))
                    Text(c.suffix).font(.system(size: 17, weight: .light)).foregroundStyle(TeslaDark.rowLabel)
                }
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)

            TStats(items: [
                TStat(value: Fmt.longDuration(r.minutes), caption: "Duration"),
                TStat(value: "+\(Int(r.deltaPct.rounded()))%", caption: "\(Int(startSoc))% → \(Int(target))%", color: TSurface.green),
                TStat(value: String(format: "%.1f", r.packKWh), unit: "kWh", caption: "Into battery"),
            ])
            .padding(.bottom, 16)

            if r.minutes > 0 {
                TRow("Full by \(Fmt.clock(minutes: finishMinutes))", icon: "flag.checkered", last: !inPeak(sim.minutes)) {
                    Text(bufferMinutes > 0 ? "\(bufferMinutes) min before you leave" : "right as you leave")
                        .font(.system(size: 12)).foregroundStyle(TeslaDark.rowLabel)
                }
                if inPeak(sim.minutes) {
                    TRow("Starts in TNB peak", icon: "exclamationmark.triangle", subtitle: "2pm–10pm, Mon–Fri", last: true) { EmptyView() }
                        .foregroundStyle(Theme.orange)
                }
            }
        }
    }

    private var finishMinutes: Int { ((leaveMinutes - bufferMinutes) % 1440 + 1440) % 1440 }

    private func dayLabel(_ sim: (minutes: Int, daysBefore: Int)) -> String {
        if sim.daysBefore == 0 { return "Same day" }
        if sim.daysBefore == 1 { return sim.minutes >= 17 * 60 ? "The night before" : "The day before" }
        return "\(sim.daysBefore) days before"
    }

    private func inPeak(_ minutes: Int) -> Bool { minutes >= 14 * 60 && minutes < 22 * 60 }

    // MARK: What if

    private var whatIf: some View {
        VStack(spacing: 0) {
            TCaption(text: "What if", trailing: "Not applied")
            TRow("I leave at", icon: "clock") {
                DatePicker("", selection: leaveBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            TRow("Finish early by", icon: "shield") {
                HStack(spacing: 10) {
                    TValue(value: "\(bufferMinutes)", unit: "min")
                    TStepper(value: $bufferMinutes, range: 0...60, step: 5)
                }
            }
            TRow("Start charge", icon: "battery.25percent", badge: socBadge) {
                TValue(value: "\(Int(startSoc))%")
            } below: {
                Slider(value: $startSoc, in: 0...99, step: 1).tint(.white)
            }
            TRow("Charge up to", icon: "battery.100percent", last: true) {
                TValue(value: "\(Int(target))%")
            } below: {
                VStack(spacing: 12) {
                    Slider(value: $target, in: 1...100, step: 1).tint(.white)
                    TSegment(items: Self.targets.map { "\($0)%" }, selected: Self.targets.firstIndex(of: Int(target))) {
                        target = Double(Self.targets[$0])
                    }
                }
            }
        }
    }

    private var socBadge: AnyView? {
        guard let live = model.liveSoc else { return nil }
        if abs(live - startSoc) < 0.5 { return AnyView(Badge(text: "LIVE", color: TSurface.green)) }
        return AnyView(
            Button("Use car \(Int(live.rounded()))%") { startSoc = min(99, live.rounded()) }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.teal)
                .buttonStyle(.plain)
        )
    }

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
