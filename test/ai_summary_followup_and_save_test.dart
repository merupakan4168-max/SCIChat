import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/summary_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGeminiService extends GeminiService {
  _FakeGeminiService() : super(apiKey: 'test-key');

  Completer<String>? completer;
  String? nextSummary;
  bool shouldThrow = false;

  @override
  Future<String> summarizePaper(ArxivPaper paper, {String? pdfText}) async {
    if (shouldThrow) {
      throw Exception('Network connection error');
    }
    if (completer != null) {
      return completer!.future;
    }
    return nextSummary ??
        '### Apa yang dilakukan\nKontribusi utama adalah A.\n\n<follow_up>["Pertanyaan 1?", "Pertanyaan 2?"]</follow_up>';
  }
}

class _MockPdfService extends PdfService {
  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async =>
      'Mock PDF text';
}

ArxivPaper _createSamplePaper({
  String id = '2401.12345',
  String title = 'Transformer Optimization with Quantum Attention',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    summary: 'Penelitian mengenai optimasi transformer kuantum.',
    authors: const ['Alice Researcher', 'Bob Scientist'],
    published: '2025-01-20',
    updated: '2025-01-20',
    pdfUrl: 'https://arxiv.org/pdf/$id',
    absUrl: 'https://arxiv.org/abs/$id',
    categories: const ['cs.AI', 'quant-ph'],
    sources: const ['arXiv'],
  );
}

Widget _wrapWithTheme({
  required Widget child,
  Brightness brightness = Brightness.dark,
}) {
  return MaterialApp(
    theme:
        brightness == Brightness.dark ? SciChatTheme.dark : SciChatTheme.light,
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Masalah A: Follow-up markup removal & math preservation', () {
    test('GeminiService.summarizePaper strips valid <follow_up> tag from API response',
        () async {
      const rawApiContent = '''
**Apa yang dilakukan** — Mengembangkan arsitektur baru.
**Metodologi** — Menggunakan attention sparser.
**Temuan utama** — Akurasi meningkat 15%.

<follow_up>["Bagaimana efisiensi memorinya?", "Apakah sudah diuji pada dataset ImageNet?"]</follow_up>''';

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': rawApiContent,
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final gemini = GeminiService(apiKey: 'test-key', client: mockClient);
      final paper = _createSamplePaper();
      final summary = await gemini.summarizePaper(paper);

      expect(summary, isNot(contains('<follow_up>')));
      expect(summary, isNot(contains('</follow_up>')));
      expect(summary, isNot(contains('Bagaimana efisiensi memorinya?')));
      expect(summary, contains('**Apa yang dilakukan**'));
      expect(summary, contains('Akurasi meningkat 15%.'));
    });

    test('GeminiService.summarizePaper safely handles malformed or truncated follow-up tag',
        () async {
      const malformedApiContent = '''
**Apa yang dilakukan** — Mengembangkan arsitektur baru.
<follow_up>["Saran terpotong tanpa penutup''';

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': malformedApiContent,
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final gemini = GeminiService(apiKey: 'test-key', client: mockClient);
      final paper = _createSamplePaper();
      final summary = await gemini.summarizePaper(paper);

      expect(summary, isNot(contains('<follow_up>')));
      expect(summary, contains('**Apa yang dilakukan**'));
    });

    test('GeminiService.summarizePaper preserves math notation and comparison operators',
        () async {
      const mathContent = '''
**Metodologi** — Kami menguji kondisi \$x < y\$ dan \$p < 0.05\$ dengan fungsi limit \$\\lim_{x \\to 0} < f(x)\$.
**Temuan utama** — Nilai error < 0.01 tercapai.

<follow_up>["Bagaimana stabilitas konvergensi?"]</follow_up>''';

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': mathContent,
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final gemini = GeminiService(apiKey: 'test-key', client: mockClient);
      final paper = _createSamplePaper();
      final summary = await gemini.summarizePaper(paper);

      expect(summary, isNot(contains('<follow_up>')));
      expect(summary, contains(r'$x < y$'));
      expect(summary, contains(r'$p < 0.05$'));
      expect(summary, contains('error < 0.01'));
    });

    test('SciChatProvider.savePaperSummary cleans raw follow_up markup defensively before storage',
        () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final provider = SciChatProvider(
        storageService: storage,
        geminiService: _FakeGeminiService(),
        searchService: SearchService(),
        pdfService: _MockPdfService(),
      );
      await provider.init();
      await provider.setApiKey('test-key');

      final paper = _createSamplePaper(id: 'paper_defensive');
      const dirtySummary = '''
Rangkuman inti penelitian.
<follow_up>["Pertanyaan bocor 1?", "Pertanyaan bocor 2?"]</follow_up>''';

      final saved = await provider.savePaperSummary(
        paper: paper,
        summary: dirtySummary,
      );

      expect(saved, isTrue);
      expect(provider.notes.length, 1);
      final savedContent = provider.notes.first.content;
      expect(savedContent, isNot(contains('<follow_up>')));
      expect(savedContent, isNot(contains('Pertanyaan bocor')));
      expect(savedContent, equals('Rangkuman inti penelitian.'));
    });
  });

  group('Masalah B: Save button in AI Summary Sheet from Research (ChatScreen)', () {
    late StorageService storage;
    late _FakeGeminiService gemini;
    late SciChatProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      gemini = _FakeGeminiService();

      provider = SciChatProvider(
        storageService: storage,
        geminiService: gemini,
        searchService: SearchService(),
        pdfService: _MockPdfService(),
      );
    });

    testWidgets(
        'ChatScreen: Membuka AI Summary sheet dari kartu paper, memverifikasi tombol simpan disabled saat loading lalu aktif dan dapat menyimpan catatan bersih',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final completer = Completer<String>();
      gemini.completer = completer;

      final paper = _createSamplePaper(
        id: 'paper_chat_flow_1',
        title: 'Quantum Advantage in Scientific Reasoning',
      );

      final assistantMsg = ChatMessage(
        id: 'asst_msg_1',
        role: MessageRole.assistant,
        content: 'Berikut adalah makalah yang relevan dengan pertanyaan Anda:',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        papers: [paper],
      );

      final session = ChatSession(
        id: 'session_chat_1',
        title: 'Test Session',
        updatedAt: DateTime.now(),
        messages: [assistantMsg],
      );
      await storage.saveChatSessions([session]);
      await provider.init();
      await provider.setApiKey('test-key');

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buka accordion sumber makalah jika terlipat
      final expandFinder = find.text('Lihat');
      if (expandFinder.evaluate().isNotEmpty) {
        await tester.tap(expandFinder);
        await tester.pumpAndSettle();
      }

      final rangkumFinder = find.widgetWithText(InkWell, 'Rangkum');
      expect(rangkumFinder, findsOneWidget);

      await tester.tap(rangkumFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('AI Summary'), findsOneWidget);
      expect(find.text('Quantum Advantage in Scientific Reasoning'), findsNWidgets(2));

      final bookmarkFinder = find.byTooltip('Simpan ke Catatan');
      expect(bookmarkFinder, findsOneWidget);

      // Verifikasi skeleton aktif dan tombol simpan disabled
      expect(find.byType(SummarySkeleton), findsOneWidget);
      final bookmarkBtnBefore = tester.widget<IconButton>(
        find.ancestor(of: bookmarkFinder, matching: find.byType(IconButton)),
      );
      expect(bookmarkBtnBefore.onPressed, isNull);
      expect(provider.isPaperSummarySaved(paper.id), isFalse);

      completer.complete('''
**Apa yang dilakukan** — Mendemonstrasikan keunggulan kuantum.
**Metodologi** — Circuit depth reduction.
**Temuan utama** — Speedup eksponensial.

<follow_up>["Bagaimana toleransi kesalahan?", "Apa arsitektur perangkat kerasnya?"]</follow_up>''');

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(SummarySkeleton), findsNothing);
      expect(find.textContaining('Mendemonstrasikan keunggulan kuantum'), findsOneWidget);
      expect(find.textContaining('<follow_up>'), findsNothing);
      expect(find.textContaining('Bagaimana toleransi kesalahan?'), findsNothing);

      await tester.tap(bookmarkFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ringkasan berhasil disimpan ke Catatan.'), findsOneWidget);
      expect(find.byTooltip('Tersimpan di Catatan'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(provider.isPaperSummarySaved(paper.id), isTrue);

      final savedNote = provider.notes.first;
      expect(savedNote.isPaperSummary, isTrue);
      expect(savedNote.primaryPaper?.id, paper.id);
      expect(savedNote.content, isNot(contains('<follow_up>')));
      expect(savedNote.content, contains('Mendemonstrasikan keunggulan kuantum'));

      await tester.tap(find.byTooltip('Tersimpan di Catatan'));
      await tester.pump();
      expect(provider.notes.length, 1);
    });

    testWidgets(
        'ChatScreen: Tombol simpan disabled jika ringkasan menghasilkan error',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final completer = Completer<String>();
      gemini.completer = completer;

      final paper = _createSamplePaper(id: 'paper_chat_err_1');
      final assistantMsg = ChatMessage(
        id: 'asst_msg_err',
        role: MessageRole.assistant,
        content: 'Hasil pencarian:',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        papers: [paper],
      );

      final session = ChatSession(
        id: 'session_chat_err',
        title: 'Error Session Test',
        updatedAt: DateTime.now(),
        messages: [assistantMsg],
      );
      await storage.saveChatSessions([session]);
      await provider.init();
      await provider.setApiKey('test-key');

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: _wrapWithTheme(
            child: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buka accordion sumber makalah jika terlipat
      final expandFinder = find.text('Lihat');
      if (expandFinder.evaluate().isNotEmpty) {
        await tester.tap(expandFinder);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.widgetWithText(InkWell, 'Rangkum'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      completer.complete('Failed to summarize: Exception: Koneksi terputus');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Failed to summarize'), findsOneWidget);

      final bookmarkFinder = find.byTooltip('Simpan ke Catatan');
      expect(bookmarkFinder, findsOneWidget);

      final iconBtn = tester.widget<IconButton>(
        find.ancestor(of: bookmarkFinder, matching: find.byType(IconButton)),
      );
      expect(iconBtn.onPressed, isNull);
      expect(provider.isPaperSummarySaved(paper.id), isFalse);
    });
  });
}
