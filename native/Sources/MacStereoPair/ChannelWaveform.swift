import StereoPairCore
import SwiftUI

struct ChannelWaveform: View {
    let points: [WaveformHistory.Point]
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        Canvas { context, size in
            drawWaveform(context: &context, size: size)
        }
        .frame(height: 88)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.background.opacity(0.34))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Theme.separator.opacity(0.55))
        )
        .accessibilityElement()
        .accessibilityLabel(language.text("accessibility.realtimeWaveform"))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let point = points.last,
              point.peak > 0,
              point.rms > 0 else {
            return language.text("accessibility.noSignal")
        }
        return language.format(
            "accessibility.levelsFormat",
            db(from: point.peak),
            db(from: point.rms)
        )
    }

    private func db(from normalized: Double) -> Double {
        normalized * 60 - 60
    }

    private func drawWaveform(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let center = size.height / 2
        let sampleCount = max(points.count, 2)
        let step = size.width / CGFloat(sampleCount - 1)
        let visible = points
        let halfHeight = center * 0.84

        drawGrid(
            context: &context,
            size: size,
            center: center,
            halfHeight: halfHeight
        )

        guard visible.count > 1 else {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: center))
            line.addLine(to: CGPoint(x: size.width, y: center))
            context.stroke(line, with: .color(Theme.muted.opacity(0.35)), lineWidth: 1)
            return
        }

        let peaks = visible.map(\.peak)
        let rms = visible.map(\.rms)
        let peakEnvelope = envelope(
            values: peaks,
            center: center,
            step: step,
            halfHeight: halfHeight
        )
        let rmsEnvelope = envelope(
            values: rms,
            center: center,
            step: step,
            halfHeight: halfHeight
        )
        let clipping = visible.contains(where: \.clipped)
        let lineGradient = peakLineGradient(clipping: clipping)
        let fillGradient = peakFillGradient(clipping: clipping)

        let fillContext = context
        fillContext.fill(peakEnvelope.area, with: .linearGradient(
            fillGradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        ))
        let rmsFill = context
        rmsFill.fill(rmsEnvelope.area, with: .linearGradient(
            Gradient(colors: [
                Theme.blue.opacity(0.20),
                Theme.blue.opacity(0.035)
            ]),
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        ))

        var glowContext = context
        let accent = clipping
            ? Theme.red
            : (points.last.map { peakColor(for: $0.peak) } ?? Theme.green)
        glowContext.addFilter(.shadow(color: accent.opacity(0.5), radius: 5))
        let stroke = GraphicsContext.Shading.linearGradient(
            lineGradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: 0, y: size.height)
        )
        glowContext.stroke(peakEnvelope.upper, with: stroke, lineWidth: 1.6)
        glowContext.stroke(peakEnvelope.lower, with: stroke, lineWidth: 1.6)

        context.stroke(rmsEnvelope.upper, with: .color(Theme.blue.opacity(0.9)), lineWidth: 1.1)
        context.stroke(rmsEnvelope.lower, with: .color(Theme.blue.opacity(0.9)), lineWidth: 1.1)

        var centerline = Path()
        centerline.move(to: CGPoint(x: 0, y: center))
        centerline.addLine(to: CGPoint(x: size.width, y: center))
        context.stroke(centerline, with: .color(Theme.separator.opacity(0.8)), lineWidth: 0.6)
    }

    private func drawGrid(
        context: inout GraphicsContext,
        size: CGSize,
        center: CGFloat,
        halfHeight: CGFloat
    ) {
        for db in [-48.0, -36.0, -24.0, -12.0, -6.0, -3.0] {
            let level = CGFloat(normalized(db))
            for y in [center - level * halfHeight, center + level * halfHeight] {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    line,
                    with: .color(Theme.separator.opacity(0.46)),
                    lineWidth: 0.5
                )
            }
        }
    }

    private func normalized(_ db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }

    private func peakLineGradient(clipping: Bool) -> Gradient {
        if clipping {
            return Gradient(colors: [
                Theme.red,
                Theme.red,
                Theme.amber,
                Theme.green,
                Theme.green,
                Theme.amber,
                Theme.red,
                Theme.red
            ])
        }
        return Gradient(stops: [
            .init(color: Theme.red, location: 0),
            .init(color: Theme.red, location: 0.035),
            .init(color: Theme.amber, location: 0.10),
            .init(color: Theme.amber, location: 0.15),
            .init(color: Theme.green, location: 0.22),
            .init(color: Theme.green, location: 0.78),
            .init(color: Theme.amber, location: 0.85),
            .init(color: Theme.amber, location: 0.90),
            .init(color: Theme.red, location: 0.965),
            .init(color: Theme.red, location: 1)
        ])
    }

    private func peakFillGradient(clipping: Bool) -> Gradient {
        if clipping {
            return Gradient(colors: [
                Theme.red.opacity(0.17),
                Theme.amber.opacity(0.12),
                Theme.green.opacity(0.08),
                Theme.amber.opacity(0.12),
                Theme.red.opacity(0.17)
            ])
        }
        return Gradient(stops: [
            .init(color: Theme.red.opacity(0.14), location: 0),
            .init(color: Theme.amber.opacity(0.12), location: 0.16),
            .init(color: Theme.green.opacity(0.08), location: 0.30),
            .init(color: Theme.green.opacity(0.06), location: 0.70),
            .init(color: Theme.amber.opacity(0.12), location: 0.84),
            .init(color: Theme.red.opacity(0.14), location: 1)
        ])
    }

    private func envelope(
        values: [Double],
        center: CGFloat,
        step: CGFloat,
        halfHeight: CGFloat
    ) -> (upper: Path, lower: Path, area: Path) {
        var upper = Path()
        var lower = Path()
        var area = Path()

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * step
            let energy = CGFloat(value) * halfHeight
            let upperPoint = CGPoint(x: x, y: center - energy)
            let lowerPoint = CGPoint(x: x, y: center + energy)
            if index == 0 {
                upper.move(to: upperPoint)
                lower.move(to: lowerPoint)
                area.move(to: upperPoint)
            } else {
                let previousX = CGFloat(index - 1) * step
                let control = (previousX + x) / 2
                let previousEnergy = CGFloat(values[index - 1]) * halfHeight
                upper.addCurve(
                    to: upperPoint,
                    control1: CGPoint(x: control, y: center - previousEnergy),
                    control2: CGPoint(x: control, y: center - energy)
                )
                lower.addCurve(
                    to: lowerPoint,
                    control1: CGPoint(x: control, y: center + previousEnergy),
                    control2: CGPoint(x: control, y: center + energy)
                )
                area.addCurve(
                    to: upperPoint,
                    control1: CGPoint(x: control, y: center - previousEnergy),
                    control2: CGPoint(x: control, y: center - energy)
                )
            }
        }
        for (index, value) in values.enumerated().reversed() {
            area.addLine(to: CGPoint(
                x: CGFloat(index) * step,
                y: center + CGFloat(value) * halfHeight
            ))
        }
        area.closeSubpath()
        return (upper, lower, area)
    }

    private func peakColor(for peak: Double) -> Color {
        if peak >= normalized(-3) {
            return Theme.red
        }
        if peak >= normalized(-12) {
            return Theme.amber
        }
        return Theme.green
    }
}

