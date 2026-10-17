import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/paper_detail_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/dynamic_source_button.dart';
import 'package:scichat/widgets/paper_card.dart';
import 'package:scichat/widgets/source_badge.dart';

class _FakeStorageService extends StorageService {
  final List<ArxivPaper> _favorites = [];

  @override
  Future<String?> getApiKey() async => 'test-api-key';
  @override
  Future<String?> getThemeMode() async => 'dark';
  @override
  Future<List<ArxivPaper>> getFavorites() async => _favorites;
  @override
  Future<void> saveFavorites(List<ArxivPaper> papers) async {
    _favorites.clear();
    _favorites.addAll(papers);
  }
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}
  @override
  Future<List<ResearchNote>> getNotes() async => [];
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

Widget _wrapWithApp(
  Widget child, {
  SciChatProvider? provider,
  Size size = const Size(800, 1000),
}) {
  final p = provider ??
      SciChatProvider(
        storageService: _FakeStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'dummy-api-key'),
        pdfService: PdfService(),
      );

  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ChangeNotifierProvider<SciChatProvider>.value(
      value: p,
      child: MaterialApp(
        theme: SciChatTheme.dark,
        home: Scaffold(body: child),
      ),
    ),
  );
}

ArxivPaper _samplePaper({
  String id = '2301.0001',
  String title = 'Attention Is All You Need',
  List<String> authors = const ['Ashish Vaswani', 'Noam Shazeer'],
  List<String> categories = const ['cs.CL', 'cs.AI'],
  List<String> sources = const [],
  int? citationCount,
  String pdfUrl = 'https://arxiv.org/pdf/2301.0001.pdf',
  String absUrl = 'https://arxiv.org/abs/2301.0001',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: 'The dominant sequence transduction models are based on complex recurrent or convolutional neural networks.',
    published: '2023-01-15T00:00:00Z',
    updated: '2023-01-15T00:00:00Z',
    categories: categories,
    pdfUrl: pdfUrl,
    absUrl: absUrl,
    sources: sources,
    citationCount: citationCount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fase 4: Source Provenance UI Tests', () {
    testWidgets('1. Satu sumber dirender dengan tepat pada PaperCard dan PaperDetailScreen', (tester) async {
      final paper = _samplePaper(sources: ['arXiv']);

      // Test PaperCard
      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: paper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsOneWidget);
      expect(find.text('arXiv'), findsOneWidget);

      // Test PaperDetailScreen
      await tester.pumpWidget(_wrapWithApp(PaperDetailScreen(paper: paper)));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SourceBadge), matching: find.text('arXiv')),
        findsOneWidget,
      );
      expect(find.text('SUMBER'), findsOneWidget);
    });

    testWidgets('2. Beberapa sumber dirender sebagai chip terpisah', (tester) async {
      final multiSourcePaper = _samplePaper(
        sources: ['CrossRef', 'Semantic Scholar'],
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: multiSourcePaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsNWidgets(2));
      expect(find.text('CrossRef'), findsOneWidget);
      expect(find.text('Semantic Scholar'), findsOneWidget);

      // In PaperDetailScreen
      await tester.pumpWidget(_wrapWithApp(PaperDetailScreen(paper: multiSourcePaper)));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsNWidgets(2));
      expect(find.text('CrossRef, Semantic Scholar'), findsOneWidget);
    });

    testWidgets('3. Sumber kosong tidak merender SourceBadge atau klaim palsu', (tester) async {
      final noSourcePaper = _samplePaper(sources: const []);

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: noSourcePaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsNothing);

      await tester.pumpWidget(_wrapWithApp(PaperDetailScreen(paper: noSourcePaper)));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsNothing);
      expect(find.text('Sumber'), findsNothing);
    });
  });

  group('Fase 4: Citation Count Display Tests', () {
    testWidgets('4. CitationCount bernilai valid diformat dengan mudah dibaca', (tester) async {
      final paper1 = _samplePaper(citationCount: 42);
      final paper2 = _samplePaper(citationCount: 1540);
      final paper3 = _samplePaper(citationCount: 120000);

      // 42 sitasi
      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: paper1,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('42 sitasi'), findsOneWidget);

      // 1.5k sitasi
      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: paper2,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('1.5k sitasi'), findsOneWidget);

      // 120k sitasi
      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: paper3,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('120k sitasi'), findsOneWidget);
    });

    testWidgets('5. CitationCount bernilai nol dirender sebagai 0 sitasi', (tester) async {
      final zeroPaper = _samplePaper(citationCount: 0);

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: zeroPaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('0 sitasi'), findsOneWidget);

      await tester.pumpWidget(_wrapWithApp(PaperDetailScreen(paper: zeroPaper)));
      await tester.pumpAndSettle();
      expect(find.text('0 sitasi'), findsOneWidget);
    });

    testWidgets('6. CitationCount bernilai null tidak merender informasi sitasi palsu', (tester) async {
      final nullCitationPaper = _samplePaper(citationCount: null);

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: nullCitationPaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('sitasi'), findsNothing);

      await tester.pumpWidget(_wrapWithApp(PaperDetailScreen(paper: nullCitationPaper)));
      await tester.pumpAndSettle();
      expect(find.text('Sitasi'), findsNothing);
      expect(find.textContaining('sitasi'), findsNothing);
    });
  });

  group('Fase 4: Label Panjang, Layar Sempit, dan Proteksi Overflow', () {
    testWidgets('7. Label sumber yang panjang dipotong dengan aman tanpa overflow', (tester) async {
      final longSourcePaper = _samplePaper(
        sources: ['Very Long Scientific Literature Repository Center That Might Overflow Normal Rows'],
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: longSourcePaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SourceBadge), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Layar sempit (lebar 300px) tidak mengalami RenderFlex overflow', (tester) async {
      final complexPaper = _samplePaper(
        sources: ['Internet Archive', 'Semantic Scholar'],
        citationCount: 15400,
        categories: ['cs.CL', 'cs.AI', 'physics.optics'],
      );

      // Narrow screen: 300px width
      tester.view.physicalSize = const Size(300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: complexPaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
          onSummarize: () {},
          onChatPdf: () {},
        ),
        size: const Size(300, 800),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Detail Screen on narrow screen
      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: complexPaper),
        size: const Size(300, 800),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Fase 4: Direct PDF vs Article Landing Page Distinction', () {
    testWidgets('9. Paper tanpa PDF langsung tidak menampilkan tombol Open PDF', (tester) async {
      // Landing page URL without direct PDF
      final landingPagePaper = _samplePaper(
        absUrl: 'https://openalex.org/W2741809807',
        pdfUrl: '',
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: landingPagePaper,
          isFavorite: false,
          onFavoriteToggle: () {},
          onTap: () {},
          onSummarize: () {},
          onChatPdf: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // DynamicSourceButton should say Open Paper on OpenAlex, NOT Open PDF
      expect(find.text('Open Paper on OpenAlex'), findsOneWidget);
      expect(find.text('Open PDF'), findsNothing);
      // Because pdfUrl is empty, Tanya Paper should not be shown; only Rangkum is available
      expect(find.text('Tanya Paper'), findsNothing);
      expect(find.text('Rangkum'), findsOneWidget);

      // In PaperDetailScreen
      await tester.pumpWidget(_wrapWithApp(PaperDetailScreen(paper: landingPagePaper)));
      await tester.pumpAndSettle();

      expect(find.text('Open Paper on OpenAlex'), findsOneWidget);
      expect(find.text('Open PDF'), findsNothing);
    });

    testWidgets('10. Direct PDF URL dikenali dan memicu label Open PDF', (tester) async {
      final pdfPaper = _samplePaper(
        absUrl: 'https://arxiv.org/abs/2301.0001',
        pdfUrl: 'https://arxiv.org/pdf/2301.0001.pdf',
      );

      await tester.pumpWidget(_wrapWithApp(
        PaperDetailScreen(paper: pdfPaper),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Open on arXiv'), findsOneWidget);
      expect(find.text('Open PDF'), findsOneWidget);
    });
  });

  group('Fase 4: Regresi Aksi Tombol pada PaperCard dan PaperDetailScreen', () {
    testWidgets('11. Aksi tombol pada PaperCard berfungsi secara konsisten', (tester) async {
      bool tapped = false;
      bool favorited = false;
      bool summarized = false;
      bool chatPdf = false;

      final paper = _samplePaper();

      await tester.pumpWidget(_wrapWithApp(
        PaperCard(
          paper: paper,
          isFavorite: false,
          onTap: () => tapped = true,
          onFavoriteToggle: () => favorited = true,
          onSummarize: () => summarized = true,
          onChatPdf: () => chatPdf = true,
        ),
      ));
      await tester.pumpAndSettle();

      // Tap card
      await tester.tap(find.text('Attention Is All You Need'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);

      // Tap favorite
      await tester.tap(find.byIcon(Icons.bookmark_outline));
      await tester.pumpAndSettle();
      expect(favorited, isTrue);

      // Tap Rangkum
      await tester.tap(find.text('Rangkum'));
      await tester.pumpAndSettle();
      expect(summarized, isTrue);

      // Tap Tanya Paper
      await tester.tap(find.text('Tanya Paper'));
      await tester.pumpAndSettle();
      expect(chatPdf, isTrue);

      // Tap Kutip to verify popup menu options
      await tester.tap(find.text('Kutip'));
      await tester.pumpAndSettle();
      expect(find.text('Salin BibTeX'), findsOneWidget);
      expect(find.text('Salin APA 7'), findsOneWidget);
    });
  });
}
