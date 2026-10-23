import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/home_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy');

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
    yield 'Respons mock asisten.';
    lastStreamFinishReason = 'stop';
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
    return 'Respons mock asisten.';
  }
}

class _MockStorageService extends StorageService {
  String? _key = 'dummy-api-key';
  List<ChatSession> storedSessions = [];

  @override
  Future<String?> getApiKey() async => _key;
  @override
  Future<void> saveApiKey(String key) async {
    _key = key;
  }

  @override
  Future<List<ChatSession>> getChatSessions() async => storedSessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async {
    storedSessions = List.from(s);
  }
}

Widget _buildTestWidget({
  required SciChatProvider provider,
  Size? surfaceSize,
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(true),
      home: MediaQuery(
        data: MediaQueryData(
          size: surfaceSize ?? const Size(400, 800),
          textScaler: TextScaler.linear(textScale),
          viewInsets: viewInsets,
        ),
        child: SizedBox(
          width: surfaceSize?.width ?? 400,
          height: surfaceSize?.height ?? 800,
          child: const HomeScreen(),
        ),
      ),
    ),
  );
}

Finder findInDrawer(Finder matching) =>
    find.descendant(of: find.byType(Drawer), matching: matching);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockGeminiService mockGemini;
  late _MockStorageService mockStorage;
  late SciChatProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockGemini = _MockGeminiService();
    mockStorage = _MockStorageService();
    provider = SciChatProvider(
      geminiService: mockGemini,
      storageService: mockStorage,
    );
  });

  ChatSession createSession(String id, String title, DateTime updatedAt) {
    return ChatSession(
      id: id,
      title: title,
      updatedAt: updatedAt,
      messages: [
        ChatMessage(
          id: 'm-$id',
          role: MessageRole.user,
          content: 'Pertanyaan tentang $title',
          timestamp: updatedAt,
        ),
      ],
    );
  }

  group('Fase 4A - Local Search History Tests', () {
    testWidgets('1. Searching for a matching title displays only matches in Drawer', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Analisis Algoritma Graph', now),
        createSession('s2', 'Studi Machine Learning', now),
        createSession('s3', 'Penerapan Quantum Computing', now),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      // Buka Drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Pastikan semua 3 judul awalnya tampil di Drawer
      expect(findInDrawer(find.text('Analisis Algoritma Graph')), findsOneWidget);
      expect(findInDrawer(find.text('Studi Machine Learning')), findsOneWidget);
      expect(findInDrawer(find.text('Penerapan Quantum Computing')), findsOneWidget);

      // Cari "Machine" di search field Drawer
      final searchField = findInDrawer(find.byType(TextField));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Machine');
      await tester.pumpAndSettle();

      // Hanya "Studi Machine Learning" yang tampil di Drawer
      expect(findInDrawer(find.text('Studi Machine Learning')), findsOneWidget);
      expect(findInDrawer(find.text('Analisis Algoritma Graph')), findsNothing);
      expect(findInDrawer(find.text('Penerapan Quantum Computing')), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('2. Case-insensitive search matches title regardless of casing', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Studi Machine Learning', now),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      final searchField = findInDrawer(find.byType(TextField));

      // Coba uppercase
      await tester.enterText(searchField, 'MACHINE');
      await tester.pumpAndSettle();
      expect(findInDrawer(find.text('Studi Machine Learning')), findsOneWidget);

      // Coba lowercase
      await tester.enterText(searchField, 'learning');
      await tester.pumpAndSettle();
      expect(findInDrawer(find.text('Studi Machine Learning')), findsOneWidget);

      // Coba mixed case
      await tester.enterText(searchField, 'mAcHiNe');
      await tester.pumpAndSettle();
      expect(findInDrawer(find.text('Studi Machine Learning')), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('3. Whitespace trimming in the search query works correctly', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Studi Machine Learning', now),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      final searchField = findInDrawer(find.byType(TextField));

      // Query dengan spasi di awal dan akhir
      await tester.enterText(searchField, '   Machine   ');
      await tester.pumpAndSettle();
      expect(findInDrawer(find.text('Studi Machine Learning')), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('4. Clearing search query restores all eligible sessions', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Sesi Pertama Alpha', now),
        createSession('s2', 'Sesi Kedua Beta', now),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      final searchField = findInDrawer(find.byType(TextField));
      await tester.enterText(searchField, 'Beta');
      await tester.pumpAndSettle();

      expect(findInDrawer(find.text('Sesi Kedua Beta')), findsOneWidget);
      expect(findInDrawer(find.text('Sesi Pertama Alpha')), findsNothing);

      // Tombol hapus pencarian muncul di Drawer
      final clearBtn = findInDrawer(find.byTooltip('Hapus pencarian'));
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // Seluruh sesi kembali muncul di Drawer
      expect(findInDrawer(find.text('Sesi Pertama Alpha')), findsOneWidget);
      expect(findInDrawer(find.text('Sesi Kedua Beta')), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('5. Display friendly empty state when no query matches', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Sesi Pertama Alpha', now),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      final searchField = findInDrawer(find.byType(TextField));
      await tester.enterText(searchField, 'KeywordYangTidakPernahAda123');
      await tester.pumpAndSettle();

      // Empty state friendly muncul di Drawer
      expect(findInDrawer(find.text('Riwayat tidak ditemukan')), findsOneWidget);
      expect(
        findInDrawer(find.text('Coba gunakan kata kunci lain untuk mencari riwayat riset Anda.')),
        findsOneWidget,
      );
      expect(findInDrawer(find.byIcon(Icons.search_off_rounded)), findsOneWidget);
      expect(findInDrawer(find.text('Sesi Pertama Alpha')), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('6. Empty time-group headers are omitted after filtering', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Riset Hari Ini Alpha', now),
        createSession('s2', 'Riset Kemarin Beta', now.subtract(const Duration(days: 1))),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Awalnya ada header Hari Ini dan Kemarin di Drawer
      expect(findInDrawer(find.text('Hari Ini')), findsOneWidget);
      expect(findInDrawer(find.text('Kemarin')), findsOneWidget);

      // Filter ke "Beta" (hanya ada di Kemarin)
      final searchField = findInDrawer(find.byType(TextField));
      await tester.enterText(searchField, 'Beta');
      await tester.pumpAndSettle();

      // Header "Hari Ini" tidak ditampilkan karena tidak ada sesi yang cocok di kelompok itu
      expect(findInDrawer(find.text('Hari Ini')), findsNothing);
      expect(findInDrawer(find.text('Kemarin')), findsOneWidget);
      expect(findInDrawer(find.text('Riset Kemarin Beta')), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('7. Rename and Delete menu still targets the correct session after filtering', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Riset Algoritma Pertama', now),
        createSession('s2', 'Riset Biologi Khusus', now),
      ];

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Filter ke "Biologi"
      final searchField = findInDrawer(find.byType(TextField));
      await tester.enterText(searchField, 'Biologi');
      await tester.pumpAndSettle();

      // Buka menu opsi sesi pada sesi yang terfilter
      final menuBtn = find.byTooltip('Opsi sesi');
      expect(menuBtn, findsOneWidget);
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Pilih Hapus
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      // Dialog konfirmasi harus menyebutkan judul yang benar ("Riset Biologi Khusus")
      expect(find.text('Hapus Sesi Riset?'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Riset Biologi Khusus')),
        findsOneWidget,
      );

      // Batal
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Sekarang coba Ganti Nama pada sesi yang sama
      await tester.tap(find.byTooltip('Opsi sesi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ganti Nama'));
      await tester.pumpAndSettle();

      expect(find.text('Ganti Nama Sesi'), findsOneWidget);
      final renameInput = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      expect(renameInput, findsOneWidget);
      await tester.enterText(renameInput, 'Riset Biologi Terkini');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();

      // Pastikan s2 benar-benar terganti di provider
      expect(provider.sessions.firstWhere((s) => s.id == 's2').title, equals('Riset Biologi Terkini'));
      // Dan s1 tetap tidak berubah
      expect(provider.sessions.firstWhere((s) => s.id == 's1').title, equals('Riset Algoritma Pertama'));

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('8. Tapping overflow menu does not activate the session row', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Sesi Aktif Awal', now),
        createSession('s2', 'Sesi Lain Target', now),
      ];

      await provider.init();
      // s1 adalah sesi aktif
      expect(provider.activeSessionId, equals('s1'));

      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Cari "Target"
      final searchField = findInDrawer(find.byType(TextField));
      await tester.enterText(searchField, 'Target');
      await tester.pumpAndSettle();

      // Ketuk menu titik tiga
      final menuBtn = find.byTooltip('Opsi sesi');
      await tester.tap(menuBtn);
      await tester.pumpAndSettle();

      // Sesi aktif di provider TIDAK beralih ke s2 hanya karena menekan tombol menu titik tiga
      expect(provider.activeSessionId, equals('s1'));

      // Tutup menu opsi
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(provider.activeSessionId, equals('s1'));

      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('Fase 4B - Sticky Footer & Layout Stability Tests', () {
    testWidgets('9. Footer remains outside scrollable history and visible during long scrolling', (tester) async {
      final now = DateTime.now();
      // Buat 30 sesi agar list riwayat panjang dan dapat di-scroll
      final sessions = List.generate(
        30,
        (i) => createSession('sess_$i', 'Sesi Riwayat Nomor $i', now.subtract(Duration(hours: i))),
      );
      mockStorage.storedSessions = sessions;

      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Footer "Obrolan Baru" dan "Panduan Riset" terlihat
      final newChatBtn = findInDrawer(find.widgetWithText(ElevatedButton, 'Obrolan Baru'));
      final guideBtn = findInDrawer(find.text('Panduan Riset'));
      expect(newChatBtn, findsOneWidget);
      expect(guideBtn, findsOneWidget);

      final initialFooterRect = tester.getRect(newChatBtn);

      // Scroll ListView ke bawah sejauh 600 pixel
      final listViewFinder = findInDrawer(find.byType(ListView));
      expect(listViewFinder, findsOneWidget);
      await tester.drag(listViewFinder, const Offset(0, -600));
      await tester.pumpAndSettle();

      // Footer tetap berada di koordinat yang sama persis (tidak ikut ter-scroll)
      final afterScrollFooterRect = tester.getRect(newChatBtn);
      expect(afterScrollFooterRect, equals(initialFooterRect));
      expect(findInDrawer(find.text('Panduan Riset')), findsOneWidget);

      // Mengetuk Obrolan Baru tetap berfungsi normal
      await tester.tap(newChatBtn);
      await tester.pumpAndSettle();

      // Drawer tertutup dan sesi baru kosong aktif
      expect(find.byType(Drawer), findsNothing);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('10. Layout stability on narrow widths (320dp and 360dp)', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Judul Sesi Riset yang Cukup Panjang untuk Menguji Kerapatan Layout', now),
      ];

      for (final width in [320.0, 360.0]) {
        tester.view.physicalSize = Size(width * 2.0, 700 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await provider.init();
        await tester.pumpWidget(
          _buildTestWidget(provider: provider, surfaceSize: Size(width, 700)),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();

        expect(find.byType(Drawer), findsOneWidget);
        expect(findInDrawer(find.byType(TextField)), findsOneWidget);
        expect(findInDrawer(find.widgetWithText(ElevatedButton, 'Obrolan Baru')), findsOneWidget);
        expect(findInDrawer(find.text('Panduan Riset')), findsOneWidget);

        // Tidak ada error overflow yang tertangkap
        expect(tester.takeException(), isNull);

        // Tutup drawer untuk iterasi berikutnya
        await tester.tapAt(Offset(width - 10, 300));
        await tester.pumpAndSettle();
      }

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('11. Increased text scaling (1.5x) and simulated keyboard visibility free of RenderFlex overflow', (tester) async {
      final now = DateTime.now();
      mockStorage.storedSessions = [
        createSession('s1', 'Sesi Pertama Skala Teks', now),
        createSession('s2', 'Sesi Kedua Skala Teks', now.subtract(const Duration(days: 1))),
      ];

      tester.view.physicalSize = const Size(360 * 2.0, 680 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await provider.init();
      // Render dengan teks 1.5x dan simulasi insets keyboard sebesar 220dp
      await tester.pumpWidget(
        _buildTestWidget(
          provider: provider,
          surfaceSize: const Size(360, 680),
          textScale: 1.5,
          viewInsets: const EdgeInsets.only(bottom: 220),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer terbuka bebas error
      expect(find.byType(Drawer), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Coba ketik di kotak pencarian saat skala teks besar & keyboard terbuka
      final searchField = findInDrawer(find.byType(TextField));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Pertama');
      await tester.pumpAndSettle();

      expect(findInDrawer(find.text('Sesi Pertama Skala Teks')), findsOneWidget);
      expect(findInDrawer(find.text('Sesi Kedua Skala Teks')), findsNothing);

      // Hapus pencarian
      await tester.tap(findInDrawer(find.byTooltip('Hapus pencarian')));
      await tester.pumpAndSettle();

      expect(findInDrawer(find.text('Sesi Pertama Skala Teks')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 6));
    });
  });
}
