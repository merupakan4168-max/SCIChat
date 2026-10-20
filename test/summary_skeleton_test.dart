import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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
import 'package:scichat/widgets/summary_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockStorageService extends StorageService {
  @override
  Future<String?> getApiKey() async => 'test-api-key';
  @override
  Future<void> saveApiKey(String key) async {}
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
  Future<bool> addNote(ResearchNote note) async => true;
  @override
  Future<void> removeNote(String id) async {}
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

class _MockSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async =>
      [];
  @override
  Future<List<ArxivPaper>> fetchTrending() async => [];
}

class _MockPdfService extends PdfService {
  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async =>
      'Mock PDF text';
}

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy');

  Completer<String>? summarizeCompleter;
  int summarizeCalls = 0;

  @override
  Future<String> summarizePaper(ArxivPaper paper, {String? pdfText}) async {
    summarizeCalls++;
    if (summarizeCompleter != null) {
      return summarizeCompleter!.future;
    }
    return 'Mock AI summary result for testing.';
  }
}

ArxivPaper _createSamplePaper() {
  return const ArxivPaper(
    id: '2401.00001',
    title: 'Advancements in Scientific Neural Synthesis',
    summary:
        'This paper proposes a novel framework for deep academic exploration.',
    authors: ['Ada Lovelace', 'Alan Turing'],
    published: '2025-01-15',
    updated: '2025-01-15',
    pdfUrl: 'https://arxiv.org/pdf/2401.00001',
    absUrl: 'https://arxiv.org/abs/2401.00001',
    categories: ['cs.AI', 'cs.LG'],
    sources: ['arXiv'],
  );
}

Widget _wrapWithTheme({
  required Widget child,
  Brightness brightness = Brightness.dark,
  double? textScale,
  Size? surfaceSize,
}) {
  final isDark = brightness == Brightness.dark;
  final themeData = ThemeData(
    brightness: brightness,
    extensions: [
      isDark ? SciChatTheme.darkColors : SciChatTheme.lightColors,
    ],
  );

  return MaterialApp(
    theme: themeData,
    home: MediaQuery(
      data: MediaQueryData(
        size: surfaceSize ?? const Size(400, 800),
        textScaler: TextScaler.linear(textScale ?? 1.0),
      ),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF050505) : const Color(0xFFFCFCFC),
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SummarySkeleton Widget Tests', () {
    testWidgets('renders skeleton blocks with Semantics label in dark mode',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          brightness: Brightness.dark,
          child: const SizedBox(
            height: 500,
            width: 380,
            child: SummarySkeleton(animate: false),
          ),
        ),
      );

      // Verify Semantics wrapper
      final semanticsFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Memuat ringkasan AI...' &&
            widget.excludeSemantics == true,
      );
      expect(semanticsFinder, findsOneWidget);

      // Verify presence of SummarySkeleton and SingleChildScrollView
      expect(find.byType(SummarySkeleton), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('renders properly in light mode without exceptions',
        (tester) async {
      await tester.pumpWidget(
        _wrapWithTheme(
          brightness: Brightness.light,
          child: const SizedBox(
            height: 500,
            width: 380,
            child: SummarySkeleton(animate: false),
          ),
        ),
      );

      expect(find.byType(SummarySkeleton), findsOneWidget);
    });

    testWidgets('does not overflow on narrow mobile screens (320dp)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _wrapWithTheme(
          surfaceSize: const Size(320, 600),
          child: const SizedBox(
            height: 600,
            width: 320,
            child: SummarySkeleton(animate: false),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(SummarySkeleton), findsOneWidget);
    });

    testWidgets('respects disableAnimations from MediaQuery', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [SciChatTheme.darkColors],
          ),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: SummarySkeleton(),
            ),
          ),
        ),
      );

      // Pump a single frame without continuous timer issue
      await tester.pump();
      expect(find.byType(SummarySkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scroll controller can be attached without issues',
        (tester) async {
      final controller = ScrollController();
      await tester.pumpWidget(
        _wrapWithTheme(
          child: SizedBox(
            height: 400,
            width: 380,
            child: SummarySkeleton(
              controller: controller,
              animate: false,
            ),
          ),
        ),
      );

      expect(controller.hasClients, isTrue);
      controller.dispose();
    });
  });

  group('AI Summary Bottom Sheet Integration Tests', () {
    late _MockStorageService mockStorage;
    late _MockSearchService mockSearch;
    late _MockPdfService mockPdf;
    late _MockGeminiService mockGemini;
    late SciChatProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockStorage = _MockStorageService();
      mockSearch = _MockSearchService();
      mockPdf = _MockPdfService();
      mockGemini = _MockGeminiService();

      provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: mockGemini,
      );

      await provider.setApiKey('valid-key');
    });

    testWidgets(
        'displays SummarySkeleton during loading and replaces with MarkdownBody on completion',
        (tester) async {
      final completer = Completer<String>();
      mockGemini.summarizeCompleter = completer;

      final paper = _createSamplePaper();

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: PaperDetailScreen(paper: paper),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find and tap the "Rangkum" action button
      final rangkumButton = find.text('Rangkum');
      expect(rangkumButton, findsOneWidget);
      await tester.tap(rangkumButton);
      await tester.pump(); // Start sheet animation
      await tester.pump(const Duration(milliseconds: 300)); // Sheet opened

      // Verify that SummarySkeleton is visible while loading
      expect(find.byType(SummarySkeleton), findsOneWidget);
      // Verify that the old CircularProgressIndicator spinner is NOT displayed
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Verify AI Summary header elements are preserved
      expect(find.text('AI Summary'), findsOneWidget);
      expect(find.text(paper.title), findsAtLeastNWidgets(1));

      // Now complete the summarization
      completer.complete(
          '### Apa yang dilakukan\nMakalah ini meneliti sintesis saraf.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Skeleton should now be removed and MarkdownBody should be displayed in the sheet
      expect(find.byType(SummarySkeleton), findsNothing);
      expect(
          find.descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(MarkdownBody),
          ),
          findsOneWidget);
      expect(find.textContaining('Apa yang dilakukan'), findsOneWidget);
    });

    testWidgets(
        'displays error state and removes SummarySkeleton if summarization fails',
        (tester) async {
      final completer = Completer<String>();
      mockGemini.summarizeCompleter = completer;

      final paper = _createSamplePaper();

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: PaperDetailScreen(paper: paper),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final rangkumButton = find.text('Rangkum');
      await tester.tap(rangkumButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SummarySkeleton), findsOneWidget);

      // Complete with error
      completer.completeError(Exception('Network error during summarization'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Skeleton must be gone and error displayed
      expect(find.byType(SummarySkeleton), findsNothing);
      expect(find.textContaining('Network error during summarization'),
          findsOneWidget);
    });
  });
}
