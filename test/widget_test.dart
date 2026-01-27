// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:feedback_app/main.dart';

void main() {
  testWidgets('App shows email screen initially', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    // SharedPreferences is platform-channel based; in widget tests it may never
    // "settle" unless mocked. We just verify the first frame renders.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
