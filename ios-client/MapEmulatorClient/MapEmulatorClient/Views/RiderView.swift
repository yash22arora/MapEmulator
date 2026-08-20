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
    let topic : String

    var body: some View {
        VStack(alignment: .leading) {
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
        }
        .navigationTitle("Delivering Order #\(topic)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    RiderView(topic: "1234")
}
