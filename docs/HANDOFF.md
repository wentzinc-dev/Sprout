# PDFUNK 開発引き継ぎ

最終更新: 2026-07-25

## 1. プロダクト概要

PDFUNK（読み: ピーディーファンク）は、PDFの各ページを画像として一括書き出しするmacOS専用アプリです。

- Repository: <https://github.com/wentzinc-dev/PDFUNK>
- Swift / SwiftUI / PDFKit / Core Graphics / ImageIO
- 対応OS: macOS 13以降
- Xcode Scheme: `PDFUNK`
- Bundle Identifier: `com.wentz.PDFUNK`（旧: `com.pdfunk.app`）
- Version / Build: `1.0` / `1`
- Team: WENTZ, K.K. (`UYQNZULLNC`)

## 2. 現在の完成状態

基本的な変換フローは動作しています。

1. 1つまたは複数のPDFをウィンドウへドロップする。
2. 1つ目のPDFがあるフォルダを保存先として自動設定する。
3. DPI、形式、カラープロファイルを選ぶ。
4. `EXPORT!` を押す。
5. 保存先の `PDFファイル名/` 以下へ `page-0001.ext` 形式で出力する。

複数PDFの場合はPDFごとのサブフォルダを作り、順番に処理します。保存先は `SELECT…` から変更できます。

## 3. 対応形式と設定

### 解像度

- 72 dpi
- 200 dpi（初期値）
- 300 dpi
- 350 dpi
- Custom（1〜2400 dpi）

### 出力形式

| 形式 | 実装 | 詳細 |
| --- | --- | --- |
| PNG | 対応 | RGBのみ。CMYKは形式仕様上非対応 |
| JPG | 対応 | 品質92%。RGB / CMYK |
| TIFF | 対応 | LZW圧縮。RGB / CMYK |
| PSD | 対応 | 8-bit、フラット画像。RGB 3ch / CMYK 4ch |

### カラープロファイル

- PDFに合わせる
- sRGB（初期値）
- Adobe RGB (1998)
- CMYK（Generic CMYK Profile）

「PDFに合わせる」はPDFのOutput IntentにあるICCプロファイルを使用します。Output Intentが取得できない場合はsRGBへフォールバックします。ICCとDPIメタデータは出力へ埋め込みます。

PNGはCMYKを保持できないため、`PNG + CMYK` はUIで実行不可です。「PDFに合わせる」でPDFのOutput IntentがCMYKだった場合も、PNGではなくJPG / TIFF / PSDを選ぶようエラー表示します。

## 4. UIとブランドの決定事項

- 黒、生成り、蛍光マゼンタの3色が中心
- パンクZINE、コピー、切り貼り紙の質感
- UIフォントはSF Rounded Black / Bold
- 黒い本体の表示幅は280px
- 透明描画領域を含むウィンドウは320 × 610px固定
- 標準タイトルバーを使わない透明なボーダーレスウィンドウ
- ロゴを黒い本体の左上から透明領域へ張り出して表示
- ウィンドウ背景をドラッグして移動
- 右上の独自ボタンで閉じる
- 本体角丸18px、ドロップ領域12px、設定カード10px

ロゴは切り貼りの `PDFUNK` ワードマークです。アプリアイコンは、黒背景に生成りのPDF用紙、マゼンタの爆発、黒い下向き矢印を組み合わせたPOPパンク案を採用しています。

## 5. 主要ファイル

| ファイル | 役割 |
| --- | --- |
| `Sources/PDFUNK/PDFUNKApp.swift` | Appエントリポイントと固定ウィンドウサイズ |
| `Sources/PDFUNK/ContentView.swift` | UI、ドロップ、保存先、設定、進捗 |
| `Sources/PDFUNK/ExportOptions.swift` | 形式、DPI、色設定と組み合わせ検証 |
| `Sources/PDFUNK/PDFConverter.swift` | PDF描画、色空間、ImageIO出力、Output Intent取得 |
| `Sources/PDFUNK/PSDWriter.swift` | 依存ライブラリなしのフラットPSD生成 |
| `Sources/PDFUNK/WindowConfigurator.swift` | 透明・固定サイズ・ボーダーレスNSWindow設定 |
| `Resources/Assets.xcassets/PDFUNKLogo.imageset` | UIロゴ |
| `Resources/Assets.xcassets/AppIcon.appiconset` | macOS用AppIcon各サイズ |
| `Resources/PDFUNK-AppIcon-Master.png` | 透過済み1024pxアイコンマスター |

通常は `PDFUNK.xcodeproj` をXcodeで開いて作業します。`Package.swift` は初期構成の名残として残っていますが、現在の正式なアプリ設定とアセット管理はXcodeプロジェクト側です。

## 6. 検証済み事項

- XcodeによるDebugビルド: 成功
- PNG: RGB、sRGB、DPIメタデータ
- JPG: Adobe RGB / CMYK、DPIメタデータ
- TIFF: CMYK、Generic CMYK Profile、LZW
- PSD: RGB 3チャンネル / CMYK 4チャンネルとしてファイル判定
- 複数PDFの連続処理
- macOS用AppIconの16〜1024px生成とXcode登録

ローカル環境ではCommand Line Tools単体のSwiftとSDKにビルド番号不一致があったため、検証には `/Applications/Xcode.app/Contents/Developer` のツールチェーンを明示して使用しました。Xcode GUIからの実行には影響しません。

## 7. 現在の制約・次のTODO

優先度が高い順の候補です。

1. 変換をバックグラウンド化し、大きなPDFでもUIを固めない。
2. 変換キャンセルを追加する。
3. 同名PDFや既存出力ファイルの上書き方針を決める。
4. 暗号化・破損PDFと巨大ページのエラー／メモリ対策を強化する。
5. MediaBox固定からCropBox選択へ拡張するか決める。
6. 代表PDFによる寸法、回転、色、ICCの自動回帰テストを追加する。
7. 選択済み保存先を次回起動時にも復元する場合はsecurity-scoped bookmarkを追加する。

現在のPSDは編集レイヤーを持たないフラットPSDです。レイヤー付きPSDは別機能として設計が必要です。

## 8. 配布設定

- Hardened RuntimeおよびApp Sandboxを有効化
- Sandbox権限はユーザー選択ファイル／フォルダのread-writeのみ
- DebugはApple Development、ReleaseはDeveloper ID Applicationで署名
- Releaseはarm64 / x86_64のUniversal Binary
- `scripts/archive-and-notarize.sh` でDeveloper IDアーカイブ、Apple公証、staple、Gatekeeper検証を実行
- 旧Bundle IDで永続化していた独自データはないため、データ移行処理は不要

## 9. 次の開発セッションへ渡す文面

別環境やWeb版へ相談する場合は、次の文面とこのファイルを渡せば再開できます。

> GitHubの `wentzinc-dev/PDFUNK` を確認してください。macOS 13以降向けのSwiftUI製PDF画像変換アプリです。現在の仕様と判断経緯は `docs/HANDOFF.md` にあります。既存のパンク／POPなUI、280px幅の黒い本体、透明カスタムウィンドウ、PDFUNKロゴ、AppIcon、対応形式と色管理を維持してください。作業前にREADME、HANDOFF、git statusを確認し、変更後はXcodeのPDFUNK Schemeでビルドしてください。
