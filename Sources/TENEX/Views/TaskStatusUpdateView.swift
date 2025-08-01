import SwiftUI
import NDKSwift
import NDKSwiftUI

struct TaskStatusUpdateView: View {
    let update: NDKEvent
    @Environment(NostrManager.self) var nostrManager
    
    var phase: String? {
        if let phaseTag = update.tags.first(where: { $0.first == "phase" || $0.first == "new-phase" }),
           phaseTag.count > 1 {
            return phaseTag[1]
        }
        return nil
    }
    
    var executionTime: Int? {
        if let timeTag = update.tags.first(where: { $0.first == "net-time" }),
           timeTag.count > 1,
           let time = Int(timeTag[1]) {
            return time
        }
        return nil
    }
    
    
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let createdAt = Date(timeIntervalSince1970: TimeInterval(update.createdAt))
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var formattedExecutionTime: String? {
        guard let time = executionTime else { return nil }
        
        let seconds = time / 1000
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            if remainingSeconds > 0 {
                return "\(minutes)m \(remainingSeconds)s"
            } else {
                return "\(minutes)m"
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Phase icon
            if phase != nil {
                PhaseIconView(phase: phase, size: 24)
            } else {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Author and phase
                HStack(spacing: 4) {
                    NDKUIDisplayName(pubkey: update.pubkey, fallbackStyle: .custom("Agent"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let phase = phase {
                        Text("• \(phase)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Time info
                    HStack(spacing: 8) {
                        Text(relativeTime)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        if let execTime = formattedExecutionTime {
                            HStack(spacing: 2) {
                                Image(systemName: "timer")
                                    .font(.system(size: 10))
                                Text(execTime)
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Update content
                Text(update.content)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }
}