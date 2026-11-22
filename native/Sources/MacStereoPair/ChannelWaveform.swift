import StereoPairCore
import SwiftUI

struct ChannelWaveform: View {
    let channel: ChannelStatus?
    @State private var history = WaveformHistory(capacity: 72, prefill: true)
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Canvas { context, size in
                drawWaveform(context: &context, size: size)
            }
            levelReadout
                .padding(.trailing, 4)
                .padding(.top, 4)
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
        .onChange(of: channel) { _, channel in
            history.append(
                peakDb: channel?.peakDb ?? -120,
                rmsDb: channel?.rmsDb ?? -120,
                clipped: channel?.clipped ?? false
            )
        }
        .accessibilityElement()
        .accessibilityLabel(language.text("accessibility.realtimeWaveform"))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let peak = channel?.peakDb,
              let rms = channel?.rmsDb else {
            return language.text("accessibility.noSignal")
        }
        return language.format("accessibility.levelsFormat", peak, rms)
    }

    private var levelReadout: some View {
        HStack(spacing: 7) {
            if isClipping {
                Text(verbatim: language.text("waveform.clip"))
                    .foregroundStyle(Theme.amber)
            }
            Text(verbatim: language.text("waveform.peak"))
                .foregroundStyle(Theme.muted)
            Text(verbatim: formattedDB(channel?.peakDb))
                .foregroundStyle(isClipping ? Theme.amber : Theme.green)
            Text(verbatim: language.text("waveform.rms"))
                .foregroundStyle(Theme.muted)
            Text(verbatim: formattedDB(channel?.rmsDb))
                .foregroundStyle(Theme.blue)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Theme.background.opacity(0.76))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.separator.opacity(0.65)))
    }

    private func formattedDB(_ value: Double?) -> String {
        guard let value, value > -119 else { return "— dBFS" }
        return String(format: "%.1f dBFS", value)
    }

    private var isClipping: Bool {
        channel?.clipped == true ||
            history.points.contains(where: \.clipped)
    }

    private func drawWaveform(
        context: inout GraphicsContext,
        size: CGSize
    ) {
        let center = size.height / 2
        let points = max(history.capacity, 2)
        let step = size.width / CGFloat(points - 1)
        let visible = history.points
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
        let peakColor = clipping ? Theme.amber : Theme.green

        let fillContext = context
        fillContext.fill(peakEnvelope.area, with: .linearGradient(
            Gradient(colors: [
                peakColor.opacity(0.18),
                peakColor.opacity(0.025)
            ]),
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
        glowContext.addFilter(.shadow(color: peakColor.opacity(0.55), radius: 5))
        glowContext.stroke(peakEnvelope.upper, with: .color(peakColor), lineWidth: 1.6)
        glowContext.stroke(peakEnvelope.lower, with: .color(peakColor), lineWidth: 1.6)

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
        for db in [-48.0, -36.0, -24.0, -12.0] {
            let level = CGFloat((db + 60) / 60)
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
}
