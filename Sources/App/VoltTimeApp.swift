import SwiftUI

@main
struct VoltTimeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Theme.teal)
        }
    }
}

enum AppTab {
    case myHome, home, publicCharging
}

struct ContentView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var home = HomeModel()
    @StateObject private var myHome = MyHomeModel()
    @State private var tab: AppTab = .myHome
    @State private var showEnergy = false
    @State private var showSettings = false
    @State private var showSimulate = false
    @State private var keyboardUp = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                Group {
                    switch tab {
                    case .myHome: MyHomeView(model: myHome, showEnergy: $showEnergy)
                    case .home: HomeView(model: home, showSettings: $showSettings, showSimulate: $showSimulate)
                    case .publicCharging: PublicView(showSettings: $showSettings)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !keyboardUp {
                BottomBar(tab: $tab) {
                    showSimulate = false
                    showEnergy = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { n in
            let h = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            if h > 120 { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        .preferredColorScheme(tab == .myHome ? .dark : .light)
        .sheet(isPresented: $showSettings, onDismiss: {
            Task {
                await home.refresh()
                await myHome.refresh()
            }
        }) {
            SettingsView(onPhotosCleared: { myHome.reloadPhoto() })
        }
        .sheet(isPresented: $home.showLimitSheet) {
            LimitSheet(model: home)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            // volttime://limit (notification "Others…") or volttime://home
            tab = .home
            showSimulate = false
            showEnergy = false
            if url.host == "limit" {
                showSettings = false
                home.showLimitSheet = true
            }
            Task { await home.refresh() }
        }
        .task { await home.refresh() }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await home.refresh() } }
        }
    }
}

struct BottomBar: View {
    @Binding var tab: AppTab
    var onTap: () -> Void = {}

    /// The My Home page is dark like the Tesla app, so the bar goes dark with it.
    private var dark: Bool { tab == .myHome }

    var body: some View {
        HStack(spacing: 0) {
            item(.myHome, "My Home", "bolt.house.fill")
            item(.home, "Home", "house.fill")
            item(.publicCharging, "Public", "ev.charger.fill")
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(dark ? TeslaDark.bg : Color.white, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Rectangle().fill(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.10)).frame(height: 0.5) }
    }

    private func color(_ t: AppTab) -> Color {
        if dark { return tab == t ? .white : TeslaDark.dim }
        return tab == t ? Theme.teal : Theme.tabInactive
    }

    private func item(_ t: AppTab, _ title: String, _ icon: String) -> some View {
        Button { onTap(); tab = t } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20)).frame(height: 24)
                Text(title).font(.caption2.weight(tab == t ? .bold : .regular))
            }
            .foregroundStyle(color(t))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    var onPhotosCleared: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var photoCount = ScenarioPhotos.savedCount
    @State private var photoBusy = false
    @AppStorage(HAClient.urlKey) private var haURL = ""
    @State private var haToken = ""
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
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
                    Label("GPS = 73%, TSET = 63%, Others = slider here. No answer by 11pm = 73%.", systemImage: "mappin.and.ellipse")
                    Label("Home Assistant sets the car's own one-time charge schedule to the start time and starts it if needed.", systemImage: "clock.badge.checkmark")
                    Label("Only in Routine mode. Change the mode on My Home → Settings.", systemImage: "slider.horizontal.3")
                }
                .font(.footnote)

                Section {
                    LabeledContent("Saved on this iPhone", value: "\(photoCount) of 9")
                    Button {
                        Task { await redownloadPhotos() }
                    } label: {
                        HStack {
                            Text("Download again from Home Assistant")
                            Spacer()
                            if photoBusy { ProgressView() }
                        }
                    }
                    .disabled(photoBusy)
                } header: {
                    Text("My Home photos")
                } footer: {
                    Text("The 9 scenario pictures come from /config/www/tesla_home_scenario1–9.png in Home Assistant. Replaced a picture there? Download again.")
                }

                Section {
                    LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.teal, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Keychain.set(haToken.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.homeAssistant)
                        dismiss()
                    }
                }
            }
            .onAppear { haToken = Keychain.get(Keychain.homeAssistant) ?? "" }
        }
        .preferredColorScheme(.light)
    }

    private func redownloadPhotos() async {
        guard let ha = HAClient.configured() else { return }
        photoBusy = true
        defer { photoBusy = false }
        ScenarioPhotos.clear()
        onPhotosCleared()
        photoCount = await ScenarioPhotos.fetchMissing(ha: ha)
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
