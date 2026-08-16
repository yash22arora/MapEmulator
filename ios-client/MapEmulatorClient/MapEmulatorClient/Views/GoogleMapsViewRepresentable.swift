//
//  GoogleMapsViewRepresentable.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 16/08/26.
//

import SwiftUI
import GoogleMaps
import MapKit
import UIKit

class MapCoordinator {
    var marker: GMSMarker?
}

struct GoogleMapsViewRepresentable: UIViewRepresentable {
    let riderCoordinate: CLLocationCoordinate2D?
    let homeCoordinate: CLLocationCoordinate2D
    
    /// Called once when MapsView is constructed
    func makeUIView(context: Context) -> GMSMapView {
        let mapID = GMSMapID(identifier: "120581de6cb7eed0e8d4fc7b")
        let camera = GMSCameraPosition(target: homeCoordinate, zoom: 14.7)
        let uiView = GMSMapView(frame: .zero, mapID: mapID, camera: camera)
        
        // Home Marker
        let homeMarker = GMSMarker(position: homeCoordinate)
        homeMarker.icon = GoogleMapsViewRepresentable.markerImage(systemName: "house.fill", tint: .systemGreen)
        homeMarker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
        homeMarker.map = uiView
        
        return uiView
    }
    
    /// Called at every state change - need to handle changes manually
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        // Update marker on state update
        guard let riderCoordinate else { return }
        if let marker = context.coordinator.marker {
            marker.position = riderCoordinate
        } else {
            let marker = GMSMarker(position: riderCoordinate)
            marker.icon = GoogleMapsViewRepresentable.markerImage(systemName: "car.fill", tint: .systemBlue)
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.map = uiView
            context.coordinator.marker = marker
        }
        
    }
    
    func makeCoordinator() -> MapCoordinator {
        MapCoordinator()
    }
    
    private static func markerImage(systemName: String, tint: UIColor) -> UIImage? {
        UIImage(systemName: systemName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 30, weight: .medium))
            .withTintColor(tint, renderingMode: .alwaysOriginal)
    }
}
