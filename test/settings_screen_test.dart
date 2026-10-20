import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/home_screen.dart';
import 'package:scichat/screens/settings_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/theme/scichat_theme.dart';

class MockTestStorageService extends StorageService {
  String? _storedKey;
  final List<ChatSession> _sessions = [];
  final List<ArxivPaper> _favorites = [];
  final List<ResearchNote> _notes = [];
  String _themeMode = 'system';

  MockTestStorageService({String? initialKey}) : _storedKey = initialKey;

  @override
  Future<String?> getApiKey() async => _storedKey;

  @override
  Future<void> saveApiKey(String key) async {
    _storedKey = key;
  }

  @override
  Future<List<ChatSession>> getChatSessions() async => _sessions;

  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {
    _sessions.clear();
    _sessions.addAll(sessions);
  }

  @override
  Future<List<ArxivPaper>> getFavorites() async => _favorites;

  @override
  Future<void> addFavorite(ArxivPaper paper) async {
    _favorites.add(paper);
  }

  @override
  Future<void> removeFavorite(String paperId) async {
    _favorites.removeWhere((p) => p.id == paperId);
  }

  @override
  Future<bool> isFavorite(String paperId) async {
    return _favorites.any((p) => p.id == paperId);
  }

  @override
  Future<List<ResearchNote>> getNotes() async => _notes;

  @override
  Future<bool> addNote(ResearchNote note) async {
    _notes.add(note);
    return true;
  }

  @override
  Future<void> removeNote(String noteId) async {
    _notes.removeWhere((n) => n.id == noteId);
  }

  @override
  Future<String?> getThemeMode() async => _themeMode;

  @override
  Future<void> saveThemeMode(String mode) async {
    _themeMode = mode;
  }

  SearchFilter _searchFilter = const SearchFilter();

  @override
  Future<SearchFilter> getSearchFilter() async => _searchFilter;

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {
    _searchFilter = filter;
  }
}

