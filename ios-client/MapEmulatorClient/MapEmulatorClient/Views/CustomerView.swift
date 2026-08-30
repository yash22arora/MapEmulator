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
    let topic: String

    private var etaMinutes: Int? {
        guard let seconds = viewModel.route?.expectedTravelTime else { return nil }
        return max(1, Int((seconds / 60).rounded()))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            GoogleMapsViewRepresentable(
                riderLocation: viewModel.riderLocation,
                homeCoordinate: viewModel.homeCoordinate.coordinate,
                restaurantCoordinate: viewModel.restaurantCoordinate.coordinate,
                status: viewModel.status,
                route: viewModel.route
            )
                .ignoresSafeArea()

            DeliveryStatusCard(status: viewModel.status, etaMinutes: etaMinutes)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .navigationTitle("Order #\(topic)")
        .navigationSubtitle("Pizza Bakery")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // TODO: wire up order options (help, cancel, etc.)
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .task {
            await viewModel.startFetchingRiderLocation(topic: topic)
        }
        .onChange(of: viewModel.riderLocation) {
            refreshRoute()
        }
        .onChange(of: viewModel.status) {
            // Status flips (e.g. riderReachingRestaurant -> riderPickedOrder)
            // swap the routing destination even when the rider's raw
            // coordinate hasn't moved -- without this, the switch to the
            // home-bound route would only land on the *next* location ping.
            refreshRoute()
        }
    }

    private func refreshRoute() {
        if let routeTask = routeTask {
            routeTask.cancel()
        }
        routeTask = Task {
            await viewModel.requestMapRoute()
        }
    }
}

/// ETA is computed from the live route (MKRoute.expectedTravelTime) — real
/// data. The rider avatar, call button, and delivery-instructions row are
/// visual only; there's no rider identity or instructions backend in this
/// emulator, so they're not wired to anything.
private struct DeliveryStatusCard: View {
    let status: StatusType
    let etaMinutes: Int?

    var body: some View {
        Group {
            if status == .delivered {
                deliveredContent
            } else {
                inProgressContent
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .animation(.default, value: status)
    }

    private var deliveredContent: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Order Delivered")
                    .font(.title3.bold())
                Text("Enjoy your order!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var title: String {
        switch status {
        case .pendingConfirmation: return "Order Placed"
        case .restaurantPreparingOrder: return "Preparing your order"
        case .riderReachingRestaurant: return "Rider heading to restaurant"
        case .riderPickedOrder: return "Out for delivery"
        case .delivered: return ""
        }
    }

    private var subtitle: String {
        switch status {
        case .pendingConfirmation: return "Waiting for the restaurant to confirm"
        case .restaurantPreparingOrder: return "The restaurant is preparing your order"
        case .riderReachingRestaurant: return "Your rider is heading to the restaurant"
        case .riderPickedOrder: return "Your rider is on the way"
        case .delivered: return ""
        }
    }

    /// No rider to call/message before one's actually been dispatched.
    private var showsRiderContact: Bool {
        status == .riderReachingRestaurant || status == .riderPickedOrder
    }

    private var inProgressContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let etaMinutes {
                    VStack(spacing: 0) {
                        Text("\(etaMinutes)")
                            .font(.title2.bold())
                        Text(etaMinutes == 1 ? "min" : "mins")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(minWidth: 52)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.green, in: RoundedRectangle(cornerRadius: 12))
                }
            }

            Divider()

            HStack {
                Label("Add delivery instructions", systemImage: "plus.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if showsRiderContact {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.orange)

                        Image(systemName: "phone.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .padding(10)
                            .background(.orange.opacity(0.15), in: .circle)
                    }
                }
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
