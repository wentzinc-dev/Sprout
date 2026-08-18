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

enum TIFFCompression: String, CaseIterable, Identifiable, Codable {
    case none
    case lzw
    case zip
    var id: Self { self }

    var imageIOValue: Int {
        switch self {
        case .none: 1
        case .lzw: 5
        case .zip: 8
        }
    }
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

enum SameLocationExportMode: String, CaseIterable, Identifiable, Codable {
    case directly
    case formatFolder
    var id: Self { self }
}

enum TextAdditionPosition: String, CaseIterable, Identifiable, Codable {
    case beginning
    case end
    case custom
    var id: Self { self }
}

enum FilenameOperationKind: String, Codable, CaseIterable, Identifiable {
    case add
    case replace
    var id: Self { self }
}

struct FilenameOperation: Codable, Identifiable {
    var id = UUID()
    var kind: FilenameOperationKind
    var text = ""
    var replacement = ""
    var position: TextAdditionPosition = .end
    var customPosition = 0
}

struct ExportOptions: Codable {
    // Retained for compatibility with presets created before multi-format export.
    var format: ExportFormat = .jpg
    var formats: Set<ExportFormat>?
    var pdfResolution: PDFResolutionPreset = .dpi200
    var customPDFDPI = 200
    var saveSizeMode: SaveSizeMode? = .percent
    var saveResolution: SaveResolutionPreset = .dpi200
    var customSaveDPI = 200
    var percentage = 100
    var edgePixels = 2000
    var allowsUpscaling = false
    var jpegQuality = 92
    var pngCompression = 6
    var webPQuality = 92
    var tiffCompression: TIFFCompression? = TIFFCompression.none
    var colorProfile: ColorProfile = .matchSource
    var embedsColorProfile = true
    var bitDepth: BitDepth = .matchSource
    var addsTextToFilename = false
    var addedFilenameText = ""
    var textAdditionPosition: TextAdditionPosition = .end
    var customTextPosition = 0
    var replacesFilenameText = false
    var filenameSearchText = ""
    var filenameReplacementText = ""
    var filenameOperations: [FilenameOperation]?
    var metadataMode: MetadataMode = .keep
    var preservesFileDates = true
    var sameLocationExportMode: SameLocationExportMode? = .formatFolder
    var opensDestinationWhenComplete: Bool? = true
    var resizeMethod: ResizeMethod = .automatic

    var pdfDPI: Int { pdfResolution.value(customDPI: customPDFDPI) }
    var saveDPI: Int { saveResolution.value(customDPI: customSaveDPI) }
    var effectivePDFDPI: Int { saveSizeMode == .resolution ? saveDPI : pdfDPI }
    var shouldOpenDestinationWhenComplete: Bool { opensDestinationWhenComplete ?? true }

    var selectedFormats: [ExportFormat] {
        let selection = formats.flatMap { $0.isEmpty ? nil : $0 } ?? [format]
        return ExportFormat.allCases.filter(selection.contains)
    }

    func isSelected(_ format: ExportFormat) -> Bool {
        selectedFormats.contains(format)
    }

    mutating func setSelected(_ format: ExportFormat, to isSelected: Bool) {
        if formats == nil, isSelected, format != self.format {
            formats = [format]
            self.format = format
            return
        }
        var selection = Set(selectedFormats)
        if isSelected {
            selection.insert(format)
        } else if selection.count > 1 {
            selection.remove(format)
        }
        formats = selection
        self.format = ExportFormat.allCases.first(where: selection.contains) ?? .png
    }

    func options(for format: ExportFormat) -> ExportOptions {
        var copy = self
        copy.format = format
        copy.formats = [format]
        return copy
    }

    func scaleFactor(width: Int, height: Int, sourceDPI: Int = 72) -> CGFloat {
        guard width > 0, height > 0 else { return 1 }
        let longEdge = CGFloat(max(width, height))
        let shortEdge = CGFloat(min(width, height))
        let requested: CGFloat
        switch saveSizeMode {
        case nil: requested = 1
        case .resolution?: requested = CGFloat(saveDPI) / CGFloat(max(1, sourceDPI))
        case .percent?: requested = CGFloat(percentage) / 100
        case .longEdge?, .maxLongEdge?: requested = CGFloat(edgePixels) / longEdge
        case .shortEdge?, .maxShortEdge?: requested = CGFloat(edgePixels) / shortEdge
        case .width?, .maxWidth?: requested = CGFloat(edgePixels) / CGFloat(width)
        case .height?, .maxHeight?: requested = CGFloat(edgePixels) / CGFloat(height)
        }
        if saveSizeMode == .width || saveSizeMode == .height || saveSizeMode == .resolution { return requested }
        return saveSizeMode?.neverUpscales == true || !allowsUpscaling ? min(1, requested) : requested
    }

