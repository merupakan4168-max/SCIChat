import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/utils/pdf_chunker.dart';

void main() {
  group('Phase 4D.2: Robust PDF Section and Subsection Chunking Tests', () {
    // 1 & 2. Numbered subsection detection and preservation of original subsection titles
    test('1 & 2. Numbered subsections (2.1, 2.2, 2.3, 3.1, 4.4, 2.2.1) are detected and preserve actual titles', () {
      const paperWithSubsections = '''
1. Introduction
This section introduces the foundational concepts of retrieval-augmented generation.

2. Methods
General framework overview for parametric and non-parametric memory.

2.1 Models
We formulate RAG-Sequence and RAG-Token models with distinct probability decompositions.

2.2 Retriever: DPR
The dense passage retriever uses bi-encoder BERT representations to index Wikipedia passages.

2.3 Generator: BART
The generator employs BART-large with 400M parameters as a seq2seq transformer.

2.2.1 Training
Joint fine-tuning minimizes the negative marginal log-likelihood of target tokens.

3. Experiments
Experimental setup and benchmark descriptions.

3.1 Open-Domain QA
We evaluate on Natural Questions, TriviaQA, WebQuestions, and CuratedTREC.

4. Results
Quantitative benchmark comparison.

4.4 Fact Verification
On the FEVER dataset, the model demonstrates high verification accuracy.
''';

      final chunks = PdfChunker.chunkText(paperWithSubsections);

      expect(chunks, isNotEmpty);
      final sectionTitles = chunks.map((c) => c.sectionTitle).toSet();

      // Major sections
      expect(sectionTitles, contains('Introduction'));
      expect(sectionTitles, contains('Methodology'));
      expect(sectionTitles, contains('Experiments'));
      expect(sectionTitles, contains('Results'));

      // Subsections: titles must be preserved as specific titles rather than collapsed to generic 'Methodology'
      expect(sectionTitles, contains('2.1 Models'));
      expect(sectionTitles, contains('2.2 Retriever: DPR'));
      expect(sectionTitles, contains('2.3 Generator: BART'));
      expect(sectionTitles, contains('2.2.1 Training'));
      expect(sectionTitles, contains('3.1 Open-Domain QA'));
      expect(sectionTitles, contains('4.4 Fact Verification'));

      // Verify that subsection content is retained in the corresponding chunk
      final dprChunk = chunks.firstWhere((c) => c.sectionTitle == '2.2 Retriever: DPR');
      expect(dprChunk.text, contains('dense passage retriever uses bi-encoder'));

      final bartChunk = chunks.firstWhere((c) => c.sectionTitle == '2.3 Generator: BART');
      expect(bartChunk.text, contains('BART-large with 400M parameters'));

      final factChunk = chunks.firstWhere((c) => c.sectionTitle == '4.4 Fact Verification');
      expect(factChunk.text, contains('FEVER dataset'));
    });

    // 3. Non-standard headings: Broader Impact, Acknowledgements, and Acknowledgments
    test('3. Recognizes Broader Impact, Acknowledgements, Acknowledgments, Ethical Considerations, and Checklist', () {
      const nonStandardPaper = '''
Title: Advanced Scientific AI
Authors: Turing & Lovelace

1 Introduction
Background text.

7 Broader Impact
This research discusses societal risks, potential factual hallucinations, and dual-use implications.

Acknowledgements
We thank the funding agencies and colleagues for constructive feedback on early drafts.

Ethical Considerations
Measures taken to mitigate algorithmic bias and energy consumption during training.

Checklist
1. For all authors: did you include the code? Yes.
''';

      final chunks = PdfChunker.chunkText(nonStandardPaper);

      final sectionTitles = chunks.map((c) => c.sectionTitle).toSet();
      expect(sectionTitles, contains('Broader Impact'));
      expect(sectionTitles, contains('Acknowledgements'));
      expect(sectionTitles, contains('Ethical Considerations'));
      expect(sectionTitles, contains('Checklist'));

      // Also verify American spelling variant "Acknowledgments"
      const variantPaper = '''
Acknowledgments
The authors would like to acknowledge computational grants.
''';
      final variantChunks = PdfChunker.chunkText(variantPaper);
      expect(variantChunks.first.sectionTitle, equals('Acknowledgements'));
    });

    // 4. Inline abstract formats using em dash and colon
    test('4. Inline abstract formats (em dash "—", colon ":", dot ".") are recognized without text loss or false Header', () {
      // 4a. Em dash inline abstract at the very start of text
      const inlineEmDash = 'Abstract—Large pre-trained language models have been shown to store vast factual knowledge.';
      final emDashChunks = PdfChunker.chunkText(inlineEmDash);

      expect(emDashChunks.length, equals(1));
      expect(emDashChunks.first.sectionTitle, equals('Abstract'));
      expect(emDashChunks.first.text, contains('Abstract—Large pre-trained language models'));
      expect(emDashChunks.first.charOffset, equals(0));

      // 4b. Colon inline abstract following title & authors
      const inlineColon = '''
Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks
Patrick Lewis, Ethan Perez, Aleksandra Piktus

ABSTRACT: We explore combining parametric and non-parametric memory representations.

1 Introduction
Language models have achieved remarkable success.
''';
      final colonChunks = PdfChunker.chunkText(inlineColon);

      expect(colonChunks.length, greaterThanOrEqualTo(3));
      expect(colonChunks[0].sectionTitle, equals('Header'));
      expect(colonChunks[0].text, contains('Retrieval-Augmented Generation'));

      expect(colonChunks[1].sectionTitle, equals('Abstract'));
      expect(colonChunks[1].text, contains('ABSTRACT: We explore combining parametric'));

      expect(colonChunks[2].sectionTitle, equals('Introduction'));
      expect(colonChunks[2].text, contains('Language models have achieved remarkable success.'));

      // 4c. En dash and double hyphen variants
      const inlineEnDash = 'Abstract–This work introduces hybrid dense retrieval mechanisms.';
      final enDashChunks = PdfChunker.chunkText(inlineEnDash);
      expect(enDashChunks.first.sectionTitle, equals('Abstract'));

      const inlineDoubleHyphen = 'Abstract--This work introduces hybrid dense retrieval mechanisms.';
      final doubleHyphenChunks = PdfChunker.chunkText(inlineDoubleHyphen);
      expect(doubleHyphenChunks.first.sectionTitle, equals('Abstract'));
    });

    // 5. References and Bibliography heading recognition
    test('5. References and Bibliography headings are correctly recognized', () {
      const bibText = '''
4. Results
We report top results.

References
[1] Vaswani et al. Attention is All You Need. 2017.
''';
      final refChunks = PdfChunker.chunkText(bibText);
      expect(refChunks.map((c) => c.sectionTitle), contains('References'));

      const bibVariantText = '''
4. Results
We report top results.

Bibliography
[1] Karpukhin et al. Dense Passage Retrieval. 2020.
''';
      final bibChunks = PdfChunker.chunkText(bibVariantText);
      expect(bibChunks.map((c) => c.sectionTitle), contains('References'));

      const worksCitedText = '''
4. Results
We report top results.

Works Cited
[1] Devlin et al. BERT. 2018.
''';
      final worksCitedChunks = PdfChunker.chunkText(worksCitedText);
      expect(worksCitedChunks.map((c) => c.sectionTitle), contains('References'));
    });

    // 6. Normal prose and decimal numbers are not falsely classified as headings
    test('6. Ordinary prose, decimals in sentences, and numbered bibliography items are not false headings', () {
      const proseText = '''
1. Introduction
In version 2.1 of our algorithm, we noticed that 94.2% accuracy was achieved across 10 trials.
2.1% accuracy was achieved in earlier runs.
Furthermore, 2.1 of our algorithm shows that the loss decreases monotonically over iterations.
Here is equation 2.1: x = 2.1 * y.
1. Vaswani, A., Shazeer, N., Parmar, N., Uszkoreit, J., Attention is All You Need, 2017.
2. Devlin, J., Chang, M. W., Lee, K., Toutanova, K., BERT: Pre-training of Deep Bidirectional Transformers, 2018.
Finally, we summarize the findings.
''';

      final chunks = PdfChunker.chunkText(proseText);

      // Only 'Introduction' should be a heading; the sentences with 2.1, 94.2%, and reference lines
      // must NOT create new section chunks!
      final sectionTitles = chunks.map((c) => c.sectionTitle).toList();
      expect(sectionTitles.every((t) => t == 'Introduction'), isTrue);
      expect(chunks.any((c) => c.sectionTitle.startsWith('2.1')), isFalse);
    });

    // 7. Existing chunk size and overlap constraints remain unchanged
    test('7. Chunk size targets and overlap constraints remain strictly preserved', () {
      final longSection =
          '2.2 Retriever: DPR\n${'The dense passage retriever maps questions and passages to continuous representations. ' * 50}';

      const targetSize = 1000;
      const overlapSize = 150;
      final chunks = PdfChunker.chunkText(longSection, targetChunkSize: targetSize, overlapSize: overlapSize);

      expect(chunks.length, greaterThan(1));
      for (final chunk in chunks) {
        expect(chunk.sectionTitle, equals('2.2 Retriever: DPR'));
        expect(chunk.text.length, lessThanOrEqualTo(targetSize + 50));
      }

      // Verify charOffsets are strictly monotonic
      for (int i = 1; i < chunks.length; i++) {
        expect(chunks[i].charOffset, greaterThan(chunks[i - 1].charOffset));
      }
    });
  });
}
