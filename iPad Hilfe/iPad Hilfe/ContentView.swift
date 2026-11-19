import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject var appState = AppState()
    @State private var selectedTab: String? = "newChat"
    @State private var studentChats: [ChatRecord] = []
    @State private var allAdminChats: [ChatRecord] = []
    @State private var pendingSignOutRecheck = false
    
    // Timer für die automatische 5-Sekunden-Synchronisation
    @State private var syncTimer: Timer? = nil

    var body: some View {
        if !appState.isRegistered {
            StudentOnboardingView(appState: appState)
        } else {
            NavigationSplitView {
                List(selection: $selectedTab) {
                    
                    // ==========================================
                    // 1. ANSICHT FÜR SCHÜLER / LEHRER (isSupporter == false)
                    // ==========================================
                    if !appState.isSupporter {
                        Section("Support") {
                            NavigationLink(value: "newChat") {
                                Label("Neues Problem", systemImage: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Section("Meine Tickets") {
                            ForEach(studentChats) { chat in
                                NavigationLink(value: chat.id) {
                                    HStack {
                                        Image(systemName: chat.isOpen ? "bubble.left.and.bubble.right.fill" : "checkmark.circle.fill")
                                            .foregroundColor(chat.isOpen ? .blue : .gray)
                                        Text(chat.title).lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                    
                    // ==========================================
                    // 2. ANSICHT FÜR ADMINS / SUPPORTER (isSupporter == true)
                    // ==========================================
                    if appState.isSupporter {
                        Section("Offene Support Chats") {
                            ForEach(allAdminChats) { chat in
                                NavigationLink(value: chat.id) {
                                    HStack {
                                        Image(systemName: chat.isOpen ? "tray.full.fill" : "archivebox.fill")
                                            .foregroundColor(chat.isOpen ? .purple : .gray)
                                        VStack(alignment: .leading) {
                                            Text(chat.title).lineLimit(1)
                                            Text(chat.studentName).font(.caption2).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        
                        Section("Verwaltung") {
                            NavigationLink(value: "userManagement") {
                                Label("Nutzerverwaltung", systemImage: "person.3.fill")
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    
                    // ==========================================
                    // 3. GEMEINSAME TABS
                    // ==========================================
                    Section("Einstellungen") {
                        NavigationLink(value: "profile") {
                            Label(appState.isSupporter ? "Profil (Supporter)" : "Profil", systemImage: "person.crop.circle")
                        }
                    }
                    
                    if appState.showDebugTab {
                        Section("Entwickler") {
                            NavigationLink(value: "debug") {
                                Label("Debug Console", systemImage: "ladybug.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle(appState.isSupporter ? "Admin Panel" : "Support Hub")
            } detail: {
                if selectedTab == "newChat" && !appState.isSupporter {
                    NewChatView(appState: appState, onCreated: performSync)
                } else if selectedTab == "profile" {
                    ProfileView(appState: appState)
                } else if selectedTab == "userManagement" && appState.isSupporter {
                    UserManagementView(appState: appState)
                } else if selectedTab == "debug" {
                    DebugView(appState: appState)
                } else if let chatId = selectedTab {
                    if appState.isSupporter, let chat = allAdminChats.first(where: { $0.id == chatId }) {
                        AdminChatWrapperView(chat: chat, appState: appState, onUpdate: performSync)
                    } else if !appState.isSupporter {
                        ChatDetailView(chatId: chatId, senderName: appState.userName, appState: appState)
                    } else {
                        ContentUnavailableView(
                            "Chat nicht gefunden",
                            systemImage: "exclamationmark.triangle",
                            description: Text("Der gewählte Chat konnte nicht geladen werden.")
                        )
                    }
                } else {
                    ContentUnavailableView(
                        "Willkommen",
                        systemImage: appState.isSupporter ? "shield.bordercheck.fill" : "bubble.left.and.bubble.right",
                        description: Text(appState.isSupporter ? "Wähle einen Support-Chat oder eine Verwaltungsoption aus." : "Wähle ein Ticket aus oder erstelle eine neue Problem-Meldung.")
                    )
                }
            }
            .enableTripleFingerGesture(appState: appState)
            .onAppear {
                performSync()
                startAutoSyncTimer()
            }
            .onDisappear {
                stopAutoSyncTimer()
            }
        }
    }
    
    // MARK: - Synchronisation & Timer
    
    private func startAutoSyncTimer() {
        stopAutoSyncTimer()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            performSync()
        }
    }
    
    private func stopAutoSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = nil
    }
    
    private func performSync() {
        guard !appState.userId.isEmpty else { return }
        
        NetworkManager.shared.checkUserStatus(serverURL: appState.serverURL, userId: appState.userId) { exists, isSupporter in
            if !exists {
                // Perform a one-time recheck to avoid signing out on transient errors or scene transitions
                if !pendingSignOutRecheck {
                    pendingSignOutRecheck = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.performSync()
                    }
                    return
                } else {
                    pendingSignOutRecheck = false
                    appState.userId = ""
                    appState.isRegistered = false
                    stopAutoSyncTimer()
                }
            } else {
                pendingSignOutRecheck = false
                
                if appState.isSupporter != isSupporter {
                    appState.isSupporter = isSupporter
                    selectedTab = isSupporter ? "userManagement" : "newChat"
                }
                
                if appState.isSupporter {
                    NetworkManager.shared.fetchAllChats(serverURL: appState.serverURL) { chats in
                        self.allAdminChats = chats
                    }
                } else {
                    NetworkManager.shared.fetchStudentChats(serverURL: appState.serverURL, serialNumber: appState.serialNumber) { chats in
                        self.studentChats = chats
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct StudentOnboardingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var name: String = ""
    @State private var serialNumber: String = ""
    @State private var isWaitingForSettingsReturn: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.15), Color.purple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "ipad.and.arrow.forward")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                    
                    Text("iPad Support")
                        .font(.largeTitle).bold()
                    
                    Text("Ersteinrichtung für Schüler & Lehrer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Dein Name").font(.headline)
                        TextField("Vor- und Nachname", text: $name)
                            .padding()
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. Seriennummer des iPads").font(.headline)
                        
                        if serialNumber.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("1. Tippe auf 'Einstellungen öffnen'", systemImage: "1.circle.fill")
                                Label("2. Allgemein -> Info -> Seriennummer kopieren", systemImage: "2.circle.fill")
                                Label("3. Kehre zu dieser App zurück", systemImage: "3.circle.fill")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                            
                            Button(action: openSettingsAppAndSendNotification) {
                                Label("Einstellungen öffnen", systemImage: "gearshape.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text("Erkannt:").font(.caption2).foregroundColor(.secondary)
                                    Text(serialNumber).font(.subheadline).monospaced().bold()
                                }
                                Spacer()
                                Button("Ändern") { serialNumber = "" }.font(.footnote)
                            }
                            .padding()
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(20)
                
                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
                
                Spacer()
                
                Button(action: completeRegistration) {
                    Text("Registrieren")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || serialNumber.isEmpty)
            }
            .padding(24)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && isWaitingForSettingsReturn {
                checkClipboardForSerialNumber()
            }
        }
    }
    
    private func openSettingsAppAndSendNotification() {
        isWaitingForSettingsReturn = true
        errorMessage = ""

        // Define a notification category with an action that brings the user back to the app
        let returnAction = UNNotificationAction(
            identifier: "RETURN_TO_APP",
            title: "Zur App zurückkehren",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "COPY_SERIAL_CATEGORY",
            actions: [returnAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])

        // Request authorization and schedule the instructional notification
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = "Seriennummer kopieren"
                content.body = "1. Öffne Einstellungen → Allgemein → Info. 2. Halte kurz auf 'Seriennummer' gedrückt und wähle ‚Kopieren‘. Tippe anschließend diese Benachrichtigung oder 'ìPad Hilfe' in der oberen linken Bildschirmecke an, um zur App zurückzukehren."
                content.sound = .default
                content.categoryIdentifier = "COPY_SERIAL_CATEGORY"

                // Fire shortly after switching to Settings so it's visible while the user navigates
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
                let request = UNNotificationRequest(identifier: "copy_serial_guide", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
            }
        }

        // Öffne die Einstellungen-App (öffentlich unterstützter Endpunkt führt zur App-spezifischen Seite)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    private func checkClipboardForSerialNumber() {
        isWaitingForSettingsReturn = false
        guard let copiedString = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !copiedString.isEmpty else {
            errorMessage = "Keine Seriennummer kopiert."
            return
        }
        if copiedString.count >= 8 && copiedString.count <= 14 {
            self.serialNumber = copiedString
            self.errorMessage = ""
        } else {
            errorMessage = "Kopierter Text (\(copiedString)) ist keine Seriennummer."
        }
    }
    
    private func completeRegistration() {
        let deviceName = UIDevice.current.name
        NetworkManager.shared.registerUser(serverURL: appState.serverURL, name: name, serial: serialNumber, device: deviceName) { success, userId, isSupporter in
            if success, let id = userId {
                appState.userId = id
                appState.userName = name
                appState.serialNumber = serialNumber
                appState.isSupporter = isSupporter
                appState.isRegistered = true
            } else {
                errorMessage = "Verbindungsfehler."
            }
        }
    }
}

struct ProfileView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Form {
            Section("Benutzerdetails") {
                LabeledContent("Name", value: appState.userName)
                LabeledContent("Seriennummer", value: appState.serialNumber)
                LabeledContent("Rolle", value: appState.isSupporter ? "Supporter / Admin" : "Schüler / Lehrer")
            }
        }
        .navigationTitle("Profil")
    }
}

struct NewChatView: View {
    @ObservedObject var appState: AppState
    var onCreated: () -> Void
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isSubmitting = false
    
    // Software-bezogene Vorschläge für den Nutzer
    let softwareSuggestions = [
        "App installiert/lädt nicht",
        "Passwort / Anmelde-Problem",
        "iPadOS Update / Software-Fehler",
        "Apple ID / Schul-Account Sperre",
        "GoodNotes / Schul-App stürzt ab"
    ]
    
    var body: some View {
        Form {
            Section("Häufige Software-Probleme") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(softwareSuggestions, id: \.self) { suggestion in
                            Button(action: {
                                title = suggestion
                            }) {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section("Problem beschreiben") {
                TextField("Titel (z.B. App lässt sich nicht öffnen)", text: $title)
                TextEditor(text: $content)
                    .frame(height: 140)
                    .overlay(
                        Group {
                            if content.isEmpty {
                                Text("Beschreibe dein Software-Problem so genau wie möglich...")
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
            }
            
            Section {
                Button(action: submit) {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text("Chat starten").bold() }
                        Spacer()
                    }
                }
                .disabled(title.isEmpty || content.isEmpty || isSubmitting)
            }
        }
        .navigationTitle("Neues Ticket")
    }
    
    private func submit() {
        isSubmitting = true
        let composedTitle = "\(title) – \(appState.userName)"
        // Step 1: Create chat with composed title; content can be minimal
        guard let chatURL = URL(string: "\(appState.serverURL)/api/collections/chats/records") else { return }
        var chatReq = URLRequest(url: chatURL)
        chatReq.httpMethod = "POST"
        chatReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let chatBody: [String: Any] = [
            "title": composedTitle,
            "content": self.content,
            "studentName": appState.userName,
            "serialNumber": appState.serialNumber,
            "isOpen": true
        ]
        chatReq.httpBody = try? JSONSerialization.data(withJSONObject: chatBody)

        URLSession.shared.dataTask(with: chatReq) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newChatId = json["id"] as? String else {
                DispatchQueue.main.async { self.isSubmitting = false }
                return
            }
            // Step 2: Post the first message with the description content
            guard let msgURL = URL(string: "\(appState.serverURL)/api/collections/messages/records") else { return }
            var msgReq = URLRequest(url: msgURL)
            msgReq.httpMethod = "POST"
            msgReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let msgBody: [String: Any] = [
                "chatId": newChatId,
                "senderName": appState.userName,
                "text": self.content
            ]
            msgReq.httpBody = try? JSONSerialization.data(withJSONObject: msgBody)

            URLSession.shared.dataTask(with: msgReq) { _, _, _ in
                DispatchQueue.main.async {
                    self.isSubmitting = false
                    self.title = ""
                    self.content = ""
                    onCreated()
                }
            }.resume()
        }.resume()
    }
}

struct AdminChatWrapperView: View {
    @State var chat: ChatRecord
    @ObservedObject var appState: AppState
    var onUpdate: () -> Void
    @State private var isDeleted = false

    var body: some View {
        if isDeleted {
            ContentUnavailableView("Chat gelöscht", systemImage: "trash.fill")
        } else {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nutzer: \(chat.studentName)").font(.headline)
                        Text("SN: \(chat.serialNumber)").font(.caption).monospaced().foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    if chat.isOpen {
                        Button("Chat schließen") {
                            NetworkManager.shared.updateChatStatus(serverURL: appState.serverURL, chatId: chat.id, isOpen: false) {
                                self.chat = ChatRecord(id: chat.id, title: chat.title, content: chat.content, studentName: chat.studentName, serialNumber: chat.serialNumber, isOpen: false)
                                onUpdate()
                            }
                        }
                        .tint(.orange)
                        .buttonStyle(.bordered)
                    } else {
                        Button("Chat löschen") {
                            // Client-side cascade delete: delete messages, then the chat
                            guard let listURL = URL(string: "\(appState.serverURL)/api/collections/messages/records?filter=(chatId='\(chat.id)')") else { return }
                            URLSession.shared.dataTask(with: listURL) { data, _, _ in
                                var messageIds: [String] = []
                                if let data = data,
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let items = json["items"] as? [[String: Any]] {
                                    messageIds = items.compactMap { $0["id"] as? String }
                                }
                                let group = DispatchGroup()
                                for mid in messageIds {
                                    group.enter()
                                    if let delURL = URL(string: "\(appState.serverURL)/api/collections/messages/records/\(mid)") {
                                        var req = URLRequest(url: delURL)
                                        req.httpMethod = "DELETE"
                                        URLSession.shared.dataTask(with: req) { _, _, _ in group.leave() }.resume()
                                    } else {
                                        group.leave()
                                    }
                                }
                                group.notify(queue: .main) {
                                    NetworkManager.shared.deleteChat(serverURL: appState.serverURL, chatId: chat.id) {
                                        self.isDeleted = true
                                        onUpdate()
                                    }
                                }
                            }.resume()
                        }
                        .tint(.red)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(.regularMaterial)
                
                Divider()
                
                ChatDetailView(chatId: chat.id, senderName: appState.userName, appState: appState)
            }
        }
    }
}

struct UserManagementView: View {
    @ObservedObject var appState: AppState
    @State private var users: [StudentUser] = []

    var body: some View {
        List {
            ForEach(users) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(user.name).font(.headline)
                            if user.isSupporter {
                                Text("Supporter").font(.caption2).padding(3).background(Color.purple.opacity(0.2)).cornerRadius(4)
                            }
                        }
                        Text("SN: \(user.serialNumber)").font(.caption).monospaced().foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        NetworkManager.shared.deleteUser(serverURL: appState.serverURL, userId: user.id) {
                            loadUsers()
                        }
                    } label: {
                        Image(systemName: "trash.fill")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Nutzerverwaltung")
        .onAppear(perform: loadUsers)
    }
    
    private func loadUsers() {
        NetworkManager.shared.fetchUsers(serverURL: appState.serverURL) { users in
            self.users = users
        }
    }
}

