// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:r_map_mobile/app.dart';
import 'package:r_map_mobile/screens/property_polygon_editor_screen.dart';

void main() {
  testWidgets('RMapApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const RMapApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('property polygon editor requires 4 points minimum', () {
    expect(PropertyPolygonEditorScreen.minimumRequiredPoints, 4);
  });
}
