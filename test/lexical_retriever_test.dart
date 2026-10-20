import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/utils/lexical_retriever.dart';

void main() {
  group('LexicalRetriever — BM25 Core Relevance & Heading Weighting', () {
    test('1. Query about F1-score ranks Results chunk with F1-score evidence at #1', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Deep neural networks have achieved remarkable milestones in computer vision.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_methods',
          text: 'Methodology: We train our transformer model using cross-entropy loss and gradient accumulation.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
        const PdfChunk(
          id: 'chunk_results',
          text: 'Results: On the GLUE benchmark, our model obtains an F1-score of 94.2% and accuracy of 91.5%.',
          sectionTitle: 'Results',
          charOffset: 1200,
        ),
        const PdfChunk(
          id: 'chunk_conclusion',
          text: 'Conclusion: In summary, foundation models provide robust generalization capabilities.',
          sectionTitle: 'Conclusion',
          charOffset: 2000,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Berapa F1-score pada evaluasi benchmark?',
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks, isNotEmpty);
      final topScored = result.scoredChunks.first;
      expect(topScored.chunk.id, equals('chunk_results'));
      expect(topScored.chunk.sectionTitle, equals('Results'));
      expect(topScored.chunk.text, contains('F1-score of 94.2%'));
    });

    test('2. Query about optimization methods prioritizes Methods chunk with matching evidence', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Optimization in deep learning (optimasi deep learning) has been widely studied for decades.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_methods',
          text: 'Methodology: We adopt the AdamW optimization method (metode optimasi) with cosine annealing learning rate scheduler.',
          sectionTitle: 'Methodology',
          charOffset: 400,
        ),
        const PdfChunk(
          id: 'chunk_results',
          text: 'Results: The final validation accuracy reaches 88.7% after 100 training epochs.',
          sectionTitle: 'Results',
          charOffset: 1000,
        ),
      ];

      // Test with Indonesian query
      final resultId = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Apa metode optimasi yang digunakan dalam penelitian ini?',
      );

      expect(resultId.isFallback, isFalse);
      expect(resultId.scoredChunks.first.chunk.id, equals('chunk_methods'));
      expect(resultId.scoredChunks.first.chunk.sectionTitle, equals('Methodology'));
      expect(resultId.scoredChunks.first.chunk.text, contains('AdamW optimization method'));

      // Also verify with English query
      final resultEn = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Which optimization method is used for training?',
      );

      expect(resultEn.isFallback, isFalse);
      expect(resultEn.scoredChunks.first.chunk.id, equals('chunk_methods'));
      expect(resultEn.scoredChunks.first.chunk.sectionTitle, equals('Methodology'));
      expect(resultEn.scoredChunks.first.chunk.text, contains('AdamW optimization method'));
    });

    test('3. Irrelevant chunk does NOT outrank relevant chunk purely because of heading', () {
      final chunks = [
        // A Results chunk with ZERO query keywords (completely irrelevant content)
        const PdfChunk(
          id: 'chunk_results_irrelevant',
          text: 'Results: The authors would like to acknowledge the funding agency for computational grants.',
          sectionTitle: 'Results',
          charOffset: 0,
        ),
        // A Methodology chunk with STRONG relevant query terms
        const PdfChunk(
          id: 'chunk_method_relevant',
          text: 'Methodology: The F1-score evaluation metric is computed across ten cross-validation folds.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Berapa F1-score yang dilaporkan?',
      );

      expect(result.isFallback, isFalse);
      // The Methodology chunk must win because the Results chunk has 0 relevant terms
      expect(result.scoredChunks.first.chunk.id, equals('chunk_method_relevant'));
      // The irrelevant Results chunk should have score 0.0 and not appear in positive results
      final irrelevantInResults = result.scoredChunks.any((sc) => sc.chunk.id == 'chunk_results_irrelevant');
      expect(irrelevantInResults, isFalse, reason: 'Chunk with 0 matched content terms must never receive positive score');
    });

    test('4. BM25 fairly penalizes diluted long chunks compared to dense short chunks (b parameter)', () {
      // Short dense chunk: term 'quantum' appears 2 times out of 10 words
      const shortDenseText = 'Quantum algorithms. Quantum error correction is essential.';
      // Long diluted chunk: term 'quantum' appears 2 times out of 100 words
      final longDilutedText = 'Quantum algorithms are fascinating. '
          '${'Classical computers perform arithmetic operations with silicon semiconductor transistors. ' * 10}'
          'Quantum hardware remains experimental.';

      final chunks = [
        const PdfChunk(
          id: 'chunk_short_dense',
          text: shortDenseText,
          sectionTitle: 'General',
          charOffset: 0,
        ),
        PdfChunk(
          id: 'chunk_long_diluted',
          text: longDilutedText,
          sectionTitle: 'General',
          charOffset: 200,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'quantum',
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks.length, equals(2));
      // Short chunk with same term frequency must have higher BM25 score than long diluted chunk
      final shortScore = result.scoredChunks.firstWhere((sc) => sc.chunk.id == 'chunk_short_dense').score;
      final longScore = result.scoredChunks.firstWhere((sc) => sc.chunk.id == 'chunk_long_diluted').score;
      expect(shortScore, greaterThan(longScore),
          reason: 'BM25 length normalization b=0.75 must penalize overly diluted long documents');
    });
  });

  group('LexicalRetriever — Fallback & Edge Cases', () {
    test('5. Empty query and stopwords-only query handled safely without exception', () {
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Scientific content about neural representations.',
          sectionTitle: 'Intro',
          charOffset: 0,
        ),
      ];

      // Empty query
      final emptyResult = LexicalRetriever.retrieve(chunks: chunks, query: '');
      expect(emptyResult.isFallback, isTrue);
      expect(emptyResult.fallbackReason, equals(FallbackReason.emptyQuery));
      expect(emptyResult.scoredChunks, isEmpty);

      // Whitespace query
      final wsResult = LexicalRetriever.retrieve(chunks: chunks, query: '   \n\t  ');
      expect(wsResult.isFallback, isTrue);
      expect(wsResult.fallbackReason, equals(FallbackReason.emptyQuery));

      // Stopwords-only query (English & Indonesian)
      final stopResult = LexicalRetriever.retrieve(chunks: chunks, query: 'what is the and yang di');
      expect(stopResult.isFallback, isTrue);
      expect(stopResult.fallbackReason, equals(FallbackReason.stopwordsOnly));
      expect(stopResult.scoredChunks, isEmpty);
    });

    test('6. Query with no matching terms produces explicit noMatches fallback', () {
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'This paper discusses convolutional architectures for astrophysics.',
          sectionTitle: 'General',
          charOffset: 0,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'CRISPR Cas9 gene editing therapeutics',
      );

      expect(result.isFallback, isTrue);
      expect(result.fallbackReason, equals(FallbackReason.noMatches));
      expect(result.scoredChunks, isEmpty);
    });
  });

  group('LexicalRetriever — Budget & Boundary Constraints', () {
    test('7. maxChunks limit is strictly respected', () {
      final chunks = List.generate(
        10,
        (i) => PdfChunk(
          id: 'chunk_$i',
          text: 'Benchmark evaluation of model accuracy and loss metrics iteration $i.',
          sectionTitle: 'Results',
          charOffset: i * 200,
        ),
      );

      const maxChunks = 3;
      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'benchmark accuracy metrics',
        maxChunks: maxChunks,
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks.length, equals(maxChunks));
    });

    test('8. Hard ceiling on maxChars is never violated', () {
      // 5 chunks, each 500 characters
      final chunks = List.generate(
        5,
        (i) => PdfChunk(
          id: 'chunk_$i',
          text: 'Evaluation benchmark test report on accuracy and convergence parameters. ' * 7,
          sectionTitle: 'Results',
          charOffset: i * 1000,
        ),
      );

      const maxChars = 1200;
      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'benchmark accuracy convergence',
        maxChunks: 5,
        maxChars: maxChars,
      );

      expect(result.isFallback, isFalse);
      expect(result.totalCharacters, lessThanOrEqualTo(maxChars));
      int actualCharCount = 0;
      for (final sc in result.scoredChunks) {
        actualCharCount += sc.chunk.text.length;
      }
      expect(actualCharCount, equals(result.totalCharacters));
      expect(actualCharCount, lessThanOrEqualTo(maxChars));
    });

    test('9. Selecting adjacent chunks avoids excessive duplicate overlap text in combinedText', () {
      // Two consecutive chunks with 100 characters of physical text overlap
      const chunk1Text = 'First sentence of the section. Intermediate content explaining the core algorithmic logic.';
      const chunk2Text = 'Intermediate content explaining the core algorithmic logic. Additional novel contributions.';

      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: chunk1Text,
          sectionTitle: 'Methodology',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c2',
          text: chunk2Text,
          sectionTitle: 'Methodology',
          charOffset: 31, // Starts before c1 ends, creating overlap
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'algorithmic logic contributions',
        maxChunks: 2,
      );

      expect(result.scoredChunks.length, equals(2));
      final combined = result.combinedText;

      // Combined text should not repeat the overlapping phrase twice
      final count = RegExp(r'Intermediate content explaining the core algorithmic logic')
          .allMatches(combined)
          .length;
      expect(count, equals(1), reason: 'Overlapping content between adjacent chunks should be deduplicated in combinedText');
    });

    test('10. Ranking results are deterministic for identical input', () {
      final chunks = [
        const PdfChunk(id: 'c1', text: 'Transformer attention mechanism.', sectionTitle: 'A', charOffset: 0),
        const PdfChunk(id: 'c2', text: 'Convolutional neural network pooling.', sectionTitle: 'B', charOffset: 100),
        const PdfChunk(id: 'c3', text: 'Transformer attention multi-head mechanism.', sectionTitle: 'C', charOffset: 200),
      ];

      const query = 'transformer attention';
      final run1 = LexicalRetriever.retrieve(chunks: chunks, query: query);
      final run2 = LexicalRetriever.retrieve(chunks: chunks, query: query);

      expect(run1.scoredChunks.length, equals(run2.scoredChunks.length));
      for (int i = 0; i < run1.scoredChunks.length; i++) {
        expect(run1.scoredChunks[i].chunk.id, equals(run2.scoredChunks[i].chunk.id));
        expect(run1.scoredChunks[i].score, equals(run2.scoredChunks[i].score));
      }
    });

    test('11. Tokenizer preserves Unicode, decimal numbers, and hyphenated terms', () {
      const text = 'Model ResNet-50 achieves 94.2% top-1 accuracy on zero-shot ImageNet evaluation with F1-score 0.89 in Français.';
      final tokens = LexicalRetriever.tokenize(text, filterStopWords: true);

      expect(tokens, contains('resnet-50'));
      expect(tokens, contains('94.2'));
      expect(tokens, contains('zero-shot'));
      expect(tokens, contains('imagenet'));
      expect(tokens, contains('f1-score'));
      expect(tokens, contains('0.89'));
      expect(tokens, contains('français'));
    });

    test('12. Metadata of PdfChunk is strictly preserved on retrieved results', () {
      const chunk = PdfChunk(
        id: 'chunk_alpha_42',
        text: 'Statistical variance analysis for randomized trials.',
        sectionTitle: 'Results',
        charOffset: 4200,
        pageNumber: 7,
      );

      final result = LexicalRetriever.retrieve(
        chunks: [chunk],
        query: 'statistical variance',
      );

      expect(result.scoredChunks, isNotEmpty);
      final retrieved = result.scoredChunks.first.chunk;
      expect(retrieved.id, equals('chunk_alpha_42'));
      expect(retrieved.sectionTitle, equals('Results'));
      expect(retrieved.charOffset, equals(4200));
      expect(retrieved.pageNumber, equals(7));
    });

    test('13. Input list is NOT mutated by retrieve', () {
      final originalList = [
        const PdfChunk(id: 'b_second', text: 'Machine learning approaches.', sectionTitle: 'B', charOffset: 200),
        const PdfChunk(id: 'a_first', text: 'Machine learning deep neural networks.', sectionTitle: 'A', charOffset: 50),
      ];

      // Clone original state
      final snapshot = List<PdfChunk>.from(originalList);

      LexicalRetriever.retrieve(
        chunks: originalList,
        query: 'machine learning deep',
      );

      // Verify original list has not been mutated in order or content
      expect(originalList.length, equals(snapshot.length));
      for (int i = 0; i < originalList.length; i++) {
        expect(originalList[i].id, equals(snapshot[i].id));
      }
    });

    test('14. Single chunk larger than maxChars budget is trimmed without exceeding hard ceiling', () {
      final longChunk = PdfChunk(
        id: 'huge_chunk',
        text: 'Important machine learning discovery on foundation models. ' * 80, // ~4.700 chars
        sectionTitle: 'Results',
        charOffset: 0,
      );

      const maxBudget = 1000;
      final result = LexicalRetriever.retrieve(
        chunks: [longChunk],
        query: 'machine learning discovery',
        maxChars: maxBudget,
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks.length, equals(1));
      expect(result.totalCharacters, lessThanOrEqualTo(maxBudget));
      expect(result.scoredChunks.first.chunk.text.length, equals(maxBudget));
      expect(result.totalCharacters, equals(maxBudget));
    });
  });
}
