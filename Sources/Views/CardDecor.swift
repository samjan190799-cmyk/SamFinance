import SwiftUI

/// Узор на лицевой стороне карты: рисуется тонкими полупрозрачными линиями поверх заливки, под текстом
struct CardPatternView: View {
    let pattern: CardPattern
    let color: Color

    var body: some View {
        // Холст может рисовать вне главного потока, поэтому в замыкание уходят только значения, а не сам экран
        let shape = pattern
        let tint = color
        return Canvas { context, size in
            let ink = GraphicsContext.Shading.color(tint.opacity(0.14))
            CardPatternPainter.paint(shape, in: &context, size: size, ink: ink)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Рисование узоров карты; чистые функции без доступа к состоянию экрана
enum CardPatternPainter {
    static func paint(_ pattern: CardPattern, in context: inout GraphicsContext, size: CGSize, ink: GraphicsContext.Shading) {
        switch pattern {
        case .none:
            break
        case .dots:
            drawDots(&context, size: size, ink: ink)
        case .lines:
            drawLines(&context, size: size, ink: ink)
        case .waves:
            drawWaves(&context, size: size, ink: ink)
        case .rings:
            drawRings(&context, size: size, ink: ink)
        }
    }

    private static func drawDots(_ context: inout GraphicsContext, size: CGSize, ink: GraphicsContext.Shading) {
        let step: CGFloat = 18
        var row = 0
        var y = step / 2
        while y < size.height {
            var x = step / 2 + (row.isMultiple(of: 2) ? 0 : step / 2)
            while x < size.width {
                context.fill(Path(ellipseIn: CGRect(x: x - 1.6, y: y - 1.6, width: 3.2, height: 3.2)), with: ink)
                x += step
            }
            y += step
            row += 1
        }
    }

    private static func drawLines(_ context: inout GraphicsContext, size: CGSize, ink: GraphicsContext.Shading) {
        let step: CGFloat = 16
        var offset = -size.height
        while offset < size.width {
            var path = Path()
            path.move(to: CGPoint(x: offset, y: size.height))
            path.addLine(to: CGPoint(x: offset + size.height, y: 0))
            context.stroke(path, with: ink, lineWidth: 2)
            offset += step
        }
    }

    private static func drawWaves(_ context: inout GraphicsContext, size: CGSize, ink: GraphicsContext.Shading) {
        let spacing: CGFloat = 22
        let amplitude: CGFloat = 8
        var baseline = spacing / 2
        while baseline < size.height + spacing {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: baseline))
            var x: CGFloat = 0
            while x <= size.width {
                path.addLine(to: CGPoint(x: x, y: baseline + sin(x / 22) * amplitude))
                x += 3
            }
            context.stroke(path, with: ink, lineWidth: 1.6)
            baseline += spacing
        }
    }

    private static func drawRings(_ context: inout GraphicsContext, size: CGSize, ink: GraphicsContext.Shading) {
        let center = CGPoint(x: size.width * 0.86, y: size.height * 1.05)
        var radius: CGFloat = 34
        while radius < size.width * 1.2 {
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: ink, lineWidth: 1.6)
            radius += 30
        }
    }
}

/// Знак платёжной системы на карте. Это простые подписи и две пересекающиеся окружности, а не фирменные логотипы.
struct CardNetworkMark: View {
    let network: CardNetwork
    let color: Color

    var body: some View {
        Group {
            switch network {
            case .visa:
                Text("VISA")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .italic()
            case .mastercard:
                ZStack {
                    Circle().fill(color.opacity(0.85)).frame(width: 22, height: 22).offset(x: -8)
                    Circle().fill(color.opacity(0.45)).frame(width: 22, height: 22).offset(x: 8)
                }
                .frame(width: 38, height: 22)
            case .arca:
                Text("ArCa")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            case .mir:
                Text(network.title.uppercased())
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(1)
            case .amex:
                Text("AMEX")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1.4))
            }
        }
        .foregroundColor(color)
        .accessibilityLabel(network.title)
    }
}

/// Ряд готовых цветовых схем: нажатие ставит оба цвета градиента
struct PresetSwatchRow: View {
    @Binding var gradient: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CardPreset.all) { preset in
                    swatch(preset)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func swatch(_ preset: CardPreset) -> some View {
        let isSelected = CardPreset.matching(gradient)?.id == preset.id
        return Button {
            HapticManager.shared.impact(.light)
            withAnimation(Motion.bouncy) {
                gradient = preset.colors
            }
        } label: {
            Circle()
                .fill(LinearGradient(colors: preset.colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(isSelected ? Theme.accent : Theme.line, lineWidth: isSelected ? 2 : 1))
                .scaleEffect(isSelected ? 1.12 : 1)
                .padding(3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
