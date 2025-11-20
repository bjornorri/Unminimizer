//
//  UnminimizerApp.swift
//  Unminimizer
//
//  Created by Bjorn Orri Saemundsson on 20.11.2025.
//

import SwiftUI

@main
struct UnminimizerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
