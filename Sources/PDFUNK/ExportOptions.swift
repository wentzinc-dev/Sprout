import CoreGraphics
import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case jpg
    case png
    case tiff
    case webp

    var id: Self { self }
    var displayName: String {
        switch self {
        case .jpg: "JPG"
        case .png: "PNG"
        case .tiff: "TIFF"
        case .webp: "WebP"
        }
    }
    var fileExtension: String {
        switch self {
        case .jpg: "jpg"
        case .png: "png"
        case .tiff: "tif"
        case .webp: "webp"
        }
    }
}

enum PDFResolutionPreset: String, CaseIterable, Identifiable, Codable {
    case dpi72 = "72"
    case dpi150 = "150"
    case dpi200 = "200"
    case dpi300 = "300"
    case dpi350 = "350"
    case dpi600 = "600"
    case custom = "Custom"

    var id: Self { self }
    func value(customDPI: Int) -> Int { self == .custom ? customDPI : Int(rawValue)! }
}

enum SaveResolutionPreset: String, CaseIterable, Identifiable, Codable {
    case dpi72 = "72"
    case dpi150 = "150"
    case dpi200 = "200"
    case dpi300 = "300"
    case dpi350 = "350"
    case dpi360 = "360"
    case dpi400 = "400"
    case custom = "Custom"

    var id: Self { self }
    func value(customDPI: Int) -> Int { self == .custom ? customDPI : Int(rawValue)! }
}

enum SaveSizeMode: String, CaseIterable, Identifiable, Codable {
    case percent
    case resolution
    case longEdge
    case shortEdge
    case maxLongEdge
    case maxShortEdge
    case width
    case height
    case maxWidth
    case maxHeight
    var id: Self { self }

    var usesPixelValue: Bool {
        switch self {
        case .longEdge, .shortEdge, .maxLongEdge, .maxShortEdge, .width, .height, .maxWidth, .maxHeight: true
        case .percent, .resolution: false
        }
    }

    var neverUpscales: Bool {
        self == .maxLongEdge || self == .maxShortEdge || self == .maxWidth || self == .maxHeight
    }
}

enum BitDepth: String, CaseIterable, Identifiable, Codable {
    case matchSource
    case bit8
    case bit16
    var id: Self { self }
}

enum OutputFilenameMode: String, CaseIterable, Identifiable, Codable {
    case original
    case customName
    case sequenceOnly
    var id: Self { self }
}

enum MetadataMode: String, CaseIterable, Identifiable, Codable {
    case keep
    case discard
    var id: Self { self }
}

enum ResizeMethod: String, CaseIterable, Identifiable, Codable {
    case automatic
    case bicubic
    case bicubicSharper
    case bicubicSmoother
    case nearestNeighbor

    var id: Self { self }
}

enum ColorProfile: String, CaseIterable, Identifiable, Codable {
    case matchSource
    case sRGB
    case displayP3
    case adobeRGB
    var id: Self { self }
}

enum DestinationMode: String, CaseIterable, Identifiable, Codable {
    case sameLocation
    case selectedFolder
    var id: Self { self }
}

enum TextAdditionPosition: String, CaseIterable, Identifiable, Codable {
    case beginning
    case end
    case custom
    var id: Self { self }
}

struct ExportOptions: Codable {
    var format: ExportFormat = .png
    var pdfResolution: PDFResolutionPreset = .dpi200
    var customPDFDPI = 200
    var saveSizeMode: SaveSizeMode?
    var saveResolution: SaveResolutionPreset = .dpi200
    var customSaveDPI = 200
    var percentage = 100
    var edgePixels = 2000
    var allowsUpscaling = false
    var jpegQuality = 92
    var pngCompression = 6
    var webPQuality = 92
    var colorProfile: ColorProfile = .sRGB
    var embedsColorProfile = true
    var bitDepth: BitDepth = .matchSource
    var filenameMode: OutputFilenameMode = .original
    var customFilename = "image"
    var addsTextToFilename = false
    var addedFilenameText = ""
    var textAdditionPosition: TextAdditionPosition = .end
    var customTextPosition = 0
    var replacesFilenameText = false
    var filenameSearchText = ""
    var filenameReplacementText = ""
    var metadataMode: MetadataMode = .keep
    var preservesFileDates = true
    var resizeMethod: ResizeMethod = .automatic

    var pdfDPI: Int { pdfResolution.value(customDPI: customPDFDPI) }
    var saveDPI: Int { saveResolution.value(customDPI: customSaveDPI) }
    var effectivePDFDPI: Int { saveSizeMode == .resolution ? saveDPI : pdfDPI }

    func scaleFactor(width: Int, height: Int) -> CGFloat {
        guard width > 0, height > 0 else { return 1 }
        let longEdge = CGFloat(max(width, height))
        let shortEdge = CGFloat(min(width, height))
        let requested: CGFloat
        switch saveSizeMode {
        case nil, .resolution: requested = 1
        case .percent?: requested = CGFloat(percentage) / 100
        case .longEdge?, .maxLongEdge?: requested = CGFloat(edgePixels) / longEdge
        case .shortEdge?, .maxShortEdge?: requested = CGFloat(edgePixels) / shortEdge
        case .width?, .maxWidth?: requested = CGFloat(edgePixels) / CGFloat(width)
        case .height?, .maxHeight?: requested = CGFloat(edgePixels) / CGFloat(height)
        }
        if saveSizeMode == .width || saveSizeMode == .height { return requested }
        return saveSizeMode?.neverUpscales == true || !allowsUpscaling ? min(1, requested) : requested
    }

    func validationMessage(isJapanese: Bool) -> String? {
        if saveSizeMode == .resolution && (saveDPI < 1 || saveDPI > 2400) {
            return isJapanese
                ? "保存解像度は1〜2400dpiで指定してください。"
                : "Save resolution must be between 1 and 2400 dpi."
        }
        if pdfResolution == .custom && (customPDFDPI < 1 || customPDFDPI > 2400) {
            return isJapanese
                ? "PDFのCustom DPIは1〜2400で指定してください。"
                : "Custom PDF DPI must be between 1 and 2400."
        }
        if saveSizeMode == .percent && (percentage < 1 || percentage > 1000) {
            return isJapanese ? "倍率は1〜1000%で指定してください。" : "Scale must be between 1% and 1000%."
        }
        if saveSizeMode?.usesPixelValue == true && (edgePixels < 1 || edgePixels > 100_000) {
            return isJapanese
                ? "辺のサイズは1〜100,000ピクセルで指定してください。"
                : "Edge size must be between 1 and 100,000 pixels."
        }
        if jpegQuality < 1 || jpegQuality > 100 {
            return isJapanese ? "JPEG品質は1〜100で指定してください。" : "JPEG quality must be between 1 and 100."
        }
        if pngCompression < 0 || pngCompression > 9 {
            return isJapanese ? "PNG圧縮率は0〜9で指定してください。" : "PNG compression must be between 0 and 9."
        }
        if webPQuality < 1 || webPQuality > 100 {
            return isJapanese ? "WebP品質は1〜100で指定してください。" : "WebP quality must be between 1 and 100."
        }
        if filenameMode == .customName && customFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isJapanese ? "新しいファイル名を入力してください。" : "Enter a new filename."
        }
        if replacesFilenameText && filenameSearchText.isEmpty {
            return isJapanese ? "置換する検索文字を入力してください。" : "Enter text to find."
        }
        return nil
    }
}
