// Comprehensive tests for SCIChat Phase 4B — Ordinal Citation Support

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:provider/provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/screens/paper_detail_screen.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/utils/citation_parser.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:scichat/widgets/paper_card.dart';

class _MockGeminiService extends GeminiService {
  _MockGeminiService() : super(apiKey: 'dummy-key');

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
    yield 'Teks awal ';
    yield 'dengan sitasi [1] ';
    yield 'dan [2].';
    lastStreamFinishReason = 'stop';
  }
}

class _MockStorageService extends StorageService {
  List<ChatSession> sessions = [];

  @override
  Future<String?> getApiKey() async => 'dummy-api-key';
  @override
  Future<List<ChatSession>> getChatSessions() async => sessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async {
    sessions = List.from(s);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const paper1 = ArxivPaper(
    id: 'paper-001',
    title: 'Attention Is All You Need',
    authors: ['Vaswani et al.'],
    summary: 'The dominant sequence transduction models...',
    published: '2017-06-12',
    updated: '2017-06-12',
    categories: ['cs.CL'],
    pdfUrl: 'https://arxiv.org/pdf/paper-001.pdf',
    absUrl: 'https://arxiv.org/abs/paper-001',
  );

  const paper2 = ArxivPaper(
    id: 'paper-002',
    title: 'BERT: Pre-training of Deep Bidirectional Transformers',
    authors: ['Devlin et al.'],
    summary: 'We introduce a new language representation model...',
    published: '2018-10-11',
    updated: '2018-10-11',
    categories: ['cs.CL'],
    pdfUrl: 'https://arxiv.org/pdf/paper-002.pdf',
    absUrl: 'https://arxiv.org/abs/paper-002',
  );

  const paperNoPdf = ArxivPaper(
    id: 'paper-003',
    title: 'Pure Abstract Only Document Without PDF',
    authors: ['Author Three'],
    summary: 'Only summary is available, no PDF download exists.',
    published: '2023-01-01',
    updated: '2023-01-01',
    categories: ['cs.AI'],
    pdfUrl: '',
    absUrl: 'https://arxiv.org/abs/paper-003',
  );

  group('Tahap 4B — Unit Test Resolusi Sitasi Ordinal', () {
    test('1. [1] dipetakan ke paper pertama (papers[0])', () {
      const text = 'Model transformer diperkenalkan pertama kali [1].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(matches.length, 1);
      expect(matches[0].paper.id, paper1.id);
      expect(matches[0].ordinal, 1);
      expect(matches[0].rawText, '[1]');

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );
      expect(converted, contains('[1](scichat-cite://paper-001?ordinal=1)'));
    });

    test('2. [2] dipetakan ke paper kedua (papers[1])', () {
      const text = 'Pendekatan bidirectional encoder dipopulerkan oleh [2].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(matches.length, 1);
      expect(matches[0].paper.id, paper2.id);
      expect(matches[0].ordinal, 2);
      expect(matches[0].rawText, '[2]');

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );
      expect(converted, contains('[2](scichat-cite://paper-002?ordinal=2)'));
    });

    test('3. [Paper 1] dan [Makalah 2] didukung dengan pemetaan ordinal yang benar', () {
      const text = 'Studi [Paper 1] dan perbandingannya pada [Makalah 2].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(matches.length, 2);
      expect(matches[0].paper.id, paper1.id);
      expect(matches[0].ordinal, 1);
      expect(matches[0].rawText, '[Paper 1]');

      expect(matches[1].paper.id, paper2.id);
      expect(matches[1].ordinal, 2);
      expect(matches[1].rawText, '[Makalah 2]');

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );
      expect(converted, contains('[Paper 1](scichat-cite://paper-001?ordinal=1)'));
      expect(converted, contains('[Makalah 2](scichat-cite://paper-002?ordinal=2)'));
    });

