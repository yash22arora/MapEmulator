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

    var currentDisplayCoordinate: CLLocationCoordinate2D?
    var isAnimating = false
    var pendingTargetCoordinate: CLLocationCoordinate2D?
    var pendingTargetTimestamp: Date?

    /// The last riderCoordinate/timestamp we actually reacted to — guards
    /// against re-triggering an animation when updateUIView fires for an
    /// unrelated reason (route recomputing) with the same rider position,
    /// and gives the next animation something to measure its real-world
    /// time gap against.
    var lastKnownTarget: CLLocationCoordinate2D?
    var lastKnownTimestamp: Date?
}

struct GoogleMapsViewRepresentable: UIViewRepresentable {
    let riderLocation: CLLocation?
    let homeCoordinate: CLLocationCoordinate2D
    let route: MKRoute?
    
    /// Called once when MapsView is constructed
    func makeUIView(context: Context) -> GMSMapView {
        let mapID = GMSMapID(identifier: "120581de6cb7eed0e8d4fc7b")
        let camera = GMSCameraPosition(target: homeCoordinate, zoom: 15.5)
        let uiView = GMSMapView(frame: .zero, mapID: mapID, camera: camera)

        // Caps how far fitCamera can zoom in as the rider approaches home
        // (bounds shrinking toward a single point would otherwise zoom in
        // arbitrarily far) — applies to every camera move, not just fit.
        uiView.setMinZoom(uiView.minZoom, maxZoom: 17)

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
        guard let riderLocation else { return }
        let coordinator = context.coordinator
        let riderCoordinate = riderLocation.coordinate
        let polylineCoordinates = route?.polyline.coordinates ?? []

        // Sync the route polyline first, so it's already current by the time
        // any animation below reads coordinator.polyline.
        if let route {
            let path = GMSMutablePath()
            for coordinate in polylineCoordinates {
                path.add(coordinate)
            }

            if let existingPolyline = coordinator.polyline {
                existingPolyline.path = path
            } else {
                let polyline = GMSPolyline(path: path)
                polyline.strokeColor = .systemOrange
                polyline.strokeWidth = 4
                polyline.map = uiView
                coordinator.polyline = polyline
            }
        }

        if let marker = coordinator.marker {
            let isNewTarget = coordinator.lastKnownTarget.map {
                $0.latitude != riderCoordinate.latitude || $0.longitude != riderCoordinate.longitude
            } ?? true

            if isNewTarget {
                let previousTimestamp = coordinator.lastKnownTimestamp
                coordinator.lastKnownTarget = riderCoordinate
                coordinator.lastKnownTimestamp = riderLocation.timestamp

                GoogleMapsViewRepresentable.fitCamera(
                    uiView,
                    home: homeCoordinate,
                    rider: riderCoordinate,
                    remainingPolyline: GoogleMapsViewRepresentable.remainingPolyline(from: riderCoordinate, on: polylineCoordinates)
                )

                if coordinator.isAnimating {
                    // Let the in-flight animation finish; this becomes the next target.
                    coordinator.pendingTargetCoordinate = riderCoordinate
                    coordinator.pendingTargetTimestamp = riderLocation.timestamp
                } else {
                    GoogleMapsViewRepresentable.startAnimation(
                        to: riderCoordinate,
                        at: riderLocation.timestamp,
                        previousTimestamp: previousTimestamp,
                        on: polylineCoordinates,
                        marker: marker,
                        routeOverlay: coordinator.polyline,
                        coordinator: coordinator,
                        uiView: uiView
                    )
                }
            }
            // else: this call was triggered by something else changing (e.g. route
            // recomputing) with the same rider coordinate — nothing new to animate to.
        } else {
            let marker = GMSMarker(position: riderCoordinate)
            marker.icon = UIImage(named: "car").map {
                GoogleMapsViewRepresentable.resizedImage($0, to: CGSize(width: 50, height: 40))
            }
            marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
            marker.map = uiView
            coordinator.marker = marker
            coordinator.currentDisplayCoordinate = riderCoordinate
            coordinator.lastKnownTarget = riderCoordinate
            coordinator.lastKnownTimestamp = riderLocation.timestamp

            GoogleMapsViewRepresentable.fitCamera(
                uiView,
                home: homeCoordinate,
                rider: riderCoordinate,
                remainingPolyline: polylineCoordinates
            )
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

    // MARK: - Dynamic camera framing

    private static let cameraFitPadding: CGFloat = 80

    /// Fits the camera to a bounding box around home, the rider, and
    /// whatever route remains ahead — shrinks (zooms in) as the rider
    /// approaches, since `remainingPolyline` shrinks too.
    private static func fitCamera(
        _ uiView: GMSMapView,
        home: CLLocationCoordinate2D,
        rider: CLLocationCoordinate2D,
        remainingPolyline: [CLLocationCoordinate2D]
    ) {
        var bounds = GMSCoordinateBounds(coordinate: home, coordinate: rider)
        for coordinate in remainingPolyline {
            bounds = bounds.includingCoordinate(coordinate)
        }
        uiView.animate(with: .fit(bounds, withPadding: cameraFitPadding))
    }

    /// The portion of the route from `coordinate`'s nearest snapped point
    /// onward — i.e. what's still ahead, not what's already been traveled.
    private static func remainingPolyline(
        from coordinate: CLLocationCoordinate2D,
        on polylineCoordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard let index = nearestPolylineIndex(to: coordinate, on: polylineCoordinates) else {
            return polylineCoordinates
        }
        return Array(polylineCoordinates[index...])
    }

    // MARK: - Route-snapped interpolation

    /// Index of the polyline vertex closest to `coordinate` — i.e. where a
    /// raw GPS ping actually corresponds to on the known route.
    private static func nearestPolylineIndex(
        to coordinate: CLLocationCoordinate2D,
        on polylineCoordinates: [CLLocationCoordinate2D]
    ) -> Int? {
        guard !polylineCoordinates.isEmpty else { return nil }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        var closestIndex = 0
        var closestDistance = Double.greatestFiniteMagnitude

        for (index, point) in polylineCoordinates.enumerated() {
            let pointLocation = CLLocation(latitude: point.latitude, longitude: point.longitude)
            let distance = target.distance(from: pointLocation)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }
        return closestIndex
    }

    /// The ordered slice of the route between two snapped points — this is
    /// what makes the marker follow the road (U-turns included) instead of
    /// cutting a straight line between two sparse GPS pings.
    private static func subPath(
        from startIndex: Int,
        to endIndex: Int,
        on polylineCoordinates: [CLLocationCoordinate2D]
    ) -> [CLLocationCoordinate2D] {
        guard endIndex >= startIndex else {
            // GPS noise put the new point "behind" the old one on the route —
            // no reliable path segment, just go direct between the two raw points.
            return [polylineCoordinates[startIndex], polylineCoordinates[endIndex]]
        }
        return Array(polylineCoordinates[startIndex...endIndex])
    }

    /// Splits a fixed total duration across a multi-point path's segments,
    /// proportional to each segment's real-world length, so the marker moves
    /// at roughly constant speed instead of lurching on short segments.
    private static func segmentDurations(
        for path: [CLLocationCoordinate2D],
        totalDuration: TimeInterval
    ) -> [TimeInterval] {
        guard path.count > 1 else { return [] }

        var segmentLengths: [Double] = []
        for i in 0..<(path.count - 1) {
            let from = CLLocation(latitude: path[i].latitude, longitude: path[i].longitude)
            let to = CLLocation(latitude: path[i + 1].latitude, longitude: path[i + 1].longitude)
            segmentLengths.append(from.distance(from: to))
        }

        let totalLength = segmentLengths.reduce(0, +)
        guard totalLength > 0 else {
            return Array(repeating: totalDuration / Double(segmentLengths.count), count: segmentLengths.count)
        }
        return segmentLengths.map { totalDuration * ($0 / totalLength) }
    }

    /// Initial compass bearing (0 = north, clockwise) from one coordinate to
    /// another — standard great-circle forward-azimuth formula.
    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDegrees {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLng = (end.longitude - start.longitude) * .pi / 180

        let y = sin(deltaLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng)
        let radians = atan2(y, x)
        let degrees = radians * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Animates the marker through every point in `path` in sequence, one
    /// CATransaction per segment — CATransaction only animates a single
    /// position change, so a multi-point path needs to chain several,
    /// advancing to the next segment from each one's completion block.
    /// Also rotates the marker to face each segment's direction, and trims
    /// the route overlay down to what's still ahead as each segment completes.
    private static func animateMarker(
        _ marker: GMSMarker,
        along path: [CLLocationCoordinate2D],
        fullPolyline: [CLLocationCoordinate2D],
        startIndexInFullPolyline: Int,
        routeOverlay: GMSPolyline?,
        durations: [TimeInterval],
        segmentIndex: Int = 0,
        completion: @escaping () -> Void
    ) {
        guard segmentIndex < durations.count else {
            completion()
            return
        }

        // Marker art is authored facing east (right), not north — bearing is
        // measured from north, so the icon needs a -90 correction to match.
        let heading = bearing(from: path[segmentIndex], to: path[segmentIndex + 1])

        CATransaction.begin()
        CATransaction.setAnimationDuration(durations[segmentIndex])
        CATransaction.setCompletionBlock {
            animateMarker(
                marker,
                along: path,
                fullPolyline: fullPolyline,
                startIndexInFullPolyline: startIndexInFullPolyline,
                routeOverlay: routeOverlay,
                durations: durations,
                segmentIndex: segmentIndex + 1,
                completion: completion
            )
        }
        marker.position = path[segmentIndex + 1]
        marker.rotation = heading - 90
        CATransaction.commit()

        let traveledIndex = startIndexInFullPolyline + segmentIndex + 1
        if traveledIndex < fullPolyline.count {
            let remainingPath = GMSMutablePath()
            for coordinate in fullPolyline[traveledIndex...] {
                remainingPath.add(coordinate)
            }
            routeOverlay?.path = remainingPath
        }
    }

    /// Animation duration is derived from the real gap between rider update
    /// timestamps, clamped to sane bounds — an unclamped gap could be ~0
    /// (near-instant snap) or very large (e.g. after a long silence).
    private static let minAnimationDuration: TimeInterval = 0.3
    private static let maxAnimationDuration: TimeInterval = 3.0

    /// Orchestrates one rider update: snap start/end onto the current route,
    /// slice the path between them, animate through it, then either idle or
    /// pick up whatever arrived while this animation was running.
    private static func startAnimation(
        to targetCoordinate: CLLocationCoordinate2D,
        at targetTimestamp: Date,
        previousTimestamp: Date?,
        on polylineCoordinates: [CLLocationCoordinate2D],
        marker: GMSMarker,
        routeOverlay: GMSPolyline?,
        coordinator: MapCoordinator,
        uiView: GMSMapView
    ) {
        guard !polylineCoordinates.isEmpty else {
            marker.position = targetCoordinate
            coordinator.currentDisplayCoordinate = targetCoordinate
            return
        }

        let startCoordinate = coordinator.currentDisplayCoordinate ?? targetCoordinate
        let startIndex = nearestPolylineIndex(to: startCoordinate, on: polylineCoordinates) ?? 0
        let endIndex = nearestPolylineIndex(to: targetCoordinate, on: polylineCoordinates) ?? 0
        let path = subPath(from: startIndex, to: endIndex, on: polylineCoordinates)

        guard path.count > 1 else {
            marker.position = targetCoordinate
            coordinator.currentDisplayCoordinate = targetCoordinate
            return
        }

        let rawGap = previousTimestamp.map { targetTimestamp.timeIntervalSince($0) } ?? 1.0
        let totalDuration = min(max(rawGap, minAnimationDuration), maxAnimationDuration)
        let durations = segmentDurations(for: path, totalDuration: totalDuration)
        coordinator.isAnimating = true

        animateMarker(
            marker,
            along: path,
            fullPolyline: polylineCoordinates,
            startIndexInFullPolyline: startIndex,
            routeOverlay: routeOverlay,
            durations: durations
        ) {
            coordinator.isAnimating = false
            coordinator.currentDisplayCoordinate = targetCoordinate

            if let pending = coordinator.pendingTargetCoordinate,
               let pendingTimestamp = coordinator.pendingTargetTimestamp {
                coordinator.pendingTargetCoordinate = nil
                coordinator.pendingTargetTimestamp = nil
                startAnimation(
                    to: pending,
                    at: pendingTimestamp,
                    previousTimestamp: targetTimestamp,
                    on: polylineCoordinates,
                    marker: marker,
                    routeOverlay: routeOverlay,
                    coordinator: coordinator,
                    uiView: uiView
                )
            }
        }
    }
}
