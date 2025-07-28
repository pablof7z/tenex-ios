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
                
                // Content with markdown rendering
                MarkdownView(content: article.content)
                    .padding(.horizontal)
                
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

// Basic Markdown rendering view
struct MarkdownView: View {
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(parseMarkdown(content), id: \.self) { element in
                renderElement(element)
            }
        }
    }
    
    func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.components(separatedBy: .newlines)
        var currentParagraph = ""
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.isEmpty {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
            } else if trimmedLine.hasPrefix("# ") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
                elements.append(.heading1(String(trimmedLine.dropFirst(2))))
            } else if trimmedLine.hasPrefix("## ") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
                elements.append(.heading2(String(trimmedLine.dropFirst(3))))
            } else if trimmedLine.hasPrefix("### ") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
                elements.append(.heading3(String(trimmedLine.dropFirst(4))))
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
                elements.append(.listItem(String(trimmedLine.dropFirst(2))))
            } else if trimmedLine.hasPrefix("> ") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
                elements.append(.quote(String(trimmedLine.dropFirst(2))))
            } else if trimmedLine.hasPrefix("```") {
                if !currentParagraph.isEmpty {
                    elements.append(.paragraph(currentParagraph))
                    currentParagraph = ""
                }
                elements.append(.codeBlock(trimmedLine))
            } else {
                currentParagraph += (currentParagraph.isEmpty ? "" : " ") + trimmedLine
            }
        }
        
        if !currentParagraph.isEmpty {
            elements.append(.paragraph(currentParagraph))
        }
        
        return elements
    }
    
    @ViewBuilder
    func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .heading1(let text):
            Text(text)
                .font(.system(size: 28, weight: .bold))
                .padding(.top, 8)
        case .heading2(let text):
            Text(text)
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 6)
        case .heading3(let text):
            Text(text)
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 4)
        case .paragraph(let text):
            Text(formatInlineMarkdown(text))
                .font(.system(size: 16))
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 16))
                Text(formatInlineMarkdown(text))
                    .font(.system(size: 16))
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)
                Text(text)
                    .font(.system(size: 16))
                    .italic()
                    .foregroundColor(.gray)
            }
        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 14, design: .monospaced))
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    func formatInlineMarkdown(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        
        // Handle bold text
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = boldRegex.matches(in: text, range: nsRange)
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    if let attrRange = Range(range, in: attributed) {
                        attributed[attrRange].font = .system(size: 16, weight: .bold)
                    }
                }
            }
        }
        
        // Handle italic text
        if let italicRegex = try? NSRegularExpression(pattern: "\\*(.+?)\\*") {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = italicRegex.matches(in: text, range: nsRange)
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    if let attrRange = Range(range, in: attributed) {
                        attributed[attrRange].font = .system(size: 16).italic()
                    }
                }
            }
        }
        
        // Handle inline code
        if let codeRegex = try? NSRegularExpression(pattern: "`(.+?)`") {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = codeRegex.matches(in: text, range: nsRange)
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: text) {
                    if let attrRange = Range(range, in: attributed) {
                        attributed[attrRange].font = .system(size: 14, design: .monospaced)
                        attributed[attrRange].backgroundColor = Color.gray.opacity(0.1)
                    }
                }
            }
        }
        
        return attributed
    }
}

enum MarkdownElement: Hashable {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case paragraph(String)
    case listItem(String)
    case quote(String)
    case codeBlock(String)
}