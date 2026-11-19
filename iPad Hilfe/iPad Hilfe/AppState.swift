//
//  AppState.swift
//  iPad Hilfe
//
//  Created by benny on 27.09.26.
//


import SwiftUI
import Combine

class AppState: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = ""
    @AppStorage("userId") var userId: String = ""
    @AppStorage("userName") var userName: String = ""
    @AppStorage("serialNumber") var serialNumber: String = ""
    @AppStorage("isSupporter") var isSupporter: Bool = false
    
    @Published var isRegistered: Bool = false
    @Published var showDebugTab: Bool = false
    
    init() {
        self.isRegistered = !userId.isEmpty
    }
}
