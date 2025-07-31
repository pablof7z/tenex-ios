### Build Process

**Overview:** Always use the './build.sh' script to build the project.

## Project Overview

TENEX is an iOS application that integrates with the Nostr protocol using NDKSwift. The app provides a social learning platform where agents can post articles and lessons, and users can interact through comments and voice notes.

## Current State

The project includes:
- Basic app structure with SwiftUI views
- Nostr integration using NDKSwift
- Feed view displaying articles from Nostr
- Article detail view with commenting functionality
- Voice note recording and posting to Nostr
- Agent profile view with lessons tab functionality
- Lesson detail view with commenting capability
- Navigation between different views
- Basic audio recording and playback functionality
- Support for both articles and lessons with respective detail views

## Recent Changes

### Latest Updates (Current Session)
- Added LessonDetailView for viewing and commenting on lessons
- Enhanced AgentProfileView with lessons tab showing lessons posted by the agent
- Updated ArticleDetailView to support navigation to lesson details
- Improved navigation flow between articles, lessons, and agent profiles
- Integrated voice note support for comments on both articles and lessons

### Previous Updates
- Refactored NostrManager initialization and updated to NDKSwift v0.11
- Added voice recording support with AudioManager
- Implemented article commenting functionality
- Established basic feed view for browsing articles

## Architecture

The app follows a SwiftUI-based architecture with:
- **Views**: SwiftUI views for UI presentation
  - FeedView: Main feed displaying articles
  - ArticleDetailView: Article viewing and commenting
  - LessonDetailView: Lesson viewing and commenting
  - AgentProfileView: Agent profiles with articles/lessons tabs
  - VoiceNoteView: Voice recording interface
- **Managers**: 
  - NostrManager: Core Nostr protocol integration using NDKSwift
- **Services**: 
  - AudioManager: Voice recording and playback functionality
- **Models**: 
  - NDK models for Nostr data structures (events, users, etc.)

## Key Features

1. **Nostr Integration**: Full integration with Nostr protocol for decentralized content
2. **Content Types**: Support for both articles (kind 30023) and lessons (kind 30024)
3. **Voice Notes**: Recording and posting voice comments as audio events
4. **Social Features**: User profiles, following system, and commenting
5. **Navigation**: Seamless navigation between articles, lessons, and profiles

## Build Instructions

Always use the `./build.sh` script to build the project. This ensures proper configuration and dependency management.

## Dependencies

- NDKSwift v0.11+ (from GitHub repository)
- Standard iOS frameworks (SwiftUI, AVFoundation, etc.)