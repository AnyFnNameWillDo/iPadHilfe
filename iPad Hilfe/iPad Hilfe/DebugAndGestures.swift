//
//  TripleFingerSwipeModifier.swift
//  iPad Hilfe
//
//  Created by benny on 27.09.26.
//


import SwiftUI
import PhotosUI
import UserNotifications

// MARK: - 3-Finger Gesture

struct TripleFingerSwipeModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @State private var swipeCount = 0

    func body(content: Content) -> some View {
        content
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.height < -50 {
                            swipeCount += 1
                            if swipeCount >= 2 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    appState.showDebugTab = true
                                }
                                swipeCount = 0
                            }
                        }
                    }
            )
    }
}

extension View {
    func enableTripleFingerGesture(appState: AppState) -> some View {
        self.modifier(TripleFingerSwipeModifier(appState: appState))
    }
}

// MARK: - Debug View

struct DebugView: View {
    @ObservedObject var appState: AppState
    @State private var customCommand: String = ""
    @State private var commandLogs: String = "Console Ready..."

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "network").foregroundColor(.blue)
                    TextField("Server URL", text: $appState.serverURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
            } header: {
                Text("Server Konfiguration")
            }
            
            if appState.isSupporter {
                Section(header: Text("Admin Remote Commands")) {
                    HStack {
                        TextField("Befehl (z.B. REST_DB)", text: $customCommand)
                        Button(action: sendCommand) {
                            Image(systemName: "paperplane.fill")
                        }
                        .disabled(customCommand.isEmpty)
                    }
                    
                    TextEditor(text: .constant(commandLogs))
                        .frame(height: 100)
                        .font(.monospaced(.footnote)())
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                }
            }
        }
        .navigationTitle("Debug & Terminal")
    }
    
    private func sendCommand() {
        commandLogs += "\n> \(customCommand)"
        customCommand = ""
    }
}

// MARK: - Chat Detail View

struct ChatDetailView: View {
    let chatId: String
    let senderName: String
    @ObservedObject var appState: AppState
    
    @State private var messages: [MessageRecord] = []
    @State private var messageText: String = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var refreshTimer: Timer? = nil
    @State private var lastMessageIds: Set<String> = []
    
    @State private var isUploadingImage: Bool = false
    @State private var selectedImageData: Data? = nil
    
