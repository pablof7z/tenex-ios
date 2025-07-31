### Recent Changes

- Added a `picture` property to the `NDKProject` model for parsing the 'picture' tag from Nostr events.
- Updated `ProjectRowView` to utilize `AsyncImage` for displaying project images. If no image is provided, it defaults to a generic avatar based on the first letter of the project's name, enhancing the visual presentation of project listings.
- The documentation recording feature is fully functional, allowing users to create project documentation through voice recordings. Users can:
  1. Record voice messages for documentation.
  2. View real-time transcription.
  3. Create documentation requests routed to the project-manager agent.
  4. Upload audio files with proper metadata following Nostr standards, ensuring compliance with specifications.
- This implementation aligns with the existing VoiceRecordingView while being specifically tailored to the documentation workflow.