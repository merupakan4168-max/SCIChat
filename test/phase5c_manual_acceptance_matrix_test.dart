// Phase 5C — Manual Acceptance Testing & Reliability Matrix
//
// Melakukan validasi otomatis untuk 8 skenario pengujian manual:
// 1. PDF Lokal: verifikasi resolusi path berkas lokal dan nomor halaman target
// 2. PDF Online: verifikasi resolusi URL HTTPS dan nomor halaman target
// 3. Multi-Paper: verifikasi isolasi sitasi lintas paper tanpa salah alamat
// 4. Halaman Tidak Tervalidasi: nomor halaman tanpa bukti evidence tetap non-interaktif
// 5. Markdown dan Matematika: proteksi blok kode, math display/inline, dan tautan markdown asli
// 6. Streaming: rendering aman pada pesan streaming dan penonaktifan seleksi teks
// 7. Berkas/URL Bermasalah: umpan balik ramah via SnackBar tanpa crash
// 8. Riwayat Chat: integritas persistensi ChatSession dan penanganan pesan lama tanpa metadata

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/screens/pdf_viewer_screen.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/utils/citation_parser.dart';
import 'package:scichat/widgets/chat_bubble.dart';

void main() {
  const sampleLocalPaper = ArxivPaper(
    id: 'local_doc_101',
    title: 'Neuromorphic Bio-Inspired SNN for ECG',
    authors: ['Researcher A', 'Researcher B'],
    summary: 'Digital implementation of spiking neural network for ECG classification',
    published: '2022-07-01',
    updated: '2022-07-01',
    categories: ['cs.NE'],
    pdfUrl: 'file:///D:/papers/neuromorphic.pdf',
    absUrl: '',
  );

  const sampleOnlinePaperA = ArxivPaper(
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

  const sampleOnlinePaperB = ArxivPaper(
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

  group('Phase 5C Manual Acceptance Matrix Verification', () {
    // 1. PDF Lokal: verifikasi resolusi path berkas lokal dan halaman target
    testWidgets('Matrix 1: Local PDF opens with exact file path and target page',
        (tester) async {
      CitationReference? resolvedCitation;

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: MessageContent(
              content:
                  'Klasifikasi ECG dijelaskan pada [Halaman 6](scichat-cite://local_doc_101?page=6).',
              papers: const [sampleLocalPaper],
              validatedCitationPages: const {
                'local_doc_101': [1, 2, 6],
              },
              onCitationTap: (c) => resolvedCitation = c,
            ),
          ),
        ),
      );

      final mdWidget = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      mdWidget.onTapLink!('Halaman 6', 'scichat-cite://local_doc_101?page=6', '');
      await tester.pumpAndSettle();

      expect(resolvedCitation, isNotNull);
      expect(resolvedCitation!.documentId, 'local_doc_101');
      expect(resolvedCitation!.pageNumber, 6);
      expect(resolvedCitation!.paper.pdfUrl, 'file:///D:/papers/neuromorphic.pdf');

      final viewer = PdfViewerScreen.fromPaper(
        paper: resolvedCitation!.paper,
        initialPage: resolvedCitation!.pageNumber,
      );
      expect(viewer.effectiveInitialPage, 6);
      expect(viewer.documentContext.filePath, contains('neuromorphic.pdf'));
    });

    // 2. PDF Online: verifikasi resolusi URL HTTPS dan halaman target
    testWidgets('Matrix 2: Online HTTPS PDF opens with exact URL and target page',
        (tester) async {
      CitationReference? resolvedCitation;

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: MessageContent(
              content:
                  'Arsitektur RAG diuraikan pada [Halaman 3](scichat-cite://2005.11401?page=3).',
              papers: const [sampleOnlinePaperA],
              validatedCitationPages: const {
                '2005.11401': [1, 3, 5],
              },
              onCitationTap: (c) => resolvedCitation = c,
            ),
          ),
        ),
      );

      final mdWidget = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      mdWidget.onTapLink!('Halaman 3', 'scichat-cite://2005.11401?page=3', '');
      await tester.pumpAndSettle();

      expect(resolvedCitation, isNotNull);
      expect(resolvedCitation!.documentId, sampleOnlinePaperA.id);
      expect(resolvedCitation!.pageNumber, 3);
      expect(resolvedCitation!.paper.pdfUrl, 'https://arxiv.org/pdf/2005.11401.pdf');

      final viewer = PdfViewerScreen.fromPaper(
        paper: resolvedCitation!.paper,
        initialPage: resolvedCitation!.pageNumber,
      );
      expect(viewer.effectiveInitialPage, 3);
      expect(viewer.documentContext.url, 'https://arxiv.org/pdf/2005.11401.pdf');
    });

    // 3. Multi-Paper: pastikan setiap sitasi membuka dokumen yang tepat tanpa tertukar
    test('Matrix 3: Multi-paper citations route to their respective documents without cross-contamination', () {
      const responseText =
          'RAG menggunakan Dense Retriever [Paper 1, Halaman 4], sedangkan Transformer menggunakan Multi-Head Attention [Paper 2, Hal. 2].';

      final matches = CitationParser.findCitations(
        responseText,
        availablePapers: [sampleOnlinePaperA, sampleOnlinePaperB],
        validatedPagesMap: {
          sampleOnlinePaperA.id: {1, 4},
          sampleOnlinePaperB.id: {1, 2},
        },
      );

      expect(matches.length, 2);
      expect(matches[0].paper.id, sampleOnlinePaperA.id);
      expect(matches[0].pageNumber, 4);
      expect(matches[0].uri.toString(), 'scichat-cite://2005.11401?page=4');

      expect(matches[1].paper.id, sampleOnlinePaperB.id);
      expect(matches[1].pageNumber, 2);
      expect(matches[1].uri.toString(), 'scichat-cite://1706.03762?page=2');
    });

    // 4. Halaman Tidak Tervalidasi: nomor halaman tanpa dukungan evidence tidak menjadi tautan
    test('Matrix 4: Citations without evidence support remain plain text', () {
      const textWithHallucination =
          'Hasil eksperimen [Halaman 1] valid, namun klaim spekulatif [Halaman 88] tidak didukung data.';

      final converted = CitationParser.convertCitationsToLinks(
        textWithHallucination,
        availablePapers: [sampleOnlinePaperA],
        validatedPagesMap: {
          sampleOnlinePaperA.id: {1}, // Hanya halaman 1 yang ada di evidence
        },
      );

      expect(converted, contains('[Halaman 1](scichat-cite://2005.11401?page=1)'));
      expect(converted, contains('[Halaman 88]'));
      expect(converted, isNot(contains('page=88')));
    });

    // 5. Markdown dan Matematika: proteksi kode, math, dan markdown link
    test('Matrix 5: Citations inside code blocks, math, and existing links remain unchanged', () {
      const complexText = '''
Contoh kode:
```python
# Referensi [Halaman 4] di dalam kode tidak boleh diubah
print("Page 4")
```
Persamaan: \$\$\\sum_{i=1}^n x_i [Halaman 2]\$\$
Inline math: \$f(x) [Hal. 3]\$
Inline code: `[Halaman 5]`
Markdown link asli: [Dokumen](https://arxiv.org/abs/2005.11401)
Sitasi sah di luar blok: [Halaman 1].
''';

      final converted = CitationParser.convertCitationsToLinks(
        complexText,
        availablePapers: [sampleOnlinePaperA],
        validatedPagesMap: {
          sampleOnlinePaperA.id: {1, 2, 3, 4, 5},
        },
      );

      expect(converted, contains('[Halaman 1](scichat-cite://2005.11401?page=1)'));
      expect(converted, contains('# Referensi [Halaman 4] di dalam kode'));
      expect(converted, contains('\$\$\\sum_{i=1}^n x_i [Halaman 2]\$\$'));
      expect(converted, contains('\$f(x) [Hal. 3]\$'));
      expect(converted, contains('`[Halaman 5]`'));
      expect(converted, contains('[Dokumen](https://arxiv.org/abs/2005.11401)'));
    });

    // 6. Streaming: periksa tampilan ketika jawaban sedang dibuat dan setelah selesai
    testWidgets('Matrix 6: Streaming messages render safely and disable text selection during stream',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: const Scaffold(
            body: MessageContent(
              content: 'Sedang menganalisis literatur [Halaman 2]...',
              isStreaming: true,
              papers: [sampleOnlinePaperA],
              validatedCitationPages: {
                '2005.11401': [2],
              },
            ),
          ),
        ),
      );

      final markdownWidget = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdownWidget.selectable, isFalse);
      expect(find.textContaining('Sedang menganalisis'), findsOneWidget);
    });

    // 7. File atau URL Bermasalah: penanganan ramah tanpa crash
    testWidgets('Matrix 7: Problematic local file and missing URL show graceful SnackBar warnings',
        (tester) async {
      const brokenPaper = ArxivPaper(
        id: 'broken_file_doc',
        title: 'Berkas Rusak',
        authors: ['Penulis'],
        summary: '',
        published: '',
        updated: '',
        categories: [],
        pdfUrl: 'file:///C:/non_existent_folder_abc/file.pdf',
        absUrl: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  MessageContent.handleLinkTap(
                    ctx,
                    'scichat-cite://broken_file_doc?page=1',
                    availablePapers: const [brokenPaper],
                  );
                },
                child: const Text('Buka PDF'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Buka PDF'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Berkas PDF lokal tidak ditemukan pada penyimpanan perangkat'),
        findsOneWidget,
      );
    });

    // 8. Riwayat Chat: serialisasi dan pemulihan chat session
    test('Matrix 8: ChatSession serialization preserves validatedCitationPages; absence of metadata prevents false links', () {
      final originalMessage = ChatMessage(
        id: 'msg_01',
        role: MessageRole.assistant,
        content: 'Hasil dapat dilihat pada [Halaman 4].',
        timestamp: DateTime(2026, 10, 22),
        papers: const [sampleOnlinePaperA],
        validatedCitationPages: const {
          '2005.11401': [4],
        },
      );

      final session = ChatSession(
        id: 'session_01',
        title: 'Riset RAG',
        updatedAt: DateTime(2026, 10, 22),
        messages: [originalMessage],
      );

      final sessionJson = session.toJson();
      final restoredSession = ChatSession.fromJson(sessionJson);
      final restoredMsg = restoredSession.messages.first;

      expect(restoredMsg.validatedCitationPages, isNotNull);
      expect(restoredMsg.validatedCitationPages![sampleOnlinePaperA.id], equals([4]));

      final converted = CitationParser.convertCitationsToLinks(
        restoredMsg.content,
        availablePapers: restoredMsg.papers,
        validatedPagesMap: restoredMsg.validatedCitationPages!.map(
          (k, v) => MapEntry(k, v.toSet()),
        ),
      );
      expect(converted, contains('[Halaman 4](scichat-cite://2005.11401?page=4)'));

      // Uji jika metadata TIDAK tersimpan (pesan lama / legacy)
      final legacyJson = Map<String, dynamic>.from(sessionJson);
      final legacyMessages = (legacyJson['messages'] as List)
          .map((m) => Map<String, dynamic>.from(m as Map)..remove('validatedCitationPages'))
          .toList();
      legacyJson['messages'] = legacyMessages;

      final legacySession = ChatSession.fromJson(legacyJson);
      final legacyMsg = legacySession.messages.first;
      expect(legacyMsg.validatedCitationPages, isNull);

      final legacyConverted = CitationParser.convertCitationsToLinks(
        legacyMsg.content,
        availablePapers: legacyMsg.papers,
        validatedPagesMap: null,
      );
      expect(legacyConverted, equals(legacyMsg.content));
      expect(legacyConverted, isNot(contains('scichat-cite://')));
    });
  });
}
