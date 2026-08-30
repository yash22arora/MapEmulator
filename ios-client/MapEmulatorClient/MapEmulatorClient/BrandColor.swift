//
//  BrandColor.swift
//  MapEmulatorClient
//

import SwiftUI
import UIKit

extension Color {
    /// App accent red -- #E2182D.
    static let brandRed = Color(red: 226 / 255, green: 24 / 255, blue: 45 / 255)
}

extension UIColor {
    /// App accent red -- #E2182D. Same value as `Color.brandRed`, for
    /// UIKit-facing APIs (e.g. GMSPolyline.strokeColor) that don't accept
    /// SwiftUI's `Color`.
    static let brandRed = UIColor(red: 226 / 255, green: 24 / 255, blue: 45 / 255, alpha: 1)
}
