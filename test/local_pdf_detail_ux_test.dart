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

class _MockStorageService extends StorageService {
  final List<ArxivPaper> _favorites = [];

  @override
  Future<String?> getApiKey() async => 'test-api-key';
  @override
  Future<String?> getThemeMode() async => 'dark';
  @override
  Future<List<ArxivPaper>> getFavorites() async => _favorites;

  @override
  Future<void> addFavorite(ArxivPaper paper) async {
    if (!_favorites.any((p) => p.id == paper.id)) {
      _favorites.add(paper);
    }
  }

  @override
  Future<void> removeFavorite(String paperId) async {
    _favorites.removeWhere((p) => p.id == paperId);
  }

  @override
  Future<bool> isFavorite(String paperId) async =>
      _favorites.any((p) => p.id == paperId);

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

Widget _buildDetailScreen({
  required ArxivPaper paper,
  required SciChatProvider provider,
  Size size = const Size(380, 800),
}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ChangeNotifierProvider<SciChatProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: SciChatTheme.dark,
        home: PaperDetailScreen(paper: paper),
      ),
    ),
  );
}

void main() {
  group('Local PDF Paper Detail Screen UX Tests', () {
    late SciChatProvider provider;

    setUp(() {
      provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: SearchService(),
        geminiService: GeminiService(apiKey: 'dummy-key'),
        pdfService: PdfService(),
      );
    });

    const localPaperPlaceholder = ArxivPaper(
      id: 'local_1792648047570',
      title:
          'NeurIPS-2020-retrieval-augmented-generation-for-knowledge-intensive-nlp-tasks-Paper.pdf',
      authors: ['Local File'],
      summary: '',
      published: '2026-10-22',
      updated: '2026-10-22',
      pdfUrl:
          '/storage/emulated/0/Download/NeurIPS-2020-retrieval-augmented-generation.pdf',
      absUrl:
          '/storage/emulated/0/Download/NeurIPS-2020-retrieval-augmented-generation.pdf',
      categories: ['Local PDF', 'PDF'],
      journalRef: null,
      doi: null,
    );

    testWidgets(
        '1. Local PDF displays distinct PDF Lokal badge and omits fake PENULIS header',
        (tester) async {
      await tester.pumpWidget(_buildDetailScreen(
        paper: localPaperPlaceholder,
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Verify 'PDF Lokal' badge is rendered
      expect(find.text('PDF Lokal'), findsOneWidget);

      // Verify fake 'PENULIS' section is NOT rendered
      expect(find.text('PENULIS'), findsNothing);
      expect(find.text('Local File'), findsNothing);

      // Verify metadata fields: DITAMBAHKAN, ID DOKUMEN
      expect(find.text('DITAMBAHKAN'), findsOneWidget);
      expect(find.text('ID DOKUMEN'), findsOneWidget);
      expect(find.text('local_1792648047570'), findsOneWidget);

      // Verify extraction status label
      expect(find.text('Siap Dianalisis'), findsOneWidget);

      // Verify fallback card for empty abstract
      expect(
        find.textContaining('Abstrak terpisah tidak terdeteksi'),
        findsOneWidget,
      );
    });

    testWidgets('2. Displays real authors if present on local PDF',
        (tester) async {
      final paperWithAuthors = localPaperPlaceholder.copyWith(
        authors: ['Patrick Lewis', 'Ethan Perez', 'Douwe Kiela'],
      );

      await tester.pumpWidget(_buildDetailScreen(
        paper: paperWithAuthors,
        provider: provider,
      ));
      await tester.pumpAndSettle();

      expect(find.text('PENULIS'), findsOneWidget);
      expect(find.text('Patrick Lewis  ·  Ethan Perez  ·  Douwe Kiela'),
          findsOneWidget);
    });

    testWidgets('3. Action Button: Tanya Paper sets active paper and navigates',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildDetailScreen(
        paper: localPaperPlaceholder,
        provider: provider,
      ));
      await tester.pumpAndSettle();

      final tanyaButton = find.text('Tanya Paper');
      expect(tanyaButton, findsOneWidget);

      await tester.ensureVisible(tanyaButton);
      await tester.tap(tanyaButton);
      await tester.pumpAndSettle();

      // Verify active paper context is set in provider
      expect(provider.activePaperContext?.id, equals(localPaperPlaceholder.id));
      expect(provider.currentTab, equals(0));
    });

    testWidgets(
        '4. Action Button: Simpan ke Library toggles reactive state to Tersimpan di Pustaka',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildDetailScreen(
        paper: localPaperPlaceholder,
        provider: provider,
      ));
      await tester.pumpAndSettle();

      final saveButton = find.text('Simpan ke Pustaka (Library)');
      expect(saveButton, findsOneWidget);
      expect(provider.isFavorite(localPaperPlaceholder.id), isFalse);

      // Tap Simpan ke Pustaka
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Verify provider state updated
      expect(provider.isFavorite(localPaperPlaceholder.id), isTrue);
      // UI dynamically changes to Tersimpan di Pustaka
      final savedButton = find.text('Tersimpan di Pustaka (Library)');
      expect(savedButton, findsOneWidget);

      // Tap again to toggle off
      await tester.ensureVisible(savedButton);
      await tester.tap(savedButton);
      await tester.pumpAndSettle();
      expect(provider.isFavorite(localPaperPlaceholder.id), isFalse);
      expect(find.text('Simpan ke Pustaka (Library)'), findsOneWidget);
    });

    testWidgets('5. Action Button: Baca PDF button is rendered and configured',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildDetailScreen(
        paper: localPaperPlaceholder,
        provider: provider,
      ));
      await tester.pumpAndSettle();

      final bacaPdfButton = find.text('Baca PDF');
      expect(bacaPdfButton, findsOneWidget);
    });

    testWidgets('6. Action Button: Rangkum opens _SummarizeSheet',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(_buildDetailScreen(
        paper: localPaperPlaceholder,
        provider: provider,
      ));
      await tester.pumpAndSettle();

      final rangkumButton = find.text('Rangkum');
      expect(rangkumButton, findsOneWidget);

      await tester.tap(rangkumButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify bottom sheet appears
      expect(find.text('AI Summary'), findsOneWidget);
    });

    testWidgets('7. Layout renders without overflow on narrow 320dp screen',
        (tester) async {
      await tester.pumpWidget(_buildDetailScreen(
        paper: localPaperPlaceholder,
        provider: provider,
        size: const Size(320, 640),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
