//
//  LiveViewViewModel.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//
import SwiftUI
import MapKit

@Observable
class LiveViewViewModel {
    private(set) var riderLocation: CLLocation?
    private(set) var homeCoordinate = CLLocation.home
    private(set) var route: MKRoute?
    private var dataManager: LiveViewDataManaging
    
    init(currentLocation: LocationUpdate? = nil, dataManager: LiveViewDataManaging = LiveViewDataManager()) {
        if let currentLocation {
            self.riderLocation = CLLocation(latitude: currentLocation.lat, longitude: currentLocation.lng)
        }
        self.dataManager = dataManager
    }
    
    func startFetchingRiderLocation() async {
        do {
            for try await update in dataManager.startStreaming() {
                withAnimation(.linear(duration: 1)) {
                    riderLocation = CLLocation(latitude: update.lat, longitude: update.lng)
                }
               
            }
        } catch(let error) {
            print("Error in streaming: \(error)")
        }
    }
    
    func requestMapRoute() async {
        
        guard let riderLocation = riderLocation else { return }
        
        let request = MKDirections.Request()
        request.source = MKMapItem(location: riderLocation, address: MKAddress(fullAddress: "Rider", shortAddress: nil))
        request.destination = MKMapItem(location: .home, address: MKAddress(fullAddress: "Purva Fountain Square", shortAddress: nil))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard !Task.isCancelled else { return }
            guard let route = response.routes.first else {
                print("No route found")
                return
            }
            withAnimation(.linear(duration: 1)) {
                self.route = route
            }
        } catch {
            print("Error while fetching directions")
        }
        
    }
    
}


extension CLLocation {
    static var home = CLLocation(latitude: 12.960025715478084, longitude: 77.70524740219118)
}
