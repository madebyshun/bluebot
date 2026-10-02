import SwiftUI
import CoreGraphics

// MARK: - Blue Agent brand
//
// BlueBot is built on Blue Agent, so it wears Blue Agent's identity:
//   • the mark — a rounded square with two tall pill eyes set a little above
//     centre (blueagent-logo.svg: 530 × 530 body, ~24 % corner radius, eyes
//     75 × 152 at ±75 from centre, 37 above it);
//   • the mark's fill — a cyan glow (#34E9FE) at the centre falling to deep
//     blue (#0A00FF) at the edges, through #2C73FF;
//   • the app palette — #050508 background, #0D0D14 surface, #1A1A2E border,
//     #4FC3F7 accent (apps/web globals.css).
// Every colour the character or the chrome uses for "Blue Agent" comes from
// here, so the two never drift.

enum BlueAgentBrand {
    // Mark fill
    static let glow    = CGColor(red: 0x34/255, green: 0xE9/255, blue: 0xFE/255, alpha: 1)  // #34E9FE
    static let mid     = CGColor(red: 0x2C/255, green: 0x73/255, blue: 0xFF/255, alpha: 1)  // #2C73FF
    static let deep    = CGColor(red: 0x0A/255, green: 0x00/255, blue: 0xFF/255, alpha: 1)  // #0A00FF
    // App palette
    static let bg      = CGColor(red: 0x05/255, green: 0x05/255, blue: 0x08/255, alpha: 1)  // #050508
    static let surface = CGColor(red: 0x0D/255, green: 0x0D/255, blue: 0x14/255, alpha: 1)  // #0D0D14
    static let border  = CGColor(red: 0x1A/255, green: 0x1A/255, blue: 0x2E/255, alpha: 1)  // #1A1A2E
    static let accent  = CGColor(red: 0x4F/255, green: 0xC3/255, blue: 0xF7/255, alpha: 1)  // #4FC3F7

    /// Superellipse exponent that matches the mark's rounded square.
    static let bodyExponent: CGFloat = 4.6
    /// Body half-width / half-height in units of R (the mark is square).
    static let bodyRX: CGFloat = 1.04
    static let bodyRY: CGFloat = 1.0

    /// The mark's fill as a SwiftUI shading: glow centre, deep-blue rim.
    static func bodyShading(center: CGPoint, radius: CGFloat) -> GraphicsContext.Shading {
        .radialGradient(
            Gradient(stops: [
                .init(color: Color(cgColor: glow), location: 0),
                .init(color: Color(cgColor: mid), location: 0.55),
                .init(color: Color(cgColor: deep), location: 1),
            ]),
            center: center, startRadius: 0, endRadius: radius)
    }

    /// The same fill for CoreGraphics (greeting canvas). Caller clips first.
    static func fillBody(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let g = CGGradient(colorsSpace: cs, colors: [glow, mid, deep] as CFArray, locations: [0, 0.55, 1]) else { return }
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                               options: [.drawsAfterEndLocation])
    }
}
