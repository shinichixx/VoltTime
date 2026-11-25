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
                CarScene(car: car.car)
                    .frame(width: w * 0.92)
                    .frame(width: w, height: 180)
                    .clipped()
                    .compositingGroup()
                    .opacity(min(PagerFX.swipe(fx.carX, w), PagerFX.scrolled(fx.carScroll)))
                    .padding(.top, 82)   // 10 pt closer to the status line (build 58)
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
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)   // the pager itself never moves up or down
                .ignoresSafeArea(.container)
            }
            .onChange(of: pageID) { _, v in
                if let v, v != page { page = v }
            }
            .onChange(of: page) { _, v in
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
                case .settings: SettingsPage(home: home, myHome: myHome, energy: energy, car: car, path: $path)
                case .chargeDetails: ChargeDetailsPage(model: home)
                case .homeAssistant: HomeAssistantPage()
                case .charge: ChargePage(model: myHome)
                case .impact: ImpactView(model: energy, home: myHome)
                case .carSettings: CarSettingsPage(car: car, energy: energy, home: home)
                case .homeSettings: HomeSettingsPage(home: home, energy: energy)
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
            await Task.detached(priority: .utility) { Snapshots.takeDailyIfNeeded() }.value
            await BackupReminder.apply()
        }
        .onChange(of: phase) { old, p in
            if p == .background { S3XYLink.shared.stop() }
            guard p == .active else { return }
            S3XYLink.shared.start()
            Task { await home.refresh() }
            if old == .background {   // opened again from the background: top up, and the day's local copy
                Task {
                    await energy.refresh()
                    await Task.detached(priority: .utility) { Snapshots.takeDailyIfNeeded() }.value
                }
            }
        }
    }
}

struct HomeAssistantPage: View {
    @AppStorage(HAClient.urlKey) private var haURL = ""
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
                TRow("Address", icon: "link") {
                    TextField("100.x.x.x:8123", text: $haURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .font(.app(size: 14))
                        .foregroundStyle(.white)
                        .frame(width: 190)
                        .focused($focus, equals: "url")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(TSurface.field))
                }
                TRow("Token", icon: "key", last: true) {
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

                Button {
                    focus = nil
                    editingToken = false
                    Keychain.set(haToken.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.homeAssistant)
                    Task { await test() }
                } label: {
                    HStack(spacing: 8) {
                        if testing { ProgressView().tint(.white).scaleEffect(0.8) }
                        Text("Save & test connection").font(.app(size: 15, weight: .medium))
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

                TCaption(text: "How tonight's charge works")
                howRow("bell", "Plug in after 7pm, Sat–Wed", "You're asked where you're going tomorrow")
                howRow("mappin.and.ellipse", "GPS 73% · TSET 63% · Others", "No answer by 10pm means GPS 73%")
                howRow("clock", "The car's schedule is set for you", "Starts at the planned time, never before 10:15pm")
                howRow("slider.horizontal.3", "Routine mode only", "Change it on the Charging page", last: true)

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
        .task { if !haURL.isEmpty && !haToken.isEmpty { await test(quiet: true) } }
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
                    Text("Checked at \(checkedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.app(size: 12))
                .foregroundStyle(TeslaDark.rowLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func howRow(_ icon: String, _ title: String, _ detail: String, last: Bool = false) -> some View {
        TRow(title, icon: icon, subtitle: detail, last: last) { EmptyView() }
    }

    private func test(quiet: Bool = false) async {
        guard let ha = HAClient(urlString: haURL, token: haToken) else {
            if !quiet { testResult = "Enter both the address and the token." }
            connected = nil
            return
        }
        testing = true
        defer { testing = false; checkedAt = Date() }
        do {
            _ = try await ha.ping()
            connected = true
            let helpers = try? await ha.state(Entity.readyTime)
            testResult = helpers == nil
                ? "Connected, but the VoltTime package isn't installed in Home Assistant yet."
                : (quiet ? nil : "Connected – VoltTime package found.")
        } catch {
            connected = false
            testResult = error.localizedDescription
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
