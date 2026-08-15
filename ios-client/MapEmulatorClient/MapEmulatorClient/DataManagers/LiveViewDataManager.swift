//
//  LiveViewDataManager.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//
import Foundation

protocol LiveViewDataManaging {
    func startStreaming() -> AsyncThrowingStream<LocationUpdate, Error>
}

class LiveViewDataManager: LiveViewDataManaging {
    func startStreaming() -> AsyncThrowingStream<LocationUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let endpointURL = URL(string: "http://localhost:3000/location/stream") else {
                        continuation.finish(throwing: URLError(.badURL))
                        return
                    }
                    
                    let (bytes, response) = try await URLSession.shared.bytes(from: endpointURL)
                    
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
}
