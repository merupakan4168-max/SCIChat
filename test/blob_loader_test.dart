import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/screens/pdf_viewer_screen.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/blob_loader.dart';

void main() {
  group('BlobLoader Widget Tests', () {
    testWidgets(
        '1. BlobLoader renders two animated boxes without circular spinner or rings',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BlobLoader(size: 112.0),
            ),
          ),
        ),
      );

      // Verify BlobLoader is present
      expect(find.byType(BlobLoader), findsOneWidget);

      // Verify exactly two blob boxes exist
      expect(find.byKey(const Key('blob_box_1')), findsOneWidget);
      expect(find.byKey(const Key('blob_box_2')), findsOneWidget);

      // Verify filters are applied
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(find.byType(ColorFiltered), findsOneWidget);

      // Verify NO circular spinner or ring exists
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Advance animation partially
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('2. 4-corner trajectory and 180-degree phase shift math',
        (tester) async {
      const double travel = 44.8;

      // At t = 0.0 (0s): Box 1 at top-left, Box 2 at bottom-right
      final pos1T0 = BlobLoader.calculatePosition(0.0, travel);
      final pos2T0 = BlobLoader.calculatePosition(0.5, travel);
      expect(pos1T0.dx, closeTo(0.0, 0.01));
      expect(pos1T0.dy, closeTo(0.0, 0.01));
      expect(pos2T0.dx, closeTo(travel, 0.01));
      expect(pos2T0.dy, closeTo(travel, 0.01));

      // At t = 0.25 (0.5s): Box 1 at top-right, Box 2 at bottom-left
      final pos1T25 = BlobLoader.calculatePosition(0.25, travel);
      final pos2T25 = BlobLoader.calculatePosition(0.75, travel);
      expect(pos1T25.dx, closeTo(travel, 0.01));
      expect(pos1T25.dy, closeTo(0.0, 0.01));
      expect(pos2T25.dx, closeTo(0.0, 0.01));
      expect(pos2T25.dy, closeTo(travel, 0.01));

      // At t = 0.50 (1.0s): Box 1 at bottom-right, Box 2 at top-left
      final pos1T50 = BlobLoader.calculatePosition(0.50, travel);
      final pos2T50 = BlobLoader.calculatePosition(1.0, travel);
      expect(pos1T50.dx, closeTo(travel, 0.01));
      expect(pos1T50.dy, closeTo(travel, 0.01));
      expect(pos2T50.dx, closeTo(0.0, 0.01));
      expect(pos2T50.dy, closeTo(0.0, 0.01));

      // At t = 0.75 (1.5s): Box 1 at bottom-left, Box 2 at top-right
      final pos1T75 = BlobLoader.calculatePosition(0.75, travel);
      final pos2T75 = BlobLoader.calculatePosition(1.25, travel);
      expect(pos1T75.dx, closeTo(0.0, 0.01));
      expect(pos1T75.dy, closeTo(travel, 0.01));
      expect(pos2T75.dx, closeTo(travel, 0.01));
      expect(pos2T75.dy, closeTo(0.0, 0.01));
    });

    testWidgets('3. Respects reduced motion preference (disableAnimations)',
        (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: BlobLoader(size: 80.0),
              ),
            ),
          ),
        ),
      );

      // Verify static boxes are rendered without AnimatedBuilder inside BlobLoader
      expect(find.byKey(const Key('blob_box_1')), findsOneWidget);
      expect(find.byKey(const Key('blob_box_2')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BlobLoader),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );

      // Advancing time causes no crashes
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Light and Dark mode rendering with custom or default color',
        (tester) async {
      for (final isDark in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: SciChatTheme.getTheme(isDark),
            home: const Scaffold(
              body: Center(
                child: BlobLoader(
                  size: 96.0,
                  color: Color(0xFF474BFF),
                ),
              ),
            ),
          ),
        );

        expect(find.byType(BlobLoader), findsOneWidget);
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const Key('blob_box_1')),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration as BoxDecoration?;
        expect(decoration?.color, equals(const Color(0xFF474BFF)));
      }
    });

    testWidgets(
        '5. Proportional dimensions scale correctly with size parameter',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BlobLoader(size: 112.0),
            ),
          ),
        ),
      );

      // Reference container: 112.0 -> Box size: 112.0 * 0.4 = 44.8
      final box1 = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('blob_box_1')),
          matching: find.byType(Container),
        ),
      );
      expect(box1.constraints?.maxWidth, closeTo(44.8, 0.01));
      expect(box1.constraints?.maxHeight, closeTo(44.8, 0.01));

      // Test scaled size 56.0 -> Box size: 56.0 * 0.4 = 22.4
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BlobLoader(size: 56.0),
            ),
          ),
        ),
      );

      final scaledBox = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const Key('blob_box_1')),
          matching: find.byType(Container),
        ),
      );
      expect(scaledBox.constraints?.maxWidth, closeTo(22.4, 0.01));
      expect(scaledBox.constraints?.maxHeight, closeTo(22.4, 0.01));
    });
  });

  group('PdfViewerScreen BlobLoader Integration Tests', () {
    const samplePaper = ArxivPaper(
      id: '2401.00001',
      title: 'Federated Learning for Medical Privacy',
      summary: 'Abstract of federated learning in healthcare.',
      authors: ['Jane Doe', 'John Smith'],
      published: '2024-01-01',
      updated: '2024-01-01',
      categories: ['cs.AI'],
      pdfUrl: 'https://arxiv.org/pdf/2401.00001.pdf',
      absUrl: 'https://arxiv.org/abs/2401.00001',
    );

    testWidgets(
        '6. PdfViewerScreen renders BlobLoader as single loading indicator while loading and transitions correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: PdfViewerScreen(
            paper: samplePaper,
            url: samplePaper.pdfUrl,
          ),
        ),
      );

      // Verify BlobLoader is displayed
      expect(find.byType(BlobLoader), findsOneWidget);

      // Verify old CircularProgressIndicator is completely eliminated
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Verify header components are preserved
      expect(find.text('PDF Viewer'), findsOneWidget);
      expect(
          find.text('Federated Learning for Medical Privacy'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);

      // Verify duplicate horizontal progress bar is hidden via Opacity(opacity: 0.0) during loading
      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);
      final opacityWidget = tester.widget<Opacity>(opacityFinder);
      expect(opacityWidget.opacity, equals(0.0));

      // Advance time beyond SfPdfViewer debounce timer (500ms) to trigger transition
      await tester.pump(const Duration(milliseconds: 600));

      // After load failure in test environment (HTTP 400), BlobLoader is dismissed and error view appears
      expect(find.byType(BlobLoader), findsNothing);
      expect(find.textContaining('PDF tidak dapat dimuat langsung'),
          findsOneWidget);
      expect(find.text('Buka di Browser'), findsOneWidget);
    });
  });
}
