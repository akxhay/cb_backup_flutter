// Basic smoke test for cbbackup

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cbbackup/main.dart';

void main() {
  testWidgets('App launches and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const CbbackupApp());

    // Title from AppBar
    expect(find.text('cbbackup'), findsOneWidget);
    // Empty state prompt
    expect(find.textContaining('Import a WhatsApp'), findsOneWidget);
  });
}
