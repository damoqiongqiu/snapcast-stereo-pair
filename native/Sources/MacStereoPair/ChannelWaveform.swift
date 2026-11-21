import StereoPairCore
import SwiftUI

struct ChannelWaveform: View {
    let channel: ChannelStatus?
    @State private var history = WaveformHistory(capacity: 72, prefill: true)
    @EnvironmentObject private var language: AppLanguage

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { timeline in
            Canvas { context, size in
                drawWaveform(
                    context: &context,
                    size: size,
                    phase: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .frame(height: 88)
        .onChange(of: channel?.peakDb) { _, _ in
            history.append(peakDb: channel?.peakDb ?? -120, rmsDb: channel?.rmsDb ?? -120)
        }
        .accessibilityElement()
        .accessibilityLabel(language.text("accessibility.realtimeWaveform"))
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let peak = channel?.peakDb else { return language.text("accessibility.noSignal") }
        return language.format("accessibility.peakFormat", peak)
    }

    private func drawWaveform(context: inout GraphicsContext, size: CGSize, phase: TimeInterval) {
        let center = size.height / 2
        let points = max(history.capacity, 2)
        let step = size.width / CGFloat(points - 1)
        let visible = history.samples
        guard visible.count > 1 else {
            var line = Path()
            line.move(to: CGPoint(x: 0, y: center))
            line.addLine(to: CGPoint(x: size.width, y: center))
            context.stroke(line, with: .color(Theme.muted.opacity(0.35)), lineWidth: 1)
            return
        }

        var top = Path()
        var bottom = Path()
        var area = Path()
        let gradient = Gradient(colors: [
            Theme.blue,
            Theme.green.opacity(0.95),
            Theme.amber.opacity(0.9)
        ])

        for (index, sample) in visible.enumerated() {
            let x = CGFloat(index) * step
            let shimmer = 0.84 + (0.16 * sin((Double(index) * 1.73) + (phase * 3.2)))
            let energy = CGFloat(sample * shimmer) * center * 0.88
            let topPoint = CGPoint(x: x, y: center - energy)
            let bottomPoint = CGPoint(x: x, y: center + energy)
            if index == 0 {
                top.move(to: topPoint)
                bottom.move(to: bottomPoint)
                area.move(to: topPoint)
                area.addLine(to: bottomPoint)
            } else {
                let previousX = CGFloat(index - 1) * step
                let control = (previousX + x) / 2
                let previousShimmer = 0.84 + (0.16 * sin((Double(index - 1) * 1.73) + (phase * 3.2)))
                let previousEnergy = CGFloat(visible[index - 1] * previousShimmer) * center * 0.88
                top.addCurve(
                    to: topPoint,
                    control1: CGPoint(x: control, y: center - previousEnergy),
                    control2: CGPoint(x: control, y: center - energy)
                )
                bottom.addCurve(
                    to: bottomPoint,
                    control1: CGPoint(x: control, y: center + previousEnergy),
                    control2: CGPoint(x: control, y: center + energy)
                )
                area.addCurve(
                    to: bottomPoint,
                    control1: CGPoint(x: control, y: center + previousEnergy),
                    control2: CGPoint(x: control, y: center + energy)
                )
            }
        }
        area.closeSubpath()
        var fillContext = context
        fillContext.opacity = 0.12
        fillContext.fill(area, with: .linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: 0)
        ))
        var glowContext = context
        glowContext.addFilter(.shadow(color: Theme.green.opacity(0.55), radius: 5))
        glowContext.stroke(top, with: .linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: 0)
        ), lineWidth: 1.6)
        glowContext.stroke(bottom, with: .linearGradient(
            gradient,
            startPoint: CGPoint(x: 0, y: 0),
            endPoint: CGPoint(x: size.width, y: 0)
        ), lineWidth: 1.6)

        var centerline = Path()
        centerline.move(to: CGPoint(x: 0, y: center))
        centerline.addLine(to: CGPoint(x: size.width, y: center))
        context.stroke(centerline, with: .color(Theme.separator.opacity(0.6)), lineWidth: 0.5)
    }
}
