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
    /// The decorative curved line shown before a rider exists (no route to
    /// snap to yet) -- hidden the moment the real rider marker appears.
    var preDispatchLine: GMSPolyline?

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
    let restaurantCoordinate: CLLocationCoordinate2D
    let status: StatusType
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

        // Camera is fully programmatic (fitCamera) -- manual gestures would
        // just fight it, snapping back on the next update.
        uiView.settings.scrollGestures = false
        uiView.settings.zoomGestures = false

        // Translucent halo around home -- radius is real-world meters,
        // strokeWidth is screen points (matches the "2pt border" ask).
        let homeCircle = GMSCircle(position: homeCoordinate, radius: 100)
        homeCircle.fillColor = UIColor.systemGreen.withAlphaComponent(0.15)
        homeCircle.strokeColor = UIColor.systemGreen.withAlphaComponent(0.6)
        homeCircle.strokeWidth = 2
        homeCircle.map = uiView

        // Home Marker
        let homeMarker = GMSMarker(position: homeCoordinate)
        homeMarker.icon = UIImage(named: "home-marker").map {
            GoogleMapsViewRepresentable.resizedImage($0, to: CGSize(width: 50, height: 50))
        }
        homeMarker.groundAnchor = CGPoint(x: 0.5, y: 0.8)
        homeMarker.map = uiView

        // Restaurant Marker, with a small name label below the icon
        let restaurantMarker = GMSMarker(position: restaurantCoordinate)
        if let foodIcon = UIImage(named: "food-marker") {
            let resizedIcon = GoogleMapsViewRepresentable.resizedImage(foodIcon, to: CGSize(width: 50, height: 50))
            let labeled = GoogleMapsViewRepresentable.labeledMarkerImage(
                icon: resizedIcon,
                label: "Pizza Bakery",
                iconGroundAnchor: CGPoint(x: 0.5, y: 0.8)
            )
            restaurantMarker.icon = labeled.image
            restaurantMarker.groundAnchor = labeled.groundAnchor
        }
        restaurantMarker.map = uiView

        // Decorative curved line connecting restaurant to home, shown only
        // before a rider (and therefore a real road-snapped route) exists.
        // NOTE: this is a solid line, not dotted -- Google Maps' dashed-
        // polyline styling needs verifying against the actual SDK docs
        // rather than guessed at, so it's deliberately simplified for now.
        let curvePath = GoogleMapsViewRepresentable.curvedPath(from: restaurantCoordinate, to: homeCoordinate)
        let preDispatchLine = GMSPolyline(path: curvePath)
        preDispatchLine.strokeColor = UIColor.systemGray.withAlphaComponent(0.7)
        preDispatchLine.strokeWidth = 2
        preDispatchLine.map = uiView
        context.coordinator.preDispatchLine = preDispatchLine

        return uiView
    }

    /// Called at every state change - need to handle changes manually
    func updateUIView(_ uiView: GMSMapView, context: Context) {
        guard let riderLocation else {
            // No rider yet -- frame home+restaurant together. Doing this
            // here rather than in makeUIView because the map view still has
            // a .zero frame at construction time (SwiftUI hasn't laid it
            // out yet), and GMSCoordinateBounds.fit needs real bounds to
            // compute a meaningful zoom/center. updateUIView fires again
            // once layout has happened, so the fit lands correctly then.
            GoogleMapsViewRepresentable.fitCamera(
                uiView,
                home: homeCoordinate,
                restaurant: restaurantCoordinate,
                rider: nil,
                showAllMarkers: true,
                remainingPolyline: []
            )
            return
        }
        let coordinator = context.coordinator
        let riderCoordinate = riderLocation.coordinate
        let polylineCoordinates = route?.polyline.coordinates ?? []
        // Show all three markers until the rider is actually out for
        // delivery -- only then does the frame narrow to rider+home and
        // the decorative restaurant line stop being relevant.
        let showAllMarkers = status != .riderPickedOrder
        if status == .riderPickedOrder {
            coordinator.preDispatchLine?.map = nil
        }

        // Sync the route polyline first, so it's already current by the time
        // any animation below reads coordinator.polyline. Once `route` goes
        // back to nil (delivery complete -- see LiveViewViewModel), remove
        // whatever polyline was left on the map instead of leaving it stuck
        // at its last-drawn path.
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
        } else if let existingPolyline = coordinator.polyline {
            existingPolyline.map = nil
            coordinator.polyline = nil
        }

        if let marker = coordinator.marker {
            let isNewTarget = coordinator.lastKnownTarget.map {
                $0.latitude != riderCoordinate.latitude || $0.longitude != riderCoordinate.longitude
            } ?? true

            if isNewTarget {
                let previousTimestamp = coordinator.lastKnownTimestamp
                coordinator.lastKnownTarget = riderCoordinate
                coordinator.lastKnownTimestamp = riderLocation.timestamp

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
                        home: homeCoordinate,
                        restaurant: restaurantCoordinate,
                        showAllMarkers: showAllMarkers,
                        coordinator: coordinator,
                        uiView: uiView
                    )
                }
            }
            // else: this call was triggered by something else changing (e.g. route
            // recomputing) with the same rider coordinate — nothing new to animate to.
        } else {
            let marker = GMSMarker(position: riderCoordinate)
            marker.icon = UIImage(named: "rider-marker").map {
                GoogleMapsViewRepresentable.resizedImage($0, to: CGSize(width: 60, height: 60))
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
                restaurant: restaurantCoordinate,
                rider: riderCoordinate,
                showAllMarkers: showAllMarkers,
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

    /// Composites a small pill-shaped text label under a marker icon into a
    /// single image (GMSMarker has no separate "caption" API), and returns
    /// the groundAnchor that keeps the icon's own tip -- not the taller
    /// combined image -- pinned to the coordinate, same as before the label
    /// was added.
    private static func labeledMarkerImage(
        icon: UIImage,
        label: String,
        iconGroundAnchor: CGPoint
    ) -> (image: UIImage, groundAnchor: CGPoint) {
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let textSize = (label as NSString).size(withAttributes: attributes)

        let horizontalPadding: CGFloat = 6
        let verticalPadding: CGFloat = 3
        let spacing: CGFloat = 2
        let badgeSize = CGSize(width: textSize.width + horizontalPadding * 2, height: textSize.height + verticalPadding * 2)
        let totalSize = CGSize(width: max(icon.size.width, badgeSize.width), height: icon.size.height + spacing + badgeSize.height)

        let image = UIGraphicsImageRenderer(size: totalSize).image { _ in
            let iconOrigin = CGPoint(x: (totalSize.width - icon.size.width) / 2, y: 0)
            icon.draw(in: CGRect(origin: iconOrigin, size: icon.size))

            let badgeOrigin = CGPoint(x: (totalSize.width - badgeSize.width) / 2, y: icon.size.height + spacing)
            let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)
            UIColor.white.withAlphaComponent(0.95).setFill()
            UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeSize.height / 2).fill()

            let textOrigin = CGPoint(x: badgeOrigin.x + horizontalPadding, y: badgeOrigin.y + verticalPadding)
            (label as NSString).draw(at: textOrigin, withAttributes: attributes)
        }

        let anchorY = (icon.size.height * iconGroundAnchor.y) / totalSize.height
        return (image, CGPoint(x: 0.5, y: anchorY))
    }

    // MARK: - Dynamic camera framing

    // Bottom is significantly larger than the other edges -- the status
    // card overlays the bottom of the screen and was sometimes covering
    // a marker with the old uniform padding.
    private static let cameraFitInsets = UIEdgeInsets(top: 140, left: 60, bottom: 280, right: 60)

    /// Fits the camera to a bounding box around home, the rider (if one
    /// exists yet), and whatever route remains ahead. `showAllMarkers`
    /// additionally includes the restaurant -- true for every status
    /// except "out for delivery" (riderPickedOrder), where the restaurant
    /// is no longer relevant and the frame narrows to rider+home instead.
    private static func fitCamera(
        _ uiView: GMSMapView,
        home: CLLocationCoordinate2D,
        restaurant: CLLocationCoordinate2D,
        rider: CLLocationCoordinate2D?,
        showAllMarkers: Bool,
        remainingPolyline: [CLLocationCoordinate2D]
    ) {
        var bounds = GMSCoordinateBounds(coordinate: home, coordinate: home)
        if showAllMarkers {
            bounds = bounds.includingCoordinate(restaurant)
        }
        if let rider {
            bounds = bounds.includingCoordinate(rider)
        }
        for coordinate in remainingPolyline {
            bounds = bounds.includingCoordinate(coordinate)
        }
        uiView.animate(with: .fit(bounds, with: cameraFitInsets))
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

    /// Quadratic-Bezier-sampled path between two points, bowed out
    /// perpendicular to the straight line between them -- purely
    /// decorative, not a real route (there's no rider to snap a route to
    /// yet at the point this is shown).
    private static func curvedPath(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 24
    ) -> GMSMutablePath {
        let path = GMSMutablePath()

        let midLat = (start.latitude + end.latitude) / 2
        let midLng = (start.longitude + end.longitude) / 2
        let deltaLat = end.latitude - start.latitude
        let deltaLng = end.longitude - start.longitude
        let bowFactor = 0.15
        let controlLat = midLat - deltaLng * bowFactor
        let controlLng = midLng + deltaLat * bowFactor

        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let oneMinusT = 1 - t
            let lat = oneMinusT * oneMinusT * start.latitude
                + 2 * oneMinusT * t * controlLat
                + t * t * end.latitude
            let lng = oneMinusT * oneMinusT * start.longitude
                + 2 * oneMinusT * t * controlLng
                + t * t * end.longitude
            path.add(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }

        return path
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
        marker.rotation = heading
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
        home: CLLocationCoordinate2D,
        restaurant: CLLocationCoordinate2D,
        showAllMarkers: Bool,
        coordinator: MapCoordinator,
        uiView: GMSMapView
    ) {
        guard !polylineCoordinates.isEmpty else {
            marker.position = targetCoordinate
            coordinator.currentDisplayCoordinate = targetCoordinate
            fitCamera(uiView, home: home, restaurant: restaurant, rider: targetCoordinate, showAllMarkers: showAllMarkers, remainingPolyline: polylineCoordinates)
            return
        }

        let startCoordinate = coordinator.currentDisplayCoordinate ?? targetCoordinate
        let startIndex = nearestPolylineIndex(to: startCoordinate, on: polylineCoordinates) ?? 0
        let endIndex = nearestPolylineIndex(to: targetCoordinate, on: polylineCoordinates) ?? 0
        let path = subPath(from: startIndex, to: endIndex, on: polylineCoordinates)

        guard path.count > 1 else {
            marker.position = targetCoordinate
            coordinator.currentDisplayCoordinate = targetCoordinate
            fitCamera(
                uiView,
                home: home,
                restaurant: restaurant,
                rider: targetCoordinate,
                showAllMarkers: showAllMarkers,
                remainingPolyline: remainingPolyline(from: targetCoordinate, on: polylineCoordinates)
            )
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

            // Only re-fit the camera once the marker has actually arrived,
            // not the instant the update arrived — otherwise the bounds jump
            // ahead of the marker while it's still mid-animation, clipping
            // it out of view until it catches up.
            fitCamera(
                uiView,
                home: home,
                restaurant: restaurant,
                rider: targetCoordinate,
                showAllMarkers: showAllMarkers,
                remainingPolyline: remainingPolyline(from: targetCoordinate, on: polylineCoordinates)
            )

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
                    home: home,
                    restaurant: restaurant,
                    showAllMarkers: showAllMarkers,
                    coordinator: coordinator,
                    uiView: uiView
                )
            }
        }
    }
}
