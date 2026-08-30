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

extension ShapeStyle where Self == Color {
    /// Lets `.brandRed` dot-shorthand resolve in ShapeStyle-generic
    /// contexts (e.g. `.foregroundStyle(.brandRed)`), the same way
    /// SwiftUI's built-in colors (`.orange`, etc.) do -- a plain
    /// `static let` on `Color` alone only resolves in contexts that are
    /// concretely typed as `Color`.
    static var brandRed: Color { Color.brandRed }
}

extension UIColor {
    /// App accent red -- #E2182D. Same value as `Color.brandRed`, for
    /// UIKit-facing APIs (e.g. GMSPolyline.strokeColor) that don't accept
    /// SwiftUI's `Color`.
    static let brandRed = UIColor(red: 226 / 255, green: 24 / 255, blue: 45 / 255, alpha: 1)
}
