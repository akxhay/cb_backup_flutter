# cbbackup - Project Plan & Documentation

> This is the **living project plan**. Whenever any significant change is made (new features, refactors, bug fixes, architecture decisions, etc.), this file **must** be updated.

## Overview

**cbbackup** is a Flutter mobile application (Android + iOS) that allows users to import, view, and search their exported WhatsApp chat backups (`.zip` files containing `_chat.txt` + media).

The app provides a WhatsApp-like experience for browsing chat history offline, with proper "me vs other" message alignment, media display, and text search.

**Primary use case**: Users export chats from WhatsApp and import them into cbbackup for easy viewing, searching, and archiving.

## Requirements

### Core Functional Requirements

1. **Import WhatsApp chat zips**
   - Support importing standard WhatsApp exported `.zip` files.
   - Must work for both individual and group chats.

2. **Chat List**
   - Show all previously imported chats.
   - Display title, last message preview, message count, and type (individual/group).
   - Support deleting chats.

3. **Chat Viewer (WhatsApp-like)**
   - Chronological list of messages.
   - Proper bubble alignment (right = self, left = other).
   - Support for text messages and embedded media (images).
   - Scrollable, clean, modern UI.
   - Date/day separators visible (TODAY, YESTERDAY, dates) like WhatsApp.
   - Loading indicators for any async processing (e.g., video thumbnail generation).
   - Show sender name on other people's messages.

4. **Search**
   - Full-text search within a single chat.
   - Real-time filtering.

5. **Self Identification ("Me")**
   - The app must correctly identify which participant is the user ("me").
   - Support multiple aliases (e.g. real name in 1:1 chats + "me" or "You" in group chats).
   - If identity cannot be determined automatically, prompt the user during import.
   - Persist user's known aliases across sessions.

6. **Zip Filename as Source of Truth for Title**
   - When importing, **first try to parse the chat title (contact/group name) from the zip filename**.
   - Expected format (from sample): `WhatsApp Chat - <Name>.zip`
   - Example: `WhatsApp Chat - Rashmi Arya.zip` → Title = "Rashmi Arya"
   - If the filename does **not** match the expected format, show a clear error and reject the import.
   - This takes precedence over deriving the title from message senders.

7. **Media Support**
   - Support **all media types** from WhatsApp exports (images, videos, audio/voice notes, documents, PDFs, etc.).
   - Media messages are shown with appropriate icons.
   - Tapping any media (image or other) opens it in the device's **default application** (photo viewer, video player, PDF reader, etc.).
   - Uses `open_filex` package.
   - Media gallery is a dedicated icon (last in AppBar). Full-screen modern gallery with separate tabs: All / Photos / Stickers / Videos / Documents / Audio. Beautiful rounded grid cards, gradient overlays, counts, pinch-to-zoom for images.
   - Videos use icon + filename (thumbnails reverted due to performance lag in chat scroll).

7. **UI & Platform**
   - Modern, catchy Material 3 design.
   - Fully functional on both Android and iOS.
   - Good experience in light and dark mode.

### Non-Functional / Nice-to-Haves (Current Scope)

- "Load sample demo" using the included `sample/` zip for immediate testing.
- Local persistence only (no cloud).
- Simple JSON + file-based storage.

## Architecture & Tech Decisions

- **State Management**: `provider` + `ChangeNotifier` (lightweight and sufficient).
- **Persistence**:
  - Chat metadata + messages stored as JSON in app documents.
  - Extracted zips + media kept in per-chat folders.
  - User aliases stored via `shared_preferences`.
- **Parsing**:
  - Custom `parseChat()` for `_chat.txt` (handles timestamps, multi-line messages, attachments, unicode).
  - `parseChatTitleFromZipFilename()` for extracting title from filename (strict format check).
- **File Handling**: `file_picker` + `archive` package for zip extraction.
- **Theming**: Material 3 with teal seed color.
- **No heavy dependencies** for MVP (no Riverpod, Isar, etc. yet).

## Current Project Structure

