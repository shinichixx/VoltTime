import SwiftUI

@main
struct VoltTimeApp: App {
    init() {
        BackupReminder.registerDefaults()
        ScenarioPhotos.moveOldFolder()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
            TabView(selection: $page) {
                CarPage(car: car, home: home, path: $path, active: page == 0)
                    .tag(0)
                MyHomeView(model: myHome, path: $path)
                    .tag(1)
                SimulationPage(home: home)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)
            .background(TeslaDark.bg.ignoresSafeArea())
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
        .banner(home.toast) { home.toast = nil }
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
            await home.refresh()
            await energy.refresh()   // tops up the saved energy so Impact / Energy open instantly
            await Task.detached(priority: .utility) { Snapshots.takeDailyIfNeeded() }.value
            await BackupReminder.apply()
        }
        .onChange(of: phase) { old, p in
            guard p == .active else { return }
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
                        .font(.system(size: 14))
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
                    .font(.system(size: 14))
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
                        Text("Save & test connection").font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 12))
                        .foregroundStyle(connected == true ? TSurface.green : Theme.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                Text("Same address and token as Fleetly. Create a token in Home Assistant → your profile → Security → Long-lived access tokens. Kept in the iPhone Keychain.")
                    .font(.system(size: 11)).foregroundStyle(TeslaDark.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                TCaption(text: "How tonight's charge works")
                howRow("bell", "Plug in after 7pm, Sat–Wed", "You're asked where you're going tomorrow")
                howRow("mappin.and.ellipse", "GPS 73% · TSET 63% · Others", "No answer by 10pm means GPS 73%")
                howRow("clock", "The car's schedule is set for you", "Starts at the planned time, never before 10:15pm")
                howRow("slider.horizontal.3", "Routine mode only", "Change it on the Charging page", last: true)

                TCaption(text: "About")
                TRow("Version", icon: "info.circle", last: true) {
                    Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                        .font(.system(size: 14)).foregroundStyle(TeslaDark.rowLabel)
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
        .task { if !haURL.isEmpty && !haToken.isEmpty { await test(quiet: true) } }
    }

    private var status: some View {
        VStack(spacing: 6) {
            Image(systemName: "house")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(TSurface.icon)
            Text(connected == nil ? (testing ? "Checking…" : "Not checked") : (connected == true ? "Connected" : "Can't reach Home Assistant"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(connected == false ? Theme.orange : .white)
            if let checkedAt {
                HStack(spacing: 5) {
                    Circle().fill(connected == true ? TSurface.green : Theme.orange).frame(width: 6, height: 6)
                    Text("Checked at \(checkedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.system(size: 12))
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
