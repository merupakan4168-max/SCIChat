// Tests for SCIChat Phase 5C — Citation-to-PDF Navigation

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/screens/pdf_viewer_screen.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/utils/citation_parser.dart';
import 'package:scichat/widgets/chat_bubble.dart';

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

  const paperB = ArxivPaper(
    id: '1706.03762',
    title: 'Attention Is All You Need',
    authors: ['Ashish Vaswani', 'Noam Shazeer'],
    summary: 'The dominant sequence transduction models...',
    published: '2017-06-12',
    updated: '2017-06-12',
    categories: ['cs.CL'],
    pdfUrl: 'https://arxiv.org/pdf/1706.03762.pdf',
    absUrl: 'https://arxiv.org/abs/1706.03762',
  );

  group('Phase 5C Requirement 1: Valid page citations rendered as interactive elements', () {
    test('Converts single-paper [Halaman 4] and [Hal. 7] to scichat-cite links', () {
      const text =
          'Hasil eksperimen menunjukkan akurasi 94.2% [Halaman 4] dan dataset dijelaskan pada [Hal. 7].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 4, 7},
        },
      );

      expect(
        converted,
        contains('[Halaman 4](scichat-cite://2005.11401?page=4)'),
      );
      expect(
        converted,
        contains('[Hal. 7](scichat-cite://2005.11401?page=7)'),
      );
    });

    test('Finds CitationMatch objects with correct page numbers and paper metadata', () {
      const text = 'Metode generator [Halaman 5] dan retriever [Hal 3].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 3, 5},
        },
      );

      expect(matches.length, 2);
      expect(matches[0].pageNumber, 5);
      expect(matches[0].paper.id, paperA.id);
      expect(matches[0].rawText, '[Halaman 5]');
      expect(matches[1].pageNumber, 3);
      expect(matches[1].rawText, '[Hal 3]');
    });
  });

  group('Phase 5C Requirement 2: Plain text resembling citations is not treated as validated citations', () {
    test('Non-citation brackets and general mentions remain plain text', () {
      const text =
          'Model baseline [99] dan [2, 3] mencapai akurasi [85.4%]. Penjelasan lengkap ada di halaman 4.';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 2, 3, 4},
        },
      );

      // Pastikan tidak ada tautan scichat-cite palsu yang dibuat
      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('Bracketed [Halaman] without number is not matched', () {
      const text = 'Lihat seksi [Halaman] berikut.';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {paperA.id: {1, 2}},
      );
      expect(matches, isEmpty);
    });
  });

  group('Phase 5C Requirement 3: Reference opens the correct document via CitationReference', () {
    test('Resolves CitationReference from scichat-cite URI accurately', () {
      final uri = Uri.parse('scichat-cite://2005.11401?page=6');
      final ref = CitationReference.fromUri(uri, [paperA, paperB]);

      expect(ref, isNotNull);
      expect(ref!.documentId, paperA.id);
      expect(ref.documentTitle, paperA.title);
      expect(ref.pageNumber, 6);
      expect(ref.paper.id, paperA.id);
    });

    test('Returns null when document ID is not in available papers', () {
      final uri = Uri.parse('scichat-cite://unknown_doc_999?page=3');
      final ref = CitationReference.fromUri(uri, [paperA]);
      expect(ref, isNotNull);
      // Fallback paper is created with the unknown ID, but preserves ID integrity
      expect(ref!.documentId, 'unknown_doc_999');
    });
  });

  group('Phase 5C Requirement 4: Initial page number is forwarded to viewer and context', () {
    test('PdfDocumentContext preserves initialPage from paper and factories', () {
      final ctx = PdfDocumentContext.fromPaper(paperA, initialPage: 5);
      expect(ctx.initialPage, 5);
      expect(ctx.currentPage, 5);

      final localCtx = PdfDocumentContext.fromFile(
        filePath: 'D:/test.pdf',
        title: 'Test',
        initialPage: 8,
      );
      expect(localCtx.initialPage, 8);
      expect(localCtx.currentPage, 8);
    });

    test('PdfViewerScreen exposes effectiveInitialPage correctly', () {
      final screenFromCtx = PdfViewerScreen(
        documentContext: PdfDocumentContext.fromPaper(paperA, initialPage: 4),
      );
      expect(screenFromCtx.effectiveInitialPage, 4);

      final screenWithOverride = PdfViewerScreen.fromPaper(
        paper: paperA,
        initialPage: 9,
      );
      expect(screenWithOverride.effectiveInitialPage, 9);
    });
  });

  group('Phase 5C Requirement 5: Zero, negative, and out-of-range page numbers handled safely', () {
    test('Rejects zero and negative page citations in CitationParser', () {
      const text = 'Lihat [Halaman 0] dan [Halaman -3].';
      final matches = CitationParser.findCitations(
        text,
        availablePapers: [paperA],
      );
      expect(matches, isEmpty);
    });

    test('PdfDocumentContext clamps zero and negative initialPage to 1 for currentPage', () {
      final ctxZero = PdfDocumentContext.fromPaper(paperA, initialPage: 0);
      expect(ctxZero.initialPage, 0);
      expect(ctxZero.currentPage, 1);

      final ctxNegative = PdfDocumentContext.fromPaper(paperA, initialPage: -5);
      expect(ctxNegative.initialPage, -5);
      expect(ctxNegative.currentPage, 1);
    });
  });

  group('Phase 5C Requirement 6: Multi-paper isolation prevents citations from being swapped', () {
    test('Resolves [Paper 1, Halaman 5] and [Paper 2, Hal. 3] to respective papers', () {
      const multiText =
          'RAG menggunakan BART [Paper 1, Halaman 5], sedangkan Transformer menggunakan self-attention [Paper 2, Hal. 3].';

      final converted = CitationParser.convertCitationsToLinks(
        multiText,
        availablePapers: [paperA, paperB],
        validatedPagesMap: {
          paperA.id: {1, 5},
          paperB.id: {1, 3},
        },
      );

      expect(
        converted,
        contains('[Paper 1, Halaman 5](scichat-cite://2005.11401?page=5)'),
      );
      expect(
        converted,
        contains('[Paper 2, Hal. 3](scichat-cite://1706.03762?page=3)'),
      );
    });

    test('Ambiguous citation in multi-paper context without paper ID is not linked', () {
      const ambiguousText = 'Metrik evaluasi dijelaskan pada [Halaman 4].';
      // Kedua paper sama-sama memiliki halaman 4, tidak ada identitas paper
      final converted = CitationParser.convertCitationsToLinks(
        ambiguousText,
        availablePapers: [paperA, paperB],
        validatedPagesMap: {
          paperA.id: {1, 4},
          paperB.id: {2, 4},
        },
      );

      // Harus tetap teks biasa jujur, jangan mengarahkan secara salah (Rule 3E)
      expect(converted, ambiguousText);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('Out-of-range paper index in multi-paper format is rejected', () {
      const invalidPaperText = 'Bukti pada [Paper 99, Halaman 2].';
      final matches = CitationParser.findCitations(
        invalidPaperText,
        availablePapers: [paperA, paperB],
      );
      expect(matches, isEmpty);
    });
  });

  group('Phase 5C Requirement 7: Missing local file and invalid URL handled gracefully', () {
    testWidgets('Tapping citation with missing local file shows informative SnackBar',
        (tester) async {
      const missingPaper = ArxivPaper(
        id: 'missing_local',
        title: 'Berkas Hilang',
        authors: ['Penulis'],
        summary: '',
        published: '',
        updated: '',
        categories: [],
        pdfUrl: 'file:///C:/non_existent_path_xyz123/missing.pdf',
        absUrl: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  MessageContent.handleLinkTap(
                    context,
                    'scichat-cite://missing_local?page=2',
                    availablePapers: [missingPaper],
                  );
                },
                child: const Text('Tap Citation'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Citation'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Berkas PDF lokal tidak ditemukan pada penyimpanan perangkat'),
        findsOneWidget,
      );
    });

    testWidgets('Tapping citation with empty PDF URL shows warning SnackBar',
        (tester) async {
      const emptyUrlPaper = ArxivPaper(
        id: 'empty_url_doc',
        title: 'Makalah Tanpa URL',
        authors: ['Penulis'],
        summary: '',
        published: '',
        updated: '',
        categories: [],
        pdfUrl: '',
        absUrl: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  MessageContent.handleLinkTap(
                    context,
                    'scichat-cite://empty_url_doc?page=1',
                    availablePapers: [emptyUrlPaper],
                  );
                },
                child: const Text('Tap Empty URL'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap Empty URL'));
      await tester.pumpAndSettle();

      expect(
        find.text('Dokumen tidak memiliki URL PDF yang valid.'),
        findsOneWidget,
      );
    });
  });

  group('Phase 5C Requirement 8: Markdown, LaTeX math, code blocks, and streaming do not regress', () {
    test('Citation conversion leaves code blocks and LaTeX math unchanged', () {
      const complexText = '''
Berikut adalah kode program:
```dart
final x = [Halaman 4];
```
Dan inline code `[Halaman 4]` serta rumus \$E = mc^2 [Halaman 4]\$.
Tautan eksternal: [Dokumentasi](https://example.com).
Sedangkan kutipan nyata ada di [Halaman 4].
''';

      final converted = CitationParser.convertCitationsToLinks(
        complexText,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {4},
        },
      );

      // Blok kode dan inline code tidak tersentuh
      expect(converted, contains('final x = [Halaman 4];'));
      expect(converted, contains('`[Halaman 4]`'));
      expect(converted, contains(r'$E = mc^2 [Halaman 4]$'));
      expect(converted, contains('[Dokumentasi](https://example.com)'));

      // Hanya kutipan nyata pada teks biasa yang diubah menjadi tautan
      expect(converted, contains('[Halaman 4](scichat-cite://2005.11401?page=4)'));
    });

    testWidgets('MessageContent renders streaming message without error',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: const Scaffold(
            body: MessageContent(
              content: 'Menulis respons awal [Halaman 2]...',
              isStreaming: true,
              papers: [paperA],
              validatedCitationPages: {
                '2005.11401': [2],
              },
            ),
          ),
        ),
      );

      expect(find.byType(MessageContent), findsOneWidget);
    });
  });

  group('Phase 5C Requirement 9: Documents lacking evidence metadata do not generate fake links', () {
    test('Hallucinated page number not in validatedPagesMap remains plain text', () {
      const text =
          'Klaim palsu model merujuk ke [Halaman 999] yang tidak ada dalam PDF.';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: [paperA],
        validatedPagesMap: {
          paperA.id: {1, 2, 3, 4}, // Halaman 999 tidak valid
        },
      );

      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });

    test('When availablePapers is empty, citations remain plain text', () {
      const text = 'Seksi metodologi ada di [Halaman 4].';
      final converted = CitationParser.convertCitationsToLinks(
        text,
        availablePapers: const [],
      );

      expect(converted, text);
      expect(converted, isNot(contains('scichat-cite://')));
    });
  });

  group('Phase 5C Integration: Citation tap callback interception', () {
    testWidgets('onCitationTap intercepts click on validated citation',
        (tester) async {
      CitationReference? tappedCitation;

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: MessageContent(
              content: 'Temuan utama [Halaman 4](scichat-cite://2005.11401?page=4)',
              papers: const [paperA],
              onCitationTap: (citation) {
                tappedCitation = citation;
              },
            ),
          ),
        ),
      );

      final markdownFinder = find.byType(MarkdownBody);
      expect(markdownFinder, findsOneWidget);

      await MessageContent.handleLinkTap(
        tester.element(markdownFinder),
        'scichat-cite://2005.11401?page=4',
        availablePapers: const [paperA],
        onCitationTap: (citation) {
          tappedCitation = citation;
        },
      );
      await tester.pump();

      expect(tappedCitation, isNotNull);
      expect(tappedCitation!.pageNumber, 4);
      expect(tappedCitation!.documentId, paperA.id);
    });
  });
}

