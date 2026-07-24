import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConversionError: LocalizedError {
    case cannotOpenPDF
    case incompatibleOptions(String)
    case cannotRenderPage(Int)
    case cannotEncodePage(Int, ExportFormat)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF: "PDFを開けませんでした。"
        case .incompatibleOptions(let message): message
        case .cannotRenderPage(let page): "\(page)ページ目を描画できませんでした。"
        case .cannotEncodePage(let page, let format): "\(page)ページ目を\(format.rawValue)に変換できませんでした。"
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

struct PDFConverter {
    func convert(
        pdfURL: URL,
        destinationURL: URL,
        options: ExportOptions,
        progress: @escaping @MainActor (Int, Int) -> Void
    ) async throws {
        if let message = options.validationMessage {
            throw ConversionError.incompatibleOptions(message)
        }

        let dpi = options.resolution.value(custom: options.customDPI)
        guard let document = PDFDocument(url: pdfURL) else {
            throw ConversionError.cannotOpenPDF
        }

        let colorSpace = resolveColorSpace(for: options.colorProfile, pdfURL: pdfURL)
        if options.format == .png && colorSpace.model == .cmyk {
            throw ConversionError.incompatibleOptions(
                "このPDFの出力プロファイルはCMYKです。PNGでは保持できないため、JPG / TIFF / PSDを選んでください。"
            )
        }

        let outputFolder = destinationURL
            .appendingPathComponent(pdfURL.deletingPathExtension().lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw ConversionError.cannotRenderPage(index + 1)
            }

            let bounds = page.bounds(for: .mediaBox)
            let rendered = try render(
                page: page,
                bounds: bounds,
                dpi: dpi,
                colorSpace: colorSpace,
                pageNumber: index + 1
            )
            let filename = String(
                format: "page-%04d.%@",
                index + 1,
                options.format.fileExtension
            )
            let outputURL = outputFolder.appendingPathComponent(filename)

            switch options.format {
            case .png, .jpg, .tiff:
                try writeImageIO(
                    rendered.image,
                    to: outputURL,
                    format: options.format,
                    dpi: dpi,
                    pageNumber: index + 1
                )
            case .psd:
                try PSDWriter.write(
                    rendered: rendered,
                    to: outputURL,
                    dpi: dpi,
                    pageNumber: index + 1
                )
            }
            await progress(index + 1, document.pageCount)
        }
    }

    private func render(
        page: PDFPage,
        bounds: CGRect,
        dpi: Int,
        colorSpace: CGColorSpace,
        pageNumber: Int
    ) throws -> RenderedPage {
        let scale = CGFloat(dpi) / 72
        let width = max(1, Int((bounds.width * scale).rounded(.up)))
        let height = max(1, Int((bounds.height * scale).rounded(.up)))
        let isCMYK = colorSpace.model == .cmyk
        let bytesPerRow = width * 4
        let bitmapInfo = isCMYK
            ? CGImageAlphaInfo.none.rawValue
            : CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ConversionError.cannotRenderPage(pageNumber)
        }

        context.setFillColor(isCMYK ? [0, 0, 0, 0] : [1, 1, 1, 1])
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage(), let rawData = context.data else {
            throw ConversionError.cannotRenderPage(pageNumber)
        }
        let pixels = Data(bytes: rawData, count: bytesPerRow * height)
        return RenderedPage(
            image: image,
            pixels: pixels,
            bytesPerRow: bytesPerRow,
            colorSpace: colorSpace,
            isCMYK: isCMYK
        )
    }

    private func writeImageIO(
        _ image: CGImage,
        to url: URL,
        format: ExportFormat,
        dpi: Int,
        pageNumber: Int
    ) throws {
        let type: UTType
        switch format {
        case .png: type = .png
        case .jpg: type = .jpeg
        case .tiff: type = .tiff
        case .psd: return
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.cannotEncodePage(pageNumber, format)
        }

        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi
        ]
        if format == .jpg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
            properties[kCGImagePropertyJFIFDictionary] = [
                kCGImagePropertyJFIFXDensity: dpi,
                kCGImagePropertyJFIFYDensity: dpi,
                kCGImagePropertyJFIFDensityUnit: 1
            ]
        } else if format == .tiff {
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: 5
            ]
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.cannotEncodePage(pageNumber, format)
        }
    }

    private func resolveColorSpace(for profile: ColorProfile, pdfURL: URL) -> CGColorSpace {
        switch profile {
        case .matchPDF:
            return outputIntentColorSpace(from: pdfURL)
                ?? CGColorSpace(name: CGColorSpace.sRGB)!
        case .sRGB:
            return CGColorSpace(name: CGColorSpace.sRGB)!
        case .adobeRGB:
            return CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        case .cmyk:
            return CGColorSpace(name: CGColorSpace.genericCMYK)!
        }
    }

    private func outputIntentColorSpace(from url: URL) -> CGColorSpace? {
        guard let pdf = CGPDFDocument(url as CFURL),
              let catalog = pdf.catalog else { return nil }
        var intents: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(catalog, "OutputIntents", &intents),
              let intents else { return nil }
        var intent: CGPDFDictionaryRef?
        guard CGPDFArrayGetDictionary(intents, 0, &intent),
              let intent else { return nil }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(intent, "DestOutputProfile", &stream),
              let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) else { return nil }
        return CGColorSpace(iccData: data)
    }
}
