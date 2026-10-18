import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/screens/explore_screen.dart';
import 'package:scichat/screens/favorites_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';

class _MockStorageService extends StorageService {
  final List<ChatSession> _sessions = [];
  final List<ResearchNote> _notes = [];

  @override
  Future<String?> getApiKey() async => 'dummy-key';
  @override
  Future<String?> getThemeMode() async => 'system';
  @override
  Future<List<ArxivPaper>> getFavorites() async => _favorites;
  final List<ArxivPaper> _favorites = [];
  @override
  Future<List<ChatSession>> getChatSessions() async => _sessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {
    _sessions.clear();
    _sessions.addAll(sessions);
  }

  @override
  Future<List<ResearchNote>> getNotes() async => _notes;
  @override
  Future<void> addNote(ResearchNote note) async {
    _notes.add(note);
  }

  @override
  Future<void> removeNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
  }

  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

class _MockSearchService extends SearchService {
  List<ArxivPaper> resultsToReturn = [];
  String lastQuery = '';

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    lastQuery = query;
    return resultsToReturn;
  }

  @override
  Future<List<ArxivPaper>> fetchTrending() async => [];
}

class _MockPdfService extends PdfService {
  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async {
    return 'Mock PDF text';
  }
}

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy');

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
  }

  @override
  Future<String> chat({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper>? papers,
    Map<String, String>? fullTexts,
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) async {
    return 'Mock Response';
  }

  @override
  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    yield 'Mock Response';
  }

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required String userQuestion,
    required String aiAnswer,
    List<ArxivPaper> papers = const [],
  }) async {
    return ['Saran 1', 'Saran 2', 'Saran 3'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestWidget(
      {required Widget child, required SciChatProvider provider}) {
    return ChangeNotifierProvider<SciChatProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: SciChatTheme.light,
        darkTheme: SciChatTheme.dark,
        home: child,
      ),
    );
  }

  group('ISSUE-01: Research Notes Preview Rendering in FavoritesScreen', () {
    testWidgets(
        'Kartu pratinjau membersihkan penanda markdown mentah tanpa merusak konten asli',
        (tester) async {
      final storage = _MockStorageService();
      final noteWithMarkdown = ResearchNote(
        id: 'note-1',
        sourceMessageId: 'msg-1',
        content: '''### Temuan Utama
Berikut adalah ringkasan hasil:
- Poin **sangat penting**: akurasi 98%
- Model dievaluasi dengan `evaluate()`
Rumus matematis: \$E = mc^2\$ dan kompleksitas O(n * log(n))''',
        savedAt: DateTime.now(),
      );
      await storage.addNote(noteWithMarkdown);

      final provider = SciChatProvider(
        storageService: storage,
        geminiService: _MockGeminiService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
      );
      await provider.init();

      await tester.pumpWidget(
          createTestWidget(child: const FavoritesScreen(), provider: provider));
      await tester.pumpAndSettle();

      // Berpindah ke tab "Catatan" (tab kedua)
      final notesTabFinder = find.text('Catatan');
      expect(notesTabFinder, findsOneWidget);
      await tester.tap(notesTabFinder);
      await tester.pumpAndSettle();

      // Pratinjau kartu tidak boleh menampilkan token markdown mentah
      expect(find.textContaining('###'), findsNothing);
      expect(find.textContaining('**sangat penting**'), findsNothing);
      expect(find.textContaining('`evaluate()`'), findsNothing);

      // Teks yang dibersihkan dan ekspresi ilmiah tetap ada
      expect(find.textContaining('Temuan Utama'), findsOneWidget);
      expect(find.textContaining('sangat penting'), findsOneWidget);
      expect(find.textContaining('evaluate()'), findsOneWidget);
      expect(find.textContaining(r'$E = mc^2$'), findsOneWidget);

      // Data asli pada model provider tidak berubah
      expect(provider.notes.first.content, contains('### Temuan Utama'));
      expect(provider.notes.first.content, contains('**sangat penting**'));
    });
  });

  group('ISSUE-02: Floating Button Layout & Positioning in ChatScreen', () {
    testWidgets(
        'Tombol "Kembali ke respons terbaru" tidak muncul saat list di dasar, dan muncul saat user menggulir ke atas',
        (tester) async {
      final provider = SciChatProvider(
        geminiService: _MockGeminiService(),
        searchService: _MockSearchService(),
        storageService: _MockStorageService(),
        pdfService: _MockPdfService(),
      );
      await provider.init();

      // Buat banyak pesan sehingga ListView dapat digulir
      provider.createNewSession(notify: false);
      for (int i = 0; i < 15; i++) {
        await provider.sendMessage('Pertanyaan $i');
      }

      await tester.pumpWidget(
          createTestWidget(child: const ChatScreen(), provider: provider));
      await tester.pumpAndSettle();

      // Saat di dasar, tombol floating tidak ditampilkan
      expect(find.byKey(const Key('scrollToBottomButton')), findsNothing);

      // Gulir ke atas
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();

      // Tombol floating sekarang harus muncul di atas composer secara ringkas (tanpa teks visual)
      expect(find.byKey(const Key('scrollToBottomButton')), findsOneWidget);
      expect(find.text('Kembali ke respons terbaru'), findsNothing);
      expect(find.byTooltip('Kembali ke respons terbaru'), findsOneWidget);

      // Ketuk tombol floating
      await tester.tap(find.byKey(const Key('scrollToBottomButton')));
      await tester.pumpAndSettle();

      // Setelah digulir kembali ke dasar, tombol floating hilang
      expect(find.byKey(const Key('scrollToBottomButton')), findsNothing);
    });
  });

  group('ISSUE-03 & ISSUE-05: ExploreScreen Clear Search & Lifecycle Guards',
      () {
    testWidgets(
        'Tombol clear membersihkan teks input dan memulihkan kategori default jika kueri aktif',
        (tester) async {
      final searchService = _MockSearchService();
      searchService.resultsToReturn = [
        ArxivPaper(
          id: 'test-1',
          title: 'Quantum Computing Paper',
          authors: const ['Dr. Quantum'],
          summary: 'Abstract of paper',
          published: '2024-01-01',
          updated: '2024-01-01',
          categories: const ['quant-ph'],
          pdfUrl: 'http://example.com/qp.pdf',
          absUrl: 'http://example.com/qp',
        )
      ];

      final provider = SciChatProvider(
        geminiService: _MockGeminiService(),
        searchService: searchService,
        storageService: _MockStorageService(),
        pdfService: _MockPdfService(),
      );
      await provider.init();

      await tester.pumpWidget(createTestWidget(
          child: ExploreScreen(searchService: searchService),
          provider: provider));
      await tester.pumpAndSettle();

      // Input teks pencarian dan submit
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'quantum machine learning');
      tester
          .widget<TextField>(textField)
          .onSubmitted
          ?.call('quantum machine learning');
      await tester.pumpAndSettle();

      expect(searchService.lastQuery, equals('quantum machine learning'));

      // Temukan tombol clear (suffix icon)
      final clearButton = find.byIcon(Icons.clear);
      expect(clearButton, findsOneWidget);

      // Ketuk tombol clear
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      // Teks di controller kosong
      final updatedTextField = tester.widget<TextField>(textField);
      expect(updatedTextField.controller?.text, isEmpty);

      // Default category cs.AI dimuat ulang
      expect(searchService.lastQuery, equals('cat:cs.AI'));
    });
  });
}
