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

    /// The last riderCoordinate we actually reacted to — guards against
    /// re-triggering an animation when updateUIView fires for an unrelated
    /// reason (route recomputing) with the same rider position.
    var lastKnownTarget: CLLocationCoordinate2D?
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
        let coordinator = context.coordinator

        if let marker = coordinator.marker {
            let isNewTarget = coordinator.lastKnownTarget.map {
                $0.latitude != riderCoordinate.latitude || $0.longitude != riderCoordinate.longitude
            } ?? true

            if isNewTarget {
                coordinator.lastKnownTarget = riderCoordinate
                if coordinator.isAnimating {
                    // Let the in-flight animation finish; this becomes the next target.
                    coordinator.pendingTargetCoordinate = riderCoordinate
                } else {
                    GoogleMapsViewRepresentable.startAnimation(
                        to: riderCoordinate,
                        on: route?.polyline.coordinates ?? [],
                        marker: marker,
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
        }

        // Update route polyline on state update
        if let route {
            let path = GMSMutablePath()
            for coordinate in route.polyline.coordinates {
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

    /// Animates the marker through every point in `path` in sequence, one
    /// CATransaction per segment — CATransaction only animates a single
    /// position change, so a multi-point path needs to chain several,
    /// advancing to the next segment from each one's completion block.
    private static func animateMarker(
        _ marker: GMSMarker,
        along path: [CLLocationCoordinate2D],
        durations: [TimeInterval],
        segmentIndex: Int = 0,
        completion: @escaping () -> Void
    ) {
        guard segmentIndex < durations.count else {
            completion()
            return
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(durations[segmentIndex])
        CATransaction.setCompletionBlock {
            animateMarker(marker, along: path, durations: durations, segmentIndex: segmentIndex + 1, completion: completion)
        }
        marker.position = path[segmentIndex + 1]
        CATransaction.commit()
    }

    /// Orchestrates one rider update: snap start/end onto the current route,
    /// slice the path between them, animate through it, then either idle or
    /// pick up whatever arrived while this animation was running.
    private static func startAnimation(
        to targetCoordinate: CLLocationCoordinate2D,
        on polylineCoordinates: [CLLocationCoordinate2D],
        marker: GMSMarker,
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

        let durations = segmentDurations(for: path, totalDuration: 1.0)
        coordinator.isAnimating = true

        animateMarker(marker, along: path, durations: durations) {
            coordinator.isAnimating = false
            coordinator.currentDisplayCoordinate = targetCoordinate

            if let pending = coordinator.pendingTargetCoordinate {
                coordinator.pendingTargetCoordinate = nil
                startAnimation(to: pending, on: polylineCoordinates, marker: marker, coordinator: coordinator, uiView: uiView)
            }
        }
    }
}
