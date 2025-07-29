import SwiftUI
import NDKSwift

struct ArticleListView: View {
    let project: NDKProject
    @Environment(NostrManager.self) var nostrManager
    @State private var articles: [NDKEvent] = []
    
    private var sortedArticles: [NDKEvent] {
        articles.sorted { article1, article2 in
            let date1 = Date(timeIntervalSince1970: TimeInterval(article1.createdAt))
            let date2 = Date(timeIntervalSince1970: TimeInterval(article2.createdAt))
            return date1 > date2
        }
    }
    
    var body: some View {
        Group {
            if sortedArticles.isEmpty {
                ContentUnavailableView(
                    "No documentation yet",
                    systemImage: "doc.text",
                    description: Text("Documentation articles will appear here when published by agents.")
                )
            } else {
                List {
                    ForEach(sortedArticles, id: \.id) { article in
                        NavigationLink(destination: ArticleDetailView(
                            project: project,
                            article: article
                        )) {
                            ArticleRowView(article: article)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await streamArticles()
        }
    }
    
    private func streamArticles() async {
        // Create filter for articles (kind 30023) tagging this project
        let filter = NDKFilter(
            kinds: [30023], // Long-form content
            tags: ["a": [project.addressableId]]
        )
        
        // Use NDK directly to stream articles
        guard let ndk = nostrManager.ndk else { return }
        let articlesDataSource = ndk.observe(
            filter: filter,
            maxAge: 300, // Use 5 minute cache for articles
            cachePolicy: .cacheWithNetwork
        )
        
        // Stream articles as they arrive
        for await event in articlesDataSource.events {
            await MainActor.run {
                // Add new article if not already present
                if !articles.contains(where: { $0.id == event.id }) {
                    articles.append(event)
                }
            }
        }
    }
}

struct ArticleRowView: View {
    let article: NDKEvent
    
    var title: String {
        // Extract title from tags
        article.tags.first(where: { $0.count > 1 && $0[0] == "title" })?[1] ?? "Untitled Document"
    }
    
    var summary: String? {
        // Extract summary from tags
        article.tags.first(where: { $0.count > 1 && $0[0] == "summary" })?[1]
    }
    
    var publishedAt: Date {
        if let timestamp = article.tags.first(where: { $0.count > 1 && $0[0] == "published_at" })?[1],
           let timeInterval = TimeInterval(timestamp) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return Date(timeIntervalSince1970: TimeInterval(article.createdAt))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Doc Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                if let summary = summary {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                } else {
                    Text("No summary available")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .italic()
                }
                
                HStack(spacing: 4) {
                    Text(formatDate(publishedAt))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    if publishedAt != Date(timeIntervalSince1970: TimeInterval(article.createdAt)) {
                        Text("•")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Text("Updated")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}