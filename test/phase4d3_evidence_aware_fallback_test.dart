import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';

ArxivPaper createTestPaper({
  required String id,
  required String title,
  String summary = 'Comprehensive paper abstract introducing the core problem and scientific contributions.',
  bool isLocal = false,
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: const ['Alice Researcher', 'Bob Scientist'],
    summary: summary,
    published: '2024-01-01',
    updated: '2024-01-01',
    categories: isLocal ? const ['cs.AI', 'Local'] : const ['cs.AI'],
    pdfUrl: isLocal ? 'file:///local/path/$id.pdf' : 'https://arxiv.org/pdf/$id.pdf',
    absUrl: 'https://arxiv.org/abs/$id',
  );
}

void main() {
  group('Phase 4D.3: Evidence-Aware Fallback and Prompt Neutralization', () {
    // 1. A noMatches prompt with fallback excerpts does not contain a categorical refusal instruction
    test('1. A noMatches prompt does NOT contain categorical refusal instruction', () {
      final paper = createTestPaper(id: 'paper1', title: 'Knowledge-Intensive NLP Tasks');
      final chunks = [
        const PdfChunk(
          id: 'c_meth',
          text: 'We combine pre-trained parametric memory (BART) with non-parametric retrieval memory (DPR).',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
      ];
      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text content',
        chunks: chunks,
      );

      // Kueri yang tidak memiliki kecocokan leksikal eksak
      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Bagaimana mekanisme penggabungan generator dan retriever pada sistem ini?',
      );

      // Pastikan TIDAK ADA instruksi penolakan kategoris
      expect(prompt, isNot(contains('nyatakan bahwa rincian spesifik tidak ditemukan dalam dokumen')));
      expect(prompt, isNot(contains('rincian spesifik tidak ditemukan dalam dokumen')));
    });

    // 2. The prompt labels fallback excerpts as partial/retrieved context
    test('2. The prompt explicitly labels fallback excerpts as partial fallback excerpts', () {
      final paper = createTestPaper(id: 'paper1', title: 'Knowledge-Intensive NLP Tasks');
      final chunks = [
        const PdfChunk(
          id: 'c_meth',
          text: 'We combine pre-trained parametric memory (BART) with non-parametric retrieval memory (DPR).',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
      ];
      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text content',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Pertanyaan teknis tanpa BM25 hit',
      );

      expect(prompt, contains('fallback excerpts'));
      expect(prompt, contains('bukan representasi lengkap dari seluruh isi dokumen PDF'));
    });

    // 3. The prompt distinguishes absence from retrieved excerpts from absence in the full paper
    test('3. The prompt distinguishes absence from retrieved excerpts vs absence in full paper', () {
      final paper = createTestPaper(id: 'paper1', title: 'Knowledge-Intensive NLP Tasks');
      final chunks = [
        const PdfChunk(
          id: 'c_meth',
          text: 'Retriever details and parametric generator.',
          sectionTitle: 'Methodology',
          charOffset: 500,
        ),
      ];
      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text content',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Pertanyaan teknis tanpa BM25 hit',
      );

      expect(prompt, contains('belum dapat dipastikan dari cuplikan teks yang tersedia'));
      expect(prompt, contains('JANGAN menyimpulkan atau mengklaim bahwa informasi tersebut tidak ada di seluruh dokumen'));
      expect(prompt, contains('JANGAN mengarang nomor halaman, kutipan, dataset, metrik, metode, atau hasil'));
    });

    // 4. Relevant fallback evidence remains included in the final prompt
    test('4. Relevant fallback evidence remains included in the final prompt under noMatches', () {
      final paper = createTestPaper(id: 'paper1', title: 'Dense Passage Retrieval');
      final chunks = [
        const PdfChunk(
          id: 'c_intro',
          text: 'Introduction to open-domain question answering and dual-encoder architectures.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c_arch',
          text: 'Dual-encoder architecture uses BERT-base to embed queries and passages into 768-dimensional vectors.',
          sectionTitle: 'Model Architecture',
          charOffset: 1200,
        ),
      ];
      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      // Kueri cara kerja yang memetakan target seksi arsitektur tanpa kecocokan leksikal BM25
      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Jelaskan cara kerja komponen inferensi ini',
      );

      expect(prompt, contains('Status Bukti: Tidak ditemukan kutipan spesifik'));
      expect(prompt, contains('[Konteks Cadangan - Bagian: Model Architecture'));
      expect(prompt, contains('Dual-encoder architecture uses BERT-base'));
    });

    // 5. Unsupported claims must not be inferred from title or bibliography alone
    test('5. Unsupported claims must not be inferred from title or bibliography alone', () {
      final paper = createTestPaper(id: 'paper_bib', title: 'Survey on Large Language Models');
      final chunks = [
        const PdfChunk(
          id: 'c_ref1',
          text: '[1] Brown et al. Language models are few-shot learners. NeurIPS 2020.\n[2] Devlin et al. BERT. NAACL 2019.',
          sectionTitle: 'References',
          charOffset: 5000,
        ),
      ];
      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'References only',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Berapa akurasi exact match pada dataset TriviaQA?',
      );

      // Prompt secara ketat memperingatkan untuk tidak mengarang klaim dari judul/referensi
      expect(prompt, contains('Jangan mengarang bukti atau klaim yang tidak ada dalam teks'));
      expect(prompt, contains('jawablah hanya berdasarkan bukti tersebut'));
      expect(prompt, contains('belum dapat dipastikan dari cuplikan teks yang tersedia'));
    });

    // 6. Section diversity: Compound query gathers distinct relevant sections
    test('6. Evidence budget prefers section diversity for compound queries', () {
      final chunks = [
        const PdfChunk(
          id: 'c_m1',
          text: 'Methodology part 1: Mathematical formulation of the dual-encoder objective.',
          sectionTitle: 'Methodology',
          charOffset: 1000,
        ),
        const PdfChunk(
          id: 'c_m2',
          text: 'Methodology part 2: Further implementation details of optimizer and loss.',
          sectionTitle: 'Methodology',
          charOffset: 2000,
        ),
        const PdfChunk(
          id: 'c_r1',
          text: 'Results part 1: Exact match on Natural Questions is 44.5% compared to 38.8% baseline.',
          sectionTitle: 'Results',
          charOffset: 4000,
        ),
        const PdfChunk(
          id: 'c_r2',
          text: 'Results part 2: Ablation metrics across different passage lengths.',
          sectionTitle: 'Results',
          charOffset: 5000,
        ),
      ];

      // Kueri majemuk menanyakan metode dan hasil
      final selected = SciChatProvider.selectFallbackChunks(
        chunks: chunks,
        userQuery: 'Jelaskan metodologi dan hasil pengujian model ini',
        maxChunks: 2,
        maxChars: 3000,
      );

      expect(selected.length, equals(2));
      // Dengan diversitas seksi, 1 chunk dari Methodology dan 1 chunk dari Results harus terpilih
      final sectionTitles = selected.map((c) => c.sectionTitle).toSet();
      expect(sectionTitles, contains('Methodology'));
      expect(sectionTitles, contains('Results'));
      expect(selected[0].id, equals('c_m1'));
      expect(selected[1].id, equals('c_r1'));
    });

    // 7. Duplicate chunk control and character cap preservation
    test('7. Duplicate chunk control and strict character cap preservation', () {
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Unique chunk 1 describing architecture.',
          sectionTitle: 'Methodology',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c1_dup',
          text: 'Unique chunk 1 describing architecture.', // Duplicate text & offset
          sectionTitle: 'Methodology',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c2',
          text: 'Unique chunk 2 describing evaluation.',
          sectionTitle: 'Results',
          charOffset: 2000,
        ),
      ];

      final selected = SciChatProvider.selectFallbackChunks(
        chunks: chunks,
        userQuery: 'Jelaskan model dan hasil',
        maxChunks: 3,
        maxChars: 3000,
      );

      // Duplicate chunk with same offset and text must not be inserted twice
      expect(selected.where((c) => c.charOffset == 0).length, equals(1));

      // Character cap test
      const maxCharsLimit = 50;
      final constrained = SciChatProvider.selectFallbackChunks(
        chunks: chunks,
        userQuery: 'Jelaskan model',
        maxChunks: 3,
        maxChars: maxCharsLimit,
      );
      final totalLength = constrained.fold<int>(0, (sum, c) => sum + c.text.length);
      expect(totalLength, lessThanOrEqualTo(maxCharsLimit));
    });

    // 8. Multi-paper context prompt also includes neutralized fallback excerpt guidance
    test('8. Multi-paper context prompt labels fallback excerpts as partial context', () {
      final paper1 = createTestPaper(id: 'paper1', title: 'Paper One');
      final chunks1 = [
        const PdfChunk(
          id: 'c1',
          text: 'Text from paper one without BM25 match.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
      ];
      final evidence1 = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Text from paper one',
        chunks: chunks1,
      );

      final multiPrompt = SciChatProvider.buildMultiPaperContextPrompt(
        papers: [paper1],
        evidenceMap: {'paper1': evidence1},
        userQuery: 'Pertanyaan tanpa kata kunci',
      );

      expect(multiPrompt, contains('fallback excerpts'));
      expect(multiPrompt, contains('bukan teks lengkap seluruh dokumen'));
      expect(multiPrompt, contains('jangan menyimpulkan absen di seluruh paper'));
    });
  });
}
