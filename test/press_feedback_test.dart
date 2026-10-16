import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/widgets/press_feedback.dart';

void main() {
  group('PressFeedback Widget Tests', () {
    testWidgets('1. Widget scales down when pressed and returns to 1.0 after release', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                scaleFactor: 0.98,
                onTap: () => tapCount++,
                child: const SizedBox(key: Key('target'), width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      // Initial state: AnimatedScale scale should be 1.0
      AnimatedScale scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0);

      // Press down (start gesture)
      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('target'))));
      await tester.pump(); // Start animation frame
      await tester.pump(const Duration(milliseconds: 100)); // Complete press-in animation

      scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 0.98);

      // Release pointer (up)
      await gesture.up();
      await tester.pump(); // Start return animation frame
      await tester.pump(const Duration(milliseconds: 140)); // Complete release animation

      scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0);
      expect(tapCount, 1);
    });

    testWidgets('2. Gesture cancellation restores scale to 1.0 without executing tap', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                scaleFactor: 0.97,
                onTap: () => tapCount++,
                child: const SizedBox(key: Key('cancel_target'), width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('cancel_target'))));
      await tester.pump(const Duration(milliseconds: 100));

      AnimatedScale scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 0.97);

      // Cancel gesture
      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));

      scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0);
      expect(tapCount, 0); // Tap callback must NOT be called on cancel
    });

    testWidgets('3. Tap callback executes exactly once on tap', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                onTap: () => tapCount++,
                child: const Text('Tap Me'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Me'));
      await tester.pumpAndSettle();

      expect(tapCount, 1);
    });

    testWidgets('4. Disabled button does not scale or trigger tap callback', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                enabled: false,
                scaleFactor: 0.95,
                onTap: () => tapCount++,
                child: const SizedBox(key: Key('disabled_target'), width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('disabled_target'))));
      await tester.pump(const Duration(milliseconds: 100));

      AnimatedScale scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0); // Never scaled down

      await gesture.up();
      await tester.pumpAndSettle();

      expect(tapCount, 0);
    });

    testWidgets('5. Respects reduced-motion preference (scale remains 1.0)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Center(
                child: PressFeedback(
                  scaleFactor: 0.96,
                  onTap: () {},
                  child: const SizedBox(key: Key('reduced_target'), width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('reduced_target'))));
      await tester.pump();

      AnimatedScale scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0); // Reduced motion keeps scale at 1.0
      expect(scaleWidget.duration, Duration.zero);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('6. Passive Listener mode scales and cancels when dragged (e.g. scroll)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                scaleFactor: 0.96,
                // onTap is null, so it operates in passive Listener mode
                child: const SizedBox(key: Key('passive_target'), width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('passive_target'))));
      await tester.pump(const Duration(milliseconds: 100));

      AnimatedScale scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 0.96);

      // Move pointer beyond drag threshold (>10 px) simulating scroll
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));

      scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0); // Canceled and restored

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('7. Long press triggers callback and resets scale', (tester) async {
      int longPressCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                scaleFactor: 0.97,
                onLongPress: () => longPressCount++,
                child: const SizedBox(key: Key('long_target'), width: 100, height: 100),
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byKey(const Key('long_target')));
      await tester.pumpAndSettle();

      expect(longPressCount, 1);
      final AnimatedScale scaleWidget = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scaleWidget.scale, 1.0);
    });

    testWidgets('8. Passive mode wrapping IconButton: scales and fires callback once', (tester) async {
      int count = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                scaleFactor: 0.92,
                child: IconButton(
                  key: const Key('icon_btn'),
                  icon: const Icon(Icons.add),
                  onPressed: () => count++,
                ),
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('icon_btn'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.92);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
      expect(count, 1);
    });

    testWidgets('9. Passive mode keeps list scrolling working and resets scale', (tester) async {
      int taps = 0;
      final controller = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controller,
              children: [
                PressFeedback(
                  child: InkWell(
                    key: const Key('row0'),
                    onTap: () => taps++,
                    child: const SizedBox(height: 80, child: Text('row0')),
                  ),
                ),
                for (int i = 1; i < 30; i++) SizedBox(height: 80, child: Text('row$i')),
              ],
            ),
          ),
        ),
      );

      await tester.drag(find.byKey(const Key('row0')), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(0));
      expect(taps, 0);
      final scaleFinder = find.byType(AnimatedScale, skipOffstage: false);
      expect(scaleFinder, findsWidgets);
      expect(tester.widget<AnimatedScale>(scaleFinder.first).scale, 1.0);
    });

    testWidgets('10. Pressing does not change layout size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PressFeedback(
                onTap: () {},
                child: const SizedBox(key: Key('sized'), width: 120, height: 48),
              ),
            ),
          ),
        ),
      );
      final before = tester.getSize(find.byType(PressFeedback));
      final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('sized'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.byType(PressFeedback)), before);
      await g.up();
      await tester.pumpAndSettle();
    });
  });
}
