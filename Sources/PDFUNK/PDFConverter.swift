import AppKit
import CoreImage
import Foundation
import ImageIO
import PDFKit
import SDWebImage
import SDWebImageWebPCoder
import UniformTypeIdentifiers

enum ConversionError: LocalizedError {
    case cannotOpenFile(String, Bool)
    case cannotCreateOutput(String, Bool)
    case incompatibleOptions(String)
    case cannotRenderItem(Int, Bool)
    case cannotEncodeItem(Int, ExportFormat, Bool)

    var errorDescription: String? {
        switch self {
        case .cannotOpenFile(let name, let isJapanese):
            isJapanese ? "\(name)を開けませんでした。" : "Could not open \(name)."
        case .cannotCreateOutput(let path, let isJapanese):
            isJapanese
                ? "\(path)へ書き込めませんでした。保存先を「選択したフォルダ」に切り替えてください。"
                : "Could not write to \(path). Switch the destination to Selected folder."
        case .incompatibleOptions(let message): message
        case .cannotRenderItem(let item, let isJapanese):
            isJapanese
                ? "\(item)番目のページ／フレームを描画できませんでした。"
                : "Could not render page/frame \(item)."
        case .cannotEncodeItem(let item, let format, let isJapanese):
            isJapanese
                ? "\(item)番目のページ／フレームを\(format.displayName)に変換できませんでした。"
                : "Could not encode page/frame \(item) as \(format.displayName)."
        }
    }
}

struct RenderedPage {
    let image: CGImage
    let pixels: Data
    let bytesPerRow: Int
    let colorSpace: CGColorSpace
    let isCMYK: Bool
}

struct InputInspection: Sendable {
    var fileCount = 0
    var formatCounts: [String: Int] = [:]
    var pdfCount = 0
    var pdfPageCount = 0
    var psdCount = 0
    var gifCount = 0
    var outputImageCount = 0
    var upscaleImageCount = 0
    var hasMultiPagePDF = false
    var mayContainTransparency = false
}

final class OutputSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

enum InputInspector {
    static func inspect(urls: [URL], options: ExportOptions) -> InputInspection {
        var result = InputInspection()
        result.fileCount = urls.count
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let label: String = switch ext {
            case "jpg", "jpeg": "JPG"
            case "tif", "tiff": "TIFF"
            default: ext.uppercased()
            }
            result.formatCounts[label, default: 0] += 1
            if ["png", "gif", "webp", "tif", "tiff", "psd"].contains(ext) {
                result.mayContainTransparency = true
            }

            if ext == "pdf", let document = PDFDocument(url: url) {
                result.pdfCount += 1
                result.pdfPageCount += document.pageCount
                result.outputImageCount += document.pageCount
                result.hasMultiPagePDF = result.hasMultiPagePDF || document.pageCount > 1
                for index in 0..<document.pageCount {
                    guard let page = document.page(at: index) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    let scale = CGFloat(options.effectivePDFDPI) / 72
                    let width = max(1, Int((bounds.width * scale).rounded(.up)))
                    let height = max(1, Int((bounds.height * scale).rounded(.up)))
                    if options.scaleFactor(
                        width: width,
                        height: height,
                        sourceDPI: options.effectivePDFDPI
                    ) > 1.0001 {
                        result.upscaleImageCount += 1
                    }
                }
                continue
            }

            if ext == "psd" { result.psdCount += 1 }
            if ext == "gif" { result.gifCount += 1 }
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let count = ext == "gif" ? 1 : max(1, CGImageSourceGetCount(source))
                result.outputImageCount += count
                for index in 0..<count {
                    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                    let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue ?? 72
                    if options.scaleFactor(width: image.width, height: image.height, sourceDPI: dpi) > 1.0001 {
                        result.upscaleImageCount += 1
                    }
                }
            } else {
                result.outputImageCount += 1
                if let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   options.scaleFactor(width: image.width, height: image.height) > 1.0001 {
                    result.upscaleImageCount += 1
                }
            }
        }
        return result
    }
}