class MockTestGeminiService extends GeminiService {
  MockTestGeminiService() : super(apiKey: 'dummy');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildSettingsWidget(SciChatProvider provider) {
    return ChangeNotifierProvider<SciChatProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: SciChatTheme.light,
        darkTheme: SciChatTheme.dark,
        home: const SettingsScreen(),
      ),
    );
  }

  group('SettingsScreen API Key Display & Sync Tests', () {
    testWidgets('1. Key tetap dimasking secara default (obscureText: true)',
        (tester) async {
      final storage =
          MockTestStorageService(initialKey: 'sk-test1234567890abcdef');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      final textField = tester.widget<TextField>(textFieldFinder);
      expect(textField.obscureText, isTrue);
      expect(textField.controller?.text, equals('sk-test1234567890abcdef'));
    });

    testWidgets(
        '2. Tombol mata menampilkan dan menyembunyikan nilai tanpa mengubah nilainya',
        (tester) async {
      final storage =
          MockTestStorageService(initialKey: 'sk-test1234567890abcdef');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Cek tombol mata (awalnya visibility_outlined)
      final eyeButtonFinder = find.byIcon(Icons.visibility_outlined);
      expect(eyeButtonFinder, findsOneWidget);

      // Tekan tombol mata untuk melihat teks
      await tester.tap(eyeButtonFinder);
      await tester.pumpAndSettle();

      var textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isFalse);
      expect(textField.controller?.text, equals('sk-test1234567890abcdef'));
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // Tekan kembali untuk memasking ulang
      await tester.tap(find.byIcon(Icons.visibility_off_outlined));
      await tester.pumpAndSettle();

      textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.obscureText, isTrue);
      expect(textField.controller?.text, equals('sk-test1234567890abcdef'));
    });

    testWidgets(
        '3. Sinkronisasi asinkron: nilai dari provider.init() yang selesai terlambat langsung tersinkronkan ke controller',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-async-loaded-key');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );

      // Pasang widget SEBELUM provider.init() selesai
      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pump();

      // Awalnya kosong karena init belum selesai
      var textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, isEmpty);

      // Jalankan init() secara asinkron
      await provider.init();
      await tester.pumpAndSettle();

      // Controller HARUS otomatis terisi dengan kunci yang dimuat, bukan tetap kosong/placeholder
      textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals('sk-async-loaded-key'));
    });

    testWidgets('4. Menyimpan key baru memperbarui provider dan storage',
        (tester) async {
      final storage = MockTestStorageService(initialKey: '');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.enterText(textFieldFinder, 'sk-newly-saved-key-999');
      await tester.pumpAndSettle();

      final saveButtonFinder = find.text('Save API Key');
      expect(saveButtonFinder, findsOneWidget);
      await tester.tap(saveButtonFinder);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(provider.apiKey, equals('sk-newly-saved-key-999'));
      expect(provider.apiKeySet, isTrue);
      expect(await storage.getApiKey(), equals('sk-newly-saved-key-999'));
    });

    testWidgets(
        '5. Mengosongkan key dan menyimpan menghapus key dari provider dan storage',
        (tester) async {
      final storage =
          MockTestStorageService(initialKey: 'sk-old-key-to-delete');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      final textFieldFinder = find.byType(TextField);
      await tester.enterText(textFieldFinder, '');
      await tester.pumpAndSettle();

      final saveButtonFinder = find.text('Update API Key');
      expect(saveButtonFinder, findsOneWidget);
      await tester.tap(saveButtonFinder);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(provider.apiKey, isEmpty);
      expect(provider.apiKeySet, isFalse);
      expect(await storage.getApiKey(), isEmpty);
    });
  });

  group('Settings Back Navigation, PopScope & Theme Integration Tests', () {
    Widget buildAppWidget(SciChatProvider provider) {
      return ChangeNotifierProvider<SciChatProvider>.value(
        value: provider,
        child: Consumer<SciChatProvider>(
          builder: (context, p, _) => MaterialApp(
            theme: SciChatTheme.light,
            darkTheme: SciChatTheme.dark,
            themeMode: p.themeMode,
            home: const HomeScreen(),
          ),
        ),
      );
    }

    testWidgets(
        '6. Research -> Settings -> tekan tombol kembali di AppBar kembali ke Research tanpa black screen',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-test-key');
      final session = ChatSession(
        id: 'sess-1',
        title: 'Sesi Riset Kuantum',
        updatedAt: DateTime.now(),
        messages: [
          ChatMessage(
            id: 'msg-1',
            role: MessageRole.user,
            content: 'Pertanyaan pengguna tentang dekoherensi',
            timestamp: DateTime.now(),
          ),
        ],
      );
      await storage.saveChatSessions([session]);
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildAppWidget(provider));
      await tester.pumpAndSettle();

      // Mulai pada tab 0 (Research) dengan sesi aktif
      expect(provider.currentTab, equals(0));
      expect(provider.messages.length, equals(1));
      expect(find.byType(HomeScreen), findsOneWidget);

      // Pindah ke tab Settings (index 3)
      provider.setTab(3);
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(3));
      expect(find.text('Pengaturan'), findsOneWidget);

      // Tekan tombol kembali di AppBar Settings
      final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Tab kembali ke Research (index 0), root route HomeScreen tetap hidup tanpa black screen
      expect(provider.currentTab, equals(0));
      expect(find.byType(HomeScreen), findsOneWidget);
      // State percakapan tetap utuh tidak hilang
      expect(provider.messages.length, equals(1));
    });

    testWidgets(
        '7. Research -> Settings -> tekan tombol Back Android kembali ke Research melalui PopScope',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-test-key');
      final session = ChatSession(
        id: 'sess-1',
        title: 'Sesi Riset Kuantum',
        updatedAt: DateTime.now(),
        messages: [
          ChatMessage(
            id: 'msg-1',
            role: MessageRole.user,
            content: 'Pertanyaan pengguna tentang dekoherensi',
            timestamp: DateTime.now(),
          ),
        ],
      );
      await storage.saveChatSessions([session]);
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildAppWidget(provider));
      await tester.pumpAndSettle();

      // Pindah ke Settings
      provider.setTab(3);
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(3));

      // Simulasikan tombol Back Android
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // PopScope harus mengarahkan kembali ke Tab 0
      expect(provider.currentTab, equals(0));
      expect(find.byType(HomeScreen), findsOneWidget);
      // State percakapan tetap utuh
      expect(provider.messages.length, equals(1));
    });

    testWidgets(
        '8. Ubah tema Terang -> Gelap -> Sistem mempertahankan state percakapan dan navigasi',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-test-key');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      // Tambahkan chat session dan favorites untuk verifikasi keutuhan data
      final session = ChatSession(
        id: 'sess-1',
        title: 'Sesi Riset Kuantum',
        updatedAt: DateTime.now(),
        messages: [
          ChatMessage(
            id: 'msg-1',
            role: MessageRole.user,
            content: 'Pertanyaan pengguna tentang dekoherensi',
            timestamp: DateTime.now(),
          ),
          ChatMessage(
            id: 'msg-2',
            role: MessageRole.assistant,
            content: 'Jawaban riset AI',
            timestamp: DateTime.now(),
          ),
        ],
      );
      await storage.saveChatSessions([session]);
      await provider.init();

      await tester.pumpWidget(buildAppWidget(provider));
      await tester.pumpAndSettle();

      // Beralih ke Settings
      provider.setTab(3);
      await tester.pumpAndSettle();

      // 1. Ubah ke Terang
      await provider.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();
      expect(provider.themeMode, equals(ThemeMode.light));

      // 2. Ubah ke Gelap
      await provider.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(provider.themeMode, equals(ThemeMode.dark));

      // 3. Ubah ke Sistem
      await provider.setThemeMode(ThemeMode.system);
      await tester.pumpAndSettle();
      expect(provider.themeMode, equals(ThemeMode.system));

      // Kembali ke Research
      final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(provider.currentTab, equals(0));
      expect(provider.apiKey, equals('sk-test-key'));
      expect(provider.messages.length, equals(2));
      expect(provider.messages.first.content,
          equals('Pertanyaan pengguna tentang dekoherensi'));
    });

    testWidgets(
        '9. Berpindah tab berulang kali setelah tema berubah tanpa blank screen atau error',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-test-key');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildAppWidget(provider));
      await tester.pumpAndSettle();

      // Ubah tema ke Gelap
      await provider.setThemeMode(ThemeMode.dark);
      await tester.pumpAndSettle();

      // Berpindah tab berurutan 0 -> 1 -> 2 -> 3 -> 0
      provider.setTab(1); // Explore
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(1));

      provider.setTab(2); // Library
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(2));

      provider.setTab(3); // Settings
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(3));

      // Tekan tombol back di Settings AppBar
      final backButton = find.widgetWithIcon(IconButton, Icons.arrow_back);
      await tester.tap(backButton);
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(0));

      // Ubah tema ke Terang dan pindah balik
      await provider.setThemeMode(ThemeMode.light);
      await tester.pumpAndSettle();

      provider.setTab(2);
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(2));

      // Back Android dari Library kembali ke Research
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();
      expect(provider.currentTab, equals(0));
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  Widget buildAboutCardWidget({
    ThemeMode themeMode = ThemeMode.dark,
    double? textScale,
    double width = 360.0,
  }) {
    return MaterialApp(
      theme: SciChatTheme.light,
      darkTheme: SciChatTheme.dark,
      themeMode: themeMode,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 700),
          textScaler: TextScaler.linear(textScale ?? 1.0),
        ),
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: SingleChildScrollView(child: AboutCard()),
          ),
        ),
      ),
    );
  }

  group('SettingsScreen About Card Responsiveness & Layout Tests', () {
    testWidgets(
        '10. Kartu Tentang menampilkan seluruh data dan nilai berada di dalam batas kartu pada SettingsScreen',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      // Pastikan label dan nilai lengkap terlihat
      expect(find.text('SciChat'), findsOneWidget);
      expect(find.text('v2.0.0'), findsOneWidget);
      expect(find.text('Sumber Data'), findsOneWidget);
      expect(
          find.text('arXiv, CrossRef, OpenAlex, Semantic Scholar, Archive.org'),
          findsOneWidget);
      expect(find.text('Model AI'), findsOneWidget);
      expect(find.text('Agnes AI (Smart Routing)'), findsOneWidget);
      expect(find.text('Deep Search'), findsOneWidget);
      expect(find.text('Tersedia (Full-text Analysis)'), findsOneWidget);
      expect(find.text('Cache TTL'), findsOneWidget);
      expect(find.text('6 Jam'), findsOneWidget);

      // Verifikasi batas geometris: teks Sumber Data tidak meluber ke kanan melebihi kartu
      final cardFinder = find.byType(AboutCard);
      final cardRect = tester.getRect(cardFinder);
      final sumberDataRect = tester.getRect(find
          .text('arXiv, CrossRef, OpenAlex, Semantic Scholar, Archive.org'));

      expect(sumberDataRect.right, lessThanOrEqualTo(cardRect.right));
      expect(sumberDataRect.left, greaterThanOrEqualTo(cardRect.left));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '11. Responsif pada layar sempit 320dp tanpa overflow horizontal dan teks berada di dalam batas kartu',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildAboutCardWidget(width: 320));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final cardFinder = find.byType(AboutCard);
      final cardRect = tester.getRect(cardFinder);
      final sumberDataRect = tester.getRect(find
          .text('arXiv, CrossRef, OpenAlex, Semantic Scholar, Archive.org'));

      expect(sumberDataRect.right, lessThanOrEqualTo(cardRect.right));
      expect(sumberDataRect.left, greaterThanOrEqualTo(cardRect.left));
      expect(find.text('Sumber Data'), findsOneWidget);
      expect(find.text('Cache TTL'), findsOneWidget);
    });

    testWidgets(
        '12. Responsif pada layar standar 360dp dan 400dp serta text scaling 1.2x',
        (tester) async {
      for (final width in [360.0, 400.0]) {
        for (final scale in [1.0, 1.2]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1.0;

          await tester
              .pumpWidget(buildAboutCardWidget(width: width, textScale: scale));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);

          final cardFinder = find.byType(AboutCard);
          final cardRect = tester.getRect(cardFinder);
          final sumberDataRect = tester.getRect(find.text(
              'arXiv, CrossRef, OpenAlex, Semantic Scholar, Archive.org'));

          expect(sumberDataRect.right, lessThanOrEqualTo(cardRect.right));
          expect(sumberDataRect.left, greaterThanOrEqualTo(cardRect.left));
        }
      }
      tester.view.resetPhysicalSize();
    });

    testWidgets('13. Kartu Tentang konsisten pada mode terang dan gelap',
        (tester) async {
      // Mode Terang
      await tester.pumpWidget(buildAboutCardWidget(themeMode: ThemeMode.light));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sumber Data'), findsOneWidget);
      expect(find.text('Agnes AI (Smart Routing)'), findsOneWidget);

      // Mode Gelap
      await tester.pumpWidget(buildAboutCardWidget(themeMode: ThemeMode.dark));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sumber Data'), findsOneWidget);
      expect(find.text('Agnes AI (Smart Routing)'), findsOneWidget);
    });
  });
}
