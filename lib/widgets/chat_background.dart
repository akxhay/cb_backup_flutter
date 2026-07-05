import 'package:flutter/material.dart';

import '../theme/chat_theme.dart';

/// Subtle wallpaper pattern similar to WhatsApp chat backgrounds.
class ChatBackground extends StatelessWidget {
  final Widget child;

  const ChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ChatTheme.chatBackground(context),
      child: CustomPaint(
        painter: _ChatPatternPainter(
          isDark: ChatTheme.isDark(context),
        ),
        child: child,
      ),
    );
  }
}

class _ChatPatternPainter extends CustomPainter {
  final bool isDark;

  _ChatPatternPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final strokeColor = isDark
        ? const Color(0xFF1E2A34).withValues(alpha: 0.35)
        : const Color(0xFFC7D3C9).withValues(alpha: 0.45);

    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const spacing = 75.0;

    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        final offsetIndex = ((x + y) / spacing).floor();
        final offsetX = (y / spacing).floor().isEven ? 15.0 : 45.0;
        final drawX = x + offsetX;
        final drawY = y;
        
        if (drawX > size.width || drawY > size.height) continue;

        canvas.save();
        canvas.translate(drawX, drawY);
        canvas.scale(0.85);

        switch (offsetIndex % 6) {
          case 0:
            _drawBubble(canvas, paint);
            break;
          case 1:
            _drawPhone(canvas, paint);
            break;
          case 2:
            _drawStar(canvas, paint);
            break;
          case 3:
            _drawNote(canvas, paint);
            break;
          case 4:
            _drawHeart(canvas, paint);
            break;
          case 5:
            _drawSearch(canvas, paint);
            break;
        }
        canvas.restore();
      }
    }
  }

  void _drawBubble(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(-6, -4)
      ..lineTo(6, -4)
      ..quadraticBezierTo(10, -4, 10, 0)
      ..quadraticBezierTo(10, 4, 6, 4)
      ..lineTo(2, 4)
      ..lineTo(-4, 9)
      ..lineTo(-4, 4)
      ..lineTo(-6, 4)
      ..quadraticBezierTo(-10, 4, -10, 0)
      ..quadraticBezierTo(-10, -4, -6, -4);
    canvas.drawPath(path, paint);
  }

  void _drawPhone(Canvas canvas, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 8, height: 14),
        const Radius.circular(2.5),
      ),
      paint,
    );
    canvas.drawCircle(const Offset(0, 4.5), 0.8, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  void _drawStar(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(0, -6)
      ..lineTo(2, -2)
      ..lineTo(6, -2)
      ..lineTo(3, 1)
      ..lineTo(4, 5)
      ..lineTo(0, 3)
      ..lineTo(-4, 5)
      ..lineTo(-3, 1)
      ..lineTo(-6, -2)
      ..lineTo(-2, -2)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawNote(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(-3, 3), 2.0, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-1, 3), const Offset(-1, -4), paint);
    canvas.drawLine(const Offset(-1, -4), const Offset(3.5, -2.5), paint);
    canvas.drawCircle(const Offset(3.5, -2.5), 1.5, paint..style = PaintingStyle.fill);
    paint.style = PaintingStyle.stroke;
  }

  void _drawHeart(Canvas canvas, Paint paint) {
    final path = Path()
      ..moveTo(0, -2.5)
      ..cubicTo(-2.5, -5.5, -5.5, -2.5, -5.5, 0.5)
      ..cubicTo(-5.5, 3.5, 0, 6.5, 0, 7.5)
      ..cubicTo(0, 6.5, 5.5, 3.5, 5.5, 0.5)
      ..cubicTo(5.5, -2.5, 2.5, -5.5, 0, -2.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  void _drawSearch(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(-2, -2), 3.0, paint);
    canvas.drawLine(const Offset(0, 0), const Offset(4, 4), paint);
  }

  @override
  bool shouldRepaint(covariant _ChatPatternPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}