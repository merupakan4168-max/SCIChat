import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/screens/pdf_viewer_screen.dart';
import 'package:scichat/theme/scichat_theme.dart';

void main() {
  group('Phase 5A: PdfDocumentContext Model & Context Isolation', () {
    test('1. Creates PdfDocumentContext from local file path with URI normalization', () {
      final contextWindows = PdfDocumentContext.fromFile(
        filePath: 'file:///D:/papers/test_paper.pdf',
        title: 'Neuromorphic ECG Paper',
      );

      expect(contextWindows.sourceType, DocumentSourceType.localFile);
      expect(contextWindows.filePath, 'D:/papers/test_paper.pdf');
      expect(contextWindows.title, 'Neuromorphic ECG Paper');
      expect(contextWindows.currentPage, 1);
      expect(contextWindows.isValid, isTrue);

      final contextUnix = PdfDocumentContext.fromFile(
        filePath: 'file:///home/user/paper.pdf',
        title: 'Unix Paper',
      );
      expect(contextUnix.filePath, '/home/user/paper.pdf');
    });

    test('2. Creates PdfDocumentContext from ArxivPaper (Local vs Network)', () {
      const localPaper = ArxivPaper(
        id: 'local_12345',
        title: 'Local ECG Classification.pdf',
        authors: ['Local Author'],
        summary: '',
        published: '2026-01-01',
        updated: '2026-01-01',
        categories: ['Local'],
        pdfUrl: 'file:///D:/papers/ecg.pdf',
        absUrl: '',
      );

      final localCtx = PdfDocumentContext.fromPaper(localPaper);
      expect(localCtx.sourceType, DocumentSourceType.localFile);
      expect(localCtx.filePath, 'D:/papers/ecg.pdf');
      expect(localCtx.documentId, 'local_12345');
      expect(localCtx.paper, equals(localPaper));

      const onlinePaper = ArxivPaper(
        id: '2005.11401',
        title: 'Retrieval-Augmented Generation',
        authors: ['Patrick Lewis'],
        summary: 'We explore RAG models...',
        published: '2020-05-22',
        updated: '2020-05-22',
        categories: ['cs.CL'],
        pdfUrl: 'https://arxiv.org/pdf/2005.11401.pdf',
        absUrl: 'https://arxiv.org/abs/2005.11401',
      );

      final onlineCtx = PdfDocumentContext.fromPaper(onlinePaper);
      expect(onlineCtx.sourceType, DocumentSourceType.networkUrl);
      expect(onlineCtx.url, 'https://arxiv.org/pdf/2005.11401.pdf');
      expect(onlineCtx.documentId, '2005.11401');
    });

    test('3. Creates PdfDocumentContext from in-memory byte buffer', () {
      final fakeBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D]); // %PDF-
      final memCtx = PdfDocumentContext.fromBytes(
        bytes: fakeBytes,
        title: 'In-Memory Paper',
        documentId: 'mem_doc_1',
      );

      expect(memCtx.sourceType, DocumentSourceType.memoryBytes);
      expect(memCtx.bytes, equals(fakeBytes));
      expect(memCtx.documentId, 'mem_doc_1');
      expect(memCtx.isValid, isTrue);
    });

    test('4. Context isolation: documents do not mix page numbers or identities', () {
      final docA = PdfDocumentContext.fromFile(
        filePath: 'D:/papers/docA.pdf',
        title: 'Document A',
        documentId: 'doc_A',
      ).copyWith(pageCount: 12, currentPage: 4);

      final docB = PdfDocumentContext.fromFile(
        filePath: 'D:/papers/docB.pdf',
        title: 'Document B',
        documentId: 'doc_B',
      ).copyWith(pageCount: 30, currentPage: 1);

      expect(docA.documentId, isNot(equals(docB.documentId)));
      expect(docA.pageCount, 12);
      expect(docA.currentPage, 4);
      expect(docB.pageCount, 30);
      expect(docB.currentPage, 1);
    });

    test('5. Validates empty or corrupt context parameters correctly', () {
      const emptyFileCtx = PdfDocumentContext(
        documentId: 'invalid_1',
        title: 'Invalid File',
        sourceType: DocumentSourceType.localFile,
        filePath: '',
      );
      expect(emptyFileCtx.isValid, isFalse);

      const emptyUrlCtx = PdfDocumentContext(
        documentId: 'invalid_2',
        title: 'Invalid URL',
        sourceType: DocumentSourceType.networkUrl,
        url: '',
      );
      expect(emptyUrlCtx.isValid, isFalse);
    });
  });

  group('Phase 5A: PdfViewerScreen Widget & Lifecycle Tests', () {
    Widget buildTestViewer(PdfDocumentContext context) {
      return MaterialApp(
        theme: SciChatTheme.dark,
        home: PdfViewerScreen(documentContext: context),
      );
    }

    testWidgets('1. Displays title, source label, and search/bookmark actions', (tester) async {
      final ctx = PdfDocumentContext.fromFile(
        filePath: 'D:/non_existent_path_test/paper.pdf',
        title: 'SNN Neuromorphic Classification',
      );

      await tester.pumpWidget(buildTestViewer(ctx));
      await tester.pumpAndSettle();

      expect(find.text('SNN Neuromorphic Classification'), findsOneWidget);
      expect(find.text('PDF Lokal'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    });

    testWidgets('2. Displays clean error state when local file does not exist', (tester) async {
      final ctx = PdfDocumentContext.fromFile(
        filePath: 'D:/fake_dir/missing_paper.pdf',
        title: 'Missing File Test',
      );

      await tester.pumpWidget(buildTestViewer(ctx));
      await tester.pumpAndSettle();

      expect(find.text('PDF tidak dapat dimuat langsung'), findsOneWidget);
      expect(
        find.textContaining('Berkas PDF lokal tidak ditemukan pada penyimpanan perangkat'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('3. Toggles search bar when search icon is clicked', (tester) async {
      final ctx = PdfDocumentContext.fromFile(
        filePath: 'D:/fake_dir/missing_paper.pdf',
        title: 'Search UI Test',
      );

      await tester.pumpWidget(buildTestViewer(ctx));
      await tester.pumpAndSettle();

      // Search bar not open initially
      expect(find.text('Cari dalam dokumen...'), findsNothing);

      // Tap search action
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      // Search bar is now open
      expect(find.text('Cari dalam dokumen...'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Close search bar
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Cari dalam dokumen...'), findsNothing);
    });

    testWidgets('4. Disposes cleanly without controller or listener leaks', (tester) async {
      final ctx = PdfDocumentContext.fromFile(
        filePath: 'D:/fake_dir/missing_paper.pdf',
        title: 'Disposal Test',
      );

      await tester.pumpWidget(buildTestViewer(ctx));
      await tester.pumpAndSettle();

      // Replace widget with empty container to trigger dispose()
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Done'))));
      await tester.pumpAndSettle();

      expect(find.text('Done'), findsOneWidget);
    });
  });
}
