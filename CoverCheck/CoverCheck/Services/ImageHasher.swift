import Foundation
import AppKit
import CoreGraphics

enum ImageHasher {
    static let hashSize = 16

    /// Average hash (aHash) as a hex string. Robust enough for album-art matching.
    static func averageHash(from data: Data) -> String? {
        guard let image = NSImage(data: data) else { return nil }
        return averageHash(from: image)
    }

    static func averageHash(from image: NSImage) -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return averageHash(from: cgImage)
    }

    static func averageHash(from cgImage: CGImage) -> String? {
        let width = hashSize
        let height = hashSize
        let bytesPerPixel = 1
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let average = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var bits = [Bool]()
        bits.reserveCapacity(pixels.count)
        for value in pixels {
            bits.append(Int(value) >= average)
        }

        return bitStringToHex(bits)
    }

    /// Hamming similarity in 0...1 (1 = identical hashes).
    static func similarity(_ left: String, _ right: String) -> Double {
        let leftBits = hexToBits(left)
        let rightBits = hexToBits(right)
        guard !leftBits.isEmpty, leftBits.count == rightBits.count else { return 0 }

        var matches = 0
        for index in leftBits.indices where leftBits[index] == rightBits[index] {
            matches += 1
        }
        return Double(matches) / Double(leftBits.count)
    }

    static func areSimilar(_ left: String?, _ right: String?, threshold: Double = 0.90) -> Bool {
        guard let left, let right else { return false }
        return similarity(left, right) >= threshold
    }

    // MARK: - Helpers

    private static func bitStringToHex(_ bits: [Bool]) -> String {
        var hex = ""
        var index = 0
        while index < bits.count {
            var nibble = 0
            for shift in 0..<4 {
                if index + shift < bits.count, bits[index + shift] {
                    nibble |= 1 << (3 - shift)
                }
            }
            hex.append(String(nibble, radix: 16))
            index += 4
        }
        return hex
    }

    private static func hexToBits(_ hex: String) -> [Bool] {
        var bits = [Bool]()
        bits.reserveCapacity(hex.count * 4)
        for character in hex.lowercased() {
            guard let value = Int(String(character), radix: 16) else { continue }
            for shift in stride(from: 3, through: 0, by: -1) {
                bits.append(((value >> shift) & 1) == 1)
            }
        }
        return bits
    }
}
