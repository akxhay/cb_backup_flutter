import 'package:cbbackup/models/chat.dart';
import 'package:cbbackup/services/chat_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chat_parser', () {
    const sampleChat = '''
[22/09/25, 10:28:19 AM] Rashmi Arya: Messages and calls are end-to-end encrypted. Only people in this chat can read, listen to, or share them.
[22/09/25, 10:28:19 AM] Xharma: Hi
[22/09/25, 10:28:31 AM] Xharma: Dr Gaurav has shared your number for appointment
[22/09/25, 10:28:45 AM] Rashmi Arya: Good morning sir
[22/09/25, 10:28:51 AM] Rashmi Arya: For MRI ?
[22/09/25, 1:54:29 PM] Rashmi Arya: \u200e<attached: 00000019-PHOTO-2025-09-22-13-54-29.jpg>
[22/09/25, 1:58:55 PM] Rashmi Arya: Scan4Health
*Address:* D4, EBD 65, Golf Course Extension Road, Gurugram Haryana Location- https://maps.app.goo.gl/7Lwh8Erp5yzqzo7X8
[22/09/25, 5:29:43 PM] Xharma: Hi
[22/09/25, 6:00:57 PM] Rashmi Arya: Thank you
''';

    test('parses basic messages and counts', () {
      final msgs = parseChat(sampleChat);
      expect(msgs.length, greaterThanOrEqualTo(8));
      expect(msgs.first.sender, 'Rashmi Arya');
      expect(msgs[1].text, 'Hi');
    });

    test('detects image attachment', () {
      final msgs = parseChat(sampleChat);
      final attach = msgs.firstWhere((m) => m.mediaPath != null);
      expect(attach.mediaPath, contains('00000019-PHOTO'));
      expect(attach.type, MessageType.image);
    });

    test('handles multi-line continuation', () {
      final msgs = parseChat(sampleChat);
      final multi = msgs.firstWhere((m) => m.text.contains('Scan4Health'));
      expect(multi.text, contains('Address'));
    });

    test('extracts unique senders', () {
      final msgs = parseChat(sampleChat);
      final senders = extractSenders(msgs);
      expect(senders, containsAll(['Rashmi Arya', 'Xharma']));
    });

    test('isLikelyGroupChat returns false for 2-person chat', () {
      final msgs = parseChat(sampleChat);
      expect(isLikelyGroupChat(msgs), isFalse);
    });

    test('respects myAliases for caller (parser is neutral)', () {
      final msgs = parseChat(sampleChat);
      // Parser itself doesn't mark self; that is done in UI layer
      expect(msgs.every((m) => m.isFromSelf == false), isTrue);
    });
  });

  group('parseChatTitleFromZipFilename', () {
    test('parses correctly from sample filename', () {
      const path = 'sample/WhatsApp Chat - Rashmi Arya.zip';
      final title = parseChatTitleFromZipFilename(path);
      expect(title, 'Rashmi Arya');
    });

    test('parses group chat name', () {
      const path = '/downloads/WhatsApp Chat - Team Project.zip';
      final title = parseChatTitleFromZipFilename(path);
      expect(title, 'Team Project');
    });

    test('is case insensitive for prefix', () {
      const path = 'WhatsApp Chat - john doe.ZIP';
      expect(parseChatTitleFromZipFilename(path), 'john doe');
    });

    test('throws clear error for wrong format', () {
      expect(
        () => parseChatTitleFromZipFilename('Rashmi-Chat.zip'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Invalid zip filename format'),
        )),
      );
    });

    test('throws when name part is empty', () {
      expect(
        () => parseChatTitleFromZipFilename('WhatsApp Chat - .zip'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('getMediaTypeFromFilename', () {
    test('detects common image types', () {
      expect(getMediaTypeFromFilename('photo.jpg'), MessageType.image);
      expect(getMediaTypeFromFilename('image.PNG'), MessageType.image);
      expect(getMediaTypeFromFilename('pic.heic'), MessageType.image);
    });

    test('detects video types', () {
      expect(getMediaTypeFromFilename('clip.mp4'), MessageType.video);
      expect(getMediaTypeFromFilename('movie.MOV'), MessageType.video);
    });

    test('detects audio types', () {
      expect(getMediaTypeFromFilename('voice.opus'), MessageType.audio);
      expect(getMediaTypeFromFilename('song.m4a'), MessageType.audio);
    });

    test('treats documents and unknown as document', () {
      expect(getMediaTypeFromFilename('report.pdf'), MessageType.document);
      expect(getMediaTypeFromFilename('notes.txt'), MessageType.document);
      expect(getMediaTypeFromFilename('unknown.xyz'), MessageType.document);
    });
  });
}
