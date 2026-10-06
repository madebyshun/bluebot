import SwiftUI

// MARK: - Bot outfits
//
// Hats, glasses and costumes the main bot can wear (Account card → Outfit).
// Drawn with the body's transform (centre at 0,0, y up is negative, body top
// at -ry), in front of the body. Flat fills, like the bot's own flat body.
// Everything here is BlueBot's own drawing.

enum AccessoryLayer { case underEyes, overEyes }

extension BotEngine {

    func drawAccessory(context: GraphicsContext, layer: AccessoryLayer,
                       bodyPath: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        guard !isMini, accessory != .none, accessory != .seasonal else { return }
        // Fades out as the body morphs into the upload box
        let fade = max(0, 1 - morph * 4)
        guard fade > 0.01 else { return }
        var ctx = context
        ctx.opacity = Double(fade)

        // Hats sit on a round head: they follow the look a little
        var head = ctx
        head.translateBy(x: sin(yaw) * rx * 0.3, y: -sin(pitch) * ry * 0.08)

        switch (accessory, layer) {
        case (.pumpkin, .underEyes):  drawPumpkin(&ctx, bodyPath: bodyPath, R: R, rx: rx, ry: ry)
        case (.beanie, .overEyes):    drawBeanie(&head, R: R, rx: rx, ry: ry)
        case (.santaHat, .overEyes):  drawSantaHat(&head, R: R, rx: rx, ry: ry)
        case (.partyHat, .overEyes):  drawPartyHat(&head, R: R, ry: ry)
        case (.crown, .overEyes):     drawCrown(&head, R: R, ry: ry)
        case (.witchHat, .overEyes):  drawWitchHat(&head, R: R, ry: ry)
        case (.bow, .overEyes):       drawBow(&head, R: R, ry: ry)
        case (.sunglasses, .overEyes): drawGlasses(&ctx, R: R, rx: rx, ry: ry, dark: true)
        case (.glasses, .overEyes):   drawGlasses(&ctx, R: R, rx: rx, ry: ry, dark: false)
        case (.scarf, .overEyes):     drawScarf(&ctx, R: R, rx: rx, ry: ry)
        default: break
        }
    }

    // MARK: Hats

