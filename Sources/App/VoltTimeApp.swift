import SwiftUI

@main
struct VoltTimeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.white)
                .preferredColorScheme(.dark)
        }
    }
}

/// Two pages, swiped left and right: My Home and Simulation. Everything else is pushed from My Home.
struct ContentView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var home = HomeModel()
    @StateObject private var myHome = MyHomeModel()
    @StateObject private var energy = EnergyStore()
    @State private var path: [Route] = []
    @State private var page = 0

    /// Page dots centred between the last row of text and the bottom edge of the screen
    /// (35 pt up from the edge: on the iPhone 15 Pro the last line ends 70 pt above it).
    private var pageDots: some View {
        VStack {
            Spacer()
            // 16.5 pt centre to centre, like the iOS page dots (7.5 dot + 2×4 tap padding + 1).
            HStack(spacing: 1) {
                ForEach(0..<2, id: \.self) { i in
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
            TabView(selection: $page) {
                MyHomeView(model: myHome, path: $path)
                    .modifier(FadeWhenLeaving(isCurrent: page == 0))
                    .tag(0)
                SimulationPage(home: home)
                    .modifier(FadeWhenLeaving(isCurrent: page == 1))
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)
            .background(TeslaDark.bg.ignoresSafeArea())
            .overlay { pageDots }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .energy: EnergyView(store: energy)
                case .settings: SettingsPage(home: home, myHome: myHome, path: $path)
                case .chargeDetails: ChargeDetailsPage(model: home)
                case .homeAssistant: HomeAssistantPage()
                case .charge: ChargePage(model: myHome)
                case .impact: ImpactView(model: energy, home: myHome)
                }
            }
        }
        .overlay {
            // Tonight's question, if it's still open (Sat–Wed 7–11 pm, plugged in, Routine, not answered).
            if home.shouldAsk && !home.showLimitSheet {
                AskCard(model: home)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let t = home.toast {
                Text(t)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(Color(white: 0.17))
                    .clipShape(Capsule())
                    .padding(.bottom, 60)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: home.shouldAsk)
        .animation(.easeInOut(duration: 0.25), value: home.toast)
        .sheet(isPresented: $home.showLimitSheet) {
            LimitSheet(model: home)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            // volttime://limit (notification "Others…") or volttime://home -> My Home → Settings
            page = 0
            path = [.settings]
            if url.host == "limit" { home.showLimitSheet = true }
            Task { await home.refresh() }
        }
        .task {
            await home.refresh()
            await energy.refresh()   // tops up the saved energy so Impact / Energy open instantly
        }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await home.refresh() } }
        }
    }
}

struct HomeAssistantPage: View {
    @AppStorage(HAClient.urlKey) private var haURL = ""
    @State private var haToken = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
            Form {
                Section {
                    TextField("http://100.x.x.x:8123", text: $haURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Long-lived access token", text: $haToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Keychain.set(haToken.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.homeAssistant)
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Save & test connection")
                            Spacer()
                            if testing { ProgressView() }
                        }
                    }
                    if let testResult {
                        Text(testResult).font(.footnote).foregroundStyle(testResult.hasPrefix("✓") ? Theme.green : Theme.rouge)
                    }
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text("Same URL and token as Fleetly. Create a token in Home Assistant → your profile → Security → Long-lived access tokens. The token is kept in the iPhone Keychain.")
                }

                Section("How tonight's charge works") {
                    Label("Sat–Wed nights from 7pm, plugging in asks where you're going tomorrow.", systemImage: "bell.badge")
                    Label("GPS = 73%, TSET = 63%, Others = slider. No answer by 11pm = 73%.", systemImage: "mappin.and.ellipse")
                    Label("Home Assistant sets the car's own one-time charge schedule to the start time and starts it if needed.", systemImage: "clock.badge.checkmark")
                    Label("Only in Routine mode (Settings → Charging mode).", systemImage: "slider.horizontal.3")
                }
                .font(.footnote)


                Section {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                }
            }
            .scrollContentBackground(.hidden)
            .teslaPage("Home Assistant")
            .onAppear { haToken = Keychain.get(Keychain.homeAssistant) ?? "" }
            .onDisappear { Keychain.set(haToken.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.homeAssistant) }
    }

    private func test() async {
        guard let ha = HAClient(urlString: haURL, token: haToken) else {
            testResult = "Enter both the URL and the token."
            return
        }
        testing = true
        defer { testing = false }
        do {
            _ = try await ha.ping()
            let helpers = try? await ha.state(Entity.readyTime)
            testResult = helpers == nil
                ? "✓ Connected, but the VoltTime package isn't installed in Home Assistant yet."
                : "✓ Connected – VoltTime package found."
        } catch {
            testResult = error.localizedDescription
        }
    }
}

/// Pages slide as normal; the page you're leaving fades out as it slides away, the page coming in stays solid.
struct FadeWhenLeaving: ViewModifier {
    let isCurrent: Bool

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let minX = geo.frame(in: .global).minX
            let w = max(geo.size.width, 1)
            content
                .opacity(isCurrent ? Double(max(0, 1 - abs(minX) / w)) : 1)
        }
    }
}
