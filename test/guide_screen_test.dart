import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/guide_screen.dart';
import 'package:scichat/screens/home_screen.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/search_service.dart';
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

class _MockSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> fetchTrending() async => [];

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async =>
      [];

}

Widget _buildGuideTestApp({
  required SciChatProvider provider,
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(true),
      home: const GuideScreen(),
    ),
  );
}

Widget _buildHomeTestApp({
  required SciChatProvider provider,
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(true),
      home: const HomeScreen(),
    ),
  );
}

Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
  double delta = 150,
}) async {
  final targetScrollable = scrollable ??
      (find.byType(GuideScreen).evaluate().isNotEmpty
          ? find.descendant(
              of: find.byType(GuideScreen),
              matching: find.byType(Scrollable),
            ).first
          : find.byType(Scrollable).first);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: targetScrollable,
    );
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockGeminiService mockGemini;
  late _MockStorageService mockStorage;
  late _MockSearchService mockSearch;
  late SciChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mockGemini = _MockGeminiService();
    mockStorage = _MockStorageService();
    mockSearch = _MockSearchService();
    provider = SciChatProvider(
      geminiService: mockGemini,
      storageService: mockStorage,
      searchService: mockSearch,
    );
    await provider.init();
    await provider.setApiKey('dummy-api-key');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('A. GuideScreen Widget & UI/UX Tests', () {
    testWidgets('1. Tentang SCIChat terbuka saat halaman pertama kali dimuat',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      // Seksi Tentang SCIChat terbuka secara default
      expect(find.text('Alur Kerja Utama:'), findsOneWidget);
      expect(find.textContaining('Mencari:', findRichText: true), findsOneWidget);
      expect(find.textContaining('Memahami:', findRichText: true), findsOneWidget);
      expect(find.textContaining('Menganalisis:', findRichText: true), findsOneWidget);
      expect(find.textContaining('Menyimpan:', findRichText: true), findsOneWidget);
      expect(find.textContaining('Menggunakan:', findRichText: true), findsOneWidget);
    });

    testWidgets(
        '2. Tiga seksi lainnya tertutup secara default dan dapat dibuka/tutup',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      // Konten Tutorial Penggunaan tertutup awalnya
      expect(find.text('Tanya Paper (Konteks Aktif)'), findsNothing);

      // Ketuk header Tutorial Penggunaan untuk membuka
      await _scrollTo(tester, find.text('Tutorial Penggunaan'));
      await tester.tap(find.text('Tutorial Penggunaan'));
      await tester.pumpAndSettle();
      expect(find.text('Tanya Paper (Konteks Aktif)'), findsOneWidget);

      // Ketuk kembali untuk menutup
      await tester.tap(find.text('Tutorial Penggunaan'));
      await tester.pumpAndSettle();
      expect(find.text('Tanya Paper (Konteks Aktif)'), findsNothing);

      // Seksi Prompt Library dapat dibuka
      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();
      expect(find.text('Perbandingan 2-3 Makalah'), findsOneWidget);

      // Seksi Privasi dan Batasan dapat dibuka
      await _scrollTo(tester, find.text('Privasi dan Batasan'));
      await tester.tap(find.text('Privasi dan Batasan'));
      await tester.pumpAndSettle();
      expect(find.text('Batas Ekstraksi PDF'), findsOneWidget);
    });

    testWidgets(
        '3. Kartu accordion memiliki layout konsisten dan tidak overflow pada 360x640 dp',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      // Buka seluruh seksi untuk memverifikasi scroll dan rendering penuh
      await _scrollTo(tester, find.text('Tutorial Penggunaan'));
      await tester.tap(find.text('Tutorial Penggunaan'));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Privasi dan Batasan'));
      await tester.tap(find.text('Privasi dan Batasan'));
      await tester.pumpAndSettle();

      // Scroll dari atas hingga dasar halaman
      final listFinder = find.byType(ListView);
      await tester.drag(listFinder, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(listFinder, const Offset(0, -400));
      await tester.pumpAndSettle();

      // Tidak ada overflow atau assertion error
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '4. Microcopy aktual sinkron dengan nama fitur dan label usang tidak muncul',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      // Periksa microcopy di Tentang SCIChat (masih di layar atas)
      expect(
          find.textContaining(
              'Simpan hasil analisis ke Catatan di tab Library / Pustaka.',
              findRichText: true),
          findsOneWidget);

      // Buka Tutorial Penggunaan dan verifikasi teksnya
      await _scrollTo(tester, find.text('Tutorial Penggunaan'));
      await tester.tap(find.text('Tutorial Penggunaan'));
      await tester.pumpAndSettle();

      expect(find.text('Tanya Paper (Konteks Aktif)'), findsOneWidget);
      expect(find.text('Rangkum Makalah'), findsOneWidget);

      // Buka Privasi dan Batasan dan verifikasi parameter penting
      await _scrollTo(tester, find.text('Privasi dan Batasan'));
      await tester.tap(find.text('Privasi dan Batasan'));
      await tester.pumpAndSettle();

      expect(find.text('Penyimpanan Kredensial (BYOK)'), findsOneWidget);
      expect(
          find.textContaining('~40.000 karakter', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('maksimal 3 makalah', findRichText: true),
          findsOneWidget);
      expect(
          find.textContaining('Abstrak', findRichText: true),
          findsOneWidget);

      // Pastikan label usang tidak lagi muncul
      expect(find.textContaining('Favorites (Bookmark)'), findsNothing);
      expect(find.textContaining('Tanya Makalah Referensi'), findsNothing);
      expect(find.textContaining('Research Notes'), findsNothing);
    });

    testWidgets(
        '5. Tombol Salin Teks menyalin prompt yang benar melalui mock clipboard',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      String? copiedClipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            copiedClipboardText =
                (methodCall.arguments as Map?)?['text'] as String?;
            return null;
          }
          return null;
        },
      );

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      // Buka Prompt Library
      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();

      // Ketuk tombol Salin Teks pada kartu pertama (Perbandingan 2-3 Makalah)
      final copyBtn = find.text('Salin Teks').first;
      await _scrollTo(tester, copyBtn);
      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verifikasi teks yang masuk ke clipboard
      const expectedPrompt =
          'Bandingkan makalah-makalah ini. Apa kesamaan temuan mereka, dan di mana metodologi atau kesimpulannya saling bertentangan?';
      expect(copiedClipboardText, equals(expectedPrompt));

      // SnackBar muncul
      expect(find.text('Prompt disalin ke clipboard'), findsOneWidget);

      // Tuntaskan timer copy (1500ms) agar tidak pending
      await tester.pump(const Duration(milliseconds: 1600));
    });

    testWidgets(
        '6. Label tombol berubah menjadi Tersalin selama 1,5 detik lalu kembali',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async => null,
      );

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();

      final copyBtn = find.text('Salin Teks').first;
      await _scrollTo(tester, copyBtn);
      await tester.tap(copyBtn);
      await tester.pump();

      // Teks tombol langsung berubah menjadi 'Tersalin'
      expect(find.text('Tersalin'), findsOneWidget);

      // Setelah 1.0 detik: masih 'Tersalin'
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.text('Tersalin'), findsOneWidget);

      // Setelah total 1.6 detik (melewati ambang 1.5 detik): kembali menjadi 'Salin Teks'
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Tersalin'), findsNothing);
      expect(find.text('Salin Teks'), findsWidgets);
    });

    testWidgets('7. Kegagalan clipboard tidak menampilkan status sukses',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            throw PlatformException(
              code: 'CLIPBOARD_ERROR',
              message: 'Failed to access clipboard',
            );
          }
          return null;
        },
      );

      await tester.pumpWidget(_buildGuideTestApp(provider: provider));
      await tester.pumpAndSettle();

      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();

      final copyBtn = find.text('Salin Teks').first;
      await _scrollTo(tester, copyBtn);
      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Status 'Tersalin' tidak boleh muncul jika clipboard error
      expect(find.text('Tersalin'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('B. Integrasi Tombol Gunakan ke Composer Chat', () {
    testWidgets(
        '1 & 2. Menekan Gunakan kembali ke HomeScreen tab 0 dan mengisi composer kosong',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildHomeTestApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Pastikan awal berada di tab Research (tab 0)
      expect(provider.currentTab, 0);

      // Buka GuideScreen melalui Navigator
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => const GuideScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GuideScreen), findsOneWidget);

      // Buka Prompt Library
      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();

      // Ketuk tombol Gunakan pada prompt pertama
      final useBtn = find.text('Gunakan').first;
      await _scrollTo(tester, useBtn);
      await tester.tap(useBtn);
      await tester.pumpAndSettle();

      // GuideScreen tertutup dan kembali ke HomeScreen
      expect(find.byType(GuideScreen), findsNothing);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(provider.currentTab, 0);

      // Teks prompt tersuntikkan secara tepat ke composer
      const expectedPrompt =
          'Bandingkan makalah-makalah ini. Apa kesamaan temuan mereka, dan di mana metodologi atau kesimpulannya saling bertentangan?';
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals(expectedPrompt));

      // Kursor berada di akhir teks
      expect(
        textField.controller?.selection.baseOffset,
        equals(expectedPrompt.length),
      );

      // Tidak ada pesan terkirim
      expect(provider.messages.length, 0);
      expect(provider.pendingComposerPrompt, isNull);

      // Tuntaskan animasi hero typing agar tidak ada timer pending
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        '3 & 4. Ketika composer memiliki draf, draf dipertahankan dan prompt digabungkan',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildHomeTestApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Ketik draf teks awal di composer
      const existingDraft = 'Catatan draf awal saya';
      await tester.enterText(find.byType(TextField), existingDraft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Buka GuideScreen
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute(builder: (_) => const GuideScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Buka Prompt Library
      await _scrollTo(tester, find.text('Prompt Library'));
      await tester.tap(find.text('Prompt Library'));
      await tester.pumpAndSettle();

      // Pilih prompt kedua (Ringkasan Makalah)
      await _scrollTo(tester, find.text('Ringkasan Makalah'));
      final secondUseBtn = find.widgetWithText(InkWell, 'Gunakan').at(1);
      await _scrollTo(tester, secondUseBtn);
      await tester.tap(secondUseBtn);
      await tester.pumpAndSettle();

      // GuideScreen tertutup
      expect(find.byType(GuideScreen), findsNothing);

      // Teks composer menggabungkan draf lama dan prompt baru dengan \n\n
      const secondPrompt =
          'Berikan ringkasan eksekutif dari makalah ini yang mencakup: masalah yang diangkat, metode yang digunakan, dan temuan utama.';
      const expectedCombined = '$existingDraft\n\n$secondPrompt';

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals(expectedCombined));

      // Kursor berada di ujung akhir teks
      expect(
        textField.controller?.selection.baseOffset,
        equals(expectedCombined.length),
      );

      // Tidak ada pesan otomatis yang terkirim
      expect(provider.messages.length, 0);

      // Tuntaskan animasi hero typing
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        '5 & 6. Prompt hanya dikonsumsi sekali dan tidak disuntik ulang saat rebuild',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildHomeTestApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Suntikkan prompt melalui provider
      provider.setComposerPrompt('Prompt uji coba');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals('Prompt uji coba'));

      // Pengguna mengedit teks di composer
      await tester.enterText(
          find.byType(TextField), 'Teks setelah diedit manual');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Picu notifikasi / rebuild pada provider
      provider.notifyListeners();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Teks tidak boleh ter-reset kembali ke 'Prompt uji coba'
      final textFieldAfter = tester.widget<TextField>(find.byType(TextField));
      expect(textFieldAfter.controller?.text,
          equals('Teks setelah diedit manual'));
      expect(provider.pendingComposerPrompt, isNull);

      // Tuntaskan animasi hero typing
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
        '7. Tidak ada exception lifecycle, listener leak, atau setState after dispose',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildHomeTestApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Buka dan tutup GuideScreen berulang kali
      for (int i = 0; i < 2; i++) {
        final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
        nav.push(MaterialPageRoute(builder: (_) => const GuideScreen()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        nav.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Unmount seluruh tree aplikasi
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Pastikan bebas exception
      expect(tester.takeException(), isNull);
    });
  });
}
