import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case jpg = "JPG"
    case tiff = "TIFF"
    case psd = "PSD"

    var id: Self { self }

    var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpg: "jpg"
        case .tiff: "tiff"
        case .psd: "psd"
        }
    }
}

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case dpi72 = "72"
    case dpi200 = "200"
    case dpi300 = "300"
    case dpi350 = "350"
    case custom = "Custom"

    var id: Self { self }

    func value(custom: Int) -> Int {
        switch self {
        case .dpi72: 72
        case .dpi200: 200
        case .dpi300: 300
        case .dpi350: 350
        case .custom: custom
        }
    }
}

enum ColorProfile: String, CaseIterable, Identifiable {
    case matchPDF = "PDFに合わせる"
    case sRGB = "sRGB"
    case adobeRGB = "Adobe RGB (1998)"
    case cmyk = "CMYK"

    var id: Self { self }
}

struct ExportOptions {
    var format: ExportFormat = .png
    var resolution: ResolutionPreset = .dpi200
    var customDPI = 200
    var colorProfile: ColorProfile = .sRGB

    var validationMessage: String? {
        if customDPI < 1 || customDPI > 2400 {
            return "Custom DPIは1〜2400で指定してください。"
        }
        if format == .png && colorProfile == .cmyk {
            return "PNGはCMYKを保持できません。JPG / TIFF / PSDを選んでください。"
        }
        return nil
    }
}
