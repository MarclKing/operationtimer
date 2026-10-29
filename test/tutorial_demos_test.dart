import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:OpTimes/tutorial/tutorial_demos.dart';

void main() {
  testWidgets('inactive tutorial pulse does not keep an animation ticker alive',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TutorialPulse(
          active: false,
          child: Text('Not pulsing'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Not pulsing'), findsOneWidget);
  });
}
