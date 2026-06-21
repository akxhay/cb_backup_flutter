# cbbackup

A modern Flutter app to import, view, and search your WhatsApp chat exports (.zip).

## Features
- Import standard WhatsApp chat export zips (individual or group)
- WhatsApp-style chat viewer with aligned bubbles + inline media (images)
- Search within a chat
- Correct "me" identification with support for multiple name aliases + prompt
- Persisted chats + demo sample loader
- Clean Material 3 UI (Android + iOS)

## Usage
1. Run the app.
2. Tap **Import chat zip** or **Load sample demo**.
3. If your name isn't known, pick it from the prompt so your messages appear on the right.
4. Tap any chat to open the viewer. Use the search bar at the top.

Sample data is provided in `sample/WhatsApp Chat - Rashmi Arya.zip`.

## Development
```bash
flutter pub get
flutter run
```

See the plan for implementation details.
