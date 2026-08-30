//
//  RiderView.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//

import SwiftUI
import MapKit

struct RiderView: View {
    @State private var viewModel = RiderViewModel()
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    // Local-only guess at which stage the topic is already at, same
    // caveat as the admin dashboard's currentStageIndex: there's no GET
    // endpoint to ask the backend what stage a topic is actually at.
    @State private var currentStageIndex = 0
    let topic : String

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map {
                    if let selectedCoordinate {
                        Annotation("Pickup", coordinate: selectedCoordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .onTapGesture { screenPoint in

                    if let coordinate = proxy.convert(screenPoint, from: .local) {
                        selectedCoordinate = coordinate
                        // ts is milliseconds since epoch, matching the Leaflet control UI's Date.now()
                        let payload = LocationUpdate(topic: topic, lat: coordinate.latitude, lng: coordinate.longitude, ts: Date().timeIntervalSince1970 * 1000)
                        Task {
                            await viewModel.sendLocationUpdate(location: payload)
                        }
                    }
                }
            }

            StatusStepBar(currentStageIndex: currentStageIndex) { index, status in
                Task {
                    if await viewModel.sendStatusUpdate(topic: topic, status: status) {
                        currentStageIndex = index
                    }
                }
            }
        }
        .navigationTitle("Delivering Order #\(topic)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Mirrors the admin dashboard's sequential status button bar: arrows
/// between steps, only the step right after `currentStageIndex` is
/// clickable, and completed/current/future get distinct styling instead
/// of just being uniformly grayed out.
private struct StatusStepBar: View {
    let currentStageIndex: Int
    let onSelect: (Int, StatusType) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(StatusType.allCases.enumerated()), id: \.offset) { index, status in
                    Button {
                        onSelect(index, status)
                    } label: {
                        Text(status.shortLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(backgroundStyle(for: index), in: Capsule())
                            .foregroundStyle(foregroundStyle(for: index))
                    }
                    .disabled(index != currentStageIndex + 1)

                    if status != StatusType.allCases.last {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    private func backgroundStyle(for index: Int) -> AnyShapeStyle {
        if index <= currentStageIndex {
            AnyShapeStyle(Color.green.opacity(0.15))
        } else if index == currentStageIndex + 1 {
            AnyShapeStyle(Color.brandRed)
        } else {
            AnyShapeStyle(Color(.systemGray5))
        }
    }

    private func foregroundStyle(for index: Int) -> Color {
        if index <= currentStageIndex {
            .green
        } else if index == currentStageIndex + 1 {
            .white
        } else {
            .secondary
        }
    }
}

#Preview {
    RiderView(topic: "1234")
}
