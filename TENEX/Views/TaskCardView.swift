import SwiftUI
import NDKSwift

struct TaskCardView: View {
    let task: NDKTask
    let project: NDKProject
    @Environment(NostrManager.self) var nostrManager
    @State private var statusUpdates: [NDKEvent] = []
    @State private var latestStatus: String = "pending"
    @State private var isRunning: Bool = false
    @State private var latestUpdate: NDKEvent?
    @State private var statusSubscription: Task<Void, Never>?
    
    var onTap: (() -> Void)?
    
    var complexity: Int? {
        if let complexityTag = task.event.tags.first(where: { $0.first == "complexity" }),
           complexityTag.count > 1,
           let complexity = Int(complexityTag[1]) {
            return complexity
        }
        return nil
    }
    
    var isClaudeCodeTask: Bool {
        task.event.tags.contains { tag in
            tag.count > 1 && tag[0] == "tool" && tag[1] == "claude_code"
        }
    }
    
    var agentName: String? {
        if let agentTag = task.event.tags.first(where: { $0.first == "agent" }),
           agentTag.count > 1 {
            return agentTag[1]
        }
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                // Icon
                if isClaudeCodeTask {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Title and controls
                    HStack {
                        Text(task.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        // Stop button if running
                        if isRunning {
                            Button(action: abortTask) {
                                HStack(spacing: 4) {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 10))
                                    Text("Stop")
                                        .font(.system(size: 12))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                            }
                        }
                        
                        // Agent name
                        if let agentName = agentName {
                            Text(agentName)
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                        }
                        
                        // Claude Code badge
                        if isClaudeCodeTask {
                            Text("Claude Code")
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }
                    }
                    
                    // Latest update or content preview
                    if let latestUpdate = latestUpdate {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(latestUpdate.content)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .padding(.leading, 2)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 4)
                                        .padding(.vertical, 2),
                                    alignment: .leading
                                )
                        }
                    } else {
                        Text(task.content)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Status indicators
                    HStack(spacing: 8) {
                        // Status badge
                        HStack(spacing: 4) {
                            if isRunning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Status: \(latestStatus)")
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                        
                        // Complexity badge
                        if let complexity = complexity {
                            Text("Complexity: \(complexity)/10")
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(12)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onTapGesture {
            onTap?()
        }
        .task {
            statusSubscription = Task {
                await subscribeToStatusUpdates()
            }
        }
        .onDisappear {
            statusSubscription?.cancel()
        }
    }
    
    private func subscribeToStatusUpdates() async {
        // Subscribe to status updates for this task
        let filter = NDKFilter(
            kinds: [EventKind.genericReply],
            tags: ["e": [task.id]]
        )
        
        let statusDataSource = nostrManager.ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Stream status updates reactively
        for await event in statusDataSource.events {
            // Update the status updates array
            statusUpdates.append(event)
            
            // Get the latest update
            let sortedUpdates = statusUpdates.sorted { $0.createdAt > $1.createdAt }
            if let latest = sortedUpdates.first {
                latestUpdate = latest
                
                // Update status from the latest update
                if let statusTag = latest.tags.first(where: { $0.first == "status" }),
                   statusTag.count > 1 {
                    latestStatus = statusTag[1]
                    isRunning = (latestStatus == "progress")
                }
            }
        }
    }
    
    private func abortTask() {
        Task {
            do {
                // Create ephemeral abort event
                let abortEvent = try await NDKEventBuilder(ndk: nostrManager.ndk)
                    .kind(24133) // Ephemeral event for task abort
                    .content("abort")
                    .tag(["e", task.id, "", "task"]) // Reference the task to abort
                    .build()
                
                try await nostrManager.ndk.publish(abortEvent)
            } catch {
                print("Failed to publish abort event: \(error)")
            }
        }
    }
}
