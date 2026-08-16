//
//  LiveViewDataManager.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//
import Foundation

enum BackendConfig {
    // Swap this when ngrok's URL rotates (free tier issues a new one per session)
    // or back to "http://localhost:3000" when running against the Simulator.
    static let baseURL = "https://9f45-2401-4900-8813-1c3f-39d1-9a43-446-b583.ngrok-free.app"
}

protocol LiveViewDataManaging {
    func startStreaming(topic: String) -> AsyncThrowingStream<LocationUpdate, Error>
    func sendLocationUpdate(payload: LocationUpdate) async throws
}

class LiveViewDataManager: LiveViewDataManaging {
    func startStreaming(topic: String) -> AsyncThrowingStream<LocationUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard var components = URLComponents(
                        string: "\(BackendConfig.baseURL)/location/stream"
                    ) else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }
                    
                    components.queryItems = [
                        URLQueryItem(name: "topic", value: topic)
                    ]
                    
                    guard let endpointURL = components.url else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }

                    var request = URLRequest(url: endpointURL)
                    request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: URLError(.badServerResponse))
                        return
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let payload = line.trimmingPrefix("data: ")
                            let decoder = JSONDecoder()
                            let update = try decoder.decode(LocationUpdate.self, from: Data(payload.utf8))
                            continuation.yield(update)
                        }
                    }
                    
                    continuation.finish()
                }
                catch{
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func sendLocationUpdate(payload: LocationUpdate) async throws {
        guard let endpointURL = URL(string: "\(BackendConfig.baseURL)/location") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}