    private func drawBeanie(_ ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        let top = -ry
        var dome = Path()
        dome.move(to: CGPoint(x: -rx * 0.96, y: top + R * 0.30))
        dome.addCurve(to: CGPoint(x: 0, y: top - R * 0.42),
                      control1: CGPoint(x: -rx * 1.0, y: top - R * 0.2),
                      control2: CGPoint(x: -rx * 0.55, y: top - R * 0.42))
        dome.addCurve(to: CGPoint(x: rx * 0.96, y: top + R * 0.30),
                      control1: CGPoint(x: rx * 0.55, y: top - R * 0.42),
                      control2: CGPoint(x: rx * 1.0, y: top - R * 0.2))
        dome.closeSubpath()
        ctx.fill(dome, with: .color(Color(hex: "#F57A55")))

        // Knit ribs fanning from the crown
        var ribs = ctx
        ribs.clip(to: dome)
        for i in -3...3 {
            let x = CGFloat(i) * rx * 0.27
            var rib = Path()
            rib.move(to: CGPoint(x: x * 0.35, y: top - R * 0.42))
            rib.addQuadCurve(to: CGPoint(x: x, y: top + R * 0.3), control: CGPoint(x: x * 0.95, y: top - R * 0.15))
            ribs.stroke(rib, with: .color(Color(hex: "#C9432B").opacity(0.55)),
                        style: StrokeStyle(lineWidth: R * 0.045, lineCap: .round))
        }

        // Folded cuff
        let cuff = Path(roundedRect: CGRect(x: -rx * 1.04, y: top + R * 0.12, width: rx * 2.08, height: R * 0.3),
                        cornerRadius: R * 0.13)
        ctx.fill(cuff, with: .color(Color(hex: "#F06A47")))
        var cuffRibs = ctx
        cuffRibs.clip(to: cuff)
        var x = -rx * 1.0
        while x < rx * 1.0 {
            var rib = Path()
            rib.move(to: CGPoint(x: x, y: top + R * 0.16))
            rib.addLine(to: CGPoint(x: x, y: top + R * 0.38))
            cuffRibs.stroke(rib, with: .color(Color(hex: "#C9432B").opacity(0.6)),
                            style: StrokeStyle(lineWidth: R * 0.04, lineCap: .round))
            x += R * 0.14
        }

        // Pom-pom
        let pr = R * 0.19
        let pc = CGPoint(x: 0, y: top - R * 0.46)
        ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                 with: .color(Color(hex: "#FFF6E6")))
    }

    private func drawSantaHat(_ ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        let top = -ry
        let tip = CGPoint(x: R * 1.1, y: top + R * 0.06)
        var cone = Path()
        cone.move(to: CGPoint(x: -rx * 0.94, y: top + R * 0.2))
        cone.addCurve(to: tip,
                      control1: CGPoint(x: -rx * 0.7, y: top - R * 0.75),
                      control2: CGPoint(x: R * 0.6, y: top - R * 0.8))
        cone.addQuadCurve(to: CGPoint(x: rx * 0.94, y: top + R * 0.2),
                          control: CGPoint(x: R * 0.8, y: top - R * 0.3))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(Color(hex: "#FF4B55")))

        let band = Path(roundedRect: CGRect(x: -rx * 1.05, y: top + R * 0.08, width: rx * 2.1, height: R * 0.32),
                        cornerRadius: R * 0.16)
        drawFur(&ctx, band, R: R)

        let pr = R * 0.17
        drawFur(&ctx, Path(ellipseIn: CGRect(x: tip.x - pr, y: tip.y - pr, width: pr * 2, height: pr * 2)), R: R)
    }

    private func drawFur(_ ctx: inout GraphicsContext, _ p: Path, R: CGFloat) {
        ctx.fill(p, with: .color(Color(hex: "#FAF7F2")))
    }

    private func drawPartyHat(_ ctx: inout GraphicsContext, R: CGFloat, ry: CGFloat) {
        var hat = ctx
        hat.translateBy(x: R * 0.14, y: -ry + R * 0.06)
        hat.rotate(by: .radians(0.18))
        let hw = R * 0.36, hh = R * 0.8
        var cone = Path()
        cone.move(to: CGPoint(x: -hw, y: 0))
        cone.addLine(to: CGPoint(x: 0, y: -hh))
        cone.addLine(to: CGPoint(x: hw, y: 0))
        cone.addQuadCurve(to: CGPoint(x: -hw, y: 0), control: CGPoint(x: 0, y: R * 0.1))
        cone.closeSubpath()
        hat.fill(cone, with: .color(Color(hex: "#FFE066")))

        // Diagonal stripes
        var stripes = hat
        stripes.clip(to: cone)
        var y = -hh
        while y < R * 0.2 {
            var s = Path()
            s.move(to: CGPoint(x: -hw * 1.2, y: y))
            s.addLine(to: CGPoint(x: hw * 1.2, y: y - R * 0.22))
            stripes.stroke(s, with: .color(Color(hex: "#FF5FA2")), lineWidth: R * 0.09)
            y += R * 0.24
        }

        // Pom on the tip
        for (dx, dy, r) in [(0.0, -0.86, 0.11), (-0.08, -0.8, 0.07), (0.08, -0.8, 0.07)] as [(CGFloat, CGFloat, CGFloat)] {
            let c = CGPoint(x: dx * R, y: dy * R)
            hat.fill(Path(ellipseIn: CGRect(x: c.x - r * R, y: c.y - r * R, width: r * R * 2, height: r * R * 2)),
                     with: .color(Color(hex: "#FF5FA2")))
        }
    }

    private func drawCrown(_ ctx: inout GraphicsContext, R: CGFloat, ry: CGFloat) {
        let base = -ry + R * 0.2
        let w = R * 0.66
        let xs: [CGFloat] = [-1, -0.5, 0, 0.5, 1]
        let ys: [CGFloat] = [-0.62, -0.28, -0.72, -0.28, -0.62]   // peaks and valleys above the base
        var crown = Path()
        crown.move(to: CGPoint(x: -w, y: base))
        for (x, y) in zip(xs, ys) { crown.addLine(to: CGPoint(x: x * w, y: base + y * R)) }
        crown.addLine(to: CGPoint(x: w, y: base))
        crown.closeSubpath()
        ctx.fill(crown, with: .color(Color(hex: "#F7C53D")))
        ctx.stroke(crown, with: .color(Color(hex: "#B5730C")),
                   style: StrokeStyle(lineWidth: R * 0.03, lineJoin: .round))

        // Band and gems
        var band = Path()
        band.move(to: CGPoint(x: -w, y: base - R * 0.16))
        band.addLine(to: CGPoint(x: w, y: base - R * 0.16))
        ctx.stroke(band, with: .color(Color(hex: "#B5730C").opacity(0.7)), lineWidth: R * 0.025)
        for (x, hex) in [(-0.55, "#FF4D6D"), (0.0, "#34E9FE"), (0.55, "#FF4D6D")] as [(CGFloat, String)] {
            let r = R * (x == 0 ? 0.07 : 0.055)
            let c = CGPoint(x: x * w, y: base - R * 0.08)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: hex)))
        }
        // Balls on the peaks
        for i in [0, 2, 4] {
            let r = R * 0.06
            let c = CGPoint(x: xs[i] * w, y: base + ys[i] * R)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: "#FFF1A8")))
        }
    }

    private func drawWitchHat(_ ctx: inout GraphicsContext, R: CGFloat, ry: CGFloat) {
        let base = -ry + R * 0.08
        let purple = Color(hex: "#6A48D8")

        // Brim
        let brim = Path(ellipseIn: CGRect(x: -R * 1.3, y: base - R * 0.13, width: R * 2.6, height: R * 0.3))
        ctx.fill(brim, with: .color(purple))

        // Cone with a tip that bends over to the right
        var cone = Path()
        cone.move(to: CGPoint(x: -R * 0.56, y: base))
        cone.addQuadCurve(to: CGPoint(x: -R * 0.08, y: base - R * 0.78), control: CGPoint(x: -R * 0.36, y: base - R * 0.42))
        cone.addQuadCurve(to: CGPoint(x: R * 0.62, y: base - R * 0.86), control: CGPoint(x: R * 0.22, y: base - R * 1.1))
        cone.addQuadCurve(to: CGPoint(x: R * 0.2, y: base - R * 0.62), control: CGPoint(x: R * 0.28, y: base - R * 0.84))
        cone.addQuadCurve(to: CGPoint(x: R * 0.56, y: base), control: CGPoint(x: R * 0.4, y: base - R * 0.3))
        cone.closeSubpath()
        ctx.fill(cone, with: .color(purple))

        // Band with a gold buckle
        var bandCtx = ctx
        bandCtx.clip(to: cone)
        bandCtx.fill(Path(CGRect(x: -R, y: base - R * 0.2, width: R * 2, height: R * 0.14)),
                     with: .color(Color(hex: "#FF9F1C")))
        let buckle = Path(roundedRect: CGRect(x: -R * 0.09, y: base - R * 0.22, width: R * 0.18, height: R * 0.18),
                          cornerRadius: R * 0.03)
        ctx.stroke(buckle, with: .color(Color(hex: "#FFE066")), lineWidth: R * 0.04)
    }

    private func drawBow(_ ctx: inout GraphicsContext, R: CGFloat, ry: CGFloat) {
        var bow = ctx
        bow.translateBy(x: R * 0.6, y: -ry + R * 0.06)
        bow.rotate(by: .radians(0.32))
        let pink = Color(hex: "#FF6FAE"), deep = Color(hex: "#E0468C")
        for sd in [-1.0, 1.0] as [CGFloat] {
            var loop = Path()
            loop.move(to: .zero)
            loop.addCurve(to: CGPoint(x: sd * R * 0.36, y: R * 0.12),
                          control1: CGPoint(x: sd * R * 0.12, y: -R * 0.24),
                          control2: CGPoint(x: sd * R * 0.4, y: -R * 0.2))
            loop.addCurve(to: .zero,
                          control1: CGPoint(x: sd * R * 0.32, y: R * 0.26),
                          control2: CGPoint(x: sd * R * 0.12, y: R * 0.18))
            bow.fill(loop, with: .color(pink))
            // Inner fold
            var fold = Path()
            fold.move(to: CGPoint(x: sd * R * 0.08, y: 0))
            fold.addQuadCurve(to: CGPoint(x: sd * R * 0.26, y: R * 0.04), control: CGPoint(x: sd * R * 0.18, y: -R * 0.08))
            bow.stroke(fold, with: .color(deep), style: StrokeStyle(lineWidth: R * 0.035, lineCap: .round))
        }
        let k = R * 0.075
        bow.fill(Path(roundedRect: CGRect(x: -k, y: -k, width: k * 2, height: k * 2), cornerRadius: k * 0.6), with: .color(deep))
    }

    // MARK: Face

    /// Eye centres and foreshortening, matching drawEyes (nil = turned away).
    private func eyeFrame(sd: CGFloat, rx: CGFloat, ry: CGFloat) -> (x: CGFloat, y: CGFloat, fx: CGFloat, fy: CGFloat)? {
        let eyeYaw = sd * MochiConst.eyeSp + yaw
        var eyePitch = MochiConst.eyeP + pitch + roll
        eyePitch = ((eyePitch + .pi).truncatingRemainder(dividingBy: .pi * 2) + .pi * 2).truncatingRemainder(dividingBy: .pi * 2) - .pi
        let cp = cos(eyePitch)
        guard cos(eyeYaw) * cp > 0.04 else { return nil }
        return (sin(eyeYaw) * cp * rx, -sin(eyePitch) * ry, max(0.18, cos(eyeYaw)), max(0.18, cp))
    }

    private func drawGlasses(_ ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat, dark: Bool) {
        var body = ctx
        body.clip(to: Path(CGRect(x: -rx * 1.02, y: -ry * 1.02, width: rx * 2.04, height: ry * 2.04)))
        let frameColor = Color(hex: dark ? "#0B0B12" : "#141420")
        let lw = R * (dark ? 0.05 : 0.055)
        let lensW = R * (dark ? 0.5 : 0.44), lensH = R * (dark ? 0.4 : 0.44)

        var lenses: [(CGPoint, CGFloat)] = []   // centre, half-width after foreshortening
        for sd in [-1.0, 1.0] as [CGFloat] {
            guard let e = eyeFrame(sd: sd, rx: rx, ry: ry) else { continue }
            let w = lensW * e.fx, h = lensH * e.fy
            let rect = CGRect(x: e.x - w / 2, y: e.y - h / 2, width: w, height: h)
            if dark {
                let lens = Path(roundedRect: rect, cornerRadius: min(w, h) * 0.38)
                body.fill(lens, with: .color(Color(hex: "#2A2A36")))
                body.stroke(lens, with: .color(frameColor), lineWidth: lw)
                var glint = Path()
                glint.move(to: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.62))
                glint.addLine(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h * 0.24))
                body.stroke(glint, with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: R * 0.035, lineCap: .round))
            } else {
                let lens = Path(ellipseIn: rect)
                body.fill(lens, with: .color(.white.opacity(0.16)))
                body.stroke(lens, with: .color(frameColor), lineWidth: lw)
            }
            lenses.append((CGPoint(x: e.x, y: e.y), w / 2))
        }
        guard !lenses.isEmpty else { return }

        // Bridge between the lenses, temples out to the sides of the head
        if lenses.count == 2 {
            let l = lenses[0], r = lenses[1]
            var bridge = Path()
            bridge.move(to: CGPoint(x: l.0.x + l.1, y: l.0.y - R * 0.04))
            bridge.addQuadCurve(to: CGPoint(x: r.0.x - r.1, y: r.0.y - R * 0.04),
                                control: CGPoint(x: (l.0.x + r.0.x) / 2, y: (l.0.y + r.0.y) / 2 - R * 0.1))
            body.stroke(bridge, with: .color(frameColor), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
        for (c, hw) in lenses {
            let side: CGFloat = c.x < sin(yaw) * rx ? -1 : 1
            var temple = Path()
            temple.move(to: CGPoint(x: c.x + side * hw, y: c.y - R * 0.06))
            temple.addLine(to: CGPoint(x: side * rx * 1.02, y: c.y - R * 0.1))
            body.stroke(temple, with: .color(frameColor), style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
        }
    }

    private func drawScarf(_ ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        let red = Color(hex: "#E8434B")
        let cream = Color(hex: "#FFF4E2")

        var band = Path()
        band.move(to: CGPoint(x: -rx * 1.07, y: R * 0.36))
        band.addQuadCurve(to: CGPoint(x: rx * 1.07, y: R * 0.36), control: CGPoint(x: 0, y: R * 0.52))
        band.addLine(to: CGPoint(x: rx * 1.07, y: R * 0.66))
        band.addQuadCurve(to: CGPoint(x: -rx * 1.07, y: R * 0.66), control: CGPoint(x: 0, y: R * 0.84))
        band.closeSubpath()
        ctx.fill(band, with: .color(red))
        var stripes = ctx
        stripes.clip(to: band)
        var x = -rx * 0.9
        while x < rx * 1.1 {
            stripes.fill(Path(CGRect(x: x, y: R * 0.3, width: R * 0.1, height: R * 0.6)), with: .color(cream))
            x += R * 0.4
        }

        // Hanging tail with fringe
        var tail = ctx
        tail.translateBy(x: R * 0.5, y: R * 0.62)
        tail.rotate(by: .radians(-0.12))
        let tw = R * 0.28, th = R * 0.5
        let tailRect = Path(roundedRect: CGRect(x: -tw / 2, y: 0, width: tw, height: th), cornerRadius: R * 0.05)
        tail.fill(tailRect, with: .color(red))
        var tailStripes = tail
        tailStripes.clip(to: tailRect)
        for y in [th * 0.3, th * 0.68] {
            tailStripes.fill(Path(CGRect(x: -tw, y: y, width: tw * 2, height: R * 0.08)), with: .color(cream))
        }
        for i in 0..<4 {
            let fx = -tw / 2 + tw * (CGFloat(i) + 0.5) / 4
            var f = Path()
            f.move(to: CGPoint(x: fx, y: th))
            f.addLine(to: CGPoint(x: fx, y: th + R * 0.1))
            tail.stroke(f, with: .color(Color(hex: "#C42A35")), style: StrokeStyle(lineWidth: R * 0.035, lineCap: .round))
        }
    }

    // MARK: Costume

    private func drawPumpkin(_ ctx: inout GraphicsContext, bodyPath: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        // Stem and leaf first so the body's top edge covers their base
        var stem = Path()
        stem.move(to: CGPoint(x: -R * 0.08, y: -ry + R * 0.06))
        stem.addQuadCurve(to: CGPoint(x: R * 0.02, y: -ry - R * 0.3), control: CGPoint(x: -R * 0.1, y: -ry - R * 0.2))
        stem.addQuadCurve(to: CGPoint(x: R * 0.16, y: -ry - R * 0.26), control: CGPoint(x: R * 0.1, y: -ry - R * 0.36))
        stem.addQuadCurve(to: CGPoint(x: R * 0.08, y: -ry + R * 0.06), control: CGPoint(x: R * 0.06, y: -ry - R * 0.12))
        stem.closeSubpath()
        ctx.fill(stem, with: .color(Color(hex: "#5E8C3A")))
        var leaf = ctx
        leaf.translateBy(x: -R * 0.24, y: -ry - R * 0.08)
        leaf.rotate(by: .radians(-0.5))
        leaf.fill(Path(ellipseIn: CGRect(x: -R * 0.16, y: -R * 0.07, width: R * 0.32, height: R * 0.14)),
                  with: .color(Color(hex: "#7DB24B")))

        var body = ctx
        body.clip(to: bodyPath)
        body.fill(bodyPath, with: .color(Color(hex: "#FF9A2E")))
        // Ribs
        for k in [-0.66, -0.24, 0.24, 0.66] as [CGFloat] {
            let x = k * rx
            var rib = Path()
            rib.move(to: CGPoint(x: x * 0.7, y: -ry))
            rib.addQuadCurve(to: CGPoint(x: x * 0.7, y: ry), control: CGPoint(x: x * 1.4, y: 0))
            body.stroke(rib, with: .color(Color(hex: "#B9441A").opacity(0.45)),
                        style: StrokeStyle(lineWidth: R * 0.05, lineCap: .round))
        }
    }
}
