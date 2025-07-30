### 6. CallView Implementation

**Overview:** The CallView allows users to interact with multiple agents through voice by subscribing to real-time responses and providing a professional call interface.

#### Key Features:
1. **Event Subscription:** Subscribes to kind 21111 events to stream agent responses that tag the conversation.
2. **Incremental Content Updates:** Tracks last spoken content for each agent to avoid repetition during interactions.
3. **Text-to-Speech (TTS) Integration:** Converts agent responses to speech using the AudioManager, enriching the user experience.
4. **User Interface Design:**  
   - Dark background for an elegant call interface.  
   - Animated agent avatars that grow when speaking and shrink when finished.  
   - Visual indicator rings around speaking agents like professional systems.  
   - Displays agent names and truncated messages during speaking.  
   - Professional call controls with an end-call button and connection status indicator.
5. **Multiple Agent Support:** Automatically manages responses from multiple agents, queues their responses, and offers feedback on who is currently speaking. Users can access the CallView by tapping the phone button in a conversation without active input.