```
lib/
├── main.dart                      # App entry + MultiProvider setup
├── models/
│   └── chat.dart                  # Chat + ChatMessage models
├── services/
│   ├── chat_parser.dart           # parseChat + parseChatTitleFromZipFilename
│   ├── chat_repository.dart       # Import, extract, persist, load chats
│   └── self_identity_service.dart # Manage user's aliases
├── screens/
│   ├── chat_list_screen.dart      # List + Import + Sample loader + Self prompt
│   └── chat_screen.dart           # WhatsApp-style viewer + search
└── widgets/
    └── message_bubble.dart        # Reusable message UI component

test/
└── chat_parser_test.dart          # Parser + filename parsing tests

sample/
└── WhatsApp Chat - Rashmi Arya.zip
```

## Key Components

| Component                    | Responsibility                                      | Important Notes |
|-----------------------------|-----------------------------------------------------|-----------------|
| `ChatRepository`            | Import zips, extract, parse, persist, CRUD          | Title comes from filename first |
| `parseChatTitleFromZipFilename` | Extract name from "WhatsApp Chat - X.zip"        | Throws on bad format |
| `SelfIdentityService`       | Store/retrieve user's name aliases                  | Used for `isSelf()` logic |
| `parseChat`                 | Convert raw _chat.txt into `List<ChatMessage>`      | Handles attachments, system msgs |
| `ChatScreen`                | Render messages + in-chat search                    | Uses `MessageBubble` |
| `ChatListScreen`            | Show imported chats + import flows                  | Prompts for identity when needed |

## Implementation Status (as of 2026-06-21)

**Completed Features**:
- Full import pipeline from zip (with filename-based title)
- WhatsApp-style chat viewer with image support
- In-chat search
- Self identification with multi-alias support + prompt
- Sample data loader
- Local persistence of chats and aliases
- Proper error when zip filename is wrong format
- Unit tests for parsing logic
- Modern Material 3 UI on Android + iOS
- Modern full-screen media gallery (separate tabs for photos/stickers/videos/docs/audio) triggered by last AppBar icon, with catchy grids and image viewer

**Known Current Limitations**:
- Only images are rendered as media (videos/documents not handled)
- No export functionality (PDF, text, etc.)
- No cloud sync
- Filename parsing is strict (based on sample)

## Recent Changes

### 2026-06-21 - Major UI polish & modern chat experience (inspired by Neumorphism dark chat designs)
- Refined overall look for a more premium, modern, "catchy" chat UI while staying faithful to WhatsApp.
- **Theme**: Enhanced Material 3 with rounded CardTheme (16px), pill-shaped input fields, nicer AppBar.
- **Home / Chat list**:
  - Replaced plain ListTiles + dividers with modern Card-based rows (rounded, subtle shadows, generous padding).
  - Larger, styled avatars. Better typography hierarchy (bold title, muted subtitle).
  - Improved empty state with larger icon and clearer text.
- **Chat header**: Added leading avatar (group/person) for visual polish and quick recognition. Nicer action icons.
- **Search bar**: Cleaner pill style leveraging theme.
- **Message bubbles**:
  - Increased corner radii (20px) for softer modern look.
  - Added tasteful box shadows for depth and lift (subtle in light, stronger in dark).
  - Polished captions, timestamps, "edited", file rows, media containers.
- **Date separators & system messages**: Softer backgrounds, better padding, slight shadows.
- **Media gallery**: Added depth shadows to grid tiles, refined empty states, improved full-screen image viewer (transparent appbar, gradient caption, wider zoom range).
- **General**: Better spacing, font weights, line heights, consistent 14-20px rounding, modern icon usage.
- Keeps excellent WA bubble colors, alignment, and media fidelity.

### 2026-06-21 - Chat list preview now shows media last messages correctly (no longer blank)
- Fixed bug where home screen (chat list) subtitle was blank (or fell back to message count) when the most recent message in a chat was a media item (photo/video/audio/doc) without a text caption.
- Root cause: WhatsApp exports often prefix attachment tags with LRM (\u200E) direction mark; pure media messages ended up with non-empty but invisible `.text` containing only LRM. `buildPreview` took the "has caption" branch producing "Sender: " (blank-looking).
- Changes:
  - `_parseAttached`, timestamp capture, and continuations now strip LRM early.
  - `buildPreview` now strips LRM when deciding visible caption text for both media and text cases (robust even for legacy data).
  - `ChatMessage.fromJson` always cleans LRM from stored `text` (so old persisted messages.json get tidy text on load).
  - ListTile subtitle now defensively falls back to count if preview is empty/whitespace.
