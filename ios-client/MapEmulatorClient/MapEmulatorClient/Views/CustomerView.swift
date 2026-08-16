//
//  CustomerView.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//

import SwiftUI
import MapKit

struct CustomerView: View {
    @State private var viewModel = LiveViewViewModel()
    @State private var routeTask: Task<Void, Never>?
    let topic : String

    var body: some View {
        VStack(alignment: .leading) {
            GoogleMapsViewRepresentable(riderCoordinate: viewModel.riderLocation?.coordinate, homeCoordinate: viewModel.homeCoordinate.coordinate)
                .frame(height: 500)
        }
        .frame(alignment: .top)
        .navigationTitle("Track your Order #\(topic)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.startFetchingRiderLocation(topic: topic)
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
    CustomerView(topic: "1234")
}
