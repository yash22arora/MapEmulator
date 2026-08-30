//
//  LiveViewViewModel.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//
import SwiftUI
import MapKit

/// String-backed and Codable because these values now arrive over the
/// wire (event: status frames) -- the raw values must match the backend's
/// StatusType union exactly, case for case.
enum StatusType: String, Codable, Equatable, CaseIterable {
    case pendingConfirmation
    case restaurantPreparingOrder
    case riderReachingRestaurant
    case riderPickedOrder
    case delivered
}

extension StatusType {
    /// Short label for the Rider app's status button bar — mirrors the
    /// admin dashboard's STATUS_LABELS.
    var shortLabel: String {
        switch self {
        case .pendingConfirmation: return "Order Placed"
        case .restaurantPreparingOrder: return "Confirm Order"
        case .riderReachingRestaurant: return "Rider → Restaurant"
        case .riderPickedOrder: return "Picked Up"
        case .delivered: return "Delivered"
        }
    }
}

@Observable
class LiveViewViewModel {
    private(set) var riderLocation: CLLocation?
    private(set) var homeCoordinate = CLLocation.noidaHome
    private(set) var restaurantCoordinate = CLLocation.pizzaBakery
    private(set) var route: MKRoute?
    private var dataManager: LiveViewDataManaging
    private(set) var status: StatusType = .pendingConfirmation

    init(currentLocation: LocationUpdate? = nil, dataManager: LiveViewDataManaging = LiveViewDataManager()) {
        if let currentLocation {
            self.riderLocation = CLLocation(latitude: currentLocation.lat, longitude: currentLocation.lng)
        }
        self.dataManager = dataManager
    }

    func startFetchingRiderLocation(topic: String) async {
        do {
            for try await event in dataManager.startStreaming(topic: topic) {
                switch event {
                case .location(let update):
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
                case .statusChanged(let newStatus):
                    status = newStatus
                }
            }
            // Loop ended with no error thrown -- the only way that happens now is
            // the server's deliberate "completed" signal (StreamCompletedIntentionally,
            // handled inside the data manager). Cancellation also finishes cleanly,
            // but the view going away means nobody's around to see this anyway.
            status = .delivered
            // No more updates are coming -- drop the last route so the map
            // stops showing a route/polyline once delivery is done.
            route = nil
        } catch(let error) {
            print("Error in streaming: \(error)")
        }
    }

    /// Only recompute the route once the rider has actually drifted this far
    /// off the existing one — avoids an MKDirections call on every single
    /// location update when the rider is still on the known route.
    private static let routeRecomputeThreshold: CLLocationDistance = 20

    /// Which fixed point the rider is currently routing toward -- the
    /// restaurant for every status up through pickup, home only once the
    /// order is actually out for delivery.
    private var currentDestination: CLLocation {
        status == .riderPickedOrder || status == .delivered ? homeCoordinate : restaurantCoordinate
    }

    /// The destination `route` was last computed against -- needed because
    /// the drift-threshold check below only knows the rider hasn't moved
    /// far from the existing polyline, not that the polyline itself is now
    /// pointed at the wrong place (e.g. right after the restaurant->home
    /// destination switch, the rider is still standing right on the old
    /// restaurant-bound route).
    private var lastRouteDestination: CLLocation?

    func requestMapRoute() async {

        guard let riderLocation = riderLocation else { return }

        let destination = currentDestination
        let destinationChanged = lastRouteDestination.map {
            $0.coordinate.latitude != destination.coordinate.latitude
                || $0.coordinate.longitude != destination.coordinate.longitude
        } ?? true

        if !destinationChanged,
           let route, route.polyline.distance(to: riderLocation.coordinate) <= Self.routeRecomputeThreshold {
            return
        }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: riderLocation, address: MKAddress(fullAddress: "Rider", shortAddress: nil))
        request.destination = MKMapItem(location: destination, address: MKAddress(fullAddress: "Destination", shortAddress: nil))
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
            lastRouteDestination = destination
        } catch {
            print("Error while fetching directions")
        }

    }

}


extension CLLocation {
    static var home = CLLocation(latitude: 12.960025715478084, longitude: 77.70524740219118)
    static var noidaHome = CLLocation(latitude: 28.58686637508844, longitude: 77.39757657051086)
    static var pizzaBakery = CLLocation(latitude: 28.57509276238054, longitude: 77.38498826778395)
}
