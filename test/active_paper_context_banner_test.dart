import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/screens/pdf_viewer_screen.dart';
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
    yield 'Jawaban asisten teruji.';
    lastStreamFinishReason = 'stop';
  }
}

class _MockStorageService extends StorageService {
  List<ChatSession> sessions = [];
  List<ArxivPaper> favorites = [];

  @override
  Future<String?> getApiKey() async => 'test-api-key';
  @override
  Future<List<ChatSession>> getChatSessions() async => sessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async {
    sessions = List.from(s);
  }
  @override
  Future<List<ArxivPaper>> getFavorites() async => favorites;
}

ArxivPaper _createPaper({
  String id = 'paper-101',
  String title = 'Deep Residual Learning for Image Recognition',
}) =>
    ArxivPaper(
      id: id,
      title: title,
      authors: const ['Kaiming He', 'Xiangyu Zhang'],
      summary: 'Deeper neural networks are more difficult to train.',
      published: '2015-12-10',
      updated: '2015-12-10',
      categories: const ['cs.CV'],
      pdfUrl: '',
      absUrl: 'https://arxiv.org/abs/1512.03385',
    );

Widget _buildApp(SciChatProvider provider,
    {bool isDark = false, double textScale = 1.0, Size? mediaQuerySize}) {
  return ChangeNotifierProvider<SciChatProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: SciChatTheme.getTheme(isDark),
      builder: (context, child) {
        MediaQueryData mq = MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale));
        if (mediaQuerySize != null) {
          mq = mq.copyWith(size: mediaQuerySize);
        }
        return MediaQuery(
          data: mq,
          child: child!,
        );
      },
      home: const ChatScreen(),
    ),
  );
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
      id: 'seed-initial',
      role: MessageRole.user,
      content: 'Halo SCIChat',
      status: MessageStatus.done,
      timestamp: DateTime.now(),
    ));
  });

  group('Tahap 3 — Active Paper Context Banner Ringkas & Terintegrasi', () {
    testWidgets('1. Banner konteks ringkas tampil saat 1 paper aktif dengan 4 elemen visual',
        (tester) async {
      final paper = _createPaper();
      provider.setActivePaper(paper);
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.fullText,
      );

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      // Banner aktif ada di UI dengan ValueKey('active_paper_banner')
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);

      // Label besar "Active Paper Context" sudah dihilangkan
      expect(find.text('Active Paper Context'), findsNothing);

      // Urutan visual 4 elemen:
      // 1. Indikator dokumen dan ketersediaan full text
      expect(find.text('Full text tersedia'), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsWidgets);

      // 2. Judul paper
      expect(find.text(paper.title), findsOneWidget);

      // 3. Tombol buka paper/PDF
      expect(find.byTooltip('Buka pembaca PDF'), findsOneWidget);
      expect(find.byIcon(Icons.chrome_reader_mode_outlined), findsOneWidget);

      // 4. Tombol silang untuk menghapus konteks
      expect(find.byTooltip('Hapus konteks makalah'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('2. Judul paper sangat panjang tidak menyebabkan overflow pada layar sempit 320dp',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final veryLongTitlePaper = _createPaper(
        title:
            'A Tremendously Comprehensive, Multi-Disciplinary, Cross-Domain Analysis of Generative Artificial Intelligence, Neural Scaling Laws, and Neuromorphic Quantum Hardware Frameworks in High-Dimensional Continuous Latent Spaces',
      );

      provider.setActivePaper(veryLongTitlePaper);
      provider.contextEvidence[veryLongTitlePaper.id] = const PaperEvidence(
        level: EvidenceLevel.fullText,
      );

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      // Pastikan tidak ada exception atau overflow
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);

      // Tombol aksi tetap ada di layar dan tidak terdorong keluar
      expect(find.byTooltip('Buka pembaca PDF'), findsOneWidget);
      expect(find.byTooltip('Hapus konteks makalah'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('3. Tombol buka paper membuka PdfViewerScreen dengan paper yang benar',
        (tester) async {
      final paper = _createPaper(id: 'paper-target-pdf', title: 'Target Research Paper');
      provider.setActivePaper(paper);

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      // Tap tombol buka pembaca PDF
      await tester.tap(find.byTooltip('Buka pembaca PDF'));
      await tester.pumpAndSettle();

      // Membuka PdfViewerScreen dengan paper yang sesuai
      expect(find.byType(PdfViewerScreen), findsOneWidget);
      expect(find.text('Target Research Paper'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('4. Tombol silang menghapus konteks tanpa menghapus riwayat chat atau file',
        (tester) async {
      // Tambahkan riwayat chat awal
      provider.messages.add(ChatMessage(
        id: 'msg-prev-1',
        role: MessageRole.user,
        content: 'Pertanyaan sebelumnya tentang AI',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));
      provider.messages.add(ChatMessage(
        id: 'msg-prev-2',
        role: MessageRole.assistant,
        content: 'Jawaban sebelumnya tentang AI',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      final paper = _createPaper(id: 'paper-to-remove');
      provider.setActivePaper(paper);

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);

      // Tap tombol silang hapus konteks
      await tester.tap(find.byTooltip('Hapus konteks makalah'));
      await tester.pumpAndSettle();

      // Banner konteks hilang dari composer
      expect(find.byKey(const ValueKey('active_paper_banner')), findsNothing);
      expect(provider.activeContexts, isEmpty);

      // Riwayat pesan chat tetap utuh
      expect(find.text('Pertanyaan sebelumnya tentang AI'), findsOneWidget);
      expect(find.text('Jawaban sebelumnya tentang AI'), findsOneWidget);
      expect(provider.messages.length, 3); // 1 seed + 2 messages

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('5. Status evidence beralih akurat (loading -> fullText -> abstractOnly -> noUsableText)',
        (tester) async {
      final paper = _createPaper(id: 'paper-evidence-lifecycle');
      provider.setActivePaper(paper);

      // 5a. Level: loading
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.loading,
      );
      await tester.pumpWidget(_buildApp(provider));
      await tester.pump();
      expect(find.text('Memeriksa...'), findsOneWidget);

      // 5b. Level: fullText
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.fullText,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Full text tersedia'), findsOneWidget);

      // 5c. Level: abstractOnly
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.abstractOnly,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Abstract saja'), findsOneWidget);

      // 5d. Level: noUsableText
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.noUsableText,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Teks tidak tersedia'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('6. Composer bertambah tinggi multibaris dan input teks tetap bekerja',
        (tester) async {
      final paper = _createPaper();
      provider.setActivePaper(paper);

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      // Ketik pesan multibaris
      await tester.enterText(
        textField,
        'Baris satu pertanyaan riset\nBaris dua analisis metodologi\nBaris tiga evaluasi hasil eksperimen\nBaris empat kesimpulan',
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);

      // Tombol send aktif dan dapat dikirim
      final sendButton = find.byTooltip('Kirim pesan');
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Pesan terkirim dan masuk riwayat provider
      expect(
        provider.messages.any((m) => m.content.contains('Baris satu pertanyaan riset')),
        isTrue,
      );

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('7. Konsistensi tema terang dan tema gelap',
        (tester) async {
      final paper = _createPaper();
      provider.setActivePaper(paper);
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.fullText,
      );

      // Tema Terang
      await tester.pumpWidget(_buildApp(provider, isDark: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);
      expect(find.text('Full text tersedia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));

      // Tema Gelap
      await tester.pumpWidget(_buildApp(provider, isDark: true));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);
      expect(find.text('Full text tersedia'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('8. Tanpa paper aktif, composer tampil normal tanpa banner konteks atau divider',
        (tester) async {
      provider.activeContexts.clear();

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('active_paper_banner')), findsNothing);
      expect(find.byKey(const ValueKey('active_context_bar')), findsNothing);
      expect(find.text('Tanya soal paper, metode, atau hasil riset…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('9. Alur pengguna: buka PDF, kembali ke chat, lalu hapus konteks',
        (tester) async {
      final paper = _createPaper(id: 'paper-nav-flow');
      provider.setActivePaper(paper);

      await tester.pumpWidget(_buildApp(provider));
      await tester.pumpAndSettle();

      // Buka PDF
      await tester.tap(find.byTooltip('Buka pembaca PDF'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewerScreen), findsOneWidget);

      // Kembali ke chat
      final backButton = find.byTooltip('Kembali');
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton);
      } else {
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        navigator.pop();
      }
      await tester.pumpAndSettle();

      // Sekarang di chat screen lagi, banner tetap ada
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);

      // Hapus konteks
      await tester.tap(find.byTooltip('Hapus konteks makalah'));
      await tester.pumpAndSettle();

      // Banner hilang
      expect(find.byKey(const ValueKey('active_paper_banner')), findsNothing);
      expect(provider.activeContexts, isEmpty);

      await tester.pump(const Duration(seconds: 6));
    });
  });
}
