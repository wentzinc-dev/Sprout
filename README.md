# PDFUNK（ピーディーファンク）

macOS専用のPDFページ画像書き出しアプリです。

開発判断、技術的制約、検証結果、次のTODOは [`docs/HANDOFF.md`](docs/HANDOFF.md) にまとめています。

## 実装済みの機能

- Swift / SwiftUI、macOS 13以降
- PDF 1ファイルまたは複数ファイルのドラッグ＆ドロップ
- 最初のPDFと同じ場所を既定の保存先に設定（任意のフォルダへ変更可能）
- 全ページをPNG / JPG / TIFF / PSDとして一括書き出し
- 既定値は200 dpi / sRGB
- 解像度は72 / 200 / 300 / 350 / Customを選択可能
- カラープロファイルは「PDFに合わせる」/ sRGB / Adobe RGB (1998) / CMYK
- PDF名のサブフォルダに `page-0001.ext` 形式で保存
- ICCプロファイルと解像度メタデータを出力ファイルへ埋め込み

JPGは品質92%、TIFFはLZW圧縮です。PSDは1ページにつき1ファイルのフラット画像として書き出します。PNG形式自体がCMYKを保持できないため、PNG＋CMYKの組み合わせはUIで実行不可になります。

「PDFに合わせる」はPDFのOutput Intentに埋め込まれたICCプロファイルを使用します。Output IntentがないPDFはsRGBへフォールバックします。ページ内で複数の色空間が使われている場合は、PDFのレンダリング結果をこの出力色空間へ統合します。

## プロジェクト構成

```text
PDFUNK/
├── Package.swift
├── README.md
└── Sources/PDFUNK/
    ├── PDFUNKApp.swift       # アプリのエントリポイント
    ├── ContentView.swift     # ドロップ、設定、保存先、進捗UI
    ├── ExportOptions.swift   # 仕様上の選択肢と既定値
    ├── PDFConverter.swift    # PDFKit描画、ImageIO書き出し、色管理
    ├── PSDWriter.swift       # フラットPSDとICCリソースの生成
    └── WindowConfigurator.swift # 透明な固定サイズウィンドウ
```

## 開発・実行手順

1. Xcode 16以降をインストールする。
2. Xcodeで `PDFUNK.xcodeproj` を開く（Finderからダブルクリックでも可）。
3. Scheme `PDFUNK`、実行先 `My Mac` を選び、Runする。
4. PDFをドロップし、必要なら保存先を変更して「EXPORT!」を押す。

コマンドラインの型チェックは `swift build` で実行できます。`xcode-select -p` がCommand Line Toolsを指していてSDK不一致になる環境では、Xcodeをインストール後、Xcodeの Settings > Locations > Command Line Tools で使用するXcodeを選択してください。アプリアイコン、App Sandbox、Hardened Runtime、Developer ID署名設定は実装済みです。DebugはApple Development署名、ReleaseはDeveloper ID Application署名を使用します。

## Gumroad配布用ビルドと公証

ReleaseはApple Silicon / Intel対応のUniversal Binaryです。最初にApple IDまたはApp Store Connect APIキーをKeychainへ登録します。

```bash
xcrun notarytool store-credentials PDFUNK-notary
./scripts/archive-and-notarize.sh PDFUNK-notary
```

成功すると、公証チケットをstapleした `dist/export/PDFUNK.app` と、Gumroad掲載用の `dist/PDFUNK-1.0-notarized.zip` が生成されます。

App Sandboxの権限は、ユーザーが選んだファイル／フォルダの読み書きだけです。PDFをドロップした後、Sandboxが書き込みを許可できるよう保存先を `SELECT…` で選択します。ネットワーク、カメラ、マイク等の権限は付与していません。

旧Bundle Identifierは `com.pdfunk.app` でした。アプリ固有のUserDefaults、Application Support、Keychain、security-scoped bookmarkは保存していなかったため、移行対象データはありません。新旧ビルドはmacOS上で別アプリとして扱われます。

## 開発ロードマップ / TODO

- [ ] CropBox / MediaBoxのどちらを出力対象にするかを設定可能にするか決定
- [ ] 暗号化PDF、破損PDF、極端に大きなページへのエラー・メモリ対策
- [ ] 同名出力フォルダ・ファイルが存在する場合の上書き方針
- [ ] 変換キャンセル、詳細な進捗、Finderで表示
- [x] App Sandboxとユーザー選択ファイル／フォルダへのsecurity-scoped access
- [x] Developer ID署名、公証、Universal Binaryの配布設定
- [ ] ユニットテストと代表PDFによる画像寸法・色・回転の回帰テスト
