//
//  MapEmulatorClientApp.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//

import SwiftUI
import SwiftData
import GoogleMaps

@main
struct MapEmulatorClientApp: App {
    
    init() {
        GMSServices.provideAPIKey(Secrets.googleMapsAPIKey)
    }
    
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
