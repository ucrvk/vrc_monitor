import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vrc_monitor/widgets/app.dart';

void main() {
  testWidgets('shows login page', (WidgetTester tester) async {
    await tester.pumpWidget(const VrcMonitorApp());

    expect(find.text('VRChat 登录'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(FilledButton), findsOneWidget);
  });
}
