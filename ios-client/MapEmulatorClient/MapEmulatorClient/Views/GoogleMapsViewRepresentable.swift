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
    var polyline: GMSPolyline?
}

struct GoogleMapsViewRepresentable: UIViewRepresentable {
    let riderCoordinate: CLLocationCoordinate2D?
    let homeCoordinate: CLLocationCoordinate2D
    let route: MKRoute?
    
    /// Called once when MapsView is constructed
    func makeUIView(context: Context) -> GMSMapView {
        let mapID = GMSMapID(identifier: "120581de6cb7eed0e8d4fc7b")
        let camera = GMSCameraPosition(target: homeCoordinate, zoom: 15.5)
        let uiView = GMSMapView(frame: .zero, mapID: mapID, camera: camera)
        
        // Home Marker
        let homeMarker = GMSMarker(position: homeCoordinate)
        homeMarker.icon = UIImage(named: "home").map {
            GoogleMapsViewRepresentable.resizedImage($0, to: CGSize(width: 50, height: 50))
        }
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
            marker.icon = UIImage(named: "car").map {
                GoogleMapsViewRepresentable.resizedImage($0, to: CGSize(width: 50, height: 40))
            }
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.map = uiView
            context.coordinator.marker = marker
        }

        // Update route polyline on state update
        if let route {
            let path = GMSMutablePath()
            for coordinate in route.polyline.coordinates {
                path.add(coordinate)
            }

            if let existingPolyline = context.coordinator.polyline {
                existingPolyline.path = path
            } else {
                let polyline = GMSPolyline(path: path)
                polyline.strokeColor = .systemOrange
                polyline.strokeWidth = 4
                polyline.map = uiView
                context.coordinator.polyline = polyline
            }
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

    /// Loose bundled PNGs (no Asset Catalog scale variants) load at scale
    /// 1.0, so a 320x256 source image reports a 320x256-point UIImage.size —
    /// this redraws it down to a sane marker size.
    private static func resizedImage(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension MKPolyline {
    /// MKPolyline stores its points as raw MKMapPoints behind a C-style
    /// buffer API, not a Swift array — this bridges it to one.
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](
            repeating: kCLLocationCoordinate2DInvalid,
            count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
