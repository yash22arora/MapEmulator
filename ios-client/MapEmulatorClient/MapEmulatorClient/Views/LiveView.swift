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
    @State private var routeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading) {
            Map {
                if let route = viewModel.route {
                    MapPolyline(route.polyline)
                        .stroke(.orange, lineWidth: 4)
                }
                if let location = viewModel.riderLocation?.coordinate {
                    Annotation("Rider", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                        Image(systemName: "car.fill") // swap for a real cab/bike PNG later if you want
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                }
                Annotation("Home", coordinate: CLLocationCoordinate2D(location: .home)) {
                    Image(systemName: "house.fill")
                        .font(.title)
                        .foregroundStyle(.green)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
        }
        .navigationTitle("Live View")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.startFetchingRiderLocation()
        }
        .onChange(of: viewModel.riderLocation) {
            if let routeTask = routeTask {
                routeTask.cancel()
            }
            routeTask = Task {
                await viewModel.requestMapRoute()
            }
        }
    }
}

extension CLLocationCoordinate2D {
    init(location: CLLocation) {
        self.init()
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
    }
}

#Preview {
    LiveView()
}
