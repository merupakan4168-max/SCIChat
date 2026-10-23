import 'dart:convert';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Helper to generate real, valid PDF bytes entirely in-memory using Syncfusion.
List<int> _createSamplePdfBytes(String text) {
  final document = PdfDocument();
  final page = document.pages.add();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 10);
  page.graphics.drawString(
    text,
    font,
    bounds: const Rect.fromLTWH(0, 0, 500, 700),
  );
  final bytes = document.saveSync();
  document.dispose();
  return bytes;
}

ArxivPaper createTestPaper({
  required String id,
  required String title,
  String summary = 'Valid summary for test paper context.',
  String pdfUrl = 'https://arxiv.org/pdf/test.pdf',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: const ['Test Author'],
    summary: summary,
    published: '2024-01-01',
    updated: '2024-01-01',
    categories: const ['cs.AI'],
    pdfUrl: pdfUrl,
    absUrl: 'https://arxiv.org/abs/$id',
  );
}

/// Mock subclass that only overrides legacy extractTextFromBytes and extractTextFromUrl
class LegacyMockPdfService extends PdfService {
  int extractUrlCallCount = 0;
  int extractBytesCallCount = 0;
  String? mockUrlText;
  String? mockBytesText;

  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 40000}) async {
    extractUrlCallCount++;
    return mockUrlText;
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 40000}) async {
    extractBytesCallCount++;
    return mockBytesText;
  }
}

