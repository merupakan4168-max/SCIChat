// Reproduction tests for Phase 5C manual audit findings:
// - Non-interactive citation format: [Kutipan: Seksi 4.4, Tabel 2] and [Kutipan: Seksi 4.4, Halaman 4]
// - Prompt vs Renderer mismatch
// - Page-level navigation support in Sumber Makalah panel

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/utils/citation_parser.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:scichat/theme/scichat_theme.dart';

void main() {
  const paperA = ArxivPaper(
    id: '2005.11401',
    title: 'Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks',
    authors: ['Patrick Lewis', 'Ethan Perez'],
    summary: 'RAG models combine pre-trained parametric memory...',
    published: '2020-05-22',
    updated: '2020-05-22',
    categories: ['cs.CL'],
    pdfUrl: 'https://arxiv.org/pdf/2005.11401.pdf',
    absUrl: 'https://arxiv.org/abs/2005.11401',
  );

  group('Reproduction: Flexible Citation Formats', () {
    test('Reproduction: [Kutipan: Seksi 4.4, Halaman 4] should be parsed as interactive link', () {
      const text = 'Model ini dievaluasi pada benchmark NQ [Kutipan: Seksi 4.4, Halaman 4].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 4},
        },
      );

      expect(
        converted,
        contains('[Kutipan: Seksi 4.4, Halaman 4](scichat-cite://2005.11401?page=4)'),
      );
    });

    test('Reproduction: [Seksi 4.4, Halaman 4] should be parsed as interactive link', () {
      const text = 'Rincian arsitektur ditemukan di [Seksi 4.4, Halaman 4].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 4},
        },
      );

      expect(
        converted,
        contains('[Seksi 4.4, Halaman 4](scichat-cite://2005.11401?page=4)'),
      );
    });

    test('Reproduction: [Paper 1, Seksi 4.4, Halaman 4] should be parsed in multi-paper mode', () {
      const text = 'Eksperimen awal pada [Paper 1, Seksi 4.4, Halaman 4].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 4},
        },
      );

      expect(
        converted,
        contains('[Paper 1, Seksi 4.4, Halaman 4](scichat-cite://2005.11401?page=4)'),
      );
    });

    test('Reproduction: Section-only citation [Kutipan: Seksi 4.4, Tabel 2] resolves via chunk section metadata', () {
      const text = 'Hasil performa disajikan pada [Kutipan: Seksi 4.4, Tabel 2].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 4},
        },
        validatedSectionPagesMap: {
          paperA.id: {
            'seksi 4.4': 4,
            '4.4': 4,
          },
        },
      );

      expect(
        converted,
        contains('[Kutipan: Seksi 4.4, Tabel 2](scichat-cite://2005.11401?page=4)'),
      );
    });

    test('Reproduction: Citation with hallucinated page not in validatedPagesMap remains plain text', () {
      const text = 'Klaim tanpa bukti di [Halaman 99] atau [Kutipan: Seksi 4.4, Halaman 99].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 4}, // Halaman 99 tidak ada
        },
      );

      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    testWidgets('Widget: [Kutipan: Seksi 4.4, Halaman 4] resolves and handleLinkTap dispatches to page 4', (tester) async {
      CitationReference? tappedCitation;
      const content = 'Arsitektur RAG dievaluasi pada [Kutipan: Seksi 4.4, Halaman 4].';

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: MessageContent(
              content: content,
              papers: const [paperA],
              validatedCitationPages: const {
                '2005.11401': [4],
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
        content,
        availablePapers: const [paperA],
        validatedPagesMap: const {
          '2005.11401': {4},
        },
      );
      expect(matches.length, 1);
      expect(matches[0].pageNumber, 4);
      expect(matches[0].paper.id, paperA.id);

      await MessageContent.handleLinkTap(
        tester.element(markdownFinder),
        matches[0].uri.toString(),
        availablePapers: const [paperA],
        onCitationTap: (c) => tappedCitation = c,
      );
      await tester.pumpAndSettle();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.documentId, paperA.id);
      expect(tappedCitation!.pageNumber, 4);
    });

    testWidgets('Widget: [Kutipan: Seksi 4.4, Tabel 2] resolves via section metadata and handleLinkTap dispatches to page 4', (tester) async {
      CitationReference? tappedCitation;
      const content = 'Tabel performa disajikan pada [Kutipan: Seksi 4.4, Tabel 2].';

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: MessageContent(
              content: content,
              papers: const [paperA],
              validatedCitationPages: const {
                '2005.11401': [4],
              },
              validatedSectionPages: const {
                '2005.11401': {
                  'seksi 4.4': 4,
                  '4.4': 4,
                },
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
        content,
        availablePapers: const [paperA],
        validatedPagesMap: const {
          '2005.11401': {4},
        },
        validatedSectionPagesMap: const {
          '2005.11401': {
            'seksi 4.4': 4,
            '4.4': 4,
          },
        },
      );
      expect(matches.length, 1);
      expect(matches[0].pageNumber, 4);
      expect(matches[0].paper.id, paperA.id);

      await MessageContent.handleLinkTap(
        tester.element(markdownFinder),
        matches[0].uri.toString(),
        availablePapers: const [paperA],
        onCitationTap: (c) => tappedCitation = c,
      );
      await tester.pumpAndSettle();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.documentId, paperA.id);
      expect(tappedCitation!.pageNumber, 4);
    });

    testWidgets('Widget: Multi-paper citations navigate to respective papers and pages', (tester) async {
      const paperB = ArxivPaper(
        id: '1706.03762',
        title: 'Attention Is All You Need',
        authors: ['Ashish Vaswani'],
        summary: 'Transformer architecture...',
        published: '2017-06-12',
        updated: '2017-06-12',
        categories: ['cs.CL'],
        pdfUrl: 'https://arxiv.org/pdf/1706.03762.pdf',
        absUrl: 'https://arxiv.org/abs/1706.03762',
      );

      final tappedCitations = <CitationReference>[];
      const content = 'RAG [Paper 1, Seksi 4.4, Halaman 4] vs Transformer [Paper 2, Halaman 3].';

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: MessageContent(
              content: content,
              papers: const [paperA, paperB],
              validatedCitationPages: const {
                '2005.11401': [4],
                '1706.03762': [3],
              },
              onCitationTap: (c) => tappedCitations.add(c),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final markdownFinder = find.byType(MarkdownBody);
      expect(markdownFinder, findsOneWidget);

      final matches = CitationParser.findCitations(
        content,
        availablePapers: const [paperA, paperB],
        validatedPagesMap: const {
          '2005.11401': {4},
          '1706.03762': {3},
        },
      );
      expect(matches.length, 2);

      await MessageContent.handleLinkTap(
        tester.element(markdownFinder),
        matches[0].uri.toString(),
        availablePapers: const [paperA, paperB],
        onCitationTap: (c) => tappedCitations.add(c),
      );
      await MessageContent.handleLinkTap(
        tester.element(markdownFinder),
        matches[1].uri.toString(),
        availablePapers: const [paperA, paperB],
        onCitationTap: (c) => tappedCitations.add(c),
      );
      await tester.pumpAndSettle();

      expect(tappedCitations.length, 2);
      expect(tappedCitations[0].documentId, paperA.id);
      expect(tappedCitations[0].pageNumber, 4);
      expect(tappedCitations[1].documentId, paperB.id);
      expect(tappedCitations[1].pageNumber, 3);
    });

    testWidgets('Widget: Sumber makalah panel provides interactive page navigation chips', (tester) async {
      CitationReference? tappedCitation;

      final msg = ChatMessage(
        id: 'msg_sources_test',
        role: MessageRole.assistant,
        content: 'Penjelasan umum mengenai temuan makalah.',
        timestamp: DateTime.now(),
        papers: const [paperA],
        validatedCitationPages: const {
          '2005.11401': [1, 4],
        },
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
              onCitationTap: (c) => tappedCitation = c,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Buka panel Sumber makalah
      final accordionFinder = find.text('Sumber makalah (1)');
      expect(accordionFinder, findsOneWidget);
      await tester.tap(accordionFinder);
      await tester.pumpAndSettle();

      // Pastikan label halaman rujukan dan chip halaman muncul
      expect(find.text('Halaman rujukan:'), findsOneWidget);
      expect(find.text('Hal. 1'), findsOneWidget);
      expect(find.text('Hal. 4'), findsOneWidget);

      // Klik chip Hal. 4
      await tester.tap(find.text('Hal. 4'));
      await tester.pumpAndSettle();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.documentId, paperA.id);
      expect(tappedCitation!.pageNumber, 4);
    });
  });
}
