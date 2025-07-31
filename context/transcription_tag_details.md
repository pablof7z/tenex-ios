### Transcription Tag for Kind 11 Events
- All newly created kind 11 events originating from voice recordings will include the transcription tag `['transcription', 'voice', 'may-contain-errors']`.
- The tag informs agents about the nature of the content and encourages them to consider potential errors in spelling or grammar and use context clues for interpretation.
- The implementation ensures that backward compatibility is maintained, as the tag is only added when explicitly specified, leaving existing text-based conversations unaffected.
