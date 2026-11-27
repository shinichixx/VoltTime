import SwiftUI

@main
struct VoltTimeApp: App {
    init() {
        BackupReminder.registerDefaults()
        BatteryAlerts.registerDefaults()
        ScenarioPhotos.moveOldFolder()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .font(.app(size: 17))   // Albert Sans for any text without its own font
                .scrollBounceBehavior(.always)   // every page can be dragged and springs back, even when it fits
                .tint(.white)
                .preferredColorScheme(.dark)
        }
    }
}

/// Three pages, swiped left and right: My Car (opens first), My Home and Simulation.
struct ContentView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var home = HomeModel()
    @StateObject private var myHome = MyHomeModel()
    @StateObject private var energy = EnergyStore()
    @StateObject private var car = CarModel()
    @State private var path: [Route] = []
    @State private var page = 0
    @State private var pageID: Int? = 0      // the pager's scroll position (kept in step with `page`)
    @StateObject private var fx = PagerFX()

    /// Page dots centred between the last row of text and the bottom edge of the screen
    /// (35 pt up from the edge: on the iPhone 15 Pro the last line ends 70 pt above it).
    private var pageDots: some View {
        VStack {
            Spacer()
            // 16.5 pt centre to centre, like the iOS page dots (7.5 dot + 2×4 tap padding + 1).
            HStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(page == i ? Color.white : Color(white: 0.45))
                        .frame(width: 7.5, height: 7.5)
                        .padding(4)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation { page = i } }
                }
            }
            .padding(.bottom, 35 - 7.5 / 2 - 4)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    var body: some View {
        NavigationStack(path: $path) {
          ZStack {
            // Behind the pager: the car and the house stay put and cross-fade as you swipe
            // (car gone by half way, house in over the second half), and fade to 8% as their page scrolls.
            TeslaDark.bg.ignoresSafeArea()
            GeometryReader { g in
                let w = g.size.width
                CarScene(car: car.car, meterW: car.isHome ? myHome.liveCarW : nil)
                    .frame(width: w * 1.095)
                    .frame(width: w, height: 215)
                    .clipped()
                    .compositingGroup()
                    .opacity(min(PagerFX.swipe(fx.carX, w), PagerFX.scrolled(fx.carScroll)))
                    .padding(.top, 120)   // clear of the header, with room to fade (build 113)
                    .allowsHitTesting(false)
                MyHomeView(model: myHome, path: $path, layer: .backdrop)
                    .opacity(min(PagerFX.swipe(fx.homeX, w), PagerFX.scrolled(fx.homeScroll)))
                    .allowsHitTesting(false)
            }
            // The pager is a plain paging scroll view drawn over the whole screen (build 63). The page-style
            // TabView it replaces kept its own idea of the home-bar safe area and cut every page ~17 pt short
            // at the bottom (and ~17 pt early at the top). Each page now starts under the status bar by
            // plain padding, and runs to the very bottom edge of the screen.
            GeometryReader { g in
                // Pages start 17 pt above the safe area: every title, line and gap was measured against the
                // Tesla app with the old TabView, which drew its pages 17 pt high. Keeping that offset keeps
                // "Ultra Rouge", "Home IM2 Kuantan" and "Simulation" exactly where they were (build 64).
                let top = (g.safeAreaInsets.top > 0 ? g.safeAreaInsets.top : 59) - 17
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        CarPage(car: car, home: home, myHome: myHome, path: $path, active: page == 0, topInset: top)
                            .pagerPage(top: top)
                            .id(0)
                        MyHomeView(model: myHome, path: $path)
                            .pagerPage(top: top)
                            .id(1)
                        SimulationPage(home: home)
                            .pagerPage(top: top)
                            .id(2)
                    }
                    .scrollTargetLayout()
                    .scrollBounceBehavior(.always)   // the pages' own scroll views keep the app-wide spring
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageID)
                .pagerFX(fx)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)   // the pager itself never moves up or down
                .ignoresSafeArea(.container)
            }
            .onChange(of: pageID) { _, v in
                if let v, v != page { page = v }
            }
            .onChange(of: page) { _, v in
                if v != 2 { home.simStartSoc = nil }   // leaving Simulation: back to LIVE next visit
                if pageID != v { withAnimation(.easeInOut(duration: 0.3)) { pageID = v } }
            }
            // The house's power figures float above the pager (the Model 3 one opens Charging).
            GeometryReader { g in
                MyHomeView(model: myHome, path: $path, layer: .labels)
                    .opacity(min(PagerFX.swipe(fx.homeX, g.size.width), PagerFX.scrolled(fx.homeScroll)))
                    .allowsHitTesting(page == 1 && fx.homeScroll < 20 && PagerFX.swipe(fx.homeX, g.size.width) > 0.9)
            }
          }
            .environmentObject(fx)
            .overlay { pageDots }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .energy: EnergyView(store: energy)
                case .energyView(let c): EnergyView(store: energy, start: c)
                case .settings: SettingsPage(home: home, myHome: myHome, energy: energy, car: car, path: $path)
                case .chargeDetails: ChargeDetailsPage(model: home)
                case .homeAssistant: HomeAssistantPage()
                case .charge: ChargePage(model: myHome)
                case .impact: ImpactView(model: energy, home: myHome)
                case .menu: MenuPage(car: car, energy: energy, home: home) { i in
                    // My Products: put the pager on that page at once, behind the menu, then close the
                    // menu, so no sliding across the other pages is ever seen (build 100).
                    var instant = Transaction()
                    instant.disablesAnimations = true
                    withTransaction(instant) {
                        pageID = i
                        page = i
                        // Older iOS only (iOS 18+ follows the pager's own offset): set the two photos by hand.
                        if !fx.pagerDriven {
                            fx.carX = i == 0 ? 0 : 10_000
                            fx.homeX = i == 1 ? 0 : nil
                        }
                    }
                    DispatchQueue.main.async { path.removeAll() }
                }
                case .carDetail(let d): CarDetailPage(model: car, detail: d)
                }
            }
        }
        .overlay {
            // Tonight's question, if it's still open (Sat–Wed 7–10 pm, plugged in, Routine, not answered).
            if home.shouldAsk && !home.showLimitSheet {
                AskCard(model: home)
                    .transition(.opacity)
            }
        }
        // One banner for the whole app, laid out inside the safe area so the status bar and
        // Dynamic Island never cover it (car pages draw edge to edge underneath).
        .banner(car.toast ?? home.toast) {
            if car.toast != nil { car.dismissBanner() } else { home.toast = nil }
        }
        .overlay { TimescaleOverlay() }   // the Timescale picker panel, over every page
        .animation(.easeInOut(duration: 0.25), value: home.shouldAsk)
        .sheet(isPresented: $home.showLimitSheet) {
            LimitSheet(model: home)
                .presentationDetents([.height(450)])
                .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            // volttime://limit (notification "Others…") or volttime://home -> My Home → Charging
            page = 1   // My Home behind Charging
            path = [.settings]
            if url.host == "limit" { home.showLimitSheet = true }
            Task { await home.refresh() }
        }
        .task {
            S3XYLink.shared.context = { [weak c = car] in (c?.car.soc, !(c?.driving ?? false)) }
            S3XYLink.shared.start()   // cell balance from the S3XY Commander while TesLah is open
            await home.refresh()
            await energy.refresh()   // tops up the saved energy so Impact / Energy open instantly
            await VehicleHistory.shared.refreshToday()   // today's Charge Level and the latest charge limit
            await Task.detached(priority: .utility) { Snapshots.takeDailyIfNeeded() }.value
            await BackupReminder.apply()
        }
        .onChange(of: phase) { old, p in
            if p == .background { S3XYLink.shared.stop() }
            guard p == .active else { return }
            Task { await HARoute.shared.reset() }
            S3XYLink.shared.start()
            Task { await home.refresh() }
            if old == .background {   // opened again from the background: top up, and the day's local copy
                Task {
                    await energy.refresh()
                    await VehicleHistory.shared.refreshToday()
                    await Task.detached(priority: .utility) { Snapshots.takeDailyIfNeeded() }.value
                }
            }
        }
    }
}

struct HomeAssistantPage: View {
    @AppStorage(HAClient.urlKey) private var haURL = ""
    @AppStorage(HARoute.homeKey) private var homeURL = HARoute.defaultHome
    @AppStorage(HARoute.autoKey) private var autoSwitch = true
    @State private var homeOK: Bool?
    @State private var awayOK: Bool?
    @State private var usingHome: Bool?
    @State private var haToken = ""
    @State private var testResult: String?
    @State private var connected: Bool?
    @State private var checkedAt: Date?
    @State private var testing = false
    @State private var editingToken = false
    @FocusState private var focus: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                status
                    .padding(.top, 20)

                TCaption(text: "Connection")
                addressRow("Home Wi-Fi", icon: "wifi", text: $homeURL, prompt: "192.168.x.x:8123", key: "home",
                           note: usingHome == true ? "In use right now" : "Tried first", active: usingHome == true)
                addressRow("Tailscale", icon: "globe", text: $haURL, prompt: "100.x.x.x:8123", key: "url",
                           note: usingHome == false ? "In use right now" : "When home doesn't answer", active: usingHome == false)
                TRow("Token", icon: "key") {
                    Group {
                        if editingToken || haToken.isEmpty {
                            SecureField("Long-lived token", text: $haToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .focused($focus, equals: "token")
                        } else {
                            Button { editingToken = true; focus = "token" } label: {
                                HStack(spacing: 5) {
                                    Text("••••••••••").foregroundStyle(.white)
                                    Text("saved").foregroundStyle(TeslaDark.rowLabel)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.app(size: 14))
                    .frame(width: 190, alignment: .trailing)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                TRow("Switch automatically", icon: "arrow.left.arrow.right", subtitle: "Home first, then Tailscale", last: true) {
                    Toggle("", isOn: $autoSwitch).labelsHidden().tint(TSurface.green)
                }

                Button {
                    focus = nil
                    editingToken = false
                    Keychain.set(haToken.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.homeAssistant)
                    Task { await test() }
                } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text("Save & test both").font(.app(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 12).fill(TSurface.selected))
                }
                .buttonStyle(.plain)
                .disabled(testing)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                if let testResult {
                    Text(testResult)
                        .font(.app(size: 12))
                        .foregroundStyle(connected == true ? TSurface.green : Theme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                Text("Same address and token as Fleetly. Create a token in Home Assistant → your profile → Security → Long-lived access tokens. Kept in the iPhone Keychain.")
                    .font(.app(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if homeOK != nil || awayOK != nil {
                    TCaption(text: "Last test")
                    resultRow("Home Wi-Fi", homeOK)
                    resultRow("Tailscale", awayOK, last: true)
                }

                Spacer(minLength: 40)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .teslaPage("Home Assistant", black: true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onAppear { haToken = Keychain.get(Keychain.homeAssistant) ?? "" }
        .onDisappear { Keychain.set(haToken.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.homeAssistant) }
        .task { if !(haURL.isEmpty && homeURL.isEmpty) && !haToken.isEmpty { await test(quiet: true) } }
        .onChange(of: autoSwitch) { _, _ in Task { await test(quiet: true) } }
    }

    private var status: some View {
        VStack(spacing: 6) {
            Image(systemName: "house")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(TSurface.icon)
            Text(connected == nil ? (testing ? "Checking…" : "Not checked") : (connected == true ? "Connected" : "Can't reach Home Assistant"))
                .font(.app(size: 20, weight: .semibold))
                .foregroundStyle(connected == false ? Theme.orange : .white)
            if let checkedAt {
                HStack(spacing: 5) {
                    Circle().fill(connected == true ? TSurface.green : Theme.orange).frame(width: 6, height: 6)
                    Text("\(usingHome.map { $0 ? "Using Home Wi-Fi · " : "Using Tailscale · " } ?? "")Checked at \(checkedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.app(size: 12))
                .foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func addressRow(_ title: String, icon: String, text: Binding<String>, prompt: String, key: String,
                            note: String, active: Bool) -> some View {
        TRow(title, icon: icon, subtitle: note, dot: active ? TSurface.green : nil) {
            TextField(prompt, text: text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .font(.app(size: 13))
                .foregroundStyle(.white)
                .frame(width: 180)
                .focused($focus, equals: key)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
        }
    }

    private func resultRow(_ title: String, _ ok: Bool?, last: Bool = false) -> some View {
        TRow(title, last: last) {
            Text(ok == nil ? "Not set" : (ok == true ? "Reachable" : "Not reachable"))
                .font(.app(size: 13))
                .foregroundStyle(ok == true ? TSurface.green : (ok == false ? Theme.orange : TeslaDark.rowLabel))
        }
    }

    /// nil = no address entered; otherwise whether it answered and accepted the token.
    private func check(_ address: String, probeFirst: Bool) async -> (ok: Bool, error: String?)? {
        guard let ha = HAClient(urlString: address, token: haToken) else { return nil }
        if probeFirst, !(await HARoute.looksLikeHomeAssistant(ha.baseURL)) {
            return (false, "The home address didn't answer.")
        }
        do {
            _ = try await ha.ping()
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    private func test(quiet: Bool = false) async {
        if haToken.isEmpty || (haURL.isEmpty && homeURL.isEmpty) {
            if !quiet { testResult = "Enter an address and the token." }
            connected = nil
            return
        }
        testing = true
        defer { testing = false; checkedAt = Date() }
        await HARoute.shared.reset()
        async let h = check(homeURL, probeFirst: true)
        async let a = check(haURL, probeFirst: false)
        let (home, away) = await (h, a)
        homeOK = home?.ok
        awayOK = away?.ok
        // What the app itself will use, with the current switch setting.
        usingHome = nil
        guard let ha = HAClient.configured() else {
            connected = nil
            testResult = "Enter the Tailscale address too."
            return
        }
        let base = await ha.currentBase()
        let isHome = base == HAClient.url(from: homeURL)
        connected = (isHome ? home?.ok : away?.ok) == true
        if connected == true {
            usingHome = isHome
            let helpers = try? await ha.state(Entity.readyTime)
            testResult = helpers == nil
                ? "Connected, but the VoltTime package isn't installed in Home Assistant yet."
                : (quiet ? nil : "Connected – VoltTime package found.")
        } else {
            testResult = (isHome ? home?.error : away?.error) ?? "Can't reach Home Assistant."
        }
    }
}

private extension View {
    /// One page of the pager: exactly one screen wide and tall, laid out from just under the status bar
    /// down to the very bottom edge of the screen (under the home bar).
    func pagerPage(top: CGFloat) -> some View {
        padding(.top, top)
            .containerRelativeFrame([.horizontal, .vertical], alignment: .top)
    }
}