struct FileConverter {
    static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "pdf", "psd", "tif", "tiff", "gif", "webp"
    ]

    func convert(
        inputURL: URL,
        destinationURL: URL,
        options: ExportOptions,
        sequence: OutputSequence,
        isJapanese: Bool,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws {
        if let message = options.validationMessage(isJapanese: isJapanese) {
            throw ConversionError.incompatibleOptions(message)
        }

        if inputURL.pathExtension.lowercased() == "pdf" {
            try await convertPDF(
                inputURL,
                destinationURL: destinationURL,
                options: options,
                sequence: sequence,
                isJapanese: isJapanese,
                progress: progress
            )
        } else {
            try await convertImage(
                inputURL,
                destinationURL: destinationURL,
                options: options,
                sequence: sequence,
                isJapanese: isJapanese,
                progress: progress
            )
        }
    }

    private func convertPDF(
        _ url: URL,
        destinationURL: URL,
        options: ExportOptions,
        sequence: OutputSequence,
        isJapanese: Bool,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.cannotOpenFile(url.lastPathComponent, isJapanese)
        }

        let dpi = options.effectivePDFDPI
        let colorSpace = resolvePDFColorSpace(for: options.colorProfile, pdfURL: url)
        try validate(colorSpace: colorSpace, options: options, isJapanese: isJapanese)
        let outputFolder = try makeOutputFolder(for: url, in: destinationURL, isJapanese: isJapanese)

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw ConversionError.cannotRenderItem(index + 1, isJapanese)
            }
            let rasterized = try rasterizePDFPage(
                page,
                dpi: dpi,
                colorSpace: colorSpace,
                itemNumber: index + 1,
                isJapanese: isJapanese
            )
            let rendered = try resizeImage(
                rasterized.image,
                colorSpace: colorSpace,
                options: options,
                sourceDPI: dpi,
                itemNumber: index + 1,
                isJapanese: isJapanese
            )
            let outputURL = uniqueOutputURL(
                in: outputFolder,
                filename: OutputFilenameBuilder.filename(for: url, sequence: sequence.next(), format: options.format, options: options)
            )
            try write(
                rendered.image,
                to: outputURL,
                dpi: dpi,
                itemNumber: index + 1,
                isJapanese: isJapanese,
                options: options,
                sourceProperties: nil
            )
            preserveFileDatesIfNeeded(from: url, to: outputURL, options: options)
            await progress(index + 1, document.pageCount)
        }
    }

    private func convertImage(
        _ url: URL,
        destinationURL: URL,
        options: ExportOptions,
        sequence: OutputSequence,
        isJapanese: Bool,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws {
        let fallbackDPI = 72
        let outputFolder = try makeOutputFolder(for: url, in: destinationURL, isJapanese: isJapanese)

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let sourceCount = max(1, CGImageSourceGetCount(source))
            let count = url.pathExtension.lowercased() == "gif" ? 1 : sourceCount
            for index in 0..<count {
                guard let sourceImage = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                    throw ConversionError.cannotRenderItem(index + 1, isJapanese)
                }
                let colorSpace = resolveImageColorSpace(for: options.colorProfile, sourceImage: sourceImage)
                try validate(colorSpace: colorSpace, options: options, isJapanese: isJapanese)
                let inputDPI = imageDPI(source: source, index: index) ?? fallbackDPI
                let rendered = try resizeImage(
                    sourceImage,
                    colorSpace: colorSpace,
                    options: options,
                    sourceDPI: inputDPI,
                    itemNumber: index + 1,
                    isJapanese: isJapanese
                )
                let sourceDPI = options.saveSizeMode == .resolution
                    ? options.saveDPI
                    : inputDPI
                let outputURL = uniqueOutputURL(
                    in: outputFolder,
                    filename: OutputFilenameBuilder.filename(for: url, sequence: sequence.next(), format: options.format, options: options)
                )
                let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                try write(
                    rendered.image,
                    to: outputURL,
                    dpi: sourceDPI,
                    itemNumber: index + 1,
                    isJapanese: isJapanese,
                    options: options,
                    sourceProperties: sourceProperties
                )
                preserveFileDatesIfNeeded(from: url, to: outputURL, options: options)
                await progress(index + 1, count)
            }
            return
        }

        // AppKit can expose the flattened composite of PSD files even when
        // ImageIO does not advertise PSD as a source type.
        guard let nsImage = NSImage(contentsOf: url),
              let sourceImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConversionError.cannotOpenFile(url.lastPathComponent, isJapanese)
        }
        let colorSpace = resolveImageColorSpace(for: options.colorProfile, sourceImage: sourceImage)
        try validate(colorSpace: colorSpace, options: options, isJapanese: isJapanese)
        let rendered = try resizeImage(
            sourceImage,
            colorSpace: colorSpace,
            options: options,
            sourceDPI: fallbackDPI,
            itemNumber: 1,
            isJapanese: isJapanese
        )
        let outputURL = uniqueOutputURL(
            in: outputFolder,
            filename: OutputFilenameBuilder.filename(for: url, sequence: sequence.next(), format: options.format, options: options)
        )
        try write(
            rendered.image,
            to: outputURL,
            dpi: options.saveSizeMode == .resolution ? options.saveDPI : fallbackDPI,
            itemNumber: 1,
            isJapanese: isJapanese,
            options: options,
            sourceProperties: nil
        )
        preserveFileDatesIfNeeded(from: url, to: outputURL, options: options)
        await progress(1, 1)
    }

    private func makeOutputFolder(for inputURL: URL, in destinationURL: URL, isJapanese: Bool) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        } catch {
            throw ConversionError.cannotCreateOutput(destinationURL.path(percentEncoded: false), isJapanese)
        }
        return destinationURL
    }

    private func uniqueOutputURL(in folder: URL, filename: String) -> URL {
        let original = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let extensionName = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var number = 1
        while true {
            let candidate = folder.appendingPathComponent("\(stem) (\(number)).\(extensionName)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }

    private func rasterizePDFPage(
        _ page: PDFPage,
        dpi: Int,
        colorSpace: CGColorSpace,
        itemNumber: Int,
        isJapanese: Bool
    ) throws -> RenderedPage {
        let bounds = page.bounds(for: .mediaBox)
        let scale = CGFloat(dpi) / 72
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        let rendered = try makeBitmap(width: width, height: height, colorSpace: colorSpace, itemNumber: itemNumber, isJapanese: isJapanese) { context in
            context.setFillColor(colorSpace.model == .cmyk ? [0, 0, 0, 0] : [1, 1, 1, 1])
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        return rendered
    }

    private func resizeImage(
        _ image: CGImage,
        colorSpace: CGColorSpace,
        options: ExportOptions,
        sourceDPI: Int,
        itemNumber: Int,
        isJapanese: Bool
    ) throws -> RenderedPage {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let scale = options.scaleFactor(width: image.width, height: image.height, sourceDPI: sourceDPI)
        let width = max(1, Int((sourceWidth * scale).rounded()))
        let height = max(1, Int((sourceHeight * scale).rounded()))
        let outputBits: Int = switch options.format {
        case .png, .tiff:
            switch options.bitDepth {
            case .matchSource: image.bitsPerComponent > 8 ? 16 : 8
            case .bit8: 8
            case .bit16: 16
            }
        case .jpg, .webp: 8
        }
        let rendered = try makeBitmap(
            width: width,
            height: height,
            colorSpace: colorSpace,
            bitsPerComponent: outputBits,
            itemNumber: itemNumber,
            isJapanese: isJapanese
        ) { context in
            context.interpolationQuality = interpolationQuality(for: options.resizeMethod, scale: scale)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard abs(scale - 1) > 0.0001,
              let processed = postProcessedImage(rendered.image, method: options.resizeMethod, scale: scale) else {
            return rendered
        }
        return RenderedPage(
            image: processed,
            pixels: rendered.pixels,
            bytesPerRow: rendered.bytesPerRow,
            colorSpace: rendered.colorSpace,
            isCMYK: rendered.isCMYK
        )
    }

    private func imageDPI(source: CGImageSource, index: Int) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let dpi = properties[kCGImagePropertyDPIWidth] as? NSNumber else { return nil }
        return max(1, dpi.intValue)
    }

    private func makeBitmap(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace,
        bitsPerComponent: Int = 8,
        itemNumber: Int,
        isJapanese: Bool,
        drawing: (CGContext) -> Void
    ) throws -> RenderedPage {
        let isCMYK = colorSpace.model == .cmyk
        let bytesPerPixel = bitsPerComponent == 16 ? 8 : 4
        let bytesPerRow = width * bytesPerPixel
        let bitmapInfo = isCMYK
            ? CGImageAlphaInfo.none.rawValue
            : (bitsPerComponent == 16
                ? CGBitmapInfo.byteOrder16Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
                : CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ConversionError.cannotRenderItem(itemNumber, isJapanese)
        }
        context.interpolationQuality = .high
        drawing(context)
        guard let image = context.makeImage(), let data = context.data else {
            throw ConversionError.cannotRenderItem(itemNumber, isJapanese)
        }
        return RenderedPage(
            image: image,
            pixels: Data(bytes: data, count: bytesPerRow * height),
            bytesPerRow: bytesPerRow,
            colorSpace: colorSpace,
            isCMYK: isCMYK
        )
    }

    private func interpolationQuality(for method: ResizeMethod, scale: CGFloat) -> CGInterpolationQuality {
        switch method {
        case .nearestNeighbor: .none
        case .bicubicSmoother: .medium
        case .automatic: scale < 1 ? .high : .medium
        case .bicubic, .bicubicSharper: .high
        }
    }

    private func postProcessedImage(_ image: CGImage, method: ResizeMethod, scale: CGFloat) -> CGImage? {
        let resolvedMethod: ResizeMethod = method == .automatic
            ? (scale < 1 ? .bicubicSharper : .bicubicSmoother)
            : method
        let input = CIImage(cgImage: image)
        let output: CIImage
        switch resolvedMethod {
        case .bicubicSharper:
            let reduction = max(0, min(1, 1 - scale))
            output = input.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.18 + (0.17 * reduction)
            ])
        case .bicubicSmoother:
            output = input
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.25])
                .cropped(to: input.extent)
        case .automatic, .bicubic, .nearestNeighbor:
            return nil
        }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
    }

    private func write(
        _ image: CGImage,
        to url: URL,
        dpi: Int,
        itemNumber: Int,
        isJapanese: Bool,
        options: ExportOptions,
        sourceProperties: [CFString: Any]?
    ) throws {
        let format = options.format
        if format == .webp {
            let image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            guard let data = SDImageWebPCoder.shared.encodedData(
                with: image,
                format: .webP,
                options: [.encodeCompressionQuality: Double(options.webPQuality) / 100]
            ) else {
                throw ConversionError.cannotEncodeItem(itemNumber, format, isJapanese)
            }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ConversionError.cannotEncodeItem(itemNumber, format, isJapanese)
            }
            return
        }

        var outputImage = format == .jpg ? imageOnWhiteBackground(image) ?? image : image
        if !options.embedsColorProfile {
            outputImage = imageWithoutEmbeddedProfile(outputImage) ?? outputImage
        }

        let type: UTType = switch format {
        case .jpg: .jpeg
        case .png: .png
        case .tiff: .tiff
        case .webp: .webP
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.cannotEncodeItem(itemNumber, format, isJapanese)
        }
        var properties = options.metadataMode == .keep
            ? retainedMetadata(from: sourceProperties)
            : [:]
        properties.merge([
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]) { _, new in new }
        if format == .jpg {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(options.jpegQuality) / 100
            properties[kCGImagePropertyJFIFDictionary] = [
                kCGImagePropertyJFIFXDensity: dpi,
                kCGImagePropertyJFIFYDensity: dpi,
                kCGImagePropertyJFIFDensityUnit: 1
            ]
        } else if format == .png {
            properties[kCGImagePropertyPNGDictionary] = [
                kCGImagePropertyPNGCompressionFilter: pngFilterValue(for: options.pngCompression)
            ]
        } else if format == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: (options.tiffCompression ?? .lzw).imageIOValue
            ]
        }
        CGImageDestinationAddImage(destination, outputImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.cannotEncodeItem(itemNumber, format, isJapanese)
        }
    }

    private func retainedMetadata(from source: [CFString: Any]?) -> [CFString: Any] {
        guard let source else { return [:] }
        let allowed: [CFString] = [
            kCGImagePropertyExifDictionary,
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyOrientation
        ]
        return allowed.reduce(into: [:]) { result, key in
            if let value = source[key] { result[key] = value }
        }
    }

    private func pngFilterValue(for level: Int) -> Int {
        switch level {
        case 0: 0x08
        case 1...3: 0x08 | 0x10
        case 4...6: 0x08 | 0x10 | 0x20 | 0x40
        default: 0x08 | 0x10 | 0x20 | 0x40 | 0x80
        }
    }

    private func imageWithoutEmbeddedProfile(_ image: CGImage) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private func preserveFileDatesIfNeeded(from source: URL, to output: URL, options: ExportOptions) {
        guard options.preservesFileDates,
              let attributes = try? FileManager.default.attributesOfItem(atPath: source.path) else { return }
        var dates: [FileAttributeKey: Any] = [:]
        if let created = attributes[.creationDate] { dates[.creationDate] = created }
        if let modified = attributes[.modificationDate] { dates[.modificationDate] = modified }
        try? FileManager.default.setAttributes(dates, ofItemAtPath: output.path)
    }

    private func imageOnWhiteBackground(_ image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private func validate(colorSpace: CGColorSpace, options: ExportOptions, isJapanese: Bool) throws {
        guard (options.format == .png || options.format == .webp), colorSpace.model == .cmyk else { return }
        throw ConversionError.incompatibleOptions(
            isJapanese
                ? "入力のカラープロファイルはCMYKです。PNG / WebPでは保持できないため、JPG / TIFFまたはRGBプロファイルを選んでください。"
                : "The source profile is CMYK. Choose JPG, TIFF, or an RGB profile because PNG and WebP cannot preserve CMYK."
        )
    }

    private func resolveImageColorSpace(for profile: ColorProfile, sourceImage: CGImage) -> CGColorSpace {
        switch profile {
        case .matchSource: sourceImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        }
    }

    private func resolvePDFColorSpace(for profile: ColorProfile, pdfURL: URL) -> CGColorSpace {
        switch profile {
        case .matchSource:
            outputIntentColorSpace(from: pdfURL) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        }
    }

    private func outputIntentColorSpace(from url: URL) -> CGColorSpace? {
        guard let pdf = CGPDFDocument(url as CFURL), let catalog = pdf.catalog else { return nil }
        var intents: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(catalog, "OutputIntents", &intents), let intents else { return nil }
        var intent: CGPDFDictionaryRef?
        guard CGPDFArrayGetDictionary(intents, 0, &intent), let intent else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(intent, "DestOutputProfile", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }
        return CGColorSpace(iccData: data)
    }
}
