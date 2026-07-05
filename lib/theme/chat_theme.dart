import 'package:flutter/material.dart';

/// Centralized chat UI tokens inspired by WhatsApp / Telegram / iMessage.
class ChatTheme {
  ChatTheme._();

  static const double bubbleRadius = 12;
  static const double bubbleTailRadius = 4;
  static const double bubbleSpacing = 1.5;
  static const double groupSpacing = 6.0;

  static double bubbleMaxWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width * 0.78;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color chatBackground(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFF0B141A);
    }
    return const Color(0xFFEFEAE2);
  }

  static Color sentBubbleColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFF005C4B);
    }
    return const Color(0xFFD9FDD3);
  }

  static Color receivedBubbleColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFF202C33);
    }
    return Colors.white;
  }

  static Color sentTextColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFFE9EDEF);
    }
    return const Color(0xFF111B21);
  }

  static Color receivedTextColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFFE9EDEF);
    }
    return const Color(0xFF111B21);
  }

  static Color timestampColor(BuildContext context, {required bool isSelf}) {
    if (isDark(context)) {
      return const Color(0xFF8696A0);
    }
    return isSelf ? const Color(0xFF667781) : const Color(0xFF8696A0);
  }

  static Color datePillColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFF182229).withValues(alpha: 0.92);
    }
    return Colors.white.withValues(alpha: 0.92);
  }

  static Color datePillTextColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFF8696A0);
    }
    return const Color(0xFF54656F);
  }

  static Color systemPillColor(BuildContext context) {
    if (isDark(context)) {
      return const Color(0xFF182229).withValues(alpha: 0.9);
    }
    return Colors.white.withValues(alpha: 0.9);
  }

  static const List<Color> _avatarPalette = [
    Color(0xFF6C63FF),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFF0984E3),
    Color(0xFFFD79A8),
    Color(0xFFFDCB6E),
    Color(0xFF00CEC9),
    Color(0xFFA29BFE),
    Color(0xFFE84393),
    Color(0xFF55EFC4),
  ];

  static Color avatarColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _avatarPalette[hash % _avatarPalette.length];
  }

  static const List<Color> _senderPalette = [
    Color(0xFF06CF9C),
    Color(0xFF53BDEB),
    Color(0xFFE542A3),
    Color(0xFFF0B330),
    Color(0xFF7F66FF),
    Color(0xFFFA6533),
    Color(0xFF1FA855),
    Color(0xFFD63384),
  ];

  static Color senderNameColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    return _senderPalette[hash % _senderPalette.length];
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  static BorderRadius bubbleBorderRadius({
    required bool isSelf,
    required bool groupedAbove,
    required bool groupedBelow,
  }) {
    if (isSelf) {
      return BorderRadius.only(
        topLeft: const Radius.circular(bubbleRadius),
        topRight: Radius.circular(groupedAbove ? bubbleTailRadius : bubbleRadius),
        bottomLeft: const Radius.circular(bubbleRadius),
        bottomRight: Radius.circular(groupedBelow ? bubbleTailRadius : bubbleTailRadius),
      );
    }
    return BorderRadius.only(
      topLeft: Radius.circular(groupedAbove ? bubbleTailRadius : bubbleRadius),
      topRight: const Radius.circular(bubbleRadius),
      bottomLeft: Radius.circular(groupedBelow ? bubbleTailRadius : bubbleTailRadius),
      bottomRight: const Radius.circular(bubbleRadius),
    );
  }

  static EdgeInsets bubbleMargin({
    required bool isSelf,
    required bool groupedAbove,
    required bool groupedBelow,
    required bool showSenderName,
  }) {
    final top = groupedAbove ? bubbleSpacing : groupSpacing;
    final bottom = groupedBelow ? bubbleSpacing : groupSpacing;
    return EdgeInsets.only(
      top: showSenderName ? groupSpacing : top,
      bottom: bottom,
      left: isSelf ? 56 : 8,
      right: isSelf ? 8 : 56,
    );
  }
}