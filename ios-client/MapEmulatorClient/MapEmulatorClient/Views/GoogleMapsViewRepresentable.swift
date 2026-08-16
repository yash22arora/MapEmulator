//
//  GoogleMapsViewRepresentable.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 16/08/26.
//

import SwiftUI
import GoogleMaps
import MapKit

class MapCoordinator {
    var marker: GMSMarker?
}

struct GoogleMapsViewRepresentable: UIViewRepresentable {
    let riderCoordinate: CLLocationCoordinate2D?
    let homeCoordinate: CLLocationCoordinate2D
    
    /// Called once when MapsView is constructed
    func makeUIView(context: Context) -> GMSMapView {
        let uiView = GMSMapView()
        uiView.camera = GMSCameraPosition(target: homeCoordinate, zoom: 14)
        
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
            marker.map = uiView
            context.coordinator.marker = marker
        }
        
    }
    
    func makeCoordinator() -> MapCoordinator {
        MapCoordinator()
    }
}
