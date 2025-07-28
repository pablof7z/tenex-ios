# TENEX iOS

An iOS app built with SwiftUI and NDKSwift that replicates the TENEX web client functionality with a Telegram-inspired interface.

## Features

- 🔐 Nostr authentication (private key & NIP-46 bunker)
- 💬 Project list with Telegram-style chat interface
- 🧵 Conversation threads with agent mentions
- 🎙️ Voice calls with audio transcription (OpenAI Whisper)
- 🗣️ Text-to-speech for agent responses
- ⚙️ API key configuration (OpenRouter & OpenAI)
- 🎨 Colored phase indicators for conversation status (chat, brainstorm, plan, execute, verification, review, chores, reflection)

## Requirements

- iOS 16.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Open `TENEX.xcodeproj` in Xcode
2. Configure your development team in project settings
3. Build and run

## Architecture

- **SwiftUI**: Modern declarative UI
- **NDKSwift**: Nostr development kit for iOS
- **MVVM**: Clean architecture pattern
- **Async/Await**: Modern concurrency

## Project Structure

```
TENEX/
├── Views/           # SwiftUI views
├── ViewModels/      # View models
├── Models/          # Data models
├── Managers/        # Business logic
├── Utils/           # Utilities
└── Resources/       # Assets and config
```

## Key Components

- **NostrManager**: Manages NDK lifecycle and Nostr operations
- **NDKAuthView**: Built-in authentication UI
- **Project/Conversation Models**: Data structures for Nostr events
- **Voice Call**: Audio transcription and TTS integration