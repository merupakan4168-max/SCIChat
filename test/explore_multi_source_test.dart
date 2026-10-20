import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/explore_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/paper_card.dart';

class _MockStorageService extends StorageService {
  @override
  Future<String?> getApiKey() async => 'test-key';
  @override
  Future<String?> getThemeMode() async => 'system';
  @override
  Future<List<ArxivPaper>> getFavorites() async => [];
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

class _MockSearchService extends SearchService {
  List<ArxivPaper> resultsToReturn = [];
  String lastQuery = '';
  String? lastKeywords = '';
  bool shouldThrow = false;
  Completer<void>? delayCompleter;

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    lastQuery = query;
    lastKeywords = keywords;
    if (delayCompleter != null) {
      await delayCompleter!.future;
    }
    if (shouldThrow) {
      throw Exception('Jaringan bermasalah (Mock 503)');
    }
    return resultsToReturn;
  }

  @override
  Future<List<ArxivPaper>> fetchTrending() async => [];
}

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy');
}

class _MockPdfService extends PdfService {}

Widget createTestWidget({required Widget child, required SciChatProvider provider}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.dark,
      home: child,
    ),
  );
}

void main() {
  late _MockSearchService searchService;
  late SciChatProvider provider;

  setUp(() async {
    searchService = _MockSearchService();
    provider = SciChatProvider(
      geminiService: _MockGeminiService(),
      searchService: searchService,
      storageService: _MockStorageService(),
      pdfService: _MockPdfService(),
    );
    await provider.init();
  });

  group('ExploreScreen Multi-Source & UI States (Tahap 5A.1)', () {
    testWidgets('Header menampilkan judul "Jelajah Riset"', (tester) async {
      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: searchService),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Jelajah Riset'), findsOneWidget);
      expect(find.text('Jelajah arXiv'), findsNothing);
    });

    testWidgets('Menampilkan chips topik riset universal dan memetakan kueri ke multi-sumber', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: searchService),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Topik-topik universal hadir
      expect(find.text('Kecerdasan Buatan'), findsOneWidget);
      expect(find.text('Visi Komputer'), findsOneWidget);
      expect(find.text('Komputasi Linguistik'), findsOneWidget);
      expect(find.text('Machine Learning'), findsOneWidget);
      expect(find.text('Matematika'), findsOneWidget);
      expect(find.text('Fisika'), findsOneWidget);
      expect(find.text('Biologi Kuantitatif'), findsOneWidget);

      // Default kueri awal adalah cs.AI
      expect(searchService.lastQuery, equals('cat:cs.AI'));
      expect(searchService.lastKeywords, equals('Artificial Intelligence'));

      // Pilih topik Visi Komputer
      await tester.tap(find.text('Visi Komputer'));
      await tester.pumpAndSettle();

      // Kueri arXiv mendapat cat:cs.CV, sementara sumber non-arXiv mendapat 'Computer Vision'
      expect(searchService.lastQuery, equals('cat:cs.CV'));
      expect(searchService.lastKeywords, equals('Computer Vision'));
    });

    testWidgets('Menampilkan hasil paper dari kelima sumber literatur tanpa tereliminasi', (tester) async {
      searchService.resultsToReturn = [
        const ArxivPaper(
          id: 'arxiv-1',
          title: 'arXiv AI Paper',
          authors: ['Author A'],
          summary: 'Summary A',
          published: '2024-01-01',
          updated: '2024-01-01',
          categories: ['cs.AI'],
          pdfUrl: 'https://arxiv.org/pdf/1.pdf',
          absUrl: 'https://arxiv.org/abs/1',
          sources: ['arXiv'],
        ),
        const ArxivPaper(
          id: 's2-1',
          title: 'Semantic Scholar Paper',
          authors: ['Author B'],
          summary: 'Summary B',
          published: '2024-01-02',
          updated: '2024-01-02',
          categories: ['Semantic Scholar'],
          pdfUrl: '',
          absUrl: 'https://semanticscholar.org/paper/1',
          sources: ['Semantic Scholar'],
        ),
        const ArxivPaper(
          id: 'openalex-1',
          title: 'OpenAlex Paper',
          authors: ['Author C'],
          summary: 'Summary C',
          published: '2024-01-03',
          updated: '2024-01-03',
          categories: ['OpenAlex'],
          pdfUrl: '',
          absUrl: 'https://openalex.org/W1',
          sources: ['OpenAlex'],
        ),
        const ArxivPaper(
          id: 'crossref-1',
          title: 'CrossRef Paper',
          authors: ['Author D'],
          summary: 'Summary D',
          published: '2024-01-04',
          updated: '2024-01-04',
          categories: ['Medicine'],
          pdfUrl: '',
          absUrl: 'https://doi.org/10.1234/5',
          sources: ['CrossRef'],
        ),
        const ArxivPaper(
          id: 'archive-1',
          title: 'Internet Archive Book',
          authors: ['Author E'],
          summary: 'Summary E',
          published: '2024-01-05',
          updated: '2024-01-05',
          categories: ['Archive'],
          pdfUrl: '',
          absUrl: 'https://archive.org/details/b1',
          sources: ['Internet Archive'],
        ),
      ];

      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: searchService),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Seluruh 5 paper dari 5 sumber berbeda berhasil dirender sebagai PaperCard
      expect(provider.explorePapers.length, equals(5));
      expect(find.byType(PaperCard), findsNWidgets(5));
      expect(find.text('arXiv AI Paper'), findsOneWidget);
      expect(find.text('Semantic Scholar Paper'), findsOneWidget);
      expect(find.text('OpenAlex Paper'), findsOneWidget);
      expect(find.text('CrossRef Paper'), findsOneWidget);
      expect(find.text('Internet Archive Book'), findsOneWidget);
    });

    testWidgets('Menangani status Error dengan tombol Retry yang berfungsi', (tester) async {
      searchService.shouldThrow = true;

      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: searchService),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Error UI state tampil
      expect(find.text('Gagal Memuat Literatur'), findsOneWidget);
      expect(find.textContaining('Mock 503'), findsOneWidget);
      final retryBtn = find.text('Coba Lagi');
      expect(retryBtn, findsOneWidget);

      // Pulihkan service, ketuk Coba Lagi
      searchService.shouldThrow = false;
      searchService.resultsToReturn = [
        const ArxivPaper(
          id: 'p-retry',
          title: 'Paper Pulih Setelah Retry',
          authors: ['Dr. Hope'],
          summary: 'Abstrak hasil retry',
          published: '2024-01-01',
          updated: '2024-01-01',
          categories: ['cs.AI'],
          pdfUrl: '',
          absUrl: '',
        )
      ];

      await tester.tap(retryBtn);
      await tester.pumpAndSettle();

      // Error hilang, paper tampil
      expect(find.text('Gagal Memuat Literatur'), findsNothing);
      expect(find.text('Paper Pulih Setelah Retry'), findsOneWidget);
    });

    testWidgets('Menangani status Empty dengan pesan edukatif', (tester) async {
      searchService.resultsToReturn = [];

      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: searchService),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Tidak Ada Makalah Ditemukan'), findsOneWidget);
      expect(find.textContaining('Coba pilih topik riset lain'), findsOneWidget);
    });

    testWidgets('Pull-to-refresh memicu pemuatan ulang data', (tester) async {
      searchService.resultsToReturn = [
        const ArxivPaper(
          id: 'p-1',
          title: 'Initial Paper',
          authors: ['Author 1'],
          summary: 'Summary 1',
          published: '2024-01-01',
          updated: '2024-01-01',
          categories: ['cs.AI'],
          pdfUrl: '',
          absUrl: '',
        )
      ];

      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: searchService),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Initial Paper'), findsOneWidget);

      // Ubah data hasil di service
      searchService.resultsToReturn = [
        const ArxivPaper(
          id: 'p-refreshed',
          title: 'Refreshed Paper Content',
          authors: ['Author 2'],
          summary: 'Summary 2',
          published: '2024-01-02',
          updated: '2024-01-02',
          categories: ['cs.AI'],
          pdfUrl: '',
          absUrl: '',
        )
      ];

      // Panggil refreshExplore lewat provider
      await provider.refreshExplore(customSearch: searchService);
      await tester.pumpAndSettle();

      expect(find.text('Refreshed Paper Content'), findsOneWidget);
    });

    testWidgets('Mencegah race condition ketika pengguna berpindah topik dengan cepat', (tester) async {
      final firstCallCompleter = Completer<void>();
      final secondCallCompleter = Completer<void>();

      // Skenario: Topik 1 lambat (tertahan di network), Topik 2 cepat
      final slowFastSearchService = _MockSearchService();

      // Gunakan provider baru untuk isolasi
      final testProvider = SciChatProvider(
        geminiService: _MockGeminiService(),
        searchService: slowFastSearchService,
        storageService: _MockStorageService(),
        pdfService: _MockPdfService(),
      );
      await testProvider.init();

      await tester.pumpWidget(createTestWidget(
        child: ExploreScreen(searchService: slowFastSearchService),
        provider: testProvider,
      ));
      await tester.pumpAndSettle();

      // Panggil loadExploreTopic untuk 'cs.CV' (tertahan di background)
      slowFastSearchService.delayCompleter = firstCallCompleter;
      slowFastSearchService.resultsToReturn = [
        const ArxivPaper(
          id: 'p-slow',
          title: 'Slow Topic Paper (Old)',
          authors: ['Slow'],
          summary: 'Slow',
          published: '2024-01-01',
          updated: '2024-01-01',
          categories: ['cs.CV'],
          pdfUrl: '',
          absUrl: '',
        )
      ];

      final future1 = testProvider.loadExploreTopic('cs.CV', customSearch: slowFastSearchService);

      // Pengguna dengan cepat berpindah ke topik 'physics'
      slowFastSearchService.delayCompleter = secondCallCompleter;
      slowFastSearchService.resultsToReturn = [
        const ArxivPaper(
          id: 'p-fast',
          title: 'Fast Topic Paper (Latest)',
          authors: ['Fast'],
          summary: 'Fast',
          published: '2024-01-02',
          updated: '2024-01-02',
          categories: ['physics'],
          pdfUrl: '',
          absUrl: '',
        )
      ];

      final future2 = testProvider.loadExploreTopic('physics', customSearch: slowFastSearchService);

      // Selesaikan panggilan kedua terlebih dahulu
      secondCallCompleter.complete();
      await future2;
      await tester.pumpAndSettle();

      expect(testProvider.explorePapers.first.title, equals('Fast Topic Paper (Latest)'));

      // Kemudian panggilan pertama baru selesai terlambat
      firstCallCompleter.complete();
      await future1;
      await tester.pumpAndSettle();

      // Hasil dari permintaan lama tidak boleh menimpa permintaan terbaru!
      expect(testProvider.explorePapers.first.title, equals('Fast Topic Paper (Latest)'));
    });
  });
}
