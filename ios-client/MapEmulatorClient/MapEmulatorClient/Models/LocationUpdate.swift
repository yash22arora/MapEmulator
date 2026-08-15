//
//  LocationModel.swift
//  MapEmulatorClient
//
//  Created by Yashvardhan Arora on 02/07/26.
//

struct LocationUpdate : Codable {
    let topic: String
    let lat: Double
    let lng: Double
    let ts: Double
}
