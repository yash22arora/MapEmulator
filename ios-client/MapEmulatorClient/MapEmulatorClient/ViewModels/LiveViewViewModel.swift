//
//  LiveViewViewModel.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//
import SwiftUI
import MapKit

enum StatusType: Equatable {
    case pendingConfirmation
    case restaurantPreparingOrder
    case riderReachingRestaurant
    case riderPickedOrder
    case delivered
}

@Observable
class LiveViewViewModel {
    private(set) var riderLocation: CLLocation?
    private(set) var homeCoordinate = CLLocation.noidaHome
    private(set) var route: MKRoute?
    private var dataManager: LiveViewDataManaging
    private(set) var status: StatusType = .riderPickedOrder
    
    init(currentLocation: LocationUpdate? = nil, dataManager: LiveViewDataManaging = LiveViewDataManager()) {
        if let currentLocation {
            self.riderLocation = CLLocation(latitude: currentLocation.lat, longitude: currentLocation.lng)
        }
        self.dataManager = dataManager
    }
    
    func startFetchingRiderLocation(topic: String) async {
        do {
            for try await update in dataManager.startStreaming(topic: topic, onComplete: {
                self.status = .delivered
            }) {
                // CLLocation.timestamp carries the event's real ts (ms since epoch,
                // as sent by both producers), not construction time — this is what
                // lets the marker animation compute a true gap between updates
                // instead of a local arrival-time approximation.
                riderLocation = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: update.lat, longitude: update.lng),
                    altitude: 0,
                    horizontalAccuracy: -1,
                    verticalAccuracy: -1,
                    timestamp: Date(timeIntervalSince1970: update.ts / 1000)
                )
            }
        } catch(let error) {
            print("Error in streaming: \(error)")
        }
    }
    
    /// Only recompute the route once the rider has actually drifted this far
    /// off the existing one — avoids an MKDirections call on every single
    /// location update when the rider is still on the known route.
    private static let routeRecomputeThreshold: CLLocationDistance = 20

    func requestMapRoute() async {

        guard let riderLocation = riderLocation else { return }

        if let route, route.polyline.distance(to: riderLocation.coordinate) <= Self.routeRecomputeThreshold {
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: riderLocation, address: MKAddress(fullAddress: "Rider", shortAddress: nil))
        request.destination = MKMapItem(location: homeCoordinate, address: MKAddress(fullAddress: "Home", shortAddress: nil))
        request.transportType = .automobile
        
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard !Task.isCancelled else { return }
            guard let route = response.routes.first else {
                print("No route found")
                return
            }
            self.route = route
        } catch {
            print("Error while fetching directions")
        }
        
    }
    
}


extension CLLocation {
    static var home = CLLocation(latitude: 12.960025715478084, longitude: 77.70524740219118)
    static var noidaHome = CLLocation(latitude: 28.58686637508844, longitude: 77.39757657051086)
}