    func validationMessage(isJapanese: Bool) -> String? {
        if saveSizeMode == .resolution && (saveDPI < 1 || saveDPI > 2400) {
            return isJapanese
                ? "保存解像度は1〜2400ppiで指定してください。"
                : "Save resolution must be between 1 and 2400 ppi."
        }
        if pdfResolution == .custom && (customPDFDPI < 1 || customPDFDPI > 2400) {
            return isJapanese
                ? "PDFのカスタムPPIは1〜2400で指定してください。"
                : "Custom PDF PPI must be between 1 and 2400."
        }
        if saveSizeMode == .percent && (percentage < 1 || percentage > 1000) {
            return isJapanese ? "倍率は1〜1000%で指定してください。" : "Scale must be between 1% and 1000%."
        }
        if saveSizeMode?.usesPixelValue == true && (edgePixels < 1 || edgePixels > 100_000) {
            return isJapanese
                ? "辺のサイズは1〜100,000ピクセルで指定してください。"
                : "Edge size must be between 1 and 100,000 pixels."
        }
        if isSelected(.jpg) && (jpegQuality < 1 || jpegQuality > 100) {
            return isJapanese ? "JPEG品質は1〜100で指定してください。" : "JPEG quality must be between 1 and 100."
        }
        if isSelected(.png) && (pngCompression < 0 || pngCompression > 9) {
            return isJapanese ? "PNG圧縮率は0〜9で指定してください。" : "PNG compression must be between 0 and 9."
        }
        if isSelected(.webp) && (webPQuality < 1 || webPQuality > 100) {
            return isJapanese ? "WebP品質は1〜100で指定してください。" : "WebP quality must be between 1 and 100."
        }
        if effectiveFilenameOperations.contains(where: { $0.kind == .replace && $0.text.isEmpty }) {
            return isJapanese ? "置換する検索文字を入力してください。" : "Enter text to find."
        }
        return nil
    }

    var effectiveFilenameOperations: [FilenameOperation] {
        if let filenameOperations { return filenameOperations }
        var migrated: [FilenameOperation] = []
        if replacesFilenameText {
            migrated.append(FilenameOperation(kind: .replace, text: filenameSearchText, replacement: filenameReplacementText))
        }
        if addsTextToFilename {
            migrated.append(FilenameOperation(
                kind: .add,
                text: addedFilenameText,
                position: textAdditionPosition,
                customPosition: customTextPosition
            ))
        }
        return migrated
    }
}

enum OutputFilenameBuilder {
    static func filename(
        for inputURL: URL,
        sequence: Int,
        format: ExportFormat,
        options: ExportOptions,
        pageNumber: Int? = nil
    ) -> String {
        var name = inputURL.deletingPathExtension().lastPathComponent
        for operation in options.effectiveFilenameOperations {
            if operation.kind == .replace, !operation.text.isEmpty {
                name = name.replacingOccurrences(of: operation.text, with: operation.replacement)
            } else if operation.kind == .add, !operation.text.isEmpty {
            switch operation.position {
            case .beginning:
                name = operation.text + name
            case .end:
                name += operation.text
            case .custom:
                let offset = max(0, min(operation.customPosition, name.count))
                let index = name.index(name.startIndex, offsetBy: offset)
                name.insert(contentsOf: operation.text, at: index)
            }
            }
        }
        let invalid = CharacterSet(charactersIn: "/:")
        let sanitized = name.components(separatedBy: invalid).joined(separator: "_")
        let baseName = sanitized.isEmpty ? "image" : sanitized
        let pageSuffix = pageNumber.map { String(format: "_%03d", $0) } ?? ""
        return "\(baseName)\(pageSuffix).\(format.fileExtension)"
    }
}
