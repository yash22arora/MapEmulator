//
//  RiderViewModel.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 15/08/26.
//

import Observation

final class RiderViewModel {
    private let dataManager : LiveViewDataManaging
    
    init(dataManager: LiveViewDataManaging = LiveViewDataManager()) {
        self.dataManager = dataManager
    }
    
    func sendLocationUpdate(location: LocationUpdate) async {
        do {
            try await dataManager.sendLocationUpdate(payload: location)
        }
        catch(let error) {
            print("Error while sending location: \(error)")
        }
    }
}
