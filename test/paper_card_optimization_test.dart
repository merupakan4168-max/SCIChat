import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/paper_card.dart';

Widget _wrap(Widget child, {Size size = const Size(360, 800)}) {
  return MaterialApp(
    theme: SciChatTheme.getTheme(false),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

ArxivPaper _samplePaper({
  String id = '2301.0001',
  String title = 'Attention Is All You Need',
  List<String> authors = const ['Ashish Vaswani', 'Noam Shazeer'],
  String summary = 'The dominant sequence transduction models are based on complex recurrent networks.',
  List<String> sources = const ['arXiv'],
  List<String> categories = const ['cs.CL'],
  String absUrl = 'https://arxiv.org/abs/2301.0001',
  String pdfUrl = 'https://arxiv.org/pdf/2301.0001.pdf',
  int? citationCount = 50000,
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: summary,
    published: '2024-01-01',
    updated: '2024-01-01',
    categories: categories,
    sources: sources,
    pdfUrl: pdfUrl,
    absUrl: absUrl,
    citationCount: citationCount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tahap 1 — Optimalisasi PaperCard (Abstrak & Single-Row Footer)', () {
    testWidgets('1. Abstrak yang tersedia tetap tampil dengan gaya typography bodyMedium', (tester) async {
      final paper = _samplePaper(
        summary: 'Metode transformer menggunakan self-attention untuk memproses teks.',
      );

      await tester.pumpWidget(_wrap(PaperCard(
        paper: paper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text('Metode transformer menggunakan self-attention untuk memproses teks.'), findsOneWidget);
    });

    testWidgets('2. Abstrak kosong dan whitespace tidak meninggalkan ruang kosong atau Text kosong', (tester) async {
      // Test empty string
      final emptyPaper = _samplePaper(summary: '');

      await tester.pumpWidget(_wrap(PaperCard(
        paper: emptyPaper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
      )));
      await tester.pumpAndSettle();

      // Ensure no empty summary Text is rendered
      expect(find.byWidgetPredicate((w) => w is Text && w.data == ''), findsNothing);

      // Test whitespace-only string
      final wsPaper = _samplePaper(summary: '   \n\t  ');
      await tester.pumpWidget(_wrap(PaperCard(
        paper: wsPaper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is Text && w.data != null && w.data!.trim().isEmpty), findsNothing);
    });

    testWidgets('3. Tanya Paper tetap berfungsi ketika onChatPdf disediakan dan direct PDF tersedia', (tester) async {
      bool chatPdfCalled = false;
      final paper = _samplePaper(pdfUrl: 'https://arxiv.org/pdf/2301.0001.pdf');

      await tester.pumpWidget(_wrap(PaperCard(
        paper: paper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
        onChatPdf: () => chatPdfCalled = true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Tanya Paper'), findsOneWidget);
      await tester.tap(find.text('Tanya Paper'));
      await tester.pumpAndSettle();

      expect(chatPdfCalled, isTrue);
    });

    testWidgets('4. Rangkum tetap berfungsi ketika onSummarize disediakan', (tester) async {
      bool summarizeCalled = false;
      final paper = _samplePaper();

      await tester.pumpWidget(_wrap(PaperCard(
        paper: paper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
        onSummarize: () => summarizeCalled = true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Rangkum'), findsOneWidget);
      await tester.tap(find.text('Rangkum'));
      await tester.pumpAndSettle();

      expect(summarizeCalled, isTrue);
    });

    testWidgets('5. Kutip tetap berfungsi dan dapat ditemukan melalui label aksesibilitas', (tester) async {
      final paper = _samplePaper();

      await tester.pumpWidget(_wrap(PaperCard(
        paper: paper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
      )));
      await tester.pumpAndSettle();

      // Find by tooltip and semantics label
      expect(find.byTooltip('Kutip Makalah'), findsOneWidget);
      expect(find.bySemanticsLabel('Kutip'), findsOneWidget);

      // Tap Kutip button
      await tester.tap(find.byTooltip('Kutip Makalah'));
      await tester.pumpAndSettle();

      // Verify format citation menu options appear
      expect(find.text('Salin BibTeX'), findsOneWidget);
      expect(find.text('Salin APA 7'), findsOneWidget);

      // Tap BibTeX option
      await tester.tap(find.text('Salin BibTeX'));
      await tester.pumpAndSettle();
      expect(find.text('Sitasi bibtex disalin'), findsOneWidget);
    });

    testWidgets('6. Open tetap berfungsi dengan tooltip dan semantics ketika tautan tersedia', (tester) async {
      final paper = _samplePaper(
        absUrl: 'https://arxiv.org/abs/2301.0001',
        pdfUrl: 'https://arxiv.org/pdf/2301.0001.pdf',
      );

      await tester.pumpWidget(_wrap(PaperCard(
        paper: paper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
      )));
      await tester.pumpAndSettle();

      // Should show accessible tooltip for opening paper
      expect(find.byTooltip('Open on arXiv'), findsOneWidget);
      expect(find.bySemanticsLabel('Open on arXiv'), findsOneWidget);

      // Test without URL: button should not appear
      final noUrlPaper = _samplePaper(absUrl: '', pdfUrl: '');
      await tester.pumpWidget(_wrap(PaperCard(
        paper: noUrlPaper,
        isFavorite: false,
        onFavoriteToggle: () {},
        onTap: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Open on arXiv'), findsNothing);
    });

    testWidgets('7. PaperCard tidak mengalami overflow pada layar 320 dp dan 300 px', (tester) async {
      final paper = _samplePaper(
        title: 'Judul Makalah Sangat Panjang Sekali untuk Menguji Perilaku Responsif dan Pemotongan Teks di Layar Sempit',
        pdfUrl: 'https://arxiv.org/pdf/2301.0001.pdf',
      );

      for (final width in [320.0, 300.0]) {
        await tester.pumpWidget(_wrap(
          PaperCard(
            paper: paper,
            isFavorite: false,
            onFavoriteToggle: () {},
            onTap: () {},
            onSummarize: () {},
            onChatPdf: () {},
          ),
          size: Size(width, 800),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Harus bebas overflow pada lebar $width dp');
      }
    });

    testWidgets('8. Bookmark dan seluruh metadata paper (judul, penulis, tanggal, sitasi) tidak berubah', (tester) async {
      bool bookmarkTapped = false;
      bool cardTapped = false;
      final paper = _samplePaper(
        title: 'Deep Residual Learning for Image Recognition',
        authors: ['Kaiming He', 'Xiangyu Zhang', 'Shaoqing Ren'],
        citationCount: 154200,
      );

      await tester.pumpWidget(_wrap(PaperCard(
        paper: paper,
        isFavorite: false,
        onFavoriteToggle: () => bookmarkTapped = true,
        onTap: () => cardTapped = true,
      )));
      await tester.pumpAndSettle();

      // Title & Authors & Citation
      expect(find.text('Deep Residual Learning for Image Recognition'), findsOneWidget);
      expect(find.text('Kaiming He, Xiangyu Zhang, Shaoqing Ren'), findsOneWidget);
      expect(find.text('154k sitasi'), findsOneWidget);

      // Bookmark action
      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark_outline));
      await tester.pumpAndSettle();
      expect(bookmarkTapped, isTrue);

      // Card tap action
      await tester.tap(find.text('Deep Residual Learning for Image Recognition'));
      await tester.pumpAndSettle();
      expect(cardTapped, isTrue);
    });
  });
}
