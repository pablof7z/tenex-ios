import SwiftUI
import NDKSwift

struct ArticleDetailView: View {
    let project: NDKProject
    let article: NDKEvent
    @Environment(\.dismiss) var dismiss
    
    var title: String {
        article.tags.first(where: { $0.count > 1 && $0[0] == "title" })?[1] ?? "Untitled Document"
    }
    
    var summary: String? {
        article.tags.first(where: { $0.count > 1 && $0[0] == "summary" })?[1]
    }
    
    var publishedAt: Date {
        if let timestamp = article.tags.first(where: { $0.count > 1 && $0[0] == "published_at" })?[1],
           let timeInterval = TimeInterval(timestamp) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return Date(timeIntervalSince1970: TimeInterval(article.createdAt))
    }
    
    var createdAt: Date {
        Date(timeIntervalSince1970: TimeInterval(article.createdAt))
    }
    
    var hashtags: [String] {
        article.tags
            .filter { $0.count > 1 && $0[0] == "t" }
            .map { $0[1] }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Metadata
                    HStack(spacing: 16) {
                        Label(formatDate(createdAt), systemImage: "calendar")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                        
                        if publishedAt != createdAt {
                            Label("Updated " + formatDate(publishedAt), systemImage: "clock")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Label(readingTime, systemImage: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    // Summary
                    if let summary = summary {
                        Text(summary)
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    
                    // Tags
                    if !hashtags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(hashtags, id: \.self) { tag in
                                    HStack(spacing: 2) {
                                        Image(systemName: "number")
                                            .font(.system(size: 10))
                                        Text(tag)
                                            .font(.system(size: 12))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .padding(.horizontal)
                
                // Content
                Text(article.content)
                    .font(.system(size: 16))
                    .padding(.horizontal)
                    .textSelection(.enabled)
                
                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text("Published at \(formatTime(createdAt)) on \(formatDate(createdAt))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    if publishedAt != createdAt {
                        Text("Last updated at \(formatTime(publishedAt))")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .padding(.vertical)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        UIPasteboard.general.string = article.tags.first(where: { $0.count > 1 && $0[0] == "a" })?[1] ?? ""
                    }) {
                        Label("Copy Spec Encoding", systemImage: "doc.on.doc")
                    }
                    
                    Button(action: {
                        // Share functionality
                    }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    
    var readingTime: String {
        let wordsPerMinute = 200
        let words = article.content.split(separator: " ").count
        let minutes = max(1, words / wordsPerMinute)
        return "\(minutes) min read"
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}