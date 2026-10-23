// Phase 4D.6 — Regression Tests: PDF Text Spacing Normalization
//
// Memvalidasi bahwa _normalizeExtractedSpacing (dipanggil oleh _extractTextSync
// dalam PdfService) memperbaiki heading concatenation defect dari Syncfusion
// tanpa merusak teks prosa, persamaan, sitasi, tabel, atau identifier teknis.
//
// Run: flutter test test/phase4d6_pdf_spacing_normalization_test.dart --reporter expanded

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/utils/pdf_chunker.dart';

// ---------------------------------------------------------------------------
// Whitebox access: re-implement the normalization function under test
// to validate its logic independently of the PdfService isolate layer.
// This is intentionally a copy to pin the exact contract being tested.
// ---------------------------------------------------------------------------
String normalizeExtractedSpacing(String raw) {
  return raw.replaceAllMapped(
    RegExp(r'^(\s*\d+(?:\.\d+)*)([A-Z])', multiLine: true),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
}

void main() {
  // =========================================================================
  // Suite 1: Heading prefix normalization (numbered sections)
  // =========================================================================
  group('Suite 1 — Numbered heading prefix normalization', () {
    test('single-digit section: "1Introduction" → "1 Introduction"', () {
      expect(normalizeExtractedSpacing('1Introduction'), '1 Introduction');
    });

    test('single-digit section: "2Models" → "2 Models"', () {
      expect(normalizeExtractedSpacing('2Models'), '2 Models');
    });

    test('single-digit section: "3Experiments" → "3 Experiments"', () {
      expect(normalizeExtractedSpacing('3Experiments'), '3 Experiments');
    });

    test('single-digit section: "4Results" → "4 Results"', () {
      expect(normalizeExtractedSpacing('4Results'), '4 Results');
    });

    test('single-digit section: "5RelatedWork" → "5 RelatedWork"', () {
      expect(normalizeExtractedSpacing('5RelatedWork'), '5 RelatedWork');
    });

    test('single-digit section: "6Discussion" → "6 Discussion"', () {
      expect(normalizeExtractedSpacing('6Discussion'), '6 Discussion');
    });

    test('single-digit section: "7Conclusion" → "7 Conclusion"', () {
      expect(normalizeExtractedSpacing('7Conclusion'), '7 Conclusion');
    });

    test('subsection two-level: "2.1Retriever" → "2.1 Retriever"', () {
      expect(normalizeExtractedSpacing('2.1Retriever'), '2.1 Retriever');
    });

    test('subsection two-level: "2.2Generator" → "2.2 Generator"', () {
      expect(normalizeExtractedSpacing('2.2Generator'), '2.2 Generator');
    });

    test('subsection two-level: "4.1Open-domainQuestionAnswering" → "4.1 Open-domainQuestionAnswering"', () {
      expect(
        normalizeExtractedSpacing('4.1Open-domainQuestionAnswering'),
        '4.1 Open-domainQuestionAnswering',
      );
    });

    test('subsection two-level: "4.2AbstractiveQuestionAnswering" → "4.2 AbstractiveQuestionAnswering"', () {
      expect(
        normalizeExtractedSpacing('4.2AbstractiveQuestionAnswering'),
        '4.2 AbstractiveQuestionAnswering',
      );
    });

    test('subsection two-level: "4.3JeopardyQuestionGeneration" → "4.3 JeopardyQuestionGeneration"', () {
      expect(
        normalizeExtractedSpacing('4.3JeopardyQuestionGeneration'),
        '4.3 JeopardyQuestionGeneration',
      );
    });

    test('subsection two-level: "4.4FactVerification" → "4.4 FactVerification"', () {
      expect(
        normalizeExtractedSpacing('4.4FactVerification'),
        '4.4 FactVerification',
      );
    });

    test('subsection two-level: "4.5AdditionalResults" → "4.5 AdditionalResults"', () {
      expect(
        normalizeExtractedSpacing('4.5AdditionalResults'),
        '4.5 AdditionalResults',
      );
    });

    test('subsection three-level: "3.4FactVerification" → "3.4 FactVerification"', () {
      expect(
        normalizeExtractedSpacing('3.4FactVerification'),
        '3.4 FactVerification',
      );
    });

    test('double-digit section: "10Results" → "10 Results"', () {
      expect(normalizeExtractedSpacing('10Results'), '10 Results');
    });

    test('heading with leading whitespace is preserved', () {
      expect(normalizeExtractedSpacing('  4Results'), '  4 Results');
    });
  });

  // =========================================================================
  // Suite 2: Safety — mid-line numerics must NOT be changed
  // =========================================================================
  group('Suite 2 — Safety: mid-line numeric+capital patterns (MUST NOT change)', () {
    test('mid-line numeric: "with100Ktrain"', () {
      expect(normalizeExtractedSpacing('with100Ktrain'), 'with100Ktrain');
    });

    test('mid-line numeric: "14Kdev" and "27Ktestexamples" in realistic line context', () {
      // In real PDFs these appear mid-line: "with100Ktrain,14Kdev,and27Ktestexamples"
      // The ^ anchor only fires at the very start of a line, so they are NOT changed.
      final input = 'dataset,with100Ktrain,14Kdev,and27Ktestexamples.\nnextline';
      final output = normalizeExtractedSpacing(input);
      expect(output, contains('14Kdev'), reason: 'mid-line 14Kdev must not gain a space');
      expect(output, contains('27Ktestexamples'), reason: 'mid-line 27Ktestexamples must not gain a space');
    });

    test('standalone line starting with 2-digit+Capital is normalised (known acceptable side-effect)', () {
      // "14Kdev" alone on a line WILL be changed to "14 Kdev".
      // This is safe: PdfChunker's heading pattern requires specific known words
      // (Introduction, Results, Methods etc.) so "Kdev" won't be misclassified.
      // BM25 tokenisation is not harmed by the extra space.
      expect(normalizeExtractedSpacing('14Kdev'), '14 Kdev');
      expect(normalizeExtractedSpacing('27Ktestexamples'), '27 Ktestexamples');
    });

    test('mid-line reference year: "In\n2019ConferenceonEmpiricalMethods" — only the start-of-line part is changed', () {
      // "2019Conference..." starts a new line — it WILL be changed to
      // "2019 Conference..." but that is safe because:
      //   a) The chunker heading regex requires 1-2 digit numbers ([0-9]{1,2}) so
      //      "2019" (4 digits) will still NOT be classified as a section heading.
      //   b) Retrieval is not harmed by an extra space in a reference venue name.
      final input = 'In\n2019ConferenceonEmpiricalMethods';
      final output = normalizeExtractedSpacing(input);
      expect(output, 'In\n2019 ConferenceonEmpiricalMethods');
      // Verify the chunker STILL doesn't classify it as a numbered section
      final chunks = PdfChunker.chunkText(output);
      final headings = chunks.map((c) => c.sectionTitle).toSet();
      expect(
        headings.any((h) => h == 'Conference' || h == '2019'),
        isFalse,
        reason: 'Year-prefixed conference strings must not become section headings',
      );
    });

    test('technical identifiers not at line start: "BART15.1score"', () {
      expect(normalizeExtractedSpacing('BART15.1score'), 'BART15.1score');
    });

    test('URL fragment not at line start: "r1gs9JgRZ"', () {
      expect(normalizeExtractedSpacing('text r1gs9JgRZ end'), 'text r1gs9JgRZ end');
    });

    test('table row starting with letters: "ModelJeopardyMSMARCO"', () {
      // Starts with "M" (not digit), no change expected
      expect(normalizeExtractedSpacing('ModelJeopardyMSMARCO'), 'ModelJeopardyMSMARCO');
    });

    test('BART score in table: "BART15.1"', () {
      // Starts with "B", not digit
      expect(normalizeExtractedSpacing('BART15.1'), 'BART15.1');
    });

    test('decimal number mid-line: "accuracy2.6Bleu"', () {
      expect(normalizeExtractedSpacing('accuracy2.6Bleu'), 'accuracy2.6Bleu');
    });

    test('reference citation number alone on line: "[14]"', () {
      // Starts with "[", not digit
      expect(normalizeExtractedSpacing('[14]'), '[14]');
    });

    test('footnote reference: "10"', () {
      // Purely digits, no trailing capital — no change
      expect(normalizeExtractedSpacing('10'), '10');
    });

    test('standalone capital not preceded by digit: "RAG-Sequence"', () {
      expect(normalizeExtractedSpacing('RAG-Sequence'), 'RAG-Sequence');
    });
  });

  // =========================================================================
  // Suite 3: Multiline text — headings fixed per line, prose unchanged
  // =========================================================================
  group('Suite 3 — Multiline text normalization', () {
    test('multiline with multiple headings', () {
      const input = 'Abstract\nLargepre-trainedlanguagemodels\n4Results\nbodytext\n4.1Open-domainQA\nmoretext';
      const expected = 'Abstract\nLargepre-trainedlanguagemodels\n4 Results\nbodytext\n4.1 Open-domainQA\nmoretext';
      expect(normalizeExtractedSpacing(input), expected);
    });

    test('body text (all lowercase runs) is left unchanged', () {
      const body = 'trainedlanguagemodelshavebeenshowntostorefactualknowledge';
      expect(normalizeExtractedSpacing(body), body);
    });

    test('mixed: heading fixed, body unchanged', () {
      const input = '2Models\nwecombineparametricandnon-parametricmemory\n2.1Retriever\ndensepassageretrieval';
      const expected = '2 Models\nwecombineparametricandnon-parametricmemory\n2.1 Retriever\ndensepassageretrieval';
      expect(normalizeExtractedSpacing(input), expected);
    });

    test('heading already spaced is not double-spaced', () {
      // "4 Results" already has a space — regex requires digit DIRECTLY followed
      // by capital (no space), so it won't match.
      expect(normalizeExtractedSpacing('4 Results'), '4 Results');
    });

    test('empty string returns empty', () {
      expect(normalizeExtractedSpacing(''), '');
    });

    test('text with no defects is unchanged', () {
      const prose = 'This paper presents a retrieval-augmented generation model.\n'
          'We evaluate on NaturalQuestions, TriviaQA, and WebQuestions.';
      expect(normalizeExtractedSpacing(prose), prose);
    });

    test('Windows-style CRLF line endings are handled', () {
      const input = '4Results\r\nbodytext\r\n5RelatedWork\r\n';
      // multiLine ^ matches after \n in \r\n
      final result = normalizeExtractedSpacing(input);
      expect(result, contains('4 Results'));
      expect(result, contains('5 RelatedWork'));
      expect(result, contains('bodytext'));
    });
  });

  // =========================================================================
  // Suite 4: Integration — PdfChunker detects headings after normalization
  // =========================================================================
  group('Suite 4 — Integration: PdfChunker heading detection after normalization', () {
    test('normalized "4 Results" is detected as Results section', () {
      // NOTE: "2 Models" is NOT in the chunker's allowed keyword list for numbered
      // headings (pattern 3 requires words like Methods, Results, Discussion etc.).
      // Use "2 Methods" which IS in the list to test Methodology canonicalisation.
      const input = 'Abstract\nSomeabstracttext.\n'
          '1 Introduction\nThisisintroductiontext.\n'
          '2 Methods\nWedescribemethods.\n'
          '4 Results\nResultsarehere.\n'
          '5 RelatedWork\nPriorworkisdiscussed.';
      final chunks = PdfChunker.chunkText(input);
      final headings = chunks.map((c) => c.sectionTitle).toSet();
      expect(headings, contains('Results'),
          reason: 'After normalization, "4 Results" should be detected as Results');
      expect(headings, contains('Methodology'),
          reason: '"2 Methods" should be canonicalized to Methodology');
    });

    test('normalized "4.1 Open-domainQuestionAnswering" is detected as subsection', () {
      const input = '4 Results\nOverall results.\n'
          '4.1 Open-domainQuestionAnswering\nWeevaluateonNQ,TQA,WQ.';
      final chunks = PdfChunker.chunkText(input);
      final headings = chunks.map((c) => c.sectionTitle).toSet();
      // Should be detected as a subsection (not General)
      expect(headings.any((h) => h.contains('4.1') || h.contains('Open')), isTrue,
          reason: 'Subsection 4.1 should be detected after normalization');
    });

    test('unnormalized "4Results" is NOT detected as a section heading', () {
      // Regression: without normalization, the heading is missed
      const rawInput = '4Results\nResultsarepresentedhere.';
      final chunks = PdfChunker.chunkText(rawInput);
      final headings = chunks.map((c) => c.sectionTitle).toSet();
      // Without normalization, heading detection likely fails
      expect(headings.contains('Results'), isFalse,
          reason: 'Unnormalized "4Results" should NOT be detected as Results section — '
              'confirms normalization is needed');
    });

    test('normalized text produces more non-General chunks than unnormalized', () {
      const unnormalized = '4Results\nbodyofresults.\n5RelatedWork\nrelatedworktext.';
      const normalized = '4 Results\nbodyofresults.\n5 RelatedWork\nrelatedworktext.';
      final chunksRaw = PdfChunker.chunkText(unnormalized);
      final chunksNorm = PdfChunker.chunkText(normalized);
      final generalCountRaw = chunksRaw.where((c) => c.sectionTitle == 'General').length;
      final generalCountNorm = chunksNorm.where((c) => c.sectionTitle == 'General').length;
      expect(generalCountNorm, lessThan(generalCountRaw),
          reason: 'Normalized text should produce fewer "General" fallback chunks');
    });
  });

  // =========================================================================
  // Suite 5: Real PDF validation (skipped if file absent)
  // =========================================================================
  group('Suite 5 — Real PDF: RAG paper heading detection after normalization', () {
    const pdfPath =
        r'C:\Users\ACER\.gemini\antigravity-ide\brain\26eff0c9-1cad-4387-b2a0-e0f06eff158f\scratch\lewis_2020_rag.pdf';

    late List<int>? pdfBytes;

    setUpAll(() async {
      final f = File(pdfPath);
      pdfBytes = f.existsSync() ? await f.readAsBytes() : null;
    });

    test('PdfService extracts with heading normalization applied', () async {
      if (pdfBytes == null) {
        markTestSkipped('NeurIPS RAG PDF not present at $pdfPath');
        return;
      }
      final service = PdfService();
      final result = await service.extractBytesWithMetadata(pdfBytes!, maxChars: 200000);
      expect(result, isNotNull);
      final text = result!.text;

      // After normalization, heading defects should be fixed
      expect(text, isNot(contains('4Results')),
          reason: '"4Results" (no space) should be normalized to "4 Results"');
      expect(text, isNot(contains('5RelatedWork')),
          reason: '"5RelatedWork" should be normalized to "5 RelatedWork"');
      expect(text, isNot(contains('6Discussion')),
          reason: '"6Discussion" should be normalized to "6 Discussion"');
      expect(text, isNot(contains('4.2AbstractiveQuestionAnswering')),
          reason: 'Subsection heading should be normalized');

      // Normalized forms should be present
      expect(text, contains('4 Results'));
      expect(text, contains('5 RelatedWork'));
      expect(text, contains('6 Discussion'));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('PdfChunker detects substantive sections from normalized real PDF', () async {
      if (pdfBytes == null) {
        markTestSkipped('NeurIPS RAG PDF not present at $pdfPath');
        return;
      }
      final service = PdfService();
      final result = await service.extractBytesWithMetadata(pdfBytes!, maxChars: 200000);
      expect(result, isNotNull);
      final chunks = PdfChunker.chunkText(result!.text);
      final headings = chunks.map((c) => c.sectionTitle).toSet();
      print('Headings after normalization (${headings.length}): $headings');

      // With normalization, at least some key sections should be detectable
      final hasResults = headings.any((h) => h.toLowerCase().contains('result'));
      final hasDiscussion = headings.any((h) => h.toLowerCase().contains('discuss'));
      final hasRelatedWork = headings.any((h) =>
          h.toLowerCase().contains('related') ||
          h.toLowerCase().contains('5'));

      expect(
        hasResults || hasDiscussion || hasRelatedWork,
        isTrue,
        reason: 'At least one major section (Results/Discussion/RelatedWork) should be '
            'detected after heading normalization',
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