struct WaveformLevelReadout: View {
    let point: WaveformHistory.Point?
    let clipped: Bool
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        HStack(spacing: 6) {
            if clipped {
                Text(verbatim: language.text("waveform.clip"))
                    .foregroundStyle(Theme.red)
            }
            Text(verbatim: language.text("waveform.peak"))
                .foregroundStyle(Theme.muted)
            Text(verbatim: formattedDB(point?.peak))
                .foregroundStyle(peakAccent)
            Text(verbatim: language.text("waveform.rms"))
                .foregroundStyle(Theme.muted)
            Text(verbatim: formattedDB(point?.rms))
                .foregroundStyle(Theme.blue)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.background.opacity(0.55))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.separator.opacity(0.55)))
        .lineLimit(1)
        .fixedSize()
    }

    private var peakAccent: Color {
        if clipped || (point?.peak ?? 0) >= normalized(-3) {
            return Theme.red
        }
        if (point?.peak ?? 0) >= normalized(-12) {
            return Theme.amber
        }
        return Theme.green
    }

    private func formattedDB(_ normalized: Double?) -> String {
        guard let normalized, normalized > 0 else { return "— dBFS" }
        return String(format: "%.1f dBFS", normalized * 60 - 60)
    }

    private func normalized(_ db: Double) -> Double {
        min(1, max(0, (db + 60) / 60))
    }
}
