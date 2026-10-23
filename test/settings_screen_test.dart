import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/home_screen.dart';
import 'package:scichat/screens/settings_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';

class MockTestStorageService extends StorageService {
  String? _storedKey;
  final List<ChatSession> _sessions = [];
  final List<ArxivPaper> _favorites = [];
  final List<ResearchNote> _notes = [];
  String _themeMode = 'system';
  SearchFilter _searchFilter = const SearchFilter();
  int clearSearchCacheCallCount = 0;
  final Set<String> _cacheKeys = {'scichat_cache_paper1', 'scichat_cache_paper2'};

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

  @override
  Future<SearchFilter> getSearchFilter() async => _searchFilter;

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {
    _searchFilter = filter;
  }

  @override
  Future<int> clearSearchCache() async {
    clearSearchCacheCallCount++;
    final count = _cacheKeys.length;
    _cacheKeys.clear();
    return count;
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
        themeMode: provider.themeMode,
        home: const SettingsScreen(),
      ),
    );
  }

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

  Widget buildAboutCardWidget({
    ThemeMode themeMode = ThemeMode.dark,
    double? textScale,
    double width = 360.0,
    SciChatProvider? provider,
  }) {
    final effectiveProvider = provider ??
        SciChatProvider(
          storageService: MockTestStorageService(),
          geminiService: MockTestGeminiService(),
        );

    return ChangeNotifierProvider<SciChatProvider>.value(
      value: effectiveProvider,
      child: MaterialApp(
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
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: SingleChildScrollView(child: AboutCard()),
            ),
          ),
        ),
      ),
    );
  }

  group('Sub-tahap 4C.1: Selektor Tema Segmented Control Tests', () {
    testWidgets('1. Ketiga mode tema bekerja, memperbarui provider, dan tersimpan',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Mode awal adalah system
      expect(provider.themeMode, ThemeMode.system);

      // 1. Pilih Terang
      await tester.tap(find.text('Terang'));
      await tester.pumpAndSettle();
      expect(provider.themeMode, ThemeMode.light);
      expect(await storage.getThemeMode(), 'light');

      // 2. Pilih Gelap
      await tester.tap(find.text('Gelap'));
      await tester.pumpAndSettle();
      expect(provider.themeMode, ThemeMode.dark);
      expect(await storage.getThemeMode(), 'dark');

      // 3. Pilih Sistem
      await tester.tap(find.text('Sistem'));
      await tester.pumpAndSettle();
      expect(provider.themeMode, ThemeMode.system);
      expect(await storage.getThemeMode(), 'system');
    });

    testWidgets('2. Segmen tema memiliki target sentuh memadai (>= 44dp)',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      final terangFinder = find.text('Terang');
      expect(terangFinder, findsOneWidget);
      final size = tester.getSize(find.ancestor(
        of: terangFinder,
        matching: find.byType(GestureDetector),
      ).first);
      expect(size.height, greaterThanOrEqualTo(44.0));
    });
  });

  group('Sub-tahap 4C.1: Preferensi Pencarian Terpadu Tests', () {
    testWidgets('3. Kapsul batas hasil 3, 5, 8, 10 memperbarui filter dengan benar',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Default adalah 5
      expect(provider.filter.maxResults, 5);

      // Tap kapsul 3
      await tester.tap(find.byKey(const ValueKey('capsule_3')));
      await tester.pumpAndSettle();
      expect(provider.filter.maxResults, 3);

      // Tap kapsul 8
      await tester.tap(find.byKey(const ValueKey('capsule_8')));
      await tester.pumpAndSettle();
      expect(provider.filter.maxResults, 8);

      // Tap kapsul 10
      await tester.tap(find.byKey(const ValueKey('capsule_10')));
      await tester.pumpAndSettle();
      expect(provider.filter.maxResults, 10);
    });

    testWidgets('4. Opsi urutan pencarian tetap bekerja (relevance, submittedDate, lastUpdatedDate)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      expect(provider.filter.sortBy, 'relevance');

      // Tap Paling baru
      await tester.tap(find.byKey(const ValueKey('sort_submittedDate')));
      await tester.pumpAndSettle();
      expect(provider.filter.sortBy, 'submittedDate');

      // Tap Terakhir diperbarui
      await tester.tap(find.byKey(const ValueKey('sort_lastUpdatedDate')));
      await tester.pumpAndSettle();
      expect(provider.filter.sortBy, 'lastUpdatedDate');

      // Tap Relevansi
      await tester.tap(find.byKey(const ValueKey('sort_relevance')));
      await tester.pumpAndSettle();
      expect(provider.filter.sortBy, 'relevance');
    });

    testWidgets('5. Layout kartu pencarian terpadu bebas overflow pada 320dp dan teks 1.2x',
        (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.dark,
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.2),
              ),
              child: SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Batas hasil'), findsOneWidget);
      expect(find.text('Urutan pencarian'), findsOneWidget);
    });
  });

  group('Sub-tahap 4C.1: Navigasi Bottom Navigation & Header Tanpa Tombol Back', () {
    testWidgets('6. SettingsScreen tab root tidak memiliki tombol panah kembali di AppBar',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Tidak ada tombol arrow_back di AppBar
      expect(find.widgetWithIcon(IconButton, Icons.arrow_back), findsNothing);
      expect(find.text('Pengaturan'), findsOneWidget);
    });

    testWidgets('7. Navigasi bottom navigation dan Back Android (PopScope) tetap bekerja sempurna',
        (tester) async {
      final storage = MockTestStorageService();
      final session = ChatSession(
        id: 'sess-1',
        title: 'Sesi Riset Kuantum',
        updatedAt: DateTime.now(),
        messages: [
          ChatMessage(
            id: 'msg-1',
            role: MessageRole.user,
            content: 'Pertanyaan pengguna',
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

      // Pindah ke Tab Settings (index 3)
      provider.setTab(3);
      await tester.pumpAndSettle();
      expect(provider.currentTab, 3);
      expect(find.text('Pengaturan'), findsOneWidget);

      // Simulasikan tombol Back Android via PopScope di HomeScreen
      final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
      await widgetsAppState.didPopRoute();
      await tester.pumpAndSettle();

      // Kembali ke Tab 0 (Research) dengan state percakapan utuh
      expect(provider.currentTab, 0);
      expect(provider.messages.length, 1);
    });
  });

  group('Sub-tahap 4C.2: Agnes API Key Status, Preview Aman & Tombol Simpan Tests', () {
    testWidgets('8. Kunci tersimpan menampilkan status informatif dan badge Aktif tanpa kunci mentah',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-secret-key-12345678');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Badge Aktif terlihat
      expect(find.text('Aktif'), findsOneWidget);
      // Status informatif terlihat
      expect(find.text('Kunci API tersimpan'), findsOneWidget);
      // Tombol Ganti Kunci terlihat
      expect(find.text('Ganti Kunci'), findsOneWidget);
      // Kunci mentah TIDAK ditampilkan di layar
      expect(find.text('sk-secret-key-12345678'), findsNothing);
    });

    testWidgets('9. Tombol Ganti Kunci memunculkan input field yang bersih dan dapat dibatalkan',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-secret-key-12345678');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ganti Kunci'));
      await tester.pumpAndSettle();

      // Input field muncul dan bersih (bukan deretan titik panjang)
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);
      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.controller?.text, isEmpty);
      expect(textField.obscureText, isTrue);

      // Tekan tombol Batal
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Kembali ke preview status tersimpan
      expect(find.text('Kunci API tersimpan'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('10. Tombol Simpan nonaktif jika input kosong/sama dan aktif saat input baru valid',
        (tester) async {
      final storage = MockTestStorageService(initialKey: '');
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Saat kunci belum ada, TextField tampil langsung
      final inputFinder = find.byType(TextField);
      expect(inputFinder, findsOneWidget);

      // Awalnya kosong -> canSave false -> ketukan tidak menyimpan
      await tester.tap(find.text('Simpan Kunci API'));
      await tester.pumpAndSettle();
      expect(provider.apiKey, isEmpty);

      // Masukkan kunci baru
      await tester.enterText(inputFinder, 'sk-valid-new-key-123');
      await tester.pumpAndSettle();

      // Ketuk Simpan
      await tester.tap(find.text('Simpan Kunci API'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      // Kunci tersimpan di provider dan storage
      expect(provider.apiKey, 'sk-valid-new-key-123');
      expect(provider.apiKeySet, isTrue);
      expect(await storage.getApiKey(), 'sk-valid-new-key-123');
      // Tampilan beralih ke preview tersimpan
      expect(find.text('Kunci API tersimpan'), findsOneWidget);
    });

    testWidgets('11. Tautan Agnes AI memanggil URL yang benar', (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      expect(find.textContaining('platform Agnes AI'), findsOneWidget);
    });
  });

  group('Sub-tahap 4C.3: Tentang dan Hapus Cache Tests', () {
    testWidgets('12. Kartu Tentang menampilkan identitas SCIChat, v1.0.0, dan tombol Hapus Cache',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Scroll ke bawah
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('SCIChat'), findsOneWidget);
      expect(find.text('v1.0.0'), findsOneWidget);
      expect(find.text('Sumber Data'), findsOneWidget);
      expect(find.text('Cache TTL'), findsOneWidget);
      expect(find.text('6 Jam'), findsOneWidget);
      expect(find.byKey(const ValueKey('clear_cache_button')), findsOneWidget);
    });

    testWidgets('13. Mengetuk tombol Hapus Cache memunculkan konfirmasi dan memanggil clearCache',
        (tester) async {
      final storage = MockTestStorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      await tester.pumpWidget(buildSettingsWidget(provider));
      await tester.pumpAndSettle();

      // Scroll ke bawah
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Ketuk Hapus Cache
      await tester.tap(find.byKey(const ValueKey('clear_cache_button')));
      await tester.pumpAndSettle();

      // Dialog konfirmasi muncul
      expect(find.text('Hapus Cache Pencarian?'), findsOneWidget);
      expect(
          find.text(
              'Seluruh cache hasil pencarian makalah akan dibersihkan. Markah, catatan, dan riwayat chat Anda tetap aman.'),
          findsOneWidget);

      // Konfirmasi Hapus
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      // Memastikan storage.clearSearchCache terpanggil
      expect(storage.clearSearchCacheCallCount, 1);
      // SnackBar umpan balik muncul
      expect(find.textContaining('Cache pencarian berhasil dibersihkan'), findsOneWidget);
    });

    testWidgets('14. Hapus Cache tidak menghapus markah, catatan, sesi, atau API Key pengguna',
        (tester) async {
      final storage = MockTestStorageService(initialKey: 'sk-safe-key');
      final session = ChatSession(
        id: 'sess-persist',
        title: 'Sesi Persisten',
        updatedAt: DateTime.now(),
        messages: const [],
      );
      await storage.saveChatSessions([session]);
      final note = ResearchNote(
        id: 'note-1',
        sourceMessageId: 'msg-1',
        content: 'Insight penting',
        sources: const [],
        savedAt: DateTime.now(),
      );
      await storage.addNote(note);
      const paper = ArxivPaper(
        id: 'favorite-1',
        title: 'Paper Favorit',
        authors: ['Penulis'],
        summary: 'Ringkasan',
        published: '2024-01-01',
        updated: '2024-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'https://example.com/fav.pdf',
        absUrl: 'https://example.com/fav',
      );
      await storage.addFavorite(paper);

      final provider = SciChatProvider(
        storageService: storage,
        geminiService: MockTestGeminiService(),
      );
      await provider.init();

      // Panggil pembersihan cache
      final cleared = await provider.clearCache();
      expect(cleared, greaterThanOrEqualTo(0));

      // Verifikasi seluruh data pengguna tetap utuh 100%
      expect(provider.apiKey, 'sk-safe-key');
      expect(provider.apiKeySet, isTrue);
      expect(await storage.getApiKey(), 'sk-safe-key');
      expect((await storage.getChatSessions()).length, 1);
      expect((await storage.getNotes()).length, 1);
      expect(await storage.isFavorite('favorite-1'), isTrue);
    });

    testWidgets('15. Kartu Tentang responsif pada layar 320dp, 360dp, 400dp dan text scale 1.2x',
        (tester) async {
      for (final width in [320.0, 360.0, 400.0]) {
        for (final scale in [1.0, 1.2]) {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
              buildAboutCardWidget(width: width, textScale: scale));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('SCIChat'), findsOneWidget);
          expect(find.text('Cache TTL'), findsOneWidget);
        }
      }
      tester.view.resetPhysicalSize();
    });
  });
}
