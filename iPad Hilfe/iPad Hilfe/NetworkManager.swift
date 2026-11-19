//
//  ChatRecord.swift
//  iPad Hilfe
//
//  Created by benny on 27.09.26.
//


import Foundation

// MARK: - Datenmodelle (Models)

struct ChatRecord: Identifiable, Codable {
    let id: String
    let title: String
    let content: String
    let studentName: String
    let serialNumber: String
    let isOpen: Bool
}

struct MessageRecord: Identifiable, Codable {
    let id: String
    let chatId: String
    let senderName: String
    let text: String
    let image: String?
}

struct StudentUser: Identifiable, Codable {
    let id: String
    let name: String
    let serialNumber: String
    let deviceName: String
    let isSupporter: Bool
}

// MARK: - Network Manager

class NetworkManager {
    static let shared = NetworkManager()
    
    private func cleanURL(_ urlStr: String) -> String {
        var base = urlStr.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "https://" + base
        }
        return base
    }
    
    // MARK: - User Operations
    
    func registerUser(serverURL: String, name: String, serial: String, device: String, completion: @escaping (Bool, String?, Bool) -> Void) {
        let cleanedSerial = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseUrl = cleanURL(serverURL)
        
        guard var components = URLComponents(string: "\(baseUrl)/api/collections/app_users/records") else {
            DispatchQueue.main.async { completion(false, nil, false) }
            return
        }
        
        components.queryItems = [
            URLQueryItem(name: "filter", value: "(serialNumber='\(cleanedSerial)')")
        ]
        
        guard let checkURL = components.url else {
            DispatchQueue.main.async { completion(false, nil, false) }
            return
        }
        
        var request = URLRequest(url: checkURL)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               let existingUser = items.first,
               let existingId = existingUser["id"] as? String {
                
                let isSupporter = existingUser["isSupporter"] as? Bool ?? false
                self.updateUser(serverURL: baseUrl, userId: existingId, name: name, device: device) { success in
                    completion(success, existingId, isSupporter)
                }
            } else {
                self.createNewUser(serverURL: baseUrl, name: name, serial: cleanedSerial, device: device) { success, newId in
                    completion(success, newId, false)
                }
            }
        }.resume()
    }
    
    private func createNewUser(serverURL: String, name: String, serial: String, device: String, completion: @escaping (Bool, String?) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/app_users/records") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "name": name,
            "serialNumber": serial,
            "deviceName": device,
            "isSupporter": false
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? String {
                DispatchQueue.main.async { completion(true, id) }
            } else {
                DispatchQueue.main.async { completion(false, nil) }
            }
        }.resume()
    }
    
    private func updateUser(serverURL: String, userId: String, name: String, device: String, completion: @escaping (Bool) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/app_users/records/\(userId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["name": name, "deviceName": device]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }
    
    func checkUserStatus(serverURL: String, userId: String, completion: @escaping (Bool, Bool) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/app_users/records/\(userId)") else {
            completion(false, false)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(false, false) }
                return
            }
            let isSupporter = json["isSupporter"] as? Bool ?? false
            DispatchQueue.main.async { completion(true, isSupporter) }
        }.resume()
    }
    
    // MARK: - Supporter Upgrade via Code
    
    func redeemInviteCode(serverURL: String, userId: String, code: String, completion: @escaping (Bool) -> Void) {
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let baseUrl = cleanURL(serverURL)
        
        guard var components = URLComponents(string: "\(baseUrl)/api/collections/invite_codes/records") else { return }
        components.queryItems = [
            URLQueryItem(name: "filter", value: "(code='\(cleanedCode)' && isUsed=false)")
        ]
        
        guard let url = components.url else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]],
               let firstCode = items.first,
               let codeId = firstCode["id"] as? String {
                
                self.markCodeAsUsed(serverURL: baseUrl, recordId: codeId)
                self.setUserSupporterStatus(serverURL: baseUrl, userId: userId, isSupporter: true) { success in
                    DispatchQueue.main.async { completion(success) }
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }.resume()
    }
    
    private func markCodeAsUsed(serverURL: String, recordId: String) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/invite_codes/records/\(recordId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["isUsed": true])
        URLSession.shared.dataTask(with: req).resume()
    }
    
    private func setUserSupporterStatus(serverURL: String, userId: String, isSupporter: Bool, completion: @escaping (Bool) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/app_users/records/\(userId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["isSupporter": isSupporter])
        
        URLSession.shared.dataTask(with: req) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
    
    // MARK: - Chat Operations
    
    func createChat(serverURL: String, title: String, content: String, studentName: String, serialNumber: String, completion: @escaping (Bool, String?) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/chats/records") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "title": title,
            "content": content,
            "studentName": studentName,
            "serialNumber": serialNumber,
            "isOpen": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? String {
                DispatchQueue.main.async { completion(true, id) }
            } else {
                DispatchQueue.main.async { completion(false, nil) }
            }
        }.resume()
    }
    
    func fetchStudentChats(serverURL: String, serialNumber: String, completion: @escaping ([ChatRecord]) -> Void) {
        let cleanedSerial = serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseUrl = cleanURL(serverURL)
        
        guard var components = URLComponents(string: "\(baseUrl)/api/collections/chats/records") else { return }
        components.queryItems = [
            URLQueryItem(name: "filter", value: "(serialNumber='\(cleanedSerial)')")
        ]
        
        guard let url = components.url else { return }
        self.parseChats(url: url, completion: completion)
    }
    
    func fetchAllChats(serverURL: String, completion: @escaping ([ChatRecord]) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/chats/records") else { return }
        self.parseChats(url: url, completion: completion)
    }
    
    private func parseChats(url: URL, completion: @escaping ([ChatRecord]) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                let chats = items.compactMap { dict -> ChatRecord? in
                    guard let id = dict["id"] as? String,
                          let title = dict["title"] as? String,
                          let content = dict["content"] as? String,
                          let studentName = dict["studentName"] as? String,
                          let serial = dict["serialNumber"] as? String,
                          let isOpen = dict["isOpen"] as? Bool else { return nil }
                    return ChatRecord(id: id, title: title, content: content, studentName: studentName, serialNumber: serial, isOpen: isOpen)
                }
                DispatchQueue.main.async { completion(chats) }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    func updateChatStatus(serverURL: String, chatId: String, isOpen: Bool, completion: @escaping () -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/chats/records/\(chatId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["isOpen": isOpen])
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }
    
    func deleteChat(serverURL: String, chatId: String, completion: @escaping () -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/chats/records/\(chatId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }
    
    // MARK: - Supporter Management
    
    func fetchUsers(serverURL: String, completion: @escaping ([StudentUser]) -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/app_users/records") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                let users = items.compactMap { dict -> StudentUser? in
                    guard let id = dict["id"] as? String,
                          let name = dict["name"] as? String,
                          let serial = dict["serialNumber"] as? String,
                          let device = dict["deviceName"] as? String else { return nil }
                    let isSupp = dict["isSupporter"] as? Bool ?? false
                    return StudentUser(id: id, name: name, serialNumber: serial, deviceName: device, isSupporter: isSupp)
                }
                DispatchQueue.main.async { completion(users) }
            } else {
                DispatchQueue.main.async { completion([]) }
            }
        }.resume()
    }
    
    func deleteUser(serverURL: String, userId: String, completion: @escaping () -> Void) {
        let baseUrl = cleanURL(serverURL)
        guard let url = URL(string: "\(baseUrl)/api/collections/app_users/records/\(userId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }
}