//
//  HomeView.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 03/07/26.
//
import SwiftUI

struct HomeView: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack {
            Button {
                path.append("track")
            } label: {
                Text("Track your ride live")
                    .foregroundStyle(.foreground)
                    .font(.title3)
            }
        }
        .navigationTitle("Home")
        .navigationDestination(for: String.self) { value in
            if value == "track" {
                LiveView()
            }
        }
    }
}


#Preview {
    HomeView()
}
