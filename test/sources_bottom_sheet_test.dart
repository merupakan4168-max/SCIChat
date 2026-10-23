import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:scichat/widgets/paper_card.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy-key');

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
    yield 'Respons pengujian sumber makalah.';
    lastStreamFinishReason = 'stop';
  }
}

class _MockStorageService extends StorageService {
  List<ChatSession> sessions = [];
  List<ArxivPaper> favorites = [];

  @override
  Future<String?> getApiKey() async => 'dummy-api-key';
  @override
  Future<List<ChatSession>> getChatSessions() async => sessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async {
    sessions = List.from(s);
  }
  @override
  Future<List<ArxivPaper>> getFavorites() async => favorites;
}

ArxivPaper _createSamplePaper(int i) => ArxivPaper(
      id: 'paper-sample-$i',
      title: 'Judul Riset Akademik Makalah $i yang Komprehensif',
      authors: ['Penulis $i'],
      summary: 'Ringkasan metodologi dan eksperimen paper $i.',
      published: '202${i % 4}-0${(i % 9) + 1}-01',
      updated: '2024-01-01',
      categories: const ['cs.AI'],
      pdfUrl: 'https://arxiv.org/pdf/paper-sample-$i',
      absUrl: 'https://arxiv.org/abs/paper-sample-$i',
    );

