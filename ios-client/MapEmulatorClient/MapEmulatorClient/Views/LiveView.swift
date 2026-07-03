//
//  LiveView.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//

import SwiftUI
import MapKit

struct LiveView: View {
    @State private var viewModel = LiveViewViewModel()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Map {
                    if let location = viewModel.currentLocation {
                        Annotation("Rider", coordinate: CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)) {
                            Image(systemName: "car.fill") // swap for a real cab/bike PNG later if you want
                                .font(.title)
                                .foregroundStyle(.blue)
                        }
                    }
                    
                }
                .mapStyle(.hybrid(elevation: .flat))
                .frame(height: 400)
                .task {
                    await viewModel.startFetchingRiderLocation()
                }
            }
            .navigationTitle("Live View")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    LiveView()
}