    test('4. [0] dan nomor di luar jumlah paper tetap teks biasa tanpa tautan', () {
      const text = 'Batas indeks invalid [0], out of range [3] dan [99].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(matches, isEmpty);

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );
      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('5. Pesan tanpa paper tidak menghasilkan tautan ordinal', () {
      const text = 'Klaim dengan sitasi [1] tetapi daftar paper kosong.';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: const [],
      );

      expect(matches, isEmpty);

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: const [],
      );
      expect(converted, text);
    });

    test('6. [1](https://example.com) tetap menjadi tautan Markdown normal tanpa rusak', () {
      const text = 'Kunjungi dokumentasi resmi di [1](https://example.com/docs).';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(matches, isEmpty);

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );
      expect(converted, text);
      expect(converted, contains('[1](https://example.com/docs)'));
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('7. arr[1] di inline code tidak menjadi sitasi', () {
      const text = 'Akses elemen array menggunakan `arr[1]` pada fungsi indeks.';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(converted, text);
      expect(converted, contains('`arr[1]`'));
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('8. arr[1] di luar kode tidak salah diperlakukan sebagai sitasi jika merupakan indeks identifier', () {
      const text = 'Nilai arr[1] dan matrix[2] adalah variabel program.';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(matches, isEmpty);

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );
      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('9. Notasi matematika dan LaTeX tetap aman', () {
      const text = 'Persamaan \$x[1] + y[2] = 10\$ dan display \$\$\\sum_{i=1}^n [1]\$\$.';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
      );

      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('10. Sitasi halaman/seksi lama masih bekerja secara harmonis', () {
      const text = 'Metode pada [Paper 1, Halaman 5] dan [Seksi 4.4, Halaman 4] serta rujukan [1].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paper1, paper2],
        validatedPagesMap: {
          paper1.id: {4, 5},
        },
      );

      expect(matches.length, 3);
      expect(matches[0].rawText, '[Paper 1, Halaman 5]');
      expect(matches[0].pageNumber, 5);

      expect(matches[1].rawText, '[Seksi 4.4, Halaman 4]');
      expect(matches[1].pageNumber, 4);

      expect(matches[2].rawText, '[1]');
      expect(matches[2].ordinal, 1);
      // Paper 1 memiliki validatedPagesMap {4, 5}, sehingga sitasi ordinal [1] mengaitkan halaman bukti pertama (4)
      expect(matches[2].pageNumber, 4);

      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paper1, paper2],
        validatedPagesMap: {
          paper1.id: {4, 5},
        },
      );
      expect(converted, contains('[Paper 1, Halaman 5](scichat-cite://paper-001?page=5)'));
      expect(converted, contains('[Seksi 4.4, Halaman 4](scichat-cite://paper-001?page=4)'));
      expect(converted, contains('[1](scichat-cite://paper-001?page=4&ordinal=1)'));
    });
  });

  group('Tahap 4B — Widget & Navigation Tests', () {
    testWidgets('11 & 12. Sitasi ordinal dengan halaman bukti membuka PDF pada halaman yang benar',
        (tester) async {
      CitationReference? tappedCitation;
      const text = 'Hasil temuan tercatat pada riset transformer [1].';

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.light,
          home: Scaffold(
            body: MessageContent(
              content: text,
              papers: const [paper1, paper2],
              validatedCitationPages: const {
                'paper-001': [4, 7],
              },
              onCitationTap: (c) => tappedCitation = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdownFinder = find.byType(MarkdownBody);
      expect(markdownFinder, findsOneWidget);

      final matches = CitationParser.findCitations(
        text,
        availablePapers: const [paper1, paper2],
        validatedPagesMap: const {
          'paper-001': {4, 7},
        },
      );
      expect(matches.length, 1);
      expect(matches[0].ordinal, 1);
      expect(matches[0].pageNumber, 4);

      await MessageContent.handleLinkTap(
        tester.element(markdownFinder),
        matches[0].uri.toString(),
        availablePapers: const [paper1, paper2],
        onCitationTap: (c) => tappedCitation = c,
      );
      await tester.pumpAndSettle();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.documentId, paper1.id);
      expect(tappedCitation!.ordinal, 1);
      expect(tappedCitation!.pageNumber, 4);
    });

    testWidgets('13. Paper tanpa PDF mengikuti fallback detail paper yang benar',
        (tester) async {
      final mockStorage = _MockStorageService();
      final mockGemini = _MockGeminiService();
      final provider = SciChatProvider(
        storageService: mockStorage,
        geminiService: mockGemini,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () {
                    final ref = CitationReference(
                      documentId: paperNoPdf.id,
                      documentTitle: paperNoPdf.title,
                      ordinal: 1,
                      paper: paperNoPdf,
                      rawText: '[1]',
                    );
                    MessageContent.handleLinkTap(
                      ctx,
                      ref.toUri().toString(),
                      availablePapers: [paperNoPdf],
                    );
                  },
                  child: const Text('Simulasi Tap Sitasi Tanpa PDF'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap tombol yang memanggil handleLinkTap
      await tester.tap(find.text('Simulasi Tap Sitasi Tanpa PDF'));
      await tester.pumpAndSettle();

      // PaperDetailScreen terbuka karena URL PDF kosong
      expect(find.byType(PaperDetailScreen), findsOneWidget);
      expect(find.text(paperNoPdf.title), findsOneWidget);
    });

    testWidgets('14. Streaming dapat merender sitasi saat token tiba tanpa assertion error',
        (tester) async {
      final msg = ChatMessage(
        id: 'stream-msg',
        role: MessageRole.assistant,
        content: 'Model baru [1] sedang mengalir...',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
        papers: const [paper1],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: ChatBubble(
              message: msg,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(MarkdownBody), findsOneWidget);
      final matches = CitationParser.findCitations(
        msg.content,
        availablePapers: msg.papers,
      );
      expect(matches.length, 1);
      expect(matches.first.ordinal, 1);

      // Settle dengan status done untuk membersihkan timer render throttle
      final doneMsg = msg.copyWith(status: MessageStatus.done);
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: ChatBubble(
              message: doneMsg,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    test('15. Riwayat lama yang memiliki papers mempertahankan pemetaan berdasarkan urutan sumber tersimpan', () {
      final sessionJson = {
        'id': 'sess-123',
        'title': 'Sesi Riwayat Percakapan',
        'updatedAt': DateTime.now().toIso8601String(),
        'messages': [
          {
            'id': 'msg-1',
            'role': 'MessageRole.assistant',
            'content': 'Sesuai dengan [1] dan [2].',
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'MessageStatus.done',
            'papers': [paper2.toJson(), paper1.toJson()], // Urutan sengaja paper2 lalu paper1
          }
        ],
      };

      final session = ChatSession.fromJson(sessionJson);
      final restoredMsg = session.messages.first;

      expect(restoredMsg.papers.length, 2);
      expect(restoredMsg.papers[0].id, paper2.id); // Paper 1 pada pesan ini adalah paper2
      expect(restoredMsg.papers[1].id, paper1.id); // Paper 2 pada pesan ini adalah paper1

      final matches = CitationParser.findCitations(
        restoredMsg.content,
        availablePapers: restoredMsg.papers,
      );

      expect(matches.length, 2);
      expect(matches[0].ordinal, 1);
      expect(matches[0].paper.id, paper2.id); // [1] memetakan ke paper2 sesuai urutan tersimpan
      expect(matches[1].ordinal, 2);
      expect(matches[1].paper.id, paper1.id); // [2] memetakan ke paper1 sesuai urutan tersimpan
    });

    testWidgets('16. Bottom sheet Tahap 4A dan tombol PaperCard tetap harmonis dengan ordinal',
        (tester) async {
      final msg = ChatMessage(
        id: 'sources-sheet-msg',
        role: MessageRole.assistant,
        content: 'Pembahasan dengan sitasi ordinal [1] dan [2].',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        papers: const [paper1, paper2],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.light,
          home: Scaffold(
            body: ChatBubble(
              message: msg,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Buka bottom sheet Tahap 4A
      final trigger = find.byKey(const ValueKey('sources_sheet_trigger'));
      expect(trigger, findsOneWidget);
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text('Sumber Makalah (2)'), findsOneWidget);
      expect(find.byType(PaperCard), findsNWidgets(2));
      expect(find.text(paper1.title), findsOneWidget);
      expect(find.text(paper2.title), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('close_sources_sheet')));
      await tester.pumpAndSettle();
    });
  });
}
