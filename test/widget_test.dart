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
import 'package:transport_daily_report/screens/pre_authenticated_home_screen.dart';

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
    // NOTE: The app starts background loading; avoid pumpAndSettle timeout.
    await tester.pump(const Duration(milliseconds: 200));
    
    // Find any widget to ensure the app loaded
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
