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

enum EventType: String {
    case location
    case status
    case completed
}

/// The stream now carries two different kinds of value -- a location
/// update, or a non-terminal status change -- since both flow through the
/// same SSE connection as of Phase 15. `completed` stays out of this enum
/// deliberately: it's terminal (the stream itself ends), so it's still
/// expressed by throwing StreamCompletedIntentionally, not by yielding a
/// value.
enum StreamEvent {
    case location(LocationUpdate)
    case statusChanged(StatusType)
}

private struct StatusPayload: Decodable {
    let status: StatusType
}

struct StreamCompletedIntentionally: Error {}

protocol LiveViewDataManaging {
    func startStreaming(topic: String) -> AsyncThrowingStream<StreamEvent, Error>
    func sendLocationUpdate(payload: LocationUpdate) async throws
}

class LiveViewDataManager: LiveViewDataManaging {
    func startStreaming(topic: String) -> AsyncThrowingStream<StreamEvent, Error> {
        let retryLimit = 4
        let baseBackoffNanoseconds: UInt64 = 500_000_000

        return AsyncThrowingStream { continuation in
            Task {
                var currentRetryCount = 0
                var lastEventName: String = ""

                while true {
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
                            throw URLError(.badServerResponse)
                        }

                        // A successful connect means the backend is reachable again --
                        // reset backoff so the *next* disconnect starts fresh, not
                        // wherever the previous run of failures left off.
                        currentRetryCount = 0

                        for try await line in bytes.lines {

                            if line.hasPrefix("event: ") {
                                let eventName = line.trimmingPrefix("event: ")
                                lastEventName = eventName.lowercased()
                            }

                            if line.hasPrefix("data: ") {
                                let payload = line.trimmingPrefix("data: ")
                                let currentEventName = lastEventName
                                lastEventName = ""

                                switch currentEventName {
                                case EventType.completed.rawValue:
                                    throw StreamCompletedIntentionally()
                                case EventType.status.rawValue:
                                    let decoder = JSONDecoder()
                                    let statusPayload = try decoder.decode(StatusPayload.self, from: Data(payload.utf8))
                                    continuation.yield(.statusChanged(statusPayload.status))
                                default:
                                    let decoder = JSONDecoder()
                                    let update = try decoder.decode(LocationUpdate.self, from: Data(payload.utf8))
                                    continuation.yield(.location(update))
                                }
                            }
                        }

                        // Reading loop ended without throwing -- the server closed
                        // cleanly. Treated the same as a dropped connection: fall
                        // through and retry, not a final success.
                    } catch {
                        if error is StreamCompletedIntentionally {
                            // Deliberate ending of stream by server (marked delivered) --
                            // the consumer infers this from the loop ending with no
                            // error, same as any other clean AsyncThrowingStream finish.
                            continuation.finish()
                            return
                        }

                        if error is CancellationError || Task.isCancelled {
                            continuation.finish() // Consumer went away -- stop, don't retry.
                            return
                        }

                        guard currentRetryCount < retryLimit else {
                            continuation.finish(throwing: error)
                            return
                        }

                        currentRetryCount += 1
                        print("[LiveViewDataManager] Exponential Backoff #\(currentRetryCount)")
                        let delay = baseBackoffNanoseconds * UInt64(1 << currentRetryCount) // true exponential: 2^n
                        try? await Task.sleep(nanoseconds: delay)
                    }
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
