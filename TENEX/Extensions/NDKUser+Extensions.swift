import Foundation
import NDKSwift

extension NDKUser {
    /// Streams projects for this user following the "Never Wait, Always Stream" philosophy
    /// Returns an AsyncStream that yields projects as they arrive from relays
    func streamProjects(maxAge: TimeInterval = 600) -> AsyncStream<NDKProject> {
        AsyncStream { continuation in
            Task {
                guard let ndk = self.ndk else {
                    continuation.finish()
                    return
                }
                
                let filter = NDKFilter(
                    authors: [self.pubkey],
                    kinds: [TENEXEventKind.project]
                )
                
                let dataSource = ndk.observe(
                    filter: filter,
                    maxAge: maxAge,
                    cachePolicy: .cacheWithNetwork
                )
                
                var projectsDict: [String: NDKProject] = [:]
                
                for await event in dataSource.events {
                    let project = NDKProject(event: event)
                    
                    // Use addressableId as key to deduplicate
                    if let existing = projectsDict[project.addressableId] {
                        // Update if newer
                        if event.createdAt > existing.event.createdAt {
                            existing.update(from: event)
                            continuation.yield(existing)
                        }
                    } else {
                        projectsDict[project.addressableId] = project
                        continuation.yield(project)
                    }
                }
                
                continuation.finish()
            }
        }
    }
}