Widget _buildBubbleTestApp({
  required ChatMessage message,
  bool isDark = false,
  SciChatProvider? provider,
  bool Function(String)? isFavorite,
  Function(ArxivPaper)? onFavoriteToggle,
  Function(ArxivPaper)? onPaperTap,
  Function(ArxivPaper)? onSummarize,
  Function(ArxivPaper)? onChatPdf,
  void Function(CitationReference)? onCitationTap,
}) {
  final widgetChild = MaterialApp(
    theme: SciChatTheme.getTheme(isDark),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ChatBubble(
            message: message,
            isFavorite: isFavorite ?? ((_) => false),
            onFavoriteToggle: onFavoriteToggle ?? ((_) {}),
            onPaperTap: onPaperTap ?? ((_) {}),
            onSummarize: onSummarize,
            onChatPdf: onChatPdf,
            onCitationTap: onCitationTap,
          ),
        ),
      ),
    ),
  );

  if (provider != null) {
    return ChangeNotifierProvider<SciChatProvider>.value(
      value: provider,
      child: widgetChild,
    );
  }
  return widgetChild;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockStorageService storage;
  late _MockGeminiService gemini;
  late SciChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = _MockStorageService();
    gemini = _MockGeminiService();
    provider = SciChatProvider(
      storageService: storage,
      geminiService: gemini,
    );
    provider.messages.add(ChatMessage(
      id: 'seed-msg',
      role: MessageRole.user,
      content: 'Pertanyaan riset',
      status: MessageStatus.done,
      timestamp: DateTime.now(),
    ));
  });

  group('Tahap 4A — Bottom Sheet Sumber Makalah Tests', () {
    testWidgets('1. Tidak ada sumber: tidak ada pemicu modal', (tester) async {
      final msg = ChatMessage(
        id: 'msg-no-sources',
        role: MessageRole.assistant,
        content: 'Jawaban tanpa sumber rujukan.',
        timestamp: DateTime.now(),
        papers: const [],
      );

      await tester.pumpWidget(_buildBubbleTestApp(message: msg, provider: provider));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sumber makalah'), findsNothing);
      expect(find.byKey(const ValueKey('sources_sheet_trigger')), findsNothing);
    });

    testWidgets('2. Streaming: indikator sumber tetap ringkas dan non-interaktif', (tester) async {
      final msg = ChatMessage(
        id: 'msg-streaming',
        role: MessageRole.assistant,
        content: 'Teks sedang mengalir...',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
        papers: [_createSamplePaper(1), _createSamplePaper(2)],
      );

      await tester.pumpWidget(_buildBubbleTestApp(message: msg, provider: provider));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Menyiapkan 2 sumber makalah…'), findsOneWidget);
      expect(find.byKey(const ValueKey('sources_sheet_trigger')), findsNothing);
      expect(find.byType(PaperCard), findsNothing);

      // Selesaikan status streaming sebelum tes berakhir agar timer throttle dan indikator berhenti bersih
      final doneMsg = msg.copyWith(status: MessageStatus.done);
      await tester.pumpWidget(_buildBubbleTestApp(message: doneMsg, provider: provider));
      await tester.pumpAndSettle();
    });

    testWidgets('3. Modal terbuka dengan drag handle, judul Sumber Makalah (N), dan tombol Tutup',
        (tester) async {
      final paper = _createSamplePaper(1);
      final msg = ChatMessage(
        id: 'msg-single-source',
        role: MessageRole.assistant,
        content: 'Analisis berbasis 1 dokumen.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [paper],
      );

      await tester.pumpWidget(_buildBubbleTestApp(message: msg, provider: provider));
      await tester.pumpAndSettle();

      // Tombol pemicu terlihat di dalam chat bubble
      final trigger = find.byKey(const ValueKey('sources_sheet_trigger'));
      expect(trigger, findsOneWidget);
      expect(find.text('Sumber makalah (1)'), findsOneWidget);
      expect(find.text('Lihat'), findsOneWidget);
      expect(find.byType(PaperCard), findsNothing);

      // Buka modal sheet
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      // Verifikasi komponen modal
      expect(find.text('Sumber Makalah (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('close_sources_sheet')), findsOneWidget);
      expect(find.byType(PaperCard), findsOneWidget);
      expect(find.text(paper.title), findsOneWidget);

      // Tutup modal via tombol Tutup
      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();

      // Modal tertutup
      expect(find.byKey(const ValueKey('close_sources_sheet')), findsNothing);
      expect(find.byType(PaperCard), findsNothing);
    });

    testWidgets('4. Sepuluh sumber dapat digulir dari sumber pertama hingga terakhir',
        (tester) async {
      final tenPapers = List.generate(10, (i) => _createSamplePaper(i + 1));
      final msg = ChatMessage(
        id: 'msg-ten-sources',
        role: MessageRole.assistant,
        content: 'Tinjauan literatur 10 makalah.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: tenPapers,
      );

      await tester.pumpWidget(_buildBubbleTestApp(message: msg, provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Sumber Makalah (10)'), findsOneWidget);
      // Makalah pertama terlihat di awal
      expect(find.text(tenPapers.first.title), findsOneWidget);

      // Gulir di dalam sheet ListView hingga paper terakhir terlihat
      final sheetScrollableFinder = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      expect(sheetScrollableFinder, findsOneWidget);

      await tester.scrollUntilVisible(
        find.text(tenPapers.last.title),
        400,
        scrollable: sheetScrollableFinder,
      );
      await tester.pumpAndSettle();

      // Makalah terakhir terlihat setelah scrolling mandiri
      expect(find.text(tenPapers.last.title), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();
    });

    testWidgets('5 & 6. Menggulir modal tidak menggeser posisi chat & menutup modal mempertahankan posisi scroll chat',
        (tester) async {
      provider.messages.clear();
      // Siapkan chat dengan beberapa pesan agar scrollable dan pesan bersumber terlihat di viewport
      for (int i = 0; i < 8; i++) {
        provider.messages.add(ChatMessage(
          id: 'filler-msg-$i',
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          content: 'Pesan pengisi daftar obrolan nomor $i dengan konten panjang secukupnya.\nBaris tambahan untuk memastikan tinggi list melebihi batas layar.',
          status: MessageStatus.done,
          timestamp: DateTime.now(),
          papers: i == 7 ? [_createSamplePaper(1), _createSamplePaper(2), _createSamplePaper(3)] : const [],
        ));
      }

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(false),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Cari Scrollable utama chat
      final chatScrollableFinder = find.byType(Scrollable).first;
      final chatScrollableState = tester.state<ScrollableState>(chatScrollableFinder);

      // Gulir chat ke atas sedikit agar posisinya stabil di tengah
      await tester.drag(chatScrollableFinder, const Offset(0, 80));
      await tester.pumpAndSettle();

      final chatOffsetBeforeModal = chatScrollableState.position.pixels;

      // Buka modal sheet dari pesan bersumber
      final trigger = find.byKey(const ValueKey('sources_sheet_trigger')).first;
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text('Sumber Makalah (3)'), findsOneWidget);

      // Gulir di dalam modal sheet
      final sheetScrollableFinder = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      );
      expect(sheetScrollableFinder, findsOneWidget);

      await tester.drag(sheetScrollableFinder, const Offset(0, -150));
      await tester.pumpAndSettle();

      // Pastikan posisi chat di belakang modal TIDAK BERUBAH
      expect(chatScrollableState.position.pixels, equals(chatOffsetBeforeModal));

      // Tutup modal
      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();

      // Posisi chat tetap di offset yang sama (zero scroll jump)
      expect(chatScrollableState.position.pixels, equals(chatOffsetBeforeModal));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('7. Tanya Paper menutup modal dan mengaktifkan paper yang tepat',
        (tester) async {
      final targetPaper = _createSamplePaper(42);
      final msg = ChatMessage(
        id: 'msg-ask-paper',
        role: MessageRole.assistant,
        content: 'Riset unggulan.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [targetPaper],
      );

      await tester.pumpWidget(_buildBubbleTestApp(
        message: msg,
        provider: provider,
        onChatPdf: (p) => provider.setActivePaper(p),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('close_sources_sheet')), findsOneWidget);

      // Tap tombol Tanya Paper di dalam modal
      final tanyaButton = find.text('Tanya Paper');
      expect(tanyaButton, findsOneWidget);
      await tester.tap(tanyaButton);
      await tester.pumpAndSettle();

      // Modal harus tertutup
      expect(find.byKey(const ValueKey('close_sources_sheet')), findsNothing);

      // Paper aktif di provider terpasang
      expect(provider.activeContexts.length, 1);
      expect(provider.activeContexts.first.id, targetPaper.id);
    });

    testWidgets('8. Rangkum menutup modal sumber tanpa tumpukan modal yang salah',
        (tester) async {
      final targetPaper = _createSamplePaper(77);
      bool summarizeCalled = false;
      ArxivPaper? summarizedPaper;

      final msg = ChatMessage(
        id: 'msg-summarize-test',
        role: MessageRole.assistant,
        content: 'Riset untuk dirangkum.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [targetPaper],
      );

      await tester.pumpWidget(_buildBubbleTestApp(
        message: msg,
        provider: provider,
        onSummarize: (p) {
          summarizeCalled = true;
          summarizedPaper = p;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();

      final rangkumButton = find.text('Rangkum');
      expect(rangkumButton, findsOneWidget);
      await tester.tap(rangkumButton);
      await tester.pumpAndSettle();

      // Modal sumber tertutup
      expect(find.byKey(const ValueKey('close_sources_sheet')), findsNothing);

      // Callback Rangkum dipanggil dengan paper yang tepat
      expect(summarizeCalled, isTrue);
      expect(summarizedPaper?.id, targetPaper.id);
    });

    testWidgets('9. Chip halaman rujukan membuka paper dan halaman yang tepat',
        (tester) async {
      CitationReference? tappedCitation;
      final targetPaper = _createSamplePaper(88);

      final msg = ChatMessage(
        id: 'msg-cite-test',
        role: MessageRole.assistant,
        content: 'Temuan pada halaman 3 dan 7.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [targetPaper],
        validatedCitationPages: {
          targetPaper.id: [3, 7],
        },
      );

      await tester.pumpWidget(_buildBubbleTestApp(
        message: msg,
        provider: provider,
        onCitationTap: (c) => tappedCitation = c,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();

      expect(find.text('Halaman rujukan:'), findsOneWidget);
      expect(find.text('Hal. 3'), findsOneWidget);
      expect(find.text('Hal. 7'), findsOneWidget);

      // Tap chip Hal. 7
      await tester.tap(find.text('Hal. 7'));
      await tester.pumpAndSettle();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.documentId, targetPaper.id);
      expect(tappedCitation!.pageNumber, 7);

      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();
    });

    testWidgets('10. Bookmark/favorit berubah secara reaktif di dalam modal',
        (tester) async {
      final targetPaper = _createSamplePaper(99);
      final msg = ChatMessage(
        id: 'msg-fav-test',
        role: MessageRole.assistant,
        content: 'Makalah penting untuk disimpan.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [targetPaper],
      );

      await tester.pumpWidget(_buildBubbleTestApp(
        message: msg,
        provider: provider,
        isFavorite: (id) => provider.isFavorite(id),
        onFavoriteToggle: (p) => provider.toggleFavorite(p),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();

      expect(provider.isFavorite(targetPaper.id), isFalse);
      expect(find.byIcon(Icons.bookmark_outline), findsOneWidget);

      // Tap ikon bookmark
      await tester.tap(find.byIcon(Icons.bookmark_outline));
      await tester.pumpAndSettle();

      // Di provider status menjadi true
      expect(provider.isFavorite(targetPaper.id), isTrue);

      // Ikon di modal langsung ter-update reaktif menjadi bookmark terisi
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();
    });

    testWidgets('11. Layar sempit 320 dp tidak mengalami overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final msg = ChatMessage(
        id: 'msg-narrow-test',
        role: MessageRole.assistant,
        content: 'Uji layar sempit.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [_createSamplePaper(1), _createSamplePaper(2)],
      );

      await tester.pumpWidget(_buildBubbleTestApp(message: msg, provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Sumber Makalah (2)'), findsOneWidget);
      expect(find.byKey(const ValueKey('close_sources_sheet')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();
    });

    testWidgets('12. Tema terang dan gelap tetap konsisten', (tester) async {
      final msg = ChatMessage(
        id: 'msg-theme-test',
        role: MessageRole.assistant,
        content: 'Uji tema visual modal sumber.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: [_createSamplePaper(1)],
      );

      // Tema Terang
      await tester.pumpWidget(_buildBubbleTestApp(message: msg, isDark: false, provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sumber Makalah (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();

      // Tema Gelap
      await tester.pumpWidget(_buildBubbleTestApp(message: msg, isDark: true, provider: provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sources_sheet_trigger')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Sumber Makalah (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();
    });
  });
}
