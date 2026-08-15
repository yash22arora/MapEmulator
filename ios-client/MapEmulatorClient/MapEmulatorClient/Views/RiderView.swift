//
//  RiderView.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//

import SwiftUI
import MapKit

struct RiderView: View {
    @State private var viewModel = LiveViewViewModel()
    let topic : String

    var body: some View {
        VStack(alignment: .leading) {
            MapReader { proxy in
                Map {
                    /// Can add annotations for current location
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .onTapGesture {
                    
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
