import SwiftUI

struct WaveformView: View {
    let amplitudes: [Float]
    let isRecording: Bool
    var isPaused: Bool = false
    var barCount: Int = 50
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 2
    var minHeight: CGFloat = 4
    var maxHeight: CGFloat = 40
    
    @State private var animationPhase = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    WaveformBar(
                        amplitude: getAmplitude(for: index),
                        index: index,
                        totalBars: barCount,
                        isRecording: isRecording && !isPaused,
                        animationPhase: animationPhase,
                        barWidth: barWidth,
                        minHeight: minHeight,
                        maxHeight: maxHeight
                    )
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            if isRecording && !isPaused {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    animationPhase = 1.0
                }
            }
        }
        .onChange(of: isRecording) {
            updateAnimation()
        }
        .onChange(of: isPaused) {
            updateAnimation()
        }
    }
    
    private func updateAnimation() {
        if isRecording && !isPaused {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                animationPhase = 1.0
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                animationPhase = 0.0
            }
        }
    }
    
    private func getAmplitude(for index: Int) -> Float {
        let recentBarsCount = min(amplitudes.count, barCount)
        let startIndex = max(0, amplitudes.count - recentBarsCount)
        let relativeIndex = index - (barCount - recentBarsCount)
        
        if relativeIndex >= 0 && relativeIndex < recentBarsCount {
            let amplitudeIndex = startIndex + relativeIndex
            return amplitudes[amplitudeIndex]
        }
        
        return 0.0
    }
}

private struct WaveformBar: View {
    let amplitude: Float
    let index: Int
    let totalBars: Int
    let isRecording: Bool
    let animationPhase: Double
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    private var barHeight: CGFloat {
        let baseHeight = minHeight + (maxHeight - minHeight) * CGFloat(amplitude)
        
        // Add subtle animation for bars near the end when recording
        if isRecording && index >= totalBars - 10 {
            let distance = Double(totalBars - index) / 10.0
            let wave = sin(animationPhase * .pi * 4 + Double(index) * 0.2) * 0.3
            let modifier = 1.0 + wave * distance
            return baseHeight * CGFloat(modifier)
        }
        
        return baseHeight
    }
    
    private var barColor: Color {
        let progress = CGFloat(index) / CGFloat(totalBars)
        
        if isRecording {
            // Active recording - red gradient
            return Color.red.opacity(0.8 - progress * 0.3)
        } else {
            // Inactive - subtle white/gray
            return Color.white.opacity(0.4 - progress * 0.2)
        }
    }
    
    var body: some View {
        Capsule()
            .fill(barColor)
            .frame(width: barWidth, height: barHeight)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: barHeight)
    }
}