- Result: last media now correctly shows e.g. "Rashmi sent a photo", "Alex sent a video" on the home screen list.
- Also keeps chat bubbles and captions clean.

### 2026-06-21 - Modern full-screen media gallery (icon last + separate tabs + stickers)
- Replaced popup "View all media" dialog with a last-position icon button in the chat AppBar (photo_library icon).
- Implemented full-screen `_MediaGalleryScreen` with 6 scrollable tabs: All / Photos / Stickers / Videos / Documents / Audio.
- Tabs show live counts. Modern catchy grid: 3-col square tiles, 14px rounded ClipRRect, gradient caption overlays, type badges on non-images, nice empty states.
- Stickers separated using new `isSticker()` helper (webp files + filename heuristic).
- Photos/stickers open in built-in full-screen InteractiveViewer (pinch zoom 0.6x-5x + caption bar). Other media open via open_filex.
- Reuses lazy VideoThumbnailWidget. All media sorted newest first.
- Updated AppBar to clean title + dedicated action icons (perspective + media as last).

### 2026-06-21 - Loaders for async processing
- Added `CircularProgressIndicator` loaders in UI for any processing:
  - Video thumbnail generation (in chat message bubbles and media gallery grid) now displays a small spinner while asynchronously extracting the frame using `video_thumbnail`.
  - This covers the requirement that any processing (e.g. thumbnail creation) must show a loader.

### 2026-06-21 - Full Media Type Support + Open in Default App
- Expanded `MessageType` enum to support `video`, `audio`, `document` (in addition to `image`, `text`, `system`).
- Added `getMediaTypeFromFilename()` in `chat_parser.dart` to detect type from attachment extension.
- Updated `MessageBubble`:
  - Images still show thumbnail (tappable to open).
  - All other media show icon + filename + "Tap to open in default app".
  - Tapping any media opens it using the device's default app via `open_filex`.
- Updated `buildPreview()` to show appropriate labels ("sent a video", "sent a file", etc.).
- Non-image media are now properly represented instead of falling back to text.
- Added `open_filex` dependency.

### 2026-06-21 - Zip Filename Parsing for Chat Title
- Added `parseChatTitleFromZipFilename()` in `chat_parser.dart`.
- `ChatRepository.importZip()` now **always tries to parse title from zip filename first**.
- Expected format enforced: `WhatsApp Chat - <Name>.zip`.
- Bad format → clear error thrown before extraction.
- Updated sample import to use real filename parsing (title is now "Rashmi Arya").
- Added unit tests for the new filename parser.
- Improved error messages shown to user on import failure.
- Moved title resolution to the top of import process (fail fast).

### Earlier Milestones
- Initial scaffolding + cleanup of default counter app.
- Full chat parsing, models, repository, self-identity.
- WhatsApp-like UI with bubbles and search.
- Support for "me" detection + alias prompt.
- Added Load Sample demo button.

## How to Run & Test

```bash
flutter pub get
flutter run                    # Android or iOS

# Test the sample
# Tap "Load sample demo" in the app

# Run tests
flutter test
```

**Manual Test Cases**:
1. Load sample → title should be "Rashmi Arya".
2. Open chat → messages aligned correctly after selecting self.
3. Search inside chat.
4. Try importing a zip with bad name (e.g. `mybackup.zip`) → should show error.
5. Delete a chat → files + metadata removed.

## Development Guidelines

- Keep `PLAN.md` up to date. Every meaningful change must be documented here.
- Prefer small, focused files.
- Parser logic should stay pure (no side effects).
- Title for a chat should come from the zip filename when possible.
- Add or update tests when modifying `chat_parser.dart`.
- Use `notifyListeners()` properly in services that extend `ChangeNotifier`.

## Future Ideas / Out of Scope (for now)

- PDF / text export of chats
- Richer media support (video, audio, documents)
- Search across all chats
- Cloud backup / sync of imported chats
- Dark mode toggle (beyond system)
- Statistics / word cloud / activity graphs
- Drag & drop support on desktop
- Encryption of local data

## Change Log

- **2026-06-21**: Added full support for all media types (images, video, audio, documents, stickers). Media gallery moved to last AppBar icon, now full-screen modern with separate sections for photos/stickers/videos/documents/audio + catchy design. (see "Recent Changes")
- **2026-06-21**: Fixed home screen (chat list) last-message preview being blank for media-only last messages. LRM stripping + robust buildPreview + defensive display. Now shows "sent a photo" etc. correctly.
- **2026-06-21**: Fixed build error: Moved `IconData` / `Icons` logic out of `lib/models/chat.dart` (kept models Flutter-free). Icon mapping now lives in `message_bubble.dart`.
- **2026-06-21**: Major WhatsApp-like UI improvements:
  - Bubbles now use authentic WhatsApp colors (light green sent / white received in light mode; dark green in dark mode).
  - Date/day separators ("TODAY", "YESTERDAY", dates) between message groups like WhatsApp.
  - AppBar actions: perspective icon + media gallery icon (last).
  - Replaced popup with modern full-screen gallery: 6 separate tabs (All/Photos/Stickers/Videos/Documents/Audio), rounded catchy grid, gradient overlays, pinch-zoom image viewer for photos & stickers.
  - Stickers now classified and viewable separately (webp-based).
  - Background color closer to WhatsApp.
  - Media gallery shows counts per category.
- **2026-06-21**: Made loading of saved chats robust after app rebuild/restart:
  - loadMessages now safely handles corrupt/missing messages.json (try/catch + safe cast + fallback to parsing _chat.txt).
  - ChatScreen._load now catches errors so _loading always becomes false (prevents hanging on progress / blank screen).
  - This fixes "list shows chats (with sender names as titles) but opening a chat is blank" after rebuild.
  - Also normalized line endings in parseChat.
- **2026-06-21**: Duplicate import handling:
  - When re-importing a zip for the same contact/group (title match from filename), show a confirmation dialog asking whether to merge.
  - On "Merge": parse new messages, combine with existing (sorted by date + deduplicated by timestamp|sender|text|media), copy new media files, update messages.json + metadata.
  - Added `mergeIntoChat` method.
- **2026-06-21**: Restored video thumbnails with visibility-based loading to prevent lag:
  - Video thumbnails are generated only when the bubble/grid item enters the viewport (on screen).
  - Uses a StatefulWidget that loads in initState and releases the bitmap in dispose (when scrolled off-screen).
  - This applies lazy loading for heavy media (videos) and keeps memory low for long chats.
  - Same pattern helps with general chat data rendering lag.
  - Thumbnails show loader while processing.
  - Gallery also uses the widget for video items.
  - Loaders section from previous update removed as the causing feature was reverted.
- **2026-06-21**: Enhanced duplicate handling for imports:
  - Import as new for same base title now uses labels e.g. "Rashmi Arya (2)", keeping participant/sender names unchanged.
  - Merge popup presents options for each labeled version to merge into.
  - Uses extractBaseChatTitle / extractLabelNumber.
- **2026-06-21**: Media with captions now properly handled:
  - Parser detects <attached: ...> on its line or inside multi-line continuation, and associates following/same-line text as caption (when same sender, close timestamp).
  - Strips the <attached> tag; caption text is stored in message.text for the media item.
  - In bubbles: caption shown above image/video (limited lines), or integrated in doc row.
  - Gallery overlays caption (or filename) for non-photos.
  - buildPreview prefers caption text when present.
  - Sample "Kyc Modern team" used for testing the cases.
- **2026-06-21**: Fixed persisted chats not loading after force close / rebuild on iPhone:
  - Made _persist and all messages.json writes atomic (write to .tmp + rename + flush) to survive force close during write.
  - load() now notifies listeners after populating (helps watchers on cold start).
  - On corrupt meta, delete the bad file.
  - loadMessages auto-recovers by re-saving json from txt.
  - Added debugPrint on load errors.
  - This ensures metadata and message data survive force close and app restarts on device.
- **2026-06-21**: Added strict zip filename parsing for chat title. Enforce "WhatsApp Chat - Name.zip" format or show error. Updated sample handling and tests.
- **2026-06-21**: Fixed build error in `chat_list_screen.dart` (`ctx` → `context` in `_askCustomName` call).
- **2026-06-20**: Core MVP completed (import, viewer, search, self identification).
- **2026-06-20**: Initial project setup + bug fixes on template.

---

**Remember**: This document is the single source of truth for the project's plan and current state. Update it when you make changes.
