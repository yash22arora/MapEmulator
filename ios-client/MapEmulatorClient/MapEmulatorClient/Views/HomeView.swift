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
    @State private var topic: String = ""
    @FocusState private var isTopicFocused: Bool

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Spacer(minLength: 32)

                VStack(spacing: 14) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 84, height: 84)
                        .background(.blue.opacity(0.12), in: .circle)

                    Text("Map Emulator")
                        .font(.largeTitle.bold())

                    Text("Simulate live location tracking between a rider and a customer.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer(minLength: 44)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TOPIC")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.6)

                    TextField("e.g. order-1234", text: $topic)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
                        .focused($isTopicFocused)
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Text("Rider and customer must enter the same topic to connect.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 36)

                VStack(spacing: 12) {
                    Button {
                        isTopicFocused = false
                        guard !trimmedTopic.isEmpty else { return }
                        path.append(Destination.rider(topic: trimmedTopic))
                    } label: {
                        Label("Enter as Rider", systemImage: "car.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button {
                        isTopicFocused = false
                        guard !trimmedTopic.isEmpty else { return }
                        path.append(Destination.customer(topic: trimmedTopic))
                    } label: {
                        Label("Enter as Customer", systemImage: "location.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                .disabled(trimmedTopic.isEmpty)
                .padding(.horizontal, 24)

                Spacer(minLength: 32)
            }
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
}


#Preview {
    HomeView()
}
