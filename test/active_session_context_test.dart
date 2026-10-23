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
}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(true),
      home: surfaceSize != null
          ? MediaQuery(
              data: MediaQueryData(size: surfaceSize),
              child: SizedBox(
                width: surfaceSize.width,
                height: surfaceSize.height,
                child: const HomeScreen(),
              ),
            )
          : const HomeScreen(),
    ),
  );
}

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

  group('Tahap 5A.2 - SciChatProvider Active Session Context Invariants', () {
    test('1. activeSession & activeSessionTitle saat awal atau ID tidak valid',
        () async {
      // Saat belum ada sesi
      expect(provider.activeSession, isNull);
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));

      await provider.init();
      // createNewSession membuat sesi dengan title 'New Chat'
      expect(provider.activeSession, isNotNull);
      expect(provider.activeSession!.title, equals('New Chat'));
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));

      // Invariant: ID tidak valid TIDAK boleh secara diam-diam menampilkan sesi lain
      final dummyInvalidSession = ChatSession(
        id: 'real-session-1',
        title: 'Sesi Nyata',
        updatedAt: DateTime.now(),
        messages: [],
      );
      mockStorage.storedSessions = [dummyInvalidSession];
      await provider.init();

      expect(provider.activeSession?.title, equals('Sesi Nyata'));
      expect(provider.activeSessionTitle, equals('Sesi Nyata'));
    });

    test('2. Judul sesi aktif bereaksi saat createNewSession()', () async {
      await provider.init();
      provider.createNewSession();

      expect(provider.activeSession, isNotNull);
      expect(provider.activeSession!.title, equals('New Chat'));
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));
    });

    test('3. Judul sesi aktif terbarui saat pesan pertama dikirim', () async {
      await provider.init();
      // Pesan <= 30 karakter dipertahankan utuh
      await provider.sendMessage('Cara kerja transformer');
      expect(provider.activeSessionTitle, equals('Cara kerja transformer'));

      // Pesan panjang > 30 karakter tersimpan utuh tanpa pemotongan agresif
      provider.createNewSession();
      const longMessage =
          'Pengaruh Attention Mechanism pada Arsitektur Jaringan Neural untuk Analisis Data Astronomi';
      await provider.sendMessage(longMessage);
      expect(
        provider.activeSessionTitle,
        equals(longMessage),
      );
    });

    test('4. Judul sesi aktif berpindah dengan tepat saat loadSession()',
        () async {
      await provider.init();
      await provider.sendMessage('Pertanyaan Sesi 1');
      final session1Id = provider.activeSessionId;

      provider.createNewSession();
      await provider.sendMessage('Pertanyaan Sesi 2');
      final session2Id = provider.activeSessionId;

      expect(provider.activeSessionTitle, equals('Pertanyaan Sesi 2'));

      // Pindah kembali ke Sesi 1
      provider.loadSession(session1Id);
      expect(provider.activeSessionId, equals(session1Id));
      expect(provider.activeSessionTitle, equals('Pertanyaan Sesi 1'));

      // Pindah ke Sesi 2
      provider.loadSession(session2Id);
      expect(provider.activeSessionId, equals(session2Id));
      expect(provider.activeSessionTitle, equals('Pertanyaan Sesi 2'));
    });

    test('5. Judul sesi aktif mencerminkan awalan Cabang saat branching',
        () async {
      await provider.init();
      await provider.sendMessage('Diskusi Teori Gravitasi');
      final assistantMsg = provider.messages.firstWhere((m) => m.isAssistant);

      final branched =
          await provider.branchSessionFromMessage(assistantMsg.id);
      expect(branched, isTrue);

      expect(provider.activeSessionTitle, startsWith('Cabang: '));
      expect(
        provider.activeSessionTitle,
        equals('Cabang: Diskusi Teori Gravitasi'),
      );
    });

    test('6. Menghapus sesi aktif mengalihkan activeSessionTitle dengan aman',
        () async {
      await provider.init();
      await provider.sendMessage('Sesi A');
      final sessionAId = provider.activeSessionId;

      provider.createNewSession();
      await provider.sendMessage('Sesi B');
      final sessionBId = provider.activeSessionId;

      // Hapus sesi aktif (Sesi B)
      provider.deleteSession(sessionBId);

      // Otomatis beralih ke sesi yang tersisa (Sesi A)
      expect(provider.activeSessionId, equals(sessionAId));
      expect(provider.activeSessionTitle, equals('Sesi A'));

      // Hapus Sesi A sehingga seluruh sesi habis
      provider.deleteSession(sessionAId);
      // createNewSession dijalankan otomatis saat sesi habis
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));
    });
  });

  group('Tahap 5A.2 - ChatScreen AppBar & Drawer Widget Integration', () {
    testWidgets('1. AppBar menampilkan Eyebrow SCIChat dan Judul Sesi Aktif',
        (tester) async {
      await provider.init();

      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pump(const Duration(seconds: 6));

      // Cek Eyebrow brand
      expect(find.text('SCIChat'), findsOneWidget);
      // Cek judul sesi awal
      expect(find.text('Obrolan Baru'), findsOneWidget);
    });

    testWidgets('2. AppBar terbarui saat pesan dikirim', (tester) async {
      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pump(const Duration(seconds: 6));

      await provider.sendMessage('Riset Kuantum Komputasi');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Riset Kuantum Komputasi'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('3. Mengetuk judul AppBar membuka Drawer riwayat riset',
        (tester) async {
      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pump(const Duration(seconds: 6));

      // Drawer belum terbuka
      expect(find.text('Riwayat Riset'), findsNothing);

      // Ketuk judul AppBar (InkWell di dalam AppBar title)
      final titleInkWell = find.byTooltip('Buka riwayat riset').first;
      await tester.tap(titleInkWell);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Drawer sekarang terbuka
      expect(find.text('Riwayat Riset'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('4. Mengetuk ikon hamburger membuka Drawer riwayat riset',
        (tester) async {
      await provider.init();
      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pump(const Duration(seconds: 6));

      // Ketuk tombol hamburger
      final hamburgerButton = find.byIcon(Icons.menu);
      expect(hamburgerButton, findsOneWidget);
      await tester.tap(hamburgerButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Drawer terbuka
      expect(find.text('Riwayat Riset'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets(
        '5. Tombol Obrolan Baru dan Ekspor Chat di AppBar berfungsi saat pesan terisi',
        (tester) async {
      await provider.init();
      await provider.sendMessage('Topik Pertama');

      await tester.pumpWidget(_buildTestWidget(provider: provider));
      await tester.pumpAndSettle();

      // Tombol actions muncul karena pesan tidak kosong
      expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.download_outlined), findsOneWidget);

      // Ketuk tombol Obrolan Baru di AppBar
      await tester.tap(find.byIcon(Icons.add_comment_outlined));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 6));

      // Sesi baru dibuat, judul beralih ke Obrolan Baru
      expect(find.text('Obrolan Baru'), findsOneWidget);
      expect(provider.messages, isEmpty);
    });

    testWidgets('6. Bebas overflow pada lebar layar 320dp, 360dp, dan 400dp',
        (tester) async {
      final widths = [320.0, 360.0, 400.0];

      for (final w in widths) {
        tester.view.physicalSize = Size(w * 3.0, 800 * 3.0);
        tester.view.devicePixelRatio = 3.0;

        try {
          await provider.init();
          await provider.sendMessage(
              'Analisis Komparatif Model Bahasa Berukuran Besar pada Pemrosesan Teks Ilmiah');

          await tester.pumpWidget(
            _buildTestWidget(
              provider: provider,
              surfaceSize: Size(w, 800),
            ),
          );
          await tester.pumpAndSettle();

          // Pastikan tidak ada exception RenderFlex overflow
          expect(tester.takeException(), isNull);
          // Pastikan leading, eyebrow, dan actions tetap ter-render
          expect(find.byIcon(Icons.menu), findsOneWidget);
          expect(find.text('SCIChat'), findsOneWidget);
          expect(find.byIcon(Icons.add_comment_outlined), findsOneWidget);
          expect(find.byIcon(Icons.download_outlined), findsOneWidget);
        } finally {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      }
    });
  });

  group('Fase 1 - HomeScreen Root Scaffold Drawer Layering & Integration Tests', () {
    testWidgets('1. Drawer menutupi BottomNavigationBar secara penuh saat dibuka',
        (tester) async {
      tester.view.physicalSize = const Size(400 * 2.0, 800 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await provider.init();
      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // BottomNavigationBar terlihat
      final bnbFinder = find.byType(BottomNavigationBar);
      expect(bnbFinder, findsOneWidget);
      final bnbRect = tester.getRect(bnbFinder);

      // Buka drawer melalui tombol menu di AppBar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer sekarang terbuka
      final drawerFinder = find.byType(Drawer);
      expect(drawerFinder, findsOneWidget);
      final drawerRect = tester.getRect(drawerFinder);

      // Verifikasi Drawer membentang dari puncak layar hingga dasar layar (menutupi BottomNavigationBar)
      expect(drawerRect.top, equals(0.0));
      expect(drawerRect.bottom, equals(800.0));
      expect(drawerRect.bottom, greaterThanOrEqualTo(bnbRect.bottom));
      expect(drawerRect.left, equals(0.0));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('2. Memilih sesi dari Drawer memuat sesi dan menutup Drawer',
        (tester) async {
      final now = DateTime.now();
      final s1 = ChatSession(
        id: 'session-alpha',
        title: 'Riset Alpha',
        updatedAt: now,
        messages: [
          ChatMessage(
            id: 'm1',
            role: MessageRole.user,
            content: 'Halo Alpha',
            timestamp: now,
          ),
        ],
      );
      final s2 = ChatSession(
        id: 'session-beta',
        title: 'Riset Beta',
        updatedAt: now,
        messages: [
          ChatMessage(
            id: 'm2',
            role: MessageRole.user,
            content: 'Halo Beta',
            timestamp: now,
          ),
        ],
      );
      mockStorage.storedSessions = [s1, s2];

      await provider.init();
      expect(provider.activeSessionId, equals('session-alpha'));

      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Buka drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Cari dan ketuk sesi Beta
      final betaTile = find.text('Riset Beta');
      expect(betaTile, findsOneWidget);
      await tester.tap(betaTile);
      await tester.pumpAndSettle();

      // Drawer tertutup dan sesi aktif beralih ke Beta
      expect(find.byType(Drawer), findsNothing);
      expect(provider.activeSessionId, equals('session-beta'));
      expect(find.text('Riset Beta'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('3. Mengetuk area backdrop scrim di luar Drawer menutup Drawer',
        (tester) async {
      await provider.init();
      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Ketuk area luar (scrim) di sebelah kanan drawer (misal x=380, y=400)
      await tester.tapAt(const Offset(380, 400));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('4. Mengetuk Obrolan Baru di Drawer footer menutup Drawer dan membuat sesi baru',
        (tester) async {
      await provider.init();
      await provider.sendMessage('Pesan di sesi lama');
      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Buka drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Ketuk tombol Obrolan Baru di footer drawer
      final newChatBtn = find.widgetWithText(ElevatedButton, 'Obrolan Baru');
      expect(newChatBtn, findsOneWidget);
      await tester.tap(newChatBtn);
      await tester.pumpAndSettle();

      // Drawer tertutup dan sesi baru kosong dibuat
      expect(find.byType(Drawer), findsNothing);
      expect(provider.messages, isEmpty);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('5. Edge drag gesture aktif di tab Research (Tab 0) dan nonaktif di tab lain',
        (tester) async {
      await provider.init();
      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Saat di Tab 0 (Research), gesture drag dari tepi kiri membuka Drawer
      await tester.dragFrom(const Offset(5, 300), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Tutup drawer
      await tester.tapAt(const Offset(380, 400));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);

      // Berpindah ke Tab 1 (Explore)
      provider.setTab(1);
      await tester.pumpAndSettle();

      // Gesture drag dari tepi kiri TIDAK membuka Drawer
      await tester.dragFrom(const Offset(5, 300), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      await tester.pump(const Duration(seconds: 6));
    });
  });

  group('Fase 2 - Keamanan dan Kualitas Riwayat', () {
    test(
        '1. Judul sesi > 30 karakter tersimpan utuh dan pesan berikutnya tidak menimpa judul',
        () async {
      await provider.init();
      const firstPrompt =
          'Bagaimana arsitektur Transformer memanfaatkan Self-Attention dalam pemrosesan teks?';
      await provider.sendMessage(firstPrompt);

      expect(provider.activeSessionTitle, equals(firstPrompt));
      expect(provider.activeSession!.title, equals(firstPrompt));

      // Kirim pesan kedua pada sesi yang sama
      await provider
          .sendMessage('Tolong berikan contoh rumus Query, Key, dan Value.');
      // Judul sesi tidak tertimpa oleh pesan berikutnya
      expect(provider.activeSessionTitle, equals(firstPrompt));
      expect(provider.activeSession!.title, equals(firstPrompt));

      // Pesan melebihi 100 karakter dibatasi 100 karakter bersih tanpa akhiran '...' di storage
      provider.createNewSession();
      final over100Prompt = 'A' * 120;
      await provider.sendMessage(over100Prompt);
      expect(provider.activeSession!.title.length, equals(100));
      expect(provider.activeSession!.title.endsWith('...'), isFalse);
    });

    test('2. Load session dan branch session menghasilkan judul yang konsisten',
        () async {
      await provider.init();
      await provider.sendMessage('Sesi Induk Pertama');
      final assistantMsg = provider.messages.firstWhere((m) => m.isAssistant);

      // Branching dari sesi induk
      final branched = await provider.branchSessionFromMessage(assistantMsg.id);
      expect(branched, isTrue);
      expect(provider.activeSessionTitle, equals('Cabang: Sesi Induk Pertama'));

      // Kirim pesan di sesi cabang, judul cabang tidak tertimpa
      await provider.sendMessage('Eksplorasi cabang baru');
      expect(provider.activeSessionTitle, equals('Cabang: Sesi Induk Pertama'));
    });

    test(
        '3. createNewSession() berulang saat sesi aktif masih kosong tidak menambah entri duplikat',
        () async {
      await provider.init();
      expect(provider.sessions.length, equals(1));
      final initialSessionId = provider.activeSessionId;

      // Panggil createNewSession() beberapa kali berturut-turut saat masih kosong
      provider.createNewSession();
      provider.createNewSession();
      provider.createNewSession();

      // Jumlah sesi tidak bertambah dan ID sesi aktif tetap konsisten
      expect(provider.sessions.length, equals(1));
      expect(provider.activeSessionId, equals(initialSessionId));
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));

      // Sesi aktif tetap valid dan dapat menerima pesan
      await provider.sendMessage('Pesan pertama setelah penekanan berulang');
      expect(provider.sessions.length, equals(1));
      expect(provider.activeSessionTitle,
          equals('Pesan pertama setelah penekanan berulang'));

      // Sekarang setelah sesi memiliki pesan, memanggil createNewSession() akan membuat sesi baru
      provider.createNewSession();
      expect(provider.sessions.length, equals(2));
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));

      // Memanggil lagi saat sesi baru ini masih kosong tidak menambah entri
      provider.createNewSession();
      expect(provider.sessions.length, equals(2));
    });

    test(
        '4. Berpindah ke sesi lama lalu membuat obrolan baru bekerja dengan benar',
        () async {
      await provider.init();
      await provider.sendMessage('Konten Sesi 1');
      final session1Id = provider.activeSessionId;

      provider.createNewSession();
      await provider.sendMessage('Konten Sesi 2');
      final session2Id = provider.activeSessionId;

      expect(provider.sessions.length, equals(2));

      // Kembali ke Sesi 1
      provider.loadSession(session1Id);
      expect(provider.activeSessionId, equals(session1Id));
      expect(provider.activeSessionTitle, equals('Konten Sesi 1'));

      // Buat obrolan baru dari Sesi 1 yang terisi
      provider.createNewSession();
      expect(provider.sessions.length, equals(3));
      expect(provider.activeSessionTitle, equals('Obrolan Baru'));
      expect(provider.messages, isEmpty);

      // Sesi 1 dan Sesi 2 tetap utuh
      final s1 = provider.sessions.firstWhere((s) => s.id == session1Id);
      final s2 = provider.sessions.firstWhere((s) => s.id == session2Id);
      expect(s1.messages, isNotEmpty);
      expect(s2.messages, isNotEmpty);
    });

    testWidgets(
        '5. Konfirmasi dialog hapus sesi: Batal mempertahankan data, Hapus mengeksekusi penghapusan',
        (tester) async {
      await provider.init();
      await provider.sendMessage('Sesi Diskusi 1');
      provider.createNewSession();
      await provider.sendMessage('Sesi Diskusi 2');

      expect(provider.sessions.length, equals(2));

      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(400, 800)),
      );
      await tester.pumpAndSettle();

      // Buka drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Cari tombol opsi sesi (menu titik tiga)
      final menuButtons = find.byTooltip('Opsi sesi');
      expect(menuButtons, findsNWidgets(2));

      // Ketuk menu opsi pada item pertama
      await tester.tap(menuButtons.first);
      await tester.pumpAndSettle();

      // Menu overflow menampilkan opsi Ganti Nama dan Hapus
      expect(find.text('Ganti Nama'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      // Pilih opsi Hapus
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      // Dialog konfirmasi muncul
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Hapus Sesi Riset?'), findsOneWidget);
      expect(find.text('Batal'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      // Ketuk Batal
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();

      // Dialog tertutup, tidak ada sesi yang terhapus
      expect(find.byType(AlertDialog), findsNothing);
      expect(provider.sessions.length, equals(2));

      // Buka menu opsi lagi
      await tester.tap(find.byTooltip('Opsi sesi').first);
      await tester.pumpAndSettle();

      // Pilih opsi Hapus
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Ketuk Hapus
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      // Dialog tertutup, sesi terhapus
      expect(find.byType(AlertDialog), findsNothing);
      expect(provider.sessions.length, equals(1));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets(
        '6. Judul panjang di Drawer menampilkan hingga 2 baris bebas overflow di 320dp dan 360dp',
        (tester) async {
      await provider.init();
      const longTitle =
          'Analisis Perbandingan Algoritma Deep Learning Transformer dan Mamba untuk Pemrosesan Dokumen Ilmiah Panjang';
      await provider.sendMessage(longTitle);

      final expectedTitle = provider.activeSessionTitle;
      expect(expectedTitle.length, lessThanOrEqualTo(100));
      expect(expectedTitle.length, greaterThan(30));

      // Uji pada lebar layar sempit 320dp
      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(320, 640)),
      );
      await tester.pumpAndSettle();

      // Buka drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);

      // Verifikasi widget Text judul sesi memiliki maxLines: 2 dan ellipsis
      final titleFinder = find.descendant(
        of: find.byType(Drawer),
        matching:
            find.byWidgetPredicate((w) => w is Text && w.data == expectedTitle),
      );
      expect(titleFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(titleFinder);
      expect(textWidget.maxLines, equals(2));
      expect(textWidget.overflow, equals(TextOverflow.ellipsis));

      // Tutup drawer
      await tester.tapAt(const Offset(310, 300));
      await tester.pumpAndSettle();

      // Uji pada lebar layar 360dp
      await tester.pumpWidget(
        _buildTestWidget(provider: provider, surfaceSize: const Size(360, 740)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsOneWidget);
      expect(titleFinder, findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });
  });
}
