//
//  LiveViewViewModel.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//
import SwiftUI

@Observable
class LiveViewViewModel {
    private(set) var currentLocation: LocationUpdate?
    private var dataManager: LiveViewDataManaging
    
    init(currentLocation: LocationUpdate? = nil, dataManager: LiveViewDataManaging = LiveViewDataManager()) {
        self.currentLocation = currentLocation
        self.dataManager = dataManager
    }
    
    func startFetchingRiderLocation() async {
        do {
            for try await update in dataManager.startStreaming() {
                currentLocation = update
            }
        } catch(let error) {
            print("Error in streaming: \(error)")
        }
    }
    
}
