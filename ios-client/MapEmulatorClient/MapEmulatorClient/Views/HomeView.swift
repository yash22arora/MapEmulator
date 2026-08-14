//
//  HomeView.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 03/07/26.
//
import SwiftUI

enum Destination: Hashable {
    case rider(topic: String)
    case customer(topic: String)
}

struct HomeView: View {
    @State private var path = NavigationPath()
    @State private var topic : String = ""
    var body: some View {
        NavigationStack {
            
            TextField(text: $topic, label: {
                Text("Enter topic (order ID):")
            })
            
            Button {
                guard !topic.isEmpty else { return }
                path.append(Destination.rider(topic: topic))
            } label: {
                Text("Enter as Rider")
                    .foregroundStyle(.foreground)
                    .font(.title3)
            }
            Button {
                guard !topic.isEmpty else { return }
                path.append(Destination.customer(topic: topic))
            } label: {
                Text("Enter as Customer")
                    .foregroundStyle(.foreground)
                    .font(.title3)
            }
        }
        .navigationTitle("Home")
        .navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .customer(let topic):
                CustomerView(topic: topic)
            case .rider(let topic):
                RiderView(topic: topic)
            }
        }
    }
}


#Preview {
    HomeView()
}
