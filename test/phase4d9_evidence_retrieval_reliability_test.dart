import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/utils/lexical_retriever.dart';

void main() {
  group('Phase 4D.9 Fix B: Abstract Anchor for Local PDFs in SciChatProvider', () {
    test('1. Local PDF without metadata summary uses reliably identified extracted Abstract as anchor', () {
      final paper = const ArxivPaper(
        id: 'local_neuromorphic_1',
        title: 'Neuromorphic solutions for ECG classification',
        authors: const ['Rahim et al.'],
        summary: '', // Empty metadata summary (typical for local PDF)
        pdfUrl: 'file:///path/to/local.pdf',
        absUrl: 'file:///path/to/local.pdf',
        categories: const ['cs.NE'],
        published: '2022-08-01',
        updated: '2022-08-01',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_header',
          text: 'Bulletin of Electrical Engineering and Informatics. Vol 11, No 4.',
          sectionTitle: 'Header',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_abstract',
          text: 'Cardiac arrhythmias refer to the impairment of electrical impulses. This work proposes an SNN implementation on FPGA Zedboard achieving 1.058% hardware utilization.',
          sectionTitle: 'Abstract',
          charOffset: 200,
        ),
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Neuromorphic architectures enable energy-efficient edge computing for biomedical signals.',
          sectionTitle: 'Introduction',
          charOffset: 800,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full document text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Apa masalah dan pendekatan yang diusulkan?',
      );

      expect(prompt, contains('Abstrak (Jangkar Konteks - Ekstraksi PDF):'));
      expect(prompt, contains('achieving 1.058% hardware utilization'));
      expect(prompt, contains('Sumber: Berkas PDF Lokal'));
    });

    test('2. PDF without a detectable abstract does NOT treat an arbitrary first chunk as abstract', () {
      final paper = const ArxivPaper(
        id: 'local_no_abstract',
        title: 'Technical Note on FPGA Synthesis',
        authors: const ['Engineer A'],
        summary: 'A local PDF file', // Generic placeholder
        pdfUrl: 'file:///path/to/note.pdf',
        absUrl: 'file:///path/to/note.pdf',
        categories: const ['cs.AR'],
        published: '2023-01-01',
        updated: '2023-01-01',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_0',
          text: 'This technical report documents the synthesis scripts and timing constraints for Vivado 2020.2.',
          sectionTitle: 'General',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_1',
          text: 'Methodology: We configure the clock generator for 100MHz operations.',
          sectionTitle: 'Methodology',
          charOffset: 300,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Technical report text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Bagaimana konfigurasi Vivado?',
      );

      expect(prompt, isNot(contains('Abstrak (Jangkar Konteks')));
      expect(prompt, isNot(contains('Abstrak (Ekstraksi PDF')));
    });

    test('3. Existing valid metadata summary is preserved and NOT replaced by extracted text', () {
      final paper = const ArxivPaper(
        id: 'arxiv_paper_1',
        title: 'Retrieval-Augmented Generation for Knowledge-Intensive NLP Tasks',
        authors: const ['Patrick Lewis et al.'],
        summary: 'Large pre-trained language models store factual knowledge in parameters but have limitations.',
        pdfUrl: 'https://arxiv.org/pdf/2005.11401.pdf',
        absUrl: 'https://arxiv.org/abs/2005.11401',
        categories: const ['cs.CL'],
        published: '2020-01-01',
        updated: '2020-01-01',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_abstract',
          text: 'Different extracted text of abstract from PDF.',
          sectionTitle: 'Abstract',
          charOffset: 100,
        ),
        const PdfChunk(
          id: 'chunk_models',
          text: '2.1 Models: We combine a retriever and a generator.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Document text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Jelaskan model RAG',
      );

      expect(prompt, contains('Abstrak (Jangkar Konteks):'));
      expect(prompt, contains('Large pre-trained language models store factual knowledge'));
      expect(prompt, isNot(contains('Abstrak (Jangkar Konteks - Ekstraksi PDF):')));
    });

    test('4. Avoids duplicating the same abstract if it is already present in retrieved evidence', () {
      final paper = const ArxivPaper(
        id: 'local_duplicate_check',
        title: 'Biomedical Signal Processing',
        authors: const ['Author X'],
        summary: '',
        pdfUrl: 'file:///path/to/bio.pdf',
        absUrl: 'file:///path/to/bio.pdf',
        categories: const ['eess.SP'],
        published: '2023-01-01',
        updated: '2023-01-01',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_abstract',
          text: 'Cardiac arrhythmias and electrocardiogram feature extraction using wavelet transforms.',
          sectionTitle: 'Abstract',
          charOffset: 50,
        ),
        const PdfChunk(
          id: 'chunk_results',
          text: 'Results: Hardware utilization on Zedboard is measured at 1.058% total logic cells.',
          sectionTitle: 'Results',
          charOffset: 600,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      // Query specifically targeting the abstract
      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Apa isi abstrak mengenai arrhythmias?',
      );

      // The abstract should be present in the prompt, but NOT printed twice
      final count = RegExp(r'Cardiac arrhythmias and electrocardiogram feature extraction')
          .allMatches(prompt)
          .length;
      expect(count, equals(1), reason: 'Abstract chunk must not be printed twice if retrieval selected it');
    });

    test('5. Truncated extraction metadata warning is preserved when abstract anchor is used', () {
      final paper = const ArxivPaper(
        id: 'local_truncated',
        title: 'Long Biomedical Treatise',
        authors: const ['Author Y'],
        summary: '',
        pdfUrl: 'file:///path/to/long.pdf',
        absUrl: 'file:///path/to/long.pdf',
        categories: const ['cs.NE'],
        published: '2023-01-01',
        updated: '2023-01-01',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_abstract',
          text: 'Comprehensive study of multi-lead ECG processing on embedded systems.',
          sectionTitle: 'Abstract',
          charOffset: 50,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Study text',
        chunks: chunks,
        extractionMetadata: const PdfExtractionMetadata.truncated(
          retained: 48000,
          total: 60000,
        ),
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Apa kesimpulan makalah?',
      );

      expect(prompt, contains('Abstrak (Jangkar Konteks - Ekstraksi PDF):'));
      expect(prompt, contains('Kelengkapan Ekstraksi: Terpotong'));
      expect(prompt, contains('48000 dari 60000 karakter'));
    });
  });

  group('Phase 4D.9 Fix C: Adaptive Evidence Selection in LexicalRetriever', () {
    test('1. Relevant fourth-ranked dataset chunk is selected when budget allows', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_0',
          text: 'Methodology: SNN design on FPGA Zedboard using Vivado and MATLAB simulation.',
          sectionTitle: 'Methodology',
          charOffset: 100,
        ),
        const PdfChunk(
          id: 'chunk_1',
          text: 'Methodology: Discrete Wavelet Transform (DWT) decomposing ECG signals into coefficients.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
        const PdfChunk(
          id: 'chunk_2',
          text: 'Methodology: Spike-Timing-Dependent Plasticity (STDP) learning module and synaptic weights.',
          sectionTitle: 'Methodology',
          charOffset: 1000,
        ),
        const PdfChunk(
          id: 'chunk_3',
          text: 'Methodology: The MIT-BIH Arrhythmia Database (MITDB) consists of 48 records of 10-second duration with 3500 samples across 35 normal and 13 abnormal records.',
          sectionTitle: 'Methodology',
          charOffset: 1500,
        ),
        const PdfChunk(
          id: 'chunk_4',
          text: 'General: Acknowledgements to the university laboratory staff for technical support.',
          sectionTitle: 'Acknowledgements',
          charOffset: 2000,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Jelaskan metodologi penelitian, dataset MITDB, dan prosedur eksperimen',
        maxChunks: 4,
        maxChars: 6000,
      );

      expect(result.scoredChunks.length, equals(4));
      final selectedIds = result.scoredChunks.map((sc) => sc.chunk.id).toList();
      expect(selectedIds, contains('chunk_3'), reason: 'Fourth-ranked dataset chunk must be selected');
      final datasetChunk = result.scoredChunks.firstWhere((sc) => sc.chunk.id == 'chunk_3');
      expect(datasetChunk.chunk.text, contains('48 records'));
    });

    test('2. A chunk is NOT selected if it would exceed the character budget', () {
      final chunks = [
        PdfChunk(
          id: 'c1',
          text: 'Results analysis showing high performance metrics on test evaluation. ' * 10, // ~700 chars
          sectionTitle: 'Results',
          charOffset: 0,
        ),
        PdfChunk(
          id: 'c2',
          text: 'Results analysis showing high performance metrics on test evaluation. ' * 10, // ~700 chars
          sectionTitle: 'Results',
          charOffset: 800,
        ),
        PdfChunk(
          id: 'c3',
          text: 'Results analysis showing high performance metrics on test evaluation. ' * 10, // ~700 chars
          sectionTitle: 'Results',
          charOffset: 1600,
        ),
        PdfChunk(
          id: 'c4',
          text: 'Results analysis showing high performance metrics on test evaluation. ' * 10, // ~700 chars
          sectionTitle: 'Results',
          charOffset: 2400,
        ),
      ];

      // Total budget 2200 chars: can hold c1, c2, c3 (~2100 chars), but c4 would exceed 2200
      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'results analysis high performance metrics',
        maxChunks: 4,
        maxChars: 2200,
      );

      expect(result.scoredChunks.length, equals(3));
      expect(result.totalCharacters, lessThanOrEqualTo(2200));
      expect(result.scoredChunks.any((sc) => sc.chunk.id == 'c4'), isFalse);
    });

    test('3. Redundant chunks from the same overlapping passage are skipped in favor of diverse evidence', () {
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Section Methodology: We adopt discrete wavelet transform with db6 mother wavelet decomposing ECG into detailed and approximation coefficients.',
          sectionTitle: 'Methodology',
          charOffset: 1000,
        ),
        // c2 is almost identical passage with heavy character offset overlap (offset 1040, within 80% length)
        const PdfChunk(
          id: 'c2_redundant',
          text: 'Section Methodology: We adopt discrete wavelet transform with db6 mother wavelet decomposing ECG into detailed and approximation coefficients.',
          sectionTitle: 'Methodology',
          charOffset: 1040,
        ),
        const PdfChunk(
          id: 'c3_diverse',
          text: 'Section Methodology: The classifier uses an Izhikevich neuron model with a = 0.02 and b = 0.2 implemented in digital FPGA logic.',
          sectionTitle: 'Methodology',
          charOffset: 2500, // Non-overlapping offset
        ),
        const PdfChunk(
          id: 'c4_diverse',
          text: 'Section Methodology: Dataset allocation employs MITDB 48 ECG records for testing arrhythmia detection.',
          sectionTitle: 'Methodology',
          charOffset: 4000, // Non-overlapping offset
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'methodology discrete wavelet transform izhikevich neuron dataset',
        maxChunks: 3,
        maxChars: 5000,
      );

      final ids = result.scoredChunks.map((sc) => sc.chunk.id).toList();
      expect(ids, contains('c1'));
      expect(ids, isNot(contains('c2_redundant')), reason: 'Physically redundant chunk from same passage must be skipped');
      expect(ids, contains('c3_diverse'));
      expect(ids, contains('c4_diverse'));
    });

    test('4. Quantitative table retrieval remains successful under adaptive selection', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Biomedical circuits for arrhythmia classification.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_table',
          text: 'Table 2. Hardware resource utilization on Zedboard FPGA: LUT: 908 (1.71%), FF: 919 (0.86%), DSP: 2 (0.91%), IO: 10 (5.0%). Total: 1877 (1.058%). Table 3 comparison with Gu et al. (13660) and Zhai et al. (27959).',
          sectionTitle: 'Results',
          charOffset: 2000,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Berapa hasil kuantitatif utama dan angka pemanfaatan hardware pada tabel?',
        maxChunks: 4,
        maxChars: 5000,
      );

      expect(result.scoredChunks, isNotEmpty);
      expect(result.scoredChunks.first.chunk.id, equals('chunk_table'));
      expect(result.scoredChunks.first.chunk.text, contains('1.058%'));
      expect(result.scoredChunks.first.chunk.text, contains('1877'));
    });

    test('5. Existing fallback and cache behavior is unchanged', () {
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Astrophysics cosmic background radiation.',
          sectionTitle: 'Intro',
          charOffset: 0,
        ),
      ];

      final result = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Quantum entanglement teleportation',
      );

      expect(result.isFallback, isTrue);
      expect(result.fallbackReason, equals(FallbackReason.noMatches));
      expect(result.scoredChunks, isEmpty);
    });
  });
}
