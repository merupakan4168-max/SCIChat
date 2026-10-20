import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
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
                child: const ChatScreen(),
              ),
            )
          : const ChatScreen(),
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

      // Pesan panjang > 30 karakter terpotong dengan '...'
      provider.createNewSession();
      await provider
          .sendMessage('Pengaruh Attention Mechanism pada Arsitektur Jaringan');
      expect(
        provider.activeSessionTitle,
        equals('Pengaruh Attention Mechanism p...'),
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
}
