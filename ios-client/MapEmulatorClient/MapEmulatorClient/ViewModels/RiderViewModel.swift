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

    /// Returns whether the update actually succeeded, so the caller only
    /// advances its local "current stage" guess once the backend has
    /// confirmed it — same reasoning as the admin dashboard's
    /// advanceToStatus, which only updates its button state after the
    /// fetch resolves ok.
    @discardableResult
    func sendStatusUpdate(topic: String, status: StatusType) async -> Bool {
        do {
            try await dataManager.sendStatusUpdate(topic: topic, status: status)
            return true
        }
        catch(let error) {
            print("Error while sending status update: \(error)")
            return false
        }
    }
}
