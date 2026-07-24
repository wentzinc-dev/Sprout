import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var pdfURLs: [URL] = []
    @State private var destinationURL: URL?
    @State private var options = ExportOptions()
    @State private var isTargeted = false
    @State private var isConverting = false
    @State private var progressText = ""
    @State private var alertMessage: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            panel
                .offset(x: 40, y: 38)

            header
                .offset(x: 0, y: 2)
        }
        .frame(width: 320, height: 610, alignment: .topLeading)
        .background(Color.clear)
        .alert("PDFUNK", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var panel: some View {
        VStack(spacing: 14) {
            HStack {
                Text("PDF → IMAGE")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(punkPink)
                Spacer()
                Button {
                    NSApp.keyWindow?.close()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                }
                .buttonStyle(.plain)
                .help("閉じる")
            }
            .padding(.top, 48)

            dropArea
            settings
            if let validationMessage = options.validationMessage {
                Text(validationMessage)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(punkPink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            destination

            VStack(alignment: .trailing, spacing: 7) {
                Text(progressText)
                    .foregroundStyle(.secondary)
                Button("EXPORT!", action: export)
                    .buttonStyle(.borderedProminent)
                    .tint(punkPink)
                    .font(.system(.body, design: .rounded).weight(.black))
                    .frame(maxWidth: .infinity)
                    .disabled(pdfURLs.isEmpty || destinationURL == nil || isConverting || !selectedOptionsAreImplemented)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .background(Color(nsColor: NSColor(calibratedWhite: 0.075, alpha: 1)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(paper.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 10)
        .frame(width: 280)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(punkPink)
                .frame(width: 250, height: 34)
                .rotationEffect(.degrees(6))
                .offset(x: 18, y: 25)

            Image("PDFUNKLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 275)
                .rotationEffect(.degrees(-5))
                .offset(x: -10, y: -8)
        }
        .frame(width: 300, height: 100, alignment: .topLeading)
        .allowsHitTesting(false)
        .zIndex(2)
    }

    private var dropArea: some View {
        VStack(spacing: 6) {
            Image(systemName: pdfURLs.isEmpty ? "arrow.down.doc" : "doc.on.doc.fill")
                .font(.system(size: 27, weight: .black))
                .foregroundStyle(isTargeted ? punkPink : paper)
            Text(droppedPDFLabel)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("MULTIPLE PDFs OK")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(isTargeted ? punkPink.opacity(0.18) : Color.black.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(paper.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [7, 4])))
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfs.isEmpty, pdfs.count == urls.count else {
                alertMessage = "PDFファイルをドロップしてください。"
                return false
            }
            pdfURLs = pdfs
            destinationURL = pdfs[0].deletingLastPathComponent()
            progressText = ""
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var settings: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                settingLabel("DPI")
                HStack {
                    Picker("", selection: $options.resolution) {
                        ForEach(ResolutionPreset.allCases) { preset in
                            Text(preset == .custom ? preset.rawValue : "\(preset.rawValue) dpi").tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: options.resolution == .custom ? 86 : 152)
                    if options.resolution == .custom {
                        TextField("dpi", value: $options.customDPI, format: .number)
                            .frame(width: 70)
                        Text("dpi")
                    }
                }
            }
            GridRow {
                settingLabel("FORMAT")
                Picker("", selection: $options.format) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 152)
            }
            GridRow {
                settingLabel("COLOR")
                Picker("", selection: $options.colorProfile) {
                    ForEach(ColorProfile.allCases) { profile in
                        Text(profile.rawValue).tag(profile)
                    }
                }
                .labelsHidden()
                .frame(width: 152)
            }
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .padding(12)
        .background(paper.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            Capsule().fill(punkPink).frame(width: 72, height: 4).offset(x: 8, y: -2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                settingLabel("SAVE TO")
                Spacer()
                Button("SELECT…", action: chooseDestination)
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            Text(destinationURL?.path(percentEncoded: false) ?? "未選択")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
    }

    private var punkPink: Color { Color(red: 1, green: 0.03, blue: 0.42) }
    private var paper: Color { Color(red: 0.93, green: 0.90, blue: 0.82) }

    private func settingLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(punkPink)
    }

    private var selectedOptionsAreImplemented: Bool {
        options.validationMessage == nil
    }

    private var droppedPDFLabel: String {
        switch pdfURLs.count {
        case 0: "DROP PDFs HERE"
        case 1: pdfURLs[0].lastPathComponent
        default: "\(pdfURLs.count) PDFs SELECTED"
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "画像の保存先を選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { destinationURL = panel.url }
    }

    private func export() {
        guard !pdfURLs.isEmpty, let destinationURL else { return }
        let filesToConvert = pdfURLs
        isConverting = true
        progressText = "変換を開始しています…"

        Task {
            do {
                for (fileIndex, pdfURL) in filesToConvert.enumerated() {
                    try await PDFConverter().convert(
                        pdfURL: pdfURL,
                        destinationURL: destinationURL,
                        options: options
                    ) { completed, total in
                        progressText = "PDF \(fileIndex + 1)/\(filesToConvert.count)・\(completed)/\(total)ページ"
                    }
                }
                isConverting = false
                alertMessage = "\(filesToConvert.count)個のPDFを変換しました。"
            } catch {
                isConverting = false
                alertMessage = error.localizedDescription
            }
        }
    }
}
