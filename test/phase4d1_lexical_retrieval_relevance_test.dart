import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/utils/lexical_retriever.dart';

void main() {
  group('Phase 4D.1: Lexical Retrieval Relevance & Bibliography Awareness', () {
    // 1. Query 'Sebutkan dataset yang digunakan' ranks a relevant Experiments chunk
    // above a References chunk containing many dataset names.
    test('1. Substantive query (dataset) ranks Experiments chunk above a References chunk dense with dataset citations', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_experiments',
          text: 'Experiments and Evaluation: We evaluate our retrieval model on the Natural Questions '
              'and TriviaQA benchmark datasets, analyzing exact match accuracy across all splits.',
          sectionTitle: 'Experiments',
          charOffset: 1000,
        ),
        const PdfChunk(
          id: 'chunk_references',
          text: 'References:\n'
              '[1] Kwiatkowski et al. Natural Questions: A Benchmark for Question Answering Research. Dataset.\n'
              '[2] Joshi et al. TriviaQA: A Large Scale Distantly Supervised Challenge Dataset.\n'
              '[3] Thorne et al. FEVER: A Large-scale Dataset for Fact Extraction and Verification.\n'
              '[4] Rajpurkar et al. SQuAD: 100,000+ Questions for Machine Comprehension Dataset.',
          sectionTitle: 'References',
          charOffset: 8000,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Sebutkan dataset yang digunakan',
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks, isNotEmpty);
      // The Experiments chunk MUST rank at #1 ahead of the References chunk
      expect(result.scoredChunks.first.chunk.id, equals('chunk_experiments'));
      expect(result.scoredChunks.first.chunk.sectionTitle, equals('Experiments'));
    });

    // 2. An explicit bibliography query can still retrieve References.
    test('2. Explicit bibliography query prioritizes References / bibliography chunks', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_method',
          text: 'Methodology: We propose dense passage retrieval combined with seq2seq generation.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
        const PdfChunk(
          id: 'chunk_references',
          text: 'References and Citations:\n'
              '[1] Karpukhin et al. Dense Passage Retrieval for Open-Domain QA. EMNLP 2020.\n'
              '[2] Lewis et al. BART: Denoising Sequence-to-Sequence Pre-training. ACL 2020.',
          sectionTitle: 'References',
          charOffset: 9000,
        ),
      ];

      // Test with Indonesian citation query
      final resultId = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Apa saja referensi atau sitasi yang tercantum?',
      );

      expect(resultId.isFallback, isFalse);
      expect(resultId.scoredChunks.first.chunk.id, equals('chunk_references'));
      expect(resultId.scoredChunks.first.chunk.sectionTitle, equals('References'));

      // Test with English bibliography query
      final resultEn = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'List the citations and bibliography of this work',
      );

      expect(resultEn.isFallback, isFalse);
      expect(resultEn.scoredChunks.first.chunk.id, equals('chunk_references'));
    });

    // 2b. Works Cited / Bibliography heading variants are recognized
    test('2b. Recognizes bibliography variants such as "Works Cited" and "Bibliography"', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_body',
          text: 'Results: The system achieves state-of-the-art results on several benchmarks.',
          sectionTitle: 'Results',
          charOffset: 200,
        ),
        const PdfChunk(
          id: 'chunk_works_cited',
          text: 'Works Cited:\n[1] Vaswani et al. Attention is All You Need. NeurIPS 2017.',
          sectionTitle: 'Works Cited',
          charOffset: 5000,
        ),
      ];

      expect(LexicalRetriever.isBibliographySection('Works Cited'), isTrue);
      expect(LexicalRetriever.isBibliographySection('Bibliography'), isTrue);
      expect(LexicalRetriever.isBibliographySection('Daftar Pustaka'), isTrue);

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'daftar pustaka',
      );

      expect(result.scoredChunks.first.chunk.id, equals('chunk_works_cited'));
    });

    // 3. Query 'Ringkas abstrak dan tujuan penelitian paper ini' can match English abstract/introduction content.
    test('3. Query "Ringkas abstrak dan tujuan penelitian paper ini" matches English Abstract / Intro content', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_abstract',
          text: 'Abstract: The primary objective and aim of this research is to explore parametric '
              'and non-parametric memory representations for knowledge-intensive NLP tasks.',
          sectionTitle: 'Abstract',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_ethics',
          text: 'Broader Impact and Ethical Considerations: While this research has potential societal benefits, '
              'we must acknowledge potential dual-use risks and bias.',
          sectionTitle: 'Discussion',
          charOffset: 6000,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Ringkas abstrak dan tujuan penelitian paper ini',
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks, isNotEmpty);
      expect(result.scoredChunks.first.chunk.id, equals('chunk_abstract'));
      expect(result.scoredChunks.first.chunk.sectionTitle, equals('Abstract'));
    });

    // 4. Query 'Bagaimana evaluasinya?' can match a chunk containing 'evaluation'.
    test('4. Query "Bagaimana evaluasinya?" with clitic -nya matches chunk containing "evaluation"', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Language models have scaled significantly in recent years.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_eval',
          text: 'Experimental Evaluation: The evaluation demonstrates superior exact match scores '
              'and robust generalization across open-domain QA tasks.',
          sectionTitle: 'Experiments',
          charOffset: 1200,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Bagaimana evaluasinya?',
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks, isNotEmpty);
      expect(result.scoredChunks.first.chunk.id, equals('chunk_eval'));
    });

    // 4b. Conservative Indonesian clitic normalization tests
    test('4b. Conservative Indonesian clitic normalization strips -nya, -lah, -kah without corrupting short/technical tokens', () {
      expect(LexicalRetriever.normalizeIndonesianClitic('evaluasinya'), equals('evaluasi'));
      expect(LexicalRetriever.normalizeIndonesianClitic('metodenya'), equals('metode'));
      expect(LexicalRetriever.normalizeIndonesianClitic('tujuannya'), equals('tujuan'));
      expect(LexicalRetriever.normalizeIndonesianClitic('hasilnya'), equals('hasil'));
      expect(LexicalRetriever.normalizeIndonesianClitic('ringkaslah'), equals('ringkas'));

      // Technical terms and short words must NOT be corrupted
      expect(LexicalRetriever.normalizeIndonesianClitic('dpr'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('bart'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('bart-large'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('fever'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('triviaqa'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('rag-sequence'), isNull);

      // Non-clitic words in Indonesian must NOT be corrupted
      expect(LexicalRetriever.normalizeIndonesianClitic('hanya'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('tanya'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('punya'), isNull);
      expect(LexicalRetriever.normalizeIndonesianClitic('salah'), isNull);
    });

    // 5. Technical terms such as DPR, BART-large, RAG-Sequence, FEVER, and TriviaQA remain searchable.
    test('5. Technical terms (DPR, BART-large, RAG-Sequence, FEVER, TriviaQA) are preserved and searchable', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_arch',
          text: 'Methods: Our architecture combines DPR (Dense Passage Retriever) and BART-large generator. '
              'We formulate two variants: RAG-Sequence and RAG-Token.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
        const PdfChunk(
          id: 'chunk_results',
          text: 'Results: On the FEVER fact verification benchmark and TriviaQA question answering, '
              'our model sets new state-of-the-art results.',
          sectionTitle: 'Results',
          charOffset: 2500,
        ),
      ];

      // DPR & BART-large & RAG-Sequence
      final resultArch = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Jelaskan arsitektur DPR, BART-large, dan RAG-Sequence',
      );
      expect(resultArch.isFallback, isFalse);
      expect(resultArch.scoredChunks.first.chunk.id, equals('chunk_arch'));

      // FEVER & TriviaQA
      final resultResults = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Berapa performa pada FEVER dan TriviaQA?',
      );
      expect(resultResults.isFallback, isFalse);
      expect(resultResults.scoredChunks.first.chunk.id, equals('chunk_results'));
    });

    // 6. An irrelevant chunk does not win merely because it contains the generic word 'paper'.
    test('6. Irrelevant chunk does not win merely because it contains the generic word "paper"', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_acknowledgements',
          text: 'Acknowledgements: The authors thank our colleagues for reading drafts of this paper. '
              'This paper was written while the first author was at the institution.',
          sectionTitle: 'Acknowledgements',
          charOffset: 7000,
        ),
        const PdfChunk(
          id: 'chunk_abstract',
          text: 'Abstract: We present a novel framework for retrieval-augmented generation. '
              'The primary objective of this research is to minimize hallucination in knowledge tasks.',
          sectionTitle: 'Abstract',
          charOffset: 0,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Ringkas abstrak dan tujuan penelitian paper ini',
      );

      expect(result.isFallback, isFalse);
      // Abstract chunk MUST win; Acknowledgements must NOT win despite having "paper" twice
      expect(result.scoredChunks.first.chunk.id, equals('chunk_abstract'));
      expect(result.scoredChunks.first.chunk.sectionTitle, equals('Abstract'));
    });

    // 7. References are still returned when they are the only matching content
    test('7. References chunk is not globally discarded when it is the sole matching evidence', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: We explore modern natural language understanding architectures.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_references',
          text: 'References:\n[1] AuthorUniqueName et al. VerySpecificAlgorithmTitle 2019.',
          sectionTitle: 'References',
          charOffset: 3000,
        ),
      ];

      // Query mentions a name that only exists in the bibliography
      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'AuthorUniqueName',
      );

      expect(result.isFallback, isFalse);
      expect(result.scoredChunks.length, equals(1));
      expect(result.scoredChunks.first.chunk.id, equals('chunk_references'));
    });
  });
}