void main() {
  group('Phase 4D.4: PDF Extraction Completeness and Truncation Awareness', () {
    late PdfService pdfService;

    setUp(() {
      pdfService = PdfService();
    });

    // -------------------------------------------------------------------------
    // 1. Text shorter than cap is marked complete, not truncated
    // -------------------------------------------------------------------------
    test('1. Text shorter than cap is marked complete with exact lengths', () async {
      const sampleText = 'Introduction to Neural Information Retrieval and BM25 Ranking';
      final pdfBytes = _createSamplePdfBytes(sampleText);

      // Batas lebih besar dari panjang teks
      final result = await pdfService.extractBytesWithMetadata(pdfBytes, maxChars: 5000);

      expect(result, isNotNull);
      expect(result!.isTruncated, isFalse);
      expect(result.metadata.completeness, equals(PdfExtractionCompleteness.complete));
      expect(result.metadata.retainedLength, equals(result.text.length));
      expect(result.metadata.totalExtractedLength, equals(result.text.length));
      expect(result.metadata.retainedTextLength, equals(result.text.length));
      expect(result.metadata.totalExtractedTextLength, equals(result.text.length));
      expect(result.text, contains('Neural Information Retrieval'));
      expect(result.text, isNot(contains('[TEXT TRUNCATED DUE TO LENGTH]')));
    });

    // -------------------------------------------------------------------------
    // 2. Text longer than cap is marked truncated and reports correct retained & total lengths
    // -------------------------------------------------------------------------
    test('2. Text longer than cap is marked truncated and reports retained vs total lengths', () async {
      // Buat dokumen dengan teks panjang
      final longText = 'Section 1. Core Methodology and Algorithmic Analysis. ' * 50;
      final pdfBytes = _createSamplePdfBytes(longText);

      const cap = 200;
      final result = await pdfService.extractBytesWithMetadata(pdfBytes, maxChars: cap);

      expect(result, isNotNull);
      expect(result!.isTruncated, isTrue);
      expect(result.metadata.completeness, equals(PdfExtractionCompleteness.truncated));
      expect(result.metadata.retainedLength, equals(cap));
      expect(result.metadata.totalExtractedLength, greaterThan(cap));
      expect(result.text.length, equals(cap));
      // Teks hasil extractBytesWithMetadata tidak disisipi sentinel string
      expect(result.text, isNot(contains('[TEXT TRUNCATED DUE TO LENGTH]')));

      // Namun legacy extractTextFromBytes tetap menambahkan sentinel demi backward-compatibility
      final legacyText = await pdfService.extractTextFromBytes(pdfBytes, maxChars: cap);
      expect(legacyText, isNotNull);
      expect(legacyText, contains('[TEXT TRUNCATED DUE TO LENGTH]'));
    });

    // -------------------------------------------------------------------------
    // 3. Empty input and extraction failure safety
    // -------------------------------------------------------------------------
    test('3. Empty bytes and non-PDF bytes return null safely', () async {
      final emptyResult = await pdfService.extractBytesWithMetadata([]);
      expect(emptyResult, isNull);

      final garbageResult = await pdfService.extractBytesWithMetadata([1, 2, 3, 4, 5]);
      expect(garbageResult, isNull);

      final corruptBytes = utf8.encode('%PDF-1.4\nCorrupted content without valid xref or trailer');
      final corruptResult = await pdfService.extractBytesWithMetadata(corruptBytes);
      expect(corruptResult, isNull);
    });

    // -------------------------------------------------------------------------
    // 4. Prompt construction reflects truncated vs complete vs unknown status
    // -------------------------------------------------------------------------
    test('4. Prompt construction reflects truncated vs complete vs unknown status', () {
      final paper = createTestPaper(
        id: '2401.0001',
        title: 'Document Extraction Benchmark Study',
        summary: 'Makalah analisis ekstraksi dokumen ilmiah.',
      );

      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Abstract and methodology overview for language modeling evaluation.',
          sectionTitle: 'Methodology',
          charOffset: 0,
        ),
      ];

      // A. Truncated Evidence
      final truncatedEvidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Methodology text',
        chunks: chunks,
        extractionMetadata: const PdfExtractionMetadata.truncated(
          retained: 48000,
          total: 85000,
        ),
      );

      final promptTruncated = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: truncatedEvidence,
        userQuery: 'metodologi evaluasi',
      );

      expect(promptTruncated, contains('Kelengkapan Ekstraksi: Terpotong (48000 dari 85000 karakter diekstrak'));
      expect(promptTruncated, contains('Perhatian Pemotongan:'));
      expect(promptTruncated, contains('JANGAN mengklaim telah membaca bagian yang terpotong'));

      // B. Complete Evidence
      final completeEvidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Methodology text',
        chunks: chunks,
        extractionMetadata: const PdfExtractionMetadata.complete(32000),
      );

      final promptComplete = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: completeEvidence,
        userQuery: 'metodologi evaluasi',
      );

      expect(promptComplete, contains('Kelengkapan Ekstraksi: Dokumen Lengkap (32000 karakter).'));
      expect(promptComplete, isNot(contains('Kelengkapan Ekstraksi: Terpotong')));
      expect(promptComplete, isNot(contains('Perhatian Pemotongan:')));

      // C. Legacy / Unknown Evidence (extractionMetadata is null)
      final legacyEvidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Methodology text',
        chunks: chunks,
      );

      final promptLegacy = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: legacyEvidence,
        userQuery: 'metodologi evaluasi',
      );

      expect(promptLegacy, isNot(contains('Kelengkapan Ekstraksi: Terpotong')));
      expect(promptLegacy, isNot(contains('Perhatian Pemotongan:')));
      expect(promptLegacy, contains('Status Bukti: Ditemukan'));
    });

    // -------------------------------------------------------------------------
    // 5. Multi-paper prompt reflects per-paper completeness
    // -------------------------------------------------------------------------
    test('5. Multi-paper prompt reflects per-paper extraction completeness', () {
      final paper1 = createTestPaper(id: 'paper1', title: 'Complete Paper');
      final paper2 = createTestPaper(id: 'paper2', title: 'Truncated Paper');
      final paper3 = createTestPaper(id: 'paper3', title: 'Legacy Paper');

      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Deep learning techniques for multi-modal synthesis.',
          sectionTitle: 'Approach',
          charOffset: 0,
        ),
      ];

      final evidenceMap = {
        'paper1': PaperEvidence(
          level: EvidenceLevel.fullText,
          extractedText: 'Text 1',
          chunks: chunks,
          extractionMetadata: const PdfExtractionMetadata.complete(25000),
        ),
        'paper2': PaperEvidence(
          level: EvidenceLevel.fullText,
          extractedText: 'Text 2',
          chunks: chunks,
          extractionMetadata: const PdfExtractionMetadata.truncated(
            retained: 48000,
            total: 92000,
          ),
        ),
        'paper3': PaperEvidence(
          level: EvidenceLevel.fullText,
          extractedText: 'Text 3',
          chunks: chunks,
        ),
      };

      final multiPrompt = SciChatProvider.buildMultiPaperContextPrompt(
        papers: [paper1, paper2, paper3],
        evidenceMap: evidenceMap,
        userQuery: 'multi-modal synthesis',
      );

      expect(multiPrompt, contains('Makalah [1]:'));
      expect(multiPrompt, contains('Kelengkapan Ekstraksi: Lengkap (25000 karakter).'));

      expect(multiPrompt, contains('Makalah [2]:'));
      expect(multiPrompt, contains('Kelengkapan Ekstraksi: Terpotong (48000/92000 karakter).'));
      expect(multiPrompt, contains('Jangan menyimpulkan ketiadaan detail pada seksi yang terpotong.'));

      expect(multiPrompt, contains('Makalah [3]:'));
      // Paper 3 tanpa metadata tidak menghasilkan crash dan tidak menampilkan klaim palsu
      expect(multiPrompt, contains('Status Evidence: Full Text Tersedia'));
    });

    // -------------------------------------------------------------------------
    // 6. Preservation of Phase 4D.3 fallback behavior under noMatches
    // -------------------------------------------------------------------------
    test('6. Phase 4D.3 fallback behavior is preserved with truncated evidence', () {
      final paper = createTestPaper(
        id: '2401.0003',
        title: 'Sparse Attention Networks',
        summary: 'Ringkasan arsitektur sparse attention.',
      );

      final chunks = [
        const PdfChunk(
          id: 'c_meth',
          text: 'Methodology: We implement sparse pattern attention blocks with linear memory.',
          sectionTitle: 'Methodology',
          charOffset: 0,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Methodology: We implement sparse pattern attention blocks.',
        chunks: chunks,
        extractionMetadata: const PdfExtractionMetadata.truncated(
          retained: 48000,
          total: 70000,
        ),
      );

      // Kueri yang tidak cocok leksikal
      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'hardware satelit orbit bumi geostasioner 5G',
      );

      // Verifikasi keterpotongan tetap diungkapkan
      expect(prompt, contains('Kelengkapan Ekstraksi: Terpotong'));
      // Verifikasi netralitas Phase 4D.3 tetap utuh (TIDAK ADA penolakan mutlak)
      expect(prompt, isNot(contains('dan nyatakan bahwa rincian spesifik tidak ditemukan')));
      expect(prompt, contains('Catatan Konteks: Cuplikan dokumen di bawah ini disediakan sebagai konteks cadangan'));
      expect(prompt, contains('belum dapat dipastikan dari cuplikan teks yang tersedia untuk model saat ini'));
      expect(prompt, contains('[Konteks Cadangan - Bagian: Methodology]'));
    });

    // -------------------------------------------------------------------------
    // 7. Cache isolation across different maxChars limits
    // -------------------------------------------------------------------------
    test('7. Cache key distinguishes maxChars and prevents reusing stale truncated evidence', () {
      final paper = createTestPaper(
        id: '2401.0004',
        title: 'Cache Partition Test Paper',
      );

      final key8k = SciChatProvider.buildEvidenceKey(paper, maxChars: 8000);
      final key48k = SciChatProvider.buildEvidenceKey(paper, maxChars: 48000);

      expect(key8k, contains('maxChars::8000'));
      expect(key48k, contains('maxChars::48000'));
      expect(key8k, isNot(equals(key48k)));
    });

    // -------------------------------------------------------------------------
    // 8. Backward compatibility for mock/subclassed PdfService
    // -------------------------------------------------------------------------
    test('8. Subclassed PdfService that only overrides legacy methods works with extractBytesWithMetadata', () async {
      final mock = LegacyMockPdfService();
      mock.mockBytesText = 'Extracted text from legacy mock override';
      mock.mockUrlText = 'Extracted text from legacy url override';

      final byteResult = await mock.extractBytesWithMetadata([10, 20, 30], maxChars: 1000);
      expect(byteResult, isNotNull);
      expect(mock.extractBytesCallCount, equals(1));
      expect(byteResult!.text, equals('Extracted text from legacy mock override'));
      expect(byteResult.isTruncated, isFalse);
      expect(byteResult.metadata.completeness, equals(PdfExtractionCompleteness.complete));

      final urlResult = await mock.extractUrlWithMetadata('https://example.com/test.pdf', maxChars: 1000);
      expect(urlResult, isNotNull);
      expect(mock.extractUrlCallCount, equals(1));
      expect(urlResult!.text, equals('Extracted text from legacy url override'));

      // Jika legacy mock mengembalikan sentinel [TEXT TRUNCATED DUE TO LENGTH]
      mock.mockBytesText = 'Part of text\n\n[TEXT TRUNCATED DUE TO LENGTH]';
      final truncatedMockResult = await mock.extractBytesWithMetadata([10, 20], maxChars: 1000);
      expect(truncatedMockResult, isNotNull);
      expect(truncatedMockResult!.isTruncated, isTrue);
      expect(truncatedMockResult.metadata.completeness, equals(PdfExtractionCompleteness.truncated));
      expect(truncatedMockResult.text, equals('Part of text'));
    });

    // -------------------------------------------------------------------------
    // 9. Production cap evaluation
    // -------------------------------------------------------------------------
    test('9. Production cap kChatEvidenceMaxChars remains 48000 and is transparently bounded', () {
      expect(SciChatProvider.kChatEvidenceMaxChars, equals(48000));
    });
  });
}
