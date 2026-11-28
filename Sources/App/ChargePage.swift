import SwiftUI

/// Opened by tapping the Model 3 figure on My Home: set the charging current (5–32 A) and start / stop charging
/// straight away, without waiting for the Solar Excess automation. That automation still takes over at its next run.
struct ChargePage: View {
    @ObservedObject var model: MyHomeModel
    @Environment(\.scenePhase) private var phase

    @State private var amps: Double = 16
    @State private var editing = false
    @State private var sendingAmps = false
    @State private var wantCharging: Bool?   // start / stop sent, waiting for the car
    @State private var error: String?

    private var charging: Bool { model.charging }
    private var shownCharging: Bool { wantCharging ?? charging }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Model 3")
                    .font(.app(size: 24, weight: .semibold))
                    .kerning(-0.3)
                Text(status)
                    .font(.app(size: 13))
                    .foregroundStyle(charging ? TeslaDark.chargingGreen : TeslaDark.rowLabel)
                    .padding(.bottom, 18)

                battery
                    .padding(.bottom, 18)

                HStack(spacing: 8) {
                    stat("Power", "\(MyHomeModel.kw(model.carW)) kW")
                    stat("Current now", "\(Int((model.currentNow ?? 0).rounded())) A")
                }
                .padding(.bottom, 12)

                ampsCard
                    .padding(.bottom, 16)

                startStopButton

                if let error {
                    Text(error).font(.app(size: 12)).foregroundStyle(TeslaDark.importing)
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .teslaPage("")
        .onAppear { if let a = model.chargeAmps { amps = a } }
        .onChange(of: model.chargeAmps) { _, new in
            // Follow changes made elsewhere (Solar Excess, Controller) unless you're moving the slider.
            if let new, !editing, !sendingAmps { amps = new }
        }
        .onChange(of: model.charging) { _, now in
            if wantCharging == now { wantCharging = nil }
        }
        .task(id: phase) {
            guard phase == .active else { return }
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(nanoseconds: (wantCharging == nil ? 5 : 2) * 1_000_000_000)
            }
        }
    }

    private var status: String {
        if charging { return "Charging" }
        if model.connected { return "Plugged in · Not charging" }
        return "Not plugged in"
    }

    // MARK: Battery

    private var battery: some View {
        let soc = model.soc ?? 0
        let limit = model.chargeLimit ?? 80
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.soc.map { "\(Int($0))%" } ?? "—").font(.app(size: 44, weight: .semibold))
                Text("Limit \(Int(limit))%").font(.app(size: 11)).kerning(0.3).foregroundStyle(TeslaDark.rowLabel)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.17))
                    Capsule().fill(TeslaDark.exporting).frame(width: g.size.width * min(1, soc / 100))
                    Rectangle().fill(Color.white).frame(width: 2, height: 16)
                        .offset(x: g.size.width * min(1, limit / 100) - 1)
                }
            }
            .frame(height: 10)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.app(size: 11)).kerning(0.3).foregroundStyle(TeslaDark.rowLabel)
            Text(value).font(.app(size: 18, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Amps

    private var ampsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Charging current").font(.app(size: 14))
                Spacer()
                if sendingAmps { ProgressView().tint(.white).scaleEffect(0.7) }
                Text("\(Int(amps)) A").font(.app(size: 24, weight: .semibold))
            }
            Slider(value: $amps, in: 5...32, step: 1) { isEditing in
                editing = isEditing
                if !isEditing { Task { await sendAmps(amps) } }
            }
            .tint(.white)
            HStack {
                Text("5 A")
                Spacer()
                Text("32 A")
            }
            .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
            Text("Set right away in the vehicle. The Solar Excess automation may change it at its next run.")
                .font(.app(size: 11)).foregroundStyle(TeslaDark.rowLabel)
                .padding(.top, 4)
        }
        .padding(14)
        .background(TeslaDark.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sendAmps(_ value: Double) async {
        guard let ha = HAClient.configured(), value != model.chargeAmps else { return }
        sendingAmps = true
        defer { sendingAmps = false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        do {
            try await ha.call("number", "set_value", ["entity_id": Entity.chargeCurrent, "value": Int(value)], timeout: 40)
            model.chargeAmps = value
            error = nil
        } catch {
            self.error = "Couldn't set \(Int(value)) A: \(error.localizedDescription)"
            if let a = model.chargeAmps { amps = a }
        }
    }

    // MARK: Start / stop

    private var startStopButton: some View {
        Button {
            Task { await toggleCharging() }
        } label: {
            HStack(spacing: 8) {
                if wantCharging != nil { ProgressView().tint(.white) }
                Text(buttonTitle).font(.app(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(shownCharging ? Color(white: 0.17) : Color(white: 0.27))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!model.connected || wantCharging != nil)
        .opacity(model.connected ? 1 : 0.4)
    }

    private var buttonTitle: String {
        if !model.connected { return "Not plugged in" }
        if let w = wantCharging { return w ? "Starting…" : "Stopping…" }
        return charging ? "Stop charging" : "Start charging"
    }

    private func toggleCharging() async {
        guard let ha = HAClient.configured() else { return }
        let start = !charging
        wantCharging = start
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do {
            try await ha.call("switch", start ? "turn_on" : "turn_off", ["entity_id": Entity.charging], timeout: 40)
            error = nil
            // Give the car up to ~40 s to report it, then stop waiting.
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if wantCharging == nil { return }
                await model.refresh()
                if model.charging == start { wantCharging = nil; return }
            }
            wantCharging = nil
            if model.charging != start {
                error = start ? "The vehicle hasn't started charging yet. Check the charge limit or try again."
                              : "The vehicle hasn't stopped yet. Try again."
            }
        } catch {
            wantCharging = nil
            self.error = "Couldn't \(start ? "start" : "stop") charging: \(error.localizedDescription)"
        }
    }
}