    @State private var editingMessage: MessageRecord? = nil
    @State private var editedText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            let mine = (msg.senderName == senderName || msg.senderName == "\(senderName) (Support)")
                            ChatBubble(msg: msg, isFromMe: mine)
                                .contextMenu(mine ? ContextMenu {
                                    Button("Nachricht bearbeiten") { startEditingMessage(msg) }
                                    Button(role: .destructive) { deleteMessage(msg) } label: { Text("Nachricht löschen") }
                                } : nil)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                }
                
                TextField("Nachricht...", text: $messageText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadMessages()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    self.selectedImageData = data
                    await self.uploadSelectedPhoto()
                }
            }
        }
        .onChange(of: chatId) { _, _ in
            // Reset state when switching chats
            self.messages = []
            self.lastMessageIds = []
            self.messageText = ""
            stopAutoRefresh()
            loadMessages()
            startAutoRefresh()
        }
        .id(chatId)
    }
    
    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            loadMessages(quiet: true)
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func loadMessages(quiet: Bool = false) {
        let filter = "chatId='\(chatId)'".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "\(appState.serverURL)/api/collections/messages/records?filter=(\(filter))") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                let msgs = items.compactMap { dict -> MessageRecord? in
                    guard let id = dict["id"] as? String,
                          let cId = dict["chatId"] as? String,
                          let sender = dict["senderName"] as? String,
                          let text = dict["text"] as? String else { return nil }
                    let imageFile = dict["image"] as? String
                    let imageURLString: String? = {
                        if let file = imageFile, !file.isEmpty {
                            return "\(appState.serverURL)/api/files/messages/\(id)/\(file)"
                        } else { return nil }
                    }()
                    return MessageRecord(id: id, chatId: cId, senderName: sender, text: text, image: imageURLString)
                }
                DispatchQueue.main.async {
                    // Determine newly received messages (by id) that were not previously known
                    let newIds = Set(msgs.map { $0.id })
                    let addedIds = newIds.subtracting(self.lastMessageIds)

                    // Update state
                    self.messages = msgs
                    self.lastMessageIds = newIds

                    // If not initial load or if quiet refresh, notify about new incoming messages from others
                    if !addedIds.isEmpty {
                        let newMessages = msgs.filter { addedIds.contains($0.id) }
                        // Only notify for messages not sent by current user
                        let foreignMessages = newMessages.filter { !$0.senderName.contains(self.senderName) }
                        if quiet, !foreignMessages.isEmpty {
                            self.postNewMessageNotification(foreignMessages.last!)
                        }
                    }
                }
            }
        }.resume()
    }
    
    private func postNewMessageNotification(_ message: MessageRecord) {
        let content = UNMutableNotificationContent()
        content.title = "Neue Nachricht"
        content.body = "\(message.senderName): \(message.text)"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "new_message_\(message.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    @MainActor
    private func uploadSelectedPhoto() async {
        guard let data = selectedImageData else { return }
        isUploadingImage = true
        defer { isUploadingImage = false; selectedItem = nil; selectedImageData = nil }

        // Prepare multipart/form-data request to upload image and create message
        let boundary = "Boundary-\(UUID().uuidString)"
        guard let url = URL(string: "\(appState.serverURL)/api/collections/messages/records") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let displayName = appState.isSupporter ? "\(senderName) (Support)" : senderName
        let filename = "img_\(UUID().uuidString.prefix(8)).jpg"
        var body = Data()

        func appendFormField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        func appendFileField(name: String, filename: String, mimeType: String, fileData: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendFormField(name: "chatId", value: chatId)
        appendFormField(name: "senderName", value: displayName)
        appendFormField(name: "text", value: filename)
        appendFileField(name: "image", filename: filename, mimeType: "image/jpeg", fileData: data)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newId = json["id"] as? String {
                    let fileName = (json["image"] as? String) ?? filename
                    let fullURL = "\(appState.serverURL)/api/files/messages/\(newId)/\(fileName)"
                    self.messages.append(MessageRecord(id: newId, chatId: chatId, senderName: displayName, text: fileName, image: fullURL))
                } else {
                    // Fallback optimistic append
                    self.messages.append(MessageRecord(id: UUID().uuidString, chatId: chatId, senderName: displayName, text: filename, image: filename))
                }
            }
        }
        task.resume()
    }

    private func sendMessage() {
        if let editing = editingMessage {
            guard editing.senderName == senderName || editing.senderName == "\(senderName) (Support)" else { self.editingMessage = nil; return }
            guard let url = URL(string: "\(appState.serverURL)/api/collections/messages/records/\(editing.id)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["text": messageText]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            let newText = messageText
            messageText = ""
            URLSession.shared.dataTask(with: request) { _, _, _ in
                DispatchQueue.main.async {
                    if let idx = self.messages.firstIndex(where: { $0.id == editing.id }) {
                        self.messages[idx] = MessageRecord(id: editing.id, chatId: editing.chatId, senderName: editing.senderName, text: newText, image: editing.image)
                    }
                    self.editingMessage = nil
                }
            }.resume()
            return
        }
        
        guard let url = URL(string: "\(appState.serverURL)/api/collections/messages/records") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let displayName = appState.isSupporter ? "\(senderName) (Support)" : senderName
        let body: [String: Any] = ["chatId": chatId, "senderName": displayName, "text": messageText]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let textToSend = messageText
        messageText = ""
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.messages.append(MessageRecord(id: UUID().uuidString, chatId: chatId, senderName: displayName, text: textToSend, image: nil))
            }
        }.resume()
    }
    
    private func startEditingMessage(_ message: MessageRecord) {
        guard message.senderName == senderName || message.senderName == "\(senderName) (Support)" else { return }
        editingMessage = message
        editedText = message.text
        // Present a simple inline edit by replacing the input field's text
        self.messageText = message.text
    }

    private func deleteMessage(_ message: MessageRecord) {
        guard message.senderName == senderName || message.senderName == "\(senderName) (Support)" else { return }
        guard let url = URL(string: "\(appState.serverURL)/api/collections/messages/records/\(message.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                self.messages.removeAll { $0.id == message.id }
            }
        }.resume()
    }
}

struct ChatBubble: View {
    let msg: MessageRecord
    let isFromMe: Bool
    
    var body: some View {
        HStack {
            if isFromMe { Spacer() }
            
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 4) {
                Text(msg.senderName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                if let imageName = msg.image, !imageName.isEmpty {
                    // Attempt to construct an image URL; assumes PocketBase-like storage at /api/files/messages/{recordId}/{file}
                    // If recordId is not known, fallback to a generic files path if your backend exposes it differently.
                    // Here we show a simple image bubble without relying on record ID, expecting server to serve by filename.
                    AsyncImage(url: URL(string: imageName.hasPrefix("http") ? imageName : imageName)) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 200, height: 150)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 240, maxHeight: 180)
                                .clipped()
                        case .failure:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 90)
                                .foregroundColor(.secondary)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .background(isFromMe ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.ultraThinMaterial))
                    .cornerRadius(18)
                    .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                }
                if !msg.text.isEmpty {
                    Text(msg.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isFromMe ? AnyShapeStyle(Color.blue) : AnyShapeStyle(.ultraThinMaterial))
                        .foregroundColor(isFromMe ? .white : .primary)
                        .cornerRadius(18)
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                }
            }
            
            if !isFromMe { Spacer() }
        }
    }
}

