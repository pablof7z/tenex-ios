import SwiftUI

struct PhaseIconView: View {
    let phase: String?
    let size: CGFloat
    
    init(phase: String?, size: CGFloat = 20) {
        self.phase = phase
        self.size = size
    }
    
    var phaseColor: Color {
        switch phase {
        case "chat":
            return .blue
        case "plan":
            return .purple
        case "execute":
            return .green
        case "review":
            return .orange
        case "chores":
            return .gray
        case "brainstorm":
            return .yellow
        case "verification":
            return .teal
        case "reflection":
            return .indigo
        default:
            return .gray.opacity(0.5)
        }
    }
    
    var body: some View {
        Circle()
            .fill(phaseColor)
            .frame(width: size, height: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 30) {
            VStack(spacing: 10) {
                PhaseIconView(phase: "chat")
                Text("Chat").font(.caption)
            }
            VStack(spacing: 10) {
                PhaseIconView(phase: "brainstorm")
                Text("Brainstorm").font(.caption)
            }
            VStack(spacing: 10) {
                PhaseIconView(phase: "plan")
                Text("Plan").font(.caption)
            }
            VStack(spacing: 10) {
                PhaseIconView(phase: "execute")
                Text("Execute").font(.caption)
            }
        }
        HStack(spacing: 30) {
            VStack(spacing: 10) {
                PhaseIconView(phase: "verification")
                Text("Verification").font(.caption)
            }
            VStack(spacing: 10) {
                PhaseIconView(phase: "review")
                Text("Review").font(.caption)
            }
            VStack(spacing: 10) {
                PhaseIconView(phase: "chores")
                Text("Chores").font(.caption)
            }
            VStack(spacing: 10) {
                PhaseIconView(phase: "reflection")
                Text("Reflection").font(.caption)
            }
        }
        VStack(spacing: 10) {
            PhaseIconView(phase: nil)
            Text("Unknown").font(.caption)
        }
    }
    .padding()
}