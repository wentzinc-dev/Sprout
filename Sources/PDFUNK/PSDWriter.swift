import CoreGraphics
import Foundation

enum PSDWriter {
    static func write(
        rendered: RenderedPage,
        to url: URL,
        dpi: Int,
        pageNumber: Int
    ) throws {
        let width = rendered.image.width
        let height = rendered.image.height
        let channelCount = rendered.isCMYK ? 4 : 3
        var result = Data()

        result.appendASCII("8BPS")
        result.appendBE(UInt16(1))
        result.append(Data(repeating: 0, count: 6))
        result.appendBE(UInt16(channelCount))
        result.appendBE(UInt32(height))
        result.appendBE(UInt32(width))
        result.appendBE(UInt16(8))
        result.appendBE(UInt16(rendered.isCMYK ? 4 : 3))
        result.appendBE(UInt32(0))

        let resources = imageResources(colorSpace: rendered.colorSpace, dpi: dpi)
        result.appendBE(UInt32(resources.count))
        result.append(resources)
        result.appendBE(UInt32(0))
        result.appendBE(UInt16(0))

        rendered.pixels.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for channel in 0..<channelCount {
                for y in 0..<height {
                    let row = bytes + (y * rendered.bytesPerRow)
                    for x in 0..<width {
                        let value = row[(x * 4) + channel]
                        result.append(rendered.isCMYK ? 255 - value : value)
                    }
                }
            }
        }

        do {
            try result.write(to: url, options: .atomic)
        } catch {
            throw ConversionError.cannotEncodePage(pageNumber, .psd)
        }
    }

    private static func imageResources(colorSpace: CGColorSpace, dpi: Int) -> Data {
        var resources = Data()
        var resolution = Data()
        let fixedDPI = UInt32(dpi) << 16
        resolution.appendBE(fixedDPI)
        resolution.appendBE(UInt16(1))
        resolution.appendBE(UInt16(1))
        resolution.appendBE(fixedDPI)
        resolution.appendBE(UInt16(1))
        resolution.appendBE(UInt16(1))
        resources.appendResource(id: 1005, data: resolution)

        if let iccData = colorSpace.iccData as Data? {
            resources.appendResource(id: 1039, data: iccData)
        }
        return resources
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii)!)
    }

    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendResource(id: UInt16, data: Data) {
        appendASCII("8BIM")
        appendBE(id)
        append(0)
        append(0)
        appendBE(UInt32(data.count))
        append(data)
        if data.count.isMultiple(of: 2) == false { append(0) }
    }
}
