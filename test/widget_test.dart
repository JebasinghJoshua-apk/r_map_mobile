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
import 'package:r_map_mobile/utils/post_frame_callback.dart';

void main() {
  testWidgets('RMapApp renders', (WidgetTester tester) async {
    await tester.pumpWidget(const RMapApp(enableRuntimeServices: false));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('property polygon editor requires 4 points minimum', () {
    expect(PropertyPolygonEditorScreen.minimumRequiredPoints, 4);
  });

  testWidgets('post-frame work does not run during widget build',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: _PostFrameProbe()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Loaded'), findsOneWidget);
  });
}

class _PostFrameProbe extends StatefulWidget {
  const _PostFrameProbe();

  @override
  State<_PostFrameProbe> createState() => _PostFrameProbeState();
}

class _PostFrameProbeState extends State<_PostFrameProbe> {
  var _hasLoaded = false;
  var _didSchedule = false;

  @override
  Widget build(BuildContext context) {
    if (!_didSchedule) {
      _didSchedule = true;
      runAfterBuild(() {
        if (mounted) setState(() => _hasLoaded = true);
      });
    }

    return Text(_hasLoaded ? 'Loaded' : 'Loading');
  }
}
