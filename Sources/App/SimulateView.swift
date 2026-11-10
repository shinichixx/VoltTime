import SwiftUI

/// What-if calculator: "if I want X % by the time I leave, when does charging have to start?"
/// Uses the charger settings from the Home tab. Nothing here is sent to the car or Home Assistant.
struct SimulateView: View {
    @ObservedObject var model: HomeModel
    let onBack: () -> Void
    @AppStorage("sim.leave") private var leaveMinutes = 7 * 60
    @AppStorage("sim.target") private var target = 100.0
    @AppStorage("sim.buffer") private var bufferMinutes = 15
    @State private var startSoc = 20.0
    @State private var seeded = false

    private var result: HomeResult {
        HomeMath.calculate(HomeInputs(startSoc: startSoc, endSoc: target, amps: model.amps, volts: model.volts,
                                      efficiencyPct: model.efficiency, capacityKWh: model.capacity, tariff: model.tariff))
    }

    var body: some View {
        let r = result
        let sim = HomeMath.simulatedStart(leaveMinutes: leaveMinutes, chargeMinutes: r.minutes, bufferMinutes: bufferMinutes)
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    resultCard(r, sim)
                    inputCard(r)
                    costCard(r)
                    Text("Uses the charger settings from the Home tab (\(Int(model.amps))A · \(Int(model.volts))V · \(model.efficiency.plain)% · \(model.capacity.plain) kWh). The last few percent up to 100% charge slower than this estimate, so keep some buffer when the target is 100%.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
        }
        .onAppear {
            if !seeded {
                startSoc = min(99, (model.liveSoc ?? model.startSoc).rounded())
                seeded = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                    Text("Home").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.22))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("Simulation").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("Nothing is sent to the car").font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.purple.ignoresSafeArea(edges: .top))
    }

    // MARK: Result

    private func resultCard(_ r: HomeResult, _ sim: (minutes: Int, daysBefore: Int)) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("START CHARGING AT").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.purple).kerning(0.6)
                    Text(r.minutes == 0 ? "—" : Fmt.clock(minutes: sim.minutes))
                        .font(.system(size: 40, weight: .heavy)).foregroundStyle(.primary)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    HStack(spacing: 8) {
                        if r.minutes > 0 { Badge(text: dayLabel(sim), color: Theme.purple) }
                        Text(summary(r)).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Figure(label: "Duration", value: Fmt.longDuration(r.minutes))
                    Figure(label: "Added", value: "+\(Int(r.deltaPct.rounded()))%", color: Theme.purple)
                    Figure(label: "Energy", value: String(format: "%.1f kWh", r.packKWh))
                }
                if r.minutes > 0 {
                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: "flag.checkered").foregroundStyle(Theme.green)
                        Text("Full by \(Fmt.clock(minutes: finishMinutes))").font(.system(size: 12, weight: .semibold))
                        Text(bufferMinutes > 0 ? "\(bufferMinutes) min before you leave" : "right as you leave")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    if inPeak(sim.minutes) {
                        Label("This start falls in the TNB peak window (2pm–10pm, Mon–Fri).", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange)
                    }
                }
            }
        }
    }

    private var finishMinutes: Int { ((leaveMinutes - bufferMinutes) % 1440 + 1440) % 1440 }

    private func summary(_ r: HomeResult) -> String {
        if r.minutes == 0 { return "Target must be above the start level" }
        return "\(Int(startSoc))% → \(Int(target))% · leave at \(Fmt.clock(minutes: leaveMinutes))"
    }

    private func dayLabel(_ sim: (minutes: Int, daysBefore: Int)) -> String {
        if sim.daysBefore == 0 { return "Same day" }
        if sim.daysBefore == 1 { return sim.minutes >= 17 * 60 ? "The night before" : "The day before" }
        return "\(sim.daysBefore) days before"
    }

    private func inPeak(_ minutes: Int) -> Bool { minutes >= 14 * 60 && minutes < 22 * 60 }

    // MARK: Inputs

    private func inputCard(_ r: HomeResult) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardTitle(icon: "slider.horizontal.3", title: "What if…", color: Theme.purple, trailing: "Not applied")
                HStack {
                    Text("I leave at").font(.system(size: 13))
                    Spacer()
                    DatePicker("", selection: leaveBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Stepper(value: $bufferMinutes, in: 0...60, step: 5) {
                    HStack {
                        Text("Finish early by").font(.system(size: 13))
                        Spacer()
                        Text("\(bufferMinutes) min").font(.system(size: 13, weight: .semibold))
                    }
                }
                Divider()
                VStack(spacing: 4) {
                    HStack {
                        Text("Start state of charge").font(.system(size: 13))
                        if let live = model.liveSoc {
                            if abs(live - startSoc) < 0.5 { Badge(text: "LIVE", color: Theme.green) }
                            else {
                                Button("Use car \(Int(live.rounded()))%") { startSoc = min(99, live.rounded()) }
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.purple)
                            }
                        }
                        Spacer()
                        Text("\(Int(startSoc))%").font(.system(size: 15, weight: .bold))
                    }
                    Slider(value: $startSoc, in: 0...99, step: 1).tint(Theme.purple)
                }
                VStack(spacing: 6) {
                    HStack {
                        Text("Charge up to").font(.system(size: 13))
                        Spacer()
                        Text("\(Int(target))%").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.purple)
                    }
                    Slider(value: $target, in: 1...100, step: 1).tint(Theme.purple)
                    HStack(spacing: 6) {
                        ForEach([63, 73, 80, 90, 100], id: \.self) { p in
                            Button { target = Double(p) } label: {
                                Text("\(p)%").font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                                    .foregroundStyle(Int(target) == p ? .white : Theme.purple)
                                    .background(Int(target) == p ? Theme.purple : Theme.purple.opacity(0.10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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

    // MARK: Cost

    private func costCard(_ r: HomeResult) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Estimated cost").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                    Text(String(format: "%.2f kWh from the wall · RM %.4f / kWh", r.wallKWh, model.tariff))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Fmt.rm(r.cost)).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.green)
            }
        }
    }
}
