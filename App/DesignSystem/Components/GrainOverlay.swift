import SwiftUI
import CoreGraphics

/// §8.5 GrainOverlay (internal, used only inside `NightCanvas`): a 256×256 monochrome noise image generated
/// once with CoreGraphics (fixed seed 42), tiled, at opacity 0.08. Decorative, so hidden from VoiceOver.
struct GrainOverlay: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = GrainTexture.image {
            Image(decorative: image, scale: displayScale)
                .resizable(resizingMode: .tile)
                .interpolation(.none)
                .opacity(GrainTexture.opacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private enum GrainTexture {
    static let side = 256
    static let seed: UInt64 = 42
    static let opacity: Double = 0.08

    /// Built on first use, then cached for the life of the process.
    static let image: CGImage? = make()

    private static func make() -> CGImage? {
        let side = GrainTexture.side
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let base = context.data else {
            return nil
        }
        let pixels = base.bindMemory(to: UInt8.self, capacity: side * side)
        var generator = GrainGenerator(state: GrainTexture.seed)
        for index in 0..<(side * side) {
            pixels[index] = UInt8(truncatingIfNeeded: generator.next() >> 56)
        }
        return context.makeImage()
    }
}

/// SplitMix64: tiny deterministic generator so the grain is identical on every launch.
private struct GrainGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
