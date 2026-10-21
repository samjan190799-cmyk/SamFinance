import Foundation
import ImageIO
import Vision

/// Распознаёт текст на скриншотах прямо на телефоне: картинки никуда не отправляются.
enum ScreenshotTextRecognizer {
    enum RecognitionError: Error {
        case unreadableImage
    }

    /// Текст со скриншота построчно, сверху вниз. Между далеко отстоящими блоками (облачками СМС)
    /// ставится пустая строка: по ней парсер делит текст на отдельные сообщения.
    static func recognizeText(in imageData: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try recognize(imageData)
        }.value
    }

    private struct Row {
        var text: String
        var box: CGRect
    }

    private static func recognize(_ imageData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw RecognitionError.unreadableImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        // Автоисправление портит маски карт и названия магазинов
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        // У Vision начало координат внизу слева: сверху вниз — по убыванию Y
        let pieces = (request.results ?? [])
            .compactMap { observation -> Row? in
                guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
                return Row(text: text, box: observation.boundingBox)
            }
            .sorted { $0.box.midY > $1.box.midY }

        return joinIntoLines(groupIntoRows(pieces))
    }

    /// Куски на одной высоте склеиваются в одну строку слева направо
    private static func groupIntoRows(_ pieces: [Row]) -> [Row] {
        var rows: [[Row]] = []
        for piece in pieces {
            if let last = rows.last?.last,
               abs(last.box.midY - piece.box.midY) < min(last.box.height, piece.box.height) * 0.5 {
                rows[rows.count - 1].append(piece)
            } else {
                rows.append([piece])
            }
        }
        return rows.map { row in
            let ordered = row.sorted { $0.box.minX < $1.box.minX }
            let box = ordered.dropFirst().reduce(ordered[0].box) { $0.union($1.box) }
            return Row(text: ordered.map(\.text).joined(separator: " "), box: box)
        }
    }

    /// Строки через перенос; большой промежуток по высоте превращается в пустую строку
    private static func joinIntoLines(_ rows: [Row]) -> String {
        guard !rows.isEmpty else { return "" }
        let heights = rows.map(\.box.height).sorted()
        let typicalHeight = heights[heights.count / 2]

        var lines: [String] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let gap = rows[index - 1].box.minY - row.box.maxY
                if gap > typicalHeight * 1.2 {
                    lines.append("")
                }
            }
            lines.append(row.text)
        }
        return lines.joined(separator: "\n")
    }
}
