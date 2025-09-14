// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport_daily_report/services/backup_service.dart';
import 'package:transport_daily_report/services/storage_service.dart';

import 'package:transport_daily_report/main.dart';

void main() {
  testWidgets('App initializes smoke test', (WidgetTester tester) async {
    // Create mock initial auth state
    final initialAuthState = InitialAuthState(
      isAuthenticated: false,
      userName: null,
      backupService: BackupService(StorageService()),
    );

    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp(initialAuthState: initialAuthState));

    // Verify that the app loads successfully
    await tester.pumpAndSettle();
    
    // Find any widget to ensure the app loaded
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
