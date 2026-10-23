import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/screens/home_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStorageService extends StorageService {
  final List<ChatSession> _sessions = [];
  final List<ResearchNote> _notes = [];
  final List<ArxivPaper> _favorites = [];

  @override
  Future<String?> getApiKey() async => 'dummy-api-key';
  @override
  Future<void> saveApiKey(String key) async {}
  @override
  Future<String?> getThemeMode() async => 'system';
  @override
  Future<void> saveThemeMode(String mode) async {}
  @override
  Future<List<ArxivPaper>> getFavorites() async => _favorites;
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
  Future<bool> addNote(ResearchNote note) async {
    _notes.add(note);
    return true;
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

class _FakeSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    return [];
  }

  @override
  Future<List<ArxivPaper>> fetchTrending() async => [];
}

class _FakePdfService extends PdfService {}

class _FakeGeminiService extends GeminiService {
  _FakeGeminiService() : super(apiKey: 'dummy-key');

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
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
    yield 'Mock AI Response';
  }

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required String userQuestion,
    required String aiAnswer,
    List<ArxivPaper> papers = const [],
  }) async {
    return ['Saran 1', 'Saran 2'];
  }
}

Widget createTestApp({
  required Widget child,
  required SciChatProvider provider,
  bool isDark = false,
  Size screenSize = const Size(390, 844),
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(isDark),
      home: MediaQuery(
        data: MediaQueryData(
          size: screenSize,
          viewInsets: viewInsets,
          padding: const EdgeInsets.only(top: 44, bottom: 34),
        ),
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStorageService storage;
  late _FakeSearchService searchService;
  late _FakePdfService pdfService;
  late _FakeGeminiService geminiService;
  late SciChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = _FakeStorageService();
    searchService = _FakeSearchService();
    pdfService = _FakePdfService();
    geminiService = _FakeGeminiService();
    provider = SciChatProvider(
      storageService: storage,
      searchService: searchService,
      pdfService: pdfService,
      geminiService: geminiService,
    );
    await provider.init();
    await provider.setApiKey('dummy-api-key');

    // Buat pesan agar tidak memicu animasi hero loop di EmptyState
    provider.createNewSession(notify: false);
    await provider.sendMessage('Halo SCIChat');
  });

  group('SCIChat Chat Composer & Tools Menu Tests', () {
    testWidgets('1. Tombol menu tools menggunakan ikon tune_rounded dan membuka/menutup menu inline',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Pastikan tombol tools ada dengan ikon tune_rounded
      final toolsBtn = find.byKey(const Key('toolsMenuButton'));
      expect(toolsBtn, findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

      // Awalnya panel menu tools belum terbuka
      expect(find.byKey(const Key('toolsMenuPanel')), findsNothing);

      // Buka panel menu tools
      await tester.tap(toolsBtn);
      await tester.pumpAndSettle();

      // Panel menu tools harus muncul di atas composer
      expect(find.byKey(const Key('toolsMenuPanel')), findsOneWidget);
      expect(find.text('Mode Riset & Alat AI'), findsOneWidget);

      // Tutup via tombol close pada header panel
      final closeBtn = find.byKey(const Key('toolsMenuCloseButton'));
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Panel tertutup
      expect(find.byKey(const Key('toolsMenuPanel')), findsNothing);
    });

    testWidgets('2. Menu tools tidak menutupi BottomNavigationBar dan tab tetap dapat diakses',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Buka tools menu
      await tester.tap(find.byKey(const Key('toolsMenuButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toolsMenuPanel')), findsOneWidget);

      // Dapatkan rect panel tools dan rect BottomNavigationBar
      final panelRect = tester.getRect(find.byKey(const Key('toolsMenuPanel')));
      final bottomNavRect = tester.getRect(find.byType(BottomNavigationBar));

      // Panel tools harus berada di atas BottomNavigationBar (tidak tumpang tindih)
      expect(panelRect.bottom <= bottomNavRect.top, isTrue,
          reason: 'Panel tools tidak boleh meluber menutupi BottomNavigationBar');

      // BottomNavigationBar tetap responsif
      final exploreTab = find.text('Explore');
      expect(exploreTab, findsOneWidget);
      await tester.tap(exploreTab);
      await tester.pumpAndSettle();

      expect(provider.currentTab, equals(1));
    });

    testWidgets('3. Deep Search dapat diaktifkan, memunculkan chip, dan dinonaktifkan via tombol silang chip',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      expect(provider.deepSearch, isFalse);
      expect(find.byKey(const Key('deepSearchChip')), findsNothing);

      // Buka tools menu
      await tester.tap(find.byKey(const Key('toolsMenuButton')));
      await tester.pumpAndSettle();

      // Ketuk Deep Search item
      await tester.tap(find.byKey(const Key('toolDeepSearchItem')));
      await tester.pumpAndSettle();

      // Verifikasi state dan chip
      expect(provider.deepSearch, isTrue);
      expect(find.byKey(const Key('deepSearchChip')), findsOneWidget);
      expect(find.text('Deep Search'), findsWidgets);

      // Hapus chip dengan menekan tombol silang pada chip
      await tester.tap(find.byKey(const Key('deepSearchChipClose')));
      await tester.pumpAndSettle();

      // State kembali false dan chip hilang
      expect(provider.deepSearch, isFalse);
      expect(find.byKey(const Key('deepSearchChip')), findsNothing);
    });

    testWidgets('4. ELI5 Mode dapat diaktifkan, memunculkan chip, dan dinonaktifkan tanpa mengubah Deep Search',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Aktifkan Deep Search terlebih dahulu
      provider.toggleDeepSearch();
      await tester.pumpAndSettle();
      expect(provider.deepSearch, isTrue);

      // Buka tools menu
      await tester.tap(find.byKey(const Key('toolsMenuButton')));
      await tester.pumpAndSettle();

      // Ketuk ELI5 Mode item
      await tester.tap(find.byKey(const Key('toolEli5Item')));
      await tester.pumpAndSettle();

      // Keduanya harus aktif bersamaan
      expect(provider.deepSearch, isTrue);
      expect(provider.eli5Mode, isTrue);
      expect(find.byKey(const Key('deepSearchChip')), findsOneWidget);
      expect(find.byKey(const Key('eli5Chip')), findsOneWidget);

      // Hapus hanya ELI5 chip
      await tester.tap(find.byKey(const Key('eli5ChipClose')));
      await tester.pumpAndSettle();

      // ELI5 harus false, tapi Deep Search tetap true
      expect(provider.eli5Mode, isFalse);
      expect(provider.deepSearch, isTrue);
      expect(find.byKey(const Key('eli5Chip')), findsNothing);
      expect(find.byKey(const Key('deepSearchChip')), findsOneWidget);
    });

    testWidgets('5. Memilih AI Skill tetap berfungsi, menampilkan chip, dan dapat dibatalkan',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Buka tools menu
      await tester.tap(find.byKey(const Key('toolsMenuButton')));
      await tester.pumpAndSettle();

      // Ketuk skill Reviewer Kritis
      await tester.tap(find.byKey(const Key('toolSkill_peerReview')));
      await tester.pumpAndSettle();

      expect(provider.activeSkill, equals(AiSkill.peerReview));
      expect(find.text('Reviewer Kritis'), findsOneWidget);

      // Hapus skill via tombol silang
      final closeIcon = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byIcon(Icons.close),
      );
      expect(closeIcon, findsWidgets);
      await tester.tap(closeIcon.first);
      await tester.pumpAndSettle();

      expect(provider.activeSkill, equals(AiSkill.none));
    });

    testWidgets('6. Keyboard muncul dan hilang tanpa menyebabkan RenderFlex overflow',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
        viewInsets: const EdgeInsets.only(bottom: 300), // Keyboard terbuka
      ));
      await tester.pump(const Duration(seconds: 2));

      // Tidak ada error exception
      expect(tester.takeException(), isNull);

      // Tutup keyboard
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
        viewInsets: EdgeInsets.zero,
      ));
      await tester.pump(const Duration(seconds: 2));

      expect(tester.takeException(), isNull);
    });

    testWidgets('7. Tidak terjadi overflow pada layar kecil dan menu tools dapat di-scroll',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
        screenSize: const Size(320, 480), // Layar sangat kompak
      ));
      await tester.pumpAndSettle();

      // Buka tools menu
      await tester.tap(find.byKey(const Key('toolsMenuButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toolsMenuPanel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('8. Konsistensi tema terang dan tema gelap',
        (tester) async {
      // Tema Gelap
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
        isDark: true,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Buka menu di dark mode
      await tester.tap(find.byKey(const Key('toolsMenuButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('toolsMenuPanel')), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Tema Terang
      await tester.pumpWidget(createTestApp(
        child: const HomeScreen(),
        provider: provider,
        isDark: false,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('9. Bottom Fade Gradient dikonfigurasi setinggi 96dp',
        (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const ChatScreen(),
        provider: provider,
      ));
      await tester.pumpAndSettle();

      // Cari Positioned gradient di bawah composer
      final positionedGradients = tester.widgetList<Positioned>(
        find.byWidgetPredicate(
          (w) => w is Positioned && w.bottom == 0 && w.height == 96,
        ),
      );
      expect(positionedGradients, isNotEmpty,
          reason: 'Bottom fade gradient harus dikonfigurasi dengan height 96dp');
    });
  });
}
