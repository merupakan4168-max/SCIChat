import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/utils/pdf_chunker.dart';

void main() {
  group('PdfChunker — Input Boundary & Edge Case Tests', () {
    test('returns empty list for null, empty, or whitespace-only text', () {
      expect(PdfChunker.chunkText(null), isEmpty);
      expect(PdfChunker.chunkText(''), isEmpty);
      expect(PdfChunker.chunkText('   \n\t  \r\n   '), isEmpty);
    });

    test('handles very short text gracefully in a single chunk', () {
      const shortText = 'Quantum entanglement remains a fundamental mystery of modern physics.';
      final chunks = PdfChunker.chunkText(shortText);

      expect(chunks.length, equals(1));
      expect(chunks.first.text, equals(shortText));
      expect(chunks.first.sectionTitle, equals('General'));
      expect(chunks.first.charOffset, equals(0));
      expect(chunks.first.pageNumber, equals(PdfChunk.kUnknownPage));
    });

    test('preserves Unicode characters, Greek symbols, and hyphenated terms', () {
      const unicodeText = '''
Abstract
We investigate state-of-the-art transformer architectures with multi-head self-attention.
The learning rate schedule satisfies α_t = α_0 / (1 + β · t) with asymptotic complexity O(n · log(n)).
Experimental evaluations demonstrate significant improvements across multilingual benchmarks: 
Bahasa Indonesia, Français, and 中文.
''';

      final chunks = PdfChunker.chunkText(unicodeText);

      expect(chunks, isNotEmpty);
      final firstChunk = chunks.first;
      expect(firstChunk.sectionTitle, equals('Abstract'));
      expect(firstChunk.text, contains('state-of-the-art'));
      expect(firstChunk.text, contains('multi-head'));
      expect(firstChunk.text, contains('α_t = α_0 / (1 + β · t)'));
      expect(firstChunk.text, contains('O(n · log(n))'));
      expect(firstChunk.text, contains('Bahasa Indonesia'));
      expect(firstChunk.text, contains('Français'));
      expect(firstChunk.text, contains('中文'));
    });
  });

  group('PdfChunker — Academic Headings & Numbering Variations', () {
    test('detects and canonicalizes standard academic headings', () {
      const paperText = '''
Title: Deep Scientific Language Models
Authors: Turing et al.

Abstract
Recent breakthroughs in foundation models have reshaped scientific natural language processing.

Introduction
Scientific discovery requires synthesizing evidence across vast distributed document repositories.

Related Work
Prior efforts focused primarily on dense vector embeddings and keyword indexing.

Methodology
We formulate our research as a multi-stage evidence retrieval pipeline.

Results
Our proposed model achieves an accuracy of 94.2% on the standard benchmark.

Discussion
These findings highlight the critical trade-off between prompt length and citation accuracy.

Conclusion
In summary, local context chunking provides a scalable foundation for academic assistants.

Limitations
The primary limitation is the dependency on clean optical character recognition for scans.
''';

      final chunks = PdfChunker.chunkText(paperText);

      expect(chunks.length, greaterThanOrEqualTo(8));
      final sectionTitles = chunks.map((c) => c.sectionTitle).toSet();

      expect(sectionTitles, contains('Header'));
      expect(sectionTitles, contains('Abstract'));
      expect(sectionTitles, contains('Introduction'));
      expect(sectionTitles, contains('Related Work'));
      expect(sectionTitles, contains('Methodology'));
      expect(sectionTitles, contains('Results'));
      expect(sectionTitles, contains('Discussion'));
      expect(sectionTitles, contains('Conclusion'));
      expect(sectionTitles, contains('Limitations'));
    });

    test('handles numbered headings with dots, decimals, and Roman numerals', () {
      const numberedText = '''
1. Introduction
This is the introductory section covering historical background and motivation.

2.1 Methods
Our empirical methods involve controlled randomized experiments across datasets.

III. METHODOLOGY
Detailed mathematical derivations are presented for model convergence.

4. Experiments and Evaluation
We conduct comprehensive ablation studies on three benchmark suites.

5. RESULTS
Empirical findings demonstrate substantial latency reductions.

VI. CONCLUSIONS AND FUTURE WORK
We summarize the key takeaways and future research directions.
''';

      final chunks = PdfChunker.chunkText(numberedText);

      expect(chunks, isNotEmpty);
      final sectionTitles = chunks.map((c) => c.sectionTitle).toList();

      expect(sectionTitles, contains('Introduction'));
      expect(sectionTitles, contains('Methodology'));
      expect(sectionTitles, contains('Experiments'));
      expect(sectionTitles, contains('Results'));
      expect(sectionTitles, contains('Conclusion'));
    });
  });

  group('PdfChunker — Fallback for Documents Without Headings', () {
    test('chunks non-heading documents using paragraph-based sliding window', () {
      final paragraph = 'This is a long scientific paragraph discussing empirical observations in astronomy. ' * 8;
      final textWithoutHeadings = '$paragraph\n\n$paragraph\n\n$paragraph\n\n$paragraph';

      final chunks = PdfChunker.chunkText(textWithoutHeadings, targetChunkSize: 1000, overlapSize: 150);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.sectionTitle, equals('General'));
        expect(chunk.text.trim(), isNotEmpty);
      }
    });
  });

  group('PdfChunker — Chunk Size, Overlap & End-of-Document Preservation', () {
    test('enforces chunk size targets and generates overlap between consecutive sub-chunks', () {
      final longSection =
          '1. Introduction\n${'Deep neural networks require careful hyperparameter tuning and extensive validation. ' * 40}';

      const targetSize = 1200;
      const overlapSize = 180;
      final chunks = PdfChunker.chunkText(longSection, targetChunkSize: targetSize, overlapSize: overlapSize);

      expect(chunks.length, greaterThanOrEqualTo(2));

      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        expect(chunk.sectionTitle, equals('Introduction'));
        expect(chunk.text.length, lessThanOrEqualTo(targetSize + 250)); // Allow reasonable sentence boundary flexibility
      }

      // Check overlap between consecutive chunks
      for (int i = 0; i < chunks.length - 1; i++) {
        final currentChunk = chunks[i].text;
        final nextChunk = chunks[i + 1].text;

        // Take last 50 chars of current chunk
        final currentTail = currentChunk.substring(currentChunk.length - 50);
        // Next chunk should contain some overlap or start near the tail
        final wordsInTail = currentTail.split(' ').where((w) => w.length > 4).toList();
        final hasCommonWord = wordsInTail.any((w) => nextChunk.contains(w));
        expect(hasCommonWord, isTrue, reason: 'Consecutive chunks must share overlapping context');
      }
    });

    test('preserves end of document without silent truncation', () {
      const sentinelEnd = 'FINAL_CONCLUSION_SENTINEL_2026: The hypothesis is completely verified.';
      final fullDocument =
          '${'Scientific paragraph detailing methodology and numerical simulations. ' * 60}\n\n7. Conclusion\n$sentinelEnd';

      final chunks = PdfChunker.chunkText(fullDocument, targetChunkSize: 1000);

      expect(chunks, isNotEmpty);
      final lastChunk = chunks.last;
      expect(lastChunk.text, contains(sentinelEnd), reason: 'End of input document must never be silently truncated');
    });

    test('maintains strictly monotonic charOffset matching original text', () {
      const fullText = '''
Abstract
This is the abstract.

1. Introduction
This is the introduction paragraph with foundational background information.

2. Methods
Here we describe the experimental procedure and simulation parameters.
''';

      final chunks = PdfChunker.chunkText(fullText);

      expect(chunks.length, greaterThanOrEqualTo(3));

      int previousOffset = -1;
      for (final chunk in chunks) {
        expect(chunk.charOffset, greaterThan(previousOffset));
        expect(chunk.charOffset, greaterThanOrEqualTo(0));
        previousOffset = chunk.charOffset;

        // Verify charOffset correctly locates the start of the chunk text
        final textAtOffset = fullText.substring(chunk.charOffset);
        expect(textAtOffset.startsWith(chunk.text.substring(0, 15)), isTrue,
            reason: 'charOffset must align accurately with original document text');
      }
    });

    test('safely handles LaTeX formulas without splitting inside inline math', () {
      final mathParagraph = 'In physics, the energy-momentum relation is given by '
          '\$E^2 = (p \\cdot c)^2 + (m_0 \\cdot c^2)^2\$, which underpins relativistic dynamics. ' * 10;
      final text = '1. Introduction\n$mathParagraph';

      final chunks = PdfChunker.chunkText(text, targetChunkSize: 800, overlapSize: 100);

      expect(chunks, isNotEmpty);
      for (final chunk in chunks) {
        // Count unescaped dollar signs: should not leave an open single dollar without closing
        final unescapedDollars = RegExp(r'(?<!\\)\$').allMatches(chunk.text).length;
        expect(unescapedDollars % 2, equals(0),
            reason: 'Chunk should not leave an unmatched opening or closing LaTeX dollar delimiter');
      }
    });
  });

  group('PdfChunker — Model Metadata & Legacy Compatibility', () {
    test('PdfChunk uses documented sentinel for unknown pageNumber by default', () {
      const text = 'Abstract\nShort abstract content.';
      final chunks = PdfChunker.chunkText(text);

      expect(chunks.first.pageNumber, equals(PdfChunk.kUnknownPage));
      expect(PdfChunk.kUnknownPage, equals(-1));
    });

    test('PdfChunk respects explicit pageNumber parameter when provided', () {
      const text = 'Introduction\nPage 4 content.';
      final chunks = PdfChunker.chunkText(text, pageNumber: 4);

      expect(chunks.first.pageNumber, equals(4));
    });

    test('PaperEvidence maintains 100% backward compatibility with legacy constructor', () {
      // Legacy instantiation without chunks
      const legacyEvidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Extracted plain text from paper.',
      );

      expect(legacyEvidence.level, equals(EvidenceLevel.fullText));
      expect(legacyEvidence.extractedText, equals('Extracted plain text from paper.'));
      expect(legacyEvidence.chunks, isEmpty);

      // New instantiation with chunks
      const chunk = PdfChunk(
        id: 'chunk_0',
        text: 'Chunk content',
        sectionTitle: 'Abstract',
        charOffset: 0,
      );

      const newEvidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Chunk content',
        chunks: [chunk],
      );

      expect(newEvidence.chunks.length, equals(1));
      expect(newEvidence.chunks.first.sectionTitle, equals('Abstract'));

      // copyWith test
      final copied = legacyEvidence.copyWith(chunks: [chunk]);
      expect(copied.chunks.length, equals(1));
      expect(copied.extractedText, equals(legacyEvidence.extractedText));
    });

    test('PdfChunk copyWith and equality work consistently', () {
      const chunk1 = PdfChunk(
        id: 'c1',
        text: 'Text A',
        sectionTitle: 'Intro',
        charOffset: 10,
        pageNumber: 2,
      );

      const chunk2 = PdfChunk(
        id: 'c1',
        text: 'Text A',
        sectionTitle: 'Intro',
        charOffset: 10,
        pageNumber: 2,
      );

      expect(chunk1, equals(chunk2));
      expect(chunk1.hashCode, equals(chunk2.hashCode));

      final modified = chunk1.copyWith(text: 'Text B');
      expect(modified, isNot(equals(chunk1)));
      expect(modified.text, equals('Text B'));
      expect(modified.id, equals('c1'));
    });
  });
}
