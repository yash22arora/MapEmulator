//
//  MKPolyline+Snapping.swift
//  MapEmulatorClient
//
//  Shared route-snapping helpers used by both GoogleMapsViewRepresentable
//  (animating the marker along the route) and LiveViewViewModel (deciding
//  whether the rider has drifted far enough off-route to justify a new
//  MKDirections call).
//

import MapKit

extension MKPolyline {
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

    /// Real-world distance from `coordinate` to the nearest vertex on this polyline.
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return coordinates.reduce(Double.greatestFiniteMagnitude) { closest, point in
            let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return min(closest, target.distance(from: pointLocation))
        }
    }
}
