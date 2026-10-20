import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/utils/pdf_chunker.dart';
import 'package:scichat/utils/lexical_retriever.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/gemini_service.dart';

// Helper to construct valid ArxivPaper fixtures with all required non-null fields
ArxivPaper createTestPaper({
  required String id,
  required String title,
  String summary = 'Valid summary for test paper context.',
  String pdfUrl = 'https://arxiv.org/pdf/test.pdf',
  String? doi,
  List<String> authors = const ['Test Author'],
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: summary,
    published: '2024-01-01',
    updated: '2024-01-01',
    categories: const ['cs.AI'],
    pdfUrl: pdfUrl,
    absUrl: 'https://arxiv.org/abs/$id',
    doi: doi,
  );
}

// Fake implementations for provider tests
class FakeSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    return [];
  }
}

class FakeStorageService extends StorageService {
  String? _apiKey = 'fake_key';

  @override
  Future<String?> getApiKey() async => _apiKey;

  @override
  Future<void> saveApiKey(String key) async {
    _apiKey = key;
  }

  @override
  Future<List<ArxivPaper>?> getCached(String key) async => null;

  @override
  Future<void> setCache(String key, List<ArxivPaper> results) async {}

  @override
  Future<List<ChatSession>> getChatSessions() async => [];

  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}

  @override
  Future<bool> addNote(ResearchNote note) async => true;

  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

class FakePdfService extends PdfService {
  int extractCallCount = 0;
  Duration delay = Duration.zero;
  String? Function(String url, int maxChars)? customExtractor;

  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async {
    extractCallCount++;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (customExtractor != null) {
      return customExtractor!(url, maxChars);
    }
    return 'Introduction: This paper presents deep learning techniques.\n\n'
        'Methodology: We propose an adaptive optimizer.\n\n'
        'Results: The benchmark demonstrates superior convergence.';
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 8000}) async {
    extractCallCount++;
    return 'Introduction: Extracted bytes content.';
  }
}

class FakeGeminiService extends GeminiService {
  String lastUserMessage = '';
  List<ChatMessage> lastHistory = [];
  int chatCallCount = 0;

  FakeGeminiService() : super(apiKey: 'fake_key');

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
  }

  @override
  Future<String> chat({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) async {
    chatCallCount++;
    lastUserMessage = userMessage;
    lastHistory = history;
    return 'Respons AI untuk $userMessage';
  }

  @override
  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    chatCallCount++;
    lastUserMessage = userMessage;
    lastHistory = history;
    yield 'Respons ';
    yield 'Streaming ';
    yield 'Berhasil.';
  }

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required String userQuestion,
    required String aiAnswer,
    List<ArxivPaper> papers = const [],
  }) async {
    return const [];
  }
}

void main() {
  group('Fase 4: Query-Aware PDF Context Retrieval Tests', () {
    // -------------------------------------------------------------------------
    // 1. Query tentang F1-score memilih chunk yang berisi bukti metrik tersebut
    // -------------------------------------------------------------------------
    test('1. Query tentang F1-score memilih chunk yang berisi bukti metrik tersebut', () {
      final paper = createTestPaper(
        id: '2401.0001',
        title: 'Transformer Evaluation on NLP Benchmarks',
        authors: ['Alice Smith'],
        summary: 'Makalah ini mengevaluasi kinerja transformer pada berbagai tugas NLP.',
        pdfUrl: 'https://arxiv.org/pdf/2401.0001.pdf',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Deep neural networks have achieved remarkable milestones in language modeling.',
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
          pageNumber: 5,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text representation',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Berapa nilai F1-score yang diperoleh pada pengujian benchmark?',
      );

      expect(prompt, contains('Konteks Makalah: Transformer Evaluation on NLP Benchmarks'));
      expect(prompt, contains('ID: 2401.0001'));
      expect(prompt, contains('Abstrak (Jangkar Konteks):'));
      expect(prompt, contains('Status Bukti: Ditemukan'));
      expect(prompt, contains('[Bagian: Results, Halaman: 5]'));
      expect(prompt, contains('F1-score of 94.2% and accuracy of 91.5%'));
      expect(prompt, contains('Pertanyaan: Berapa nilai F1-score yang diperoleh pada pengujian benchmark?'));
    });

    // -------------------------------------------------------------------------
    // 2. Query tentang metode/optimasi memilih evidence yang relevan
    // -------------------------------------------------------------------------
    test('2. Query tentang metode/optimasi memilih evidence yang relevan', () {
      final paper = createTestPaper(
        id: '2401.0002',
        title: 'Neural Optimizer Studies',
        authors: ['Bob Jones'],
        summary: 'Studi optimasi pada deep neural networks.',
        pdfUrl: 'https://arxiv.org/pdf/2401.0002.pdf',
      );

      final chunks = [
        const PdfChunk(
          id: 'chunk_intro',
          text: 'Introduction: Optimization in deep learning has been widely studied for decades.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_methods',
          text: 'Methodology: We adopt the AdamW optimization method (metode optimasi) with cosine annealing learning rate scheduler.',
          sectionTitle: 'Methodology',
          charOffset: 400,
          pageNumber: 3,
        ),
        const PdfChunk(
          id: 'chunk_results',
          text: 'Results: Final loss is 0.042 with high stability across runs.',
          sectionTitle: 'Results',
          charOffset: 1000,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Apa metode optimasi yang digunakan dalam penelitian ini?',
      );

      expect(prompt, contains('[Bagian: Methodology, Halaman: 3]'));
      expect(prompt, contains('AdamW optimization method'));
      expect(prompt, contains('cosine annealing learning rate scheduler'));
    });

    // -------------------------------------------------------------------------
    // 3. Satu paper memakai query pengguna untuk retrieval (bukan hanya potong linear)
    // -------------------------------------------------------------------------
    test('3. Satu paper memakai query pengguna untuk retrieval (mencapai bagian jauh dokumen)', () {
      final paper = createTestPaper(
        id: '2401.0003',
        title: 'Deep Vision Architecture Scaling',
        authors: ['Charlie'],
        summary: 'Eksplorasi scaling arsitektur deep vision.',
        pdfUrl: 'https://arxiv.org/pdf/2401.0003.pdf',
      );

      // Skenario: Chunk penting berada di charOffset 25000 (jauh di luar batas linear 8000 char)
      final chunks = [
        const PdfChunk(
          id: 'chunk_1',
          text: 'Introduction: Early background on computer vision and convolutional filters.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_2',
          text: 'Related Work: Previous works by He et al. and Simonyan et al.',
          sectionTitle: 'Related Work',
          charOffset: 4000,
        ),
        const PdfChunk(
          id: 'chunk_3',
          text: 'Experimental Setup: Hardware setup using 8x A100 GPUs and PyTorch 2.0.',
          sectionTitle: 'Experimental Setup',
          charOffset: 9000,
        ),
        const PdfChunk(
          id: 'chunk_4',
          text: 'Ablation Study: Our ablation reveals that removing stochastic depth drops top-1 accuracy by 2.4%.',
          sectionTitle: 'Ablation Study',
          charOffset: 25000,
          pageNumber: 12,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Very long text...',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Bagaimana hasil ablation study mengenai stochastic depth?',
      );

      expect(prompt, contains('[Bagian: Ablation Study, Halaman: 12]'));
      expect(prompt, contains('removing stochastic depth drops top-1 accuracy by 2.4%'));
      // Verifikasi bahwa chunk linear awal yang tidak relevan (seperti Related Work) tidak diprioritaskan
      expect(prompt, isNot(contains('[Bagian: Related Work]')));
    });

    // -------------------------------------------------------------------------
    // 4. Beberapa paper diproses secara independen dan identitas sumber tidak tercampur
    // -------------------------------------------------------------------------
    test('4. Beberapa paper diproses secara independen dan identitas sumber tidak tercampur', () {
      final paper1 = createTestPaper(
        id: 'p1_transformer',
        title: 'Vision Transformers with Self-Attention',
        authors: ['Author A'],
        summary: 'Makalah pertama mengenai mekanik self-attention.',
        pdfUrl: 'https://arxiv.org/pdf/p1.pdf',
      );

      final paper2 = createTestPaper(
        id: 'p2_resnet',
        title: 'Residual Networks for Image Recognition',
        authors: ['Author B'],
        summary: 'Makalah kedua mengenai koneksi residual skip.',
        pdfUrl: 'https://arxiv.org/pdf/p2.pdf',
      );

      const evidence1 = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text p1',
        chunks: [
          PdfChunk(
            id: 'c1',
            text: 'Architecture: Multi-head self-attention computes query-key-value projections across 12 heads.',
            sectionTitle: 'Architecture',
            charOffset: 0,
            pageNumber: 3,
          ),
        ],
      );

      const evidence2 = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text p2',
        chunks: [
          PdfChunk(
            id: 'c2',
            text: 'Formulation: Skip connections add identity mappings to bypass one or more layers.',
            sectionTitle: 'Formulation',
            charOffset: 0,
            pageNumber: 4,
          ),
        ],
      );

      final prompt = SciChatProvider.buildMultiPaperContextPrompt(
        papers: [paper1, paper2],
        evidenceMap: {
          'p1_transformer': evidence1,
          'p2_resnet': evidence2,
        },
        userQuery: 'Bagaimana cara kerja self-attention?',
      );

      // Verifikasi pembagian sumber [1] dan [2]
      expect(prompt, contains('Makalah [1]:'));
      expect(prompt, contains('Judul: Vision Transformers with Self-Attention'));
      expect(prompt, contains('ID: p1_transformer'));
      expect(prompt, contains('[[Architecture, Hal: 3]]'));
      expect(prompt, contains('Multi-head self-attention computes query-key-value'));

      expect(prompt, contains('Makalah [2]:'));
      expect(prompt, contains('Judul: Residual Networks for Image Recognition'));
      expect(prompt, contains('ID: p2_resnet'));
      // Paper 2 tidak memiliki kata kunci self-attention, sehingga melaporkan tidak ada bukti cocok leksikal
      expect(prompt, contains('Tidak ditemukan bukti leksikal spesifik yang cocok'));
      expect(prompt, contains('Catatan: Gunakan abstrak di atas sebagai acuan umum paper ini.'));

      // Bukti dari Paper 1 TIDAK boleh tercampur ke dalam section Paper 2
      final p2Section = prompt.substring(prompt.indexOf('Makalah [2]:'));
      expect(p2Section, isNot(contains('Multi-head self-attention')));
    });

    // -------------------------------------------------------------------------
    // 5. Batas karakter per paper dan total selalu dipatuhi
    // -------------------------------------------------------------------------
    test('5. Batas karakter per paper dan total selalu dipatuhi', () {
      final massiveText1 = 'A' * 6000;
      final massiveText2 = 'B' * 6000;
      final massiveText3 = 'C' * 6000;

      final p1 = createTestPaper(
        id: 'p1',
        title: 'Title 1',
        summary: 'Abstrak 1 yang valid dan representatif untuk analisis.',
      );
      final p2 = createTestPaper(
        id: 'p2',
        title: 'Title 2',
        summary: 'Abstrak 2 yang valid dan representatif untuk analisis.',
      );
      final p3 = createTestPaper(
        id: 'p3',
        title: 'Title 3',
        summary: 'Abstrak 3 yang valid dan representatif untuk analisis.',
      );

      final ev1 = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: massiveText1,
        chunks: [
          PdfChunk(id: 'c1', text: 'Keyword target: $massiveText1', sectionTitle: 'Section 1', charOffset: 0),
        ],
      );
      final ev2 = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: massiveText2,
        chunks: [
          PdfChunk(id: 'c2', text: 'Keyword target: $massiveText2', sectionTitle: 'Section 2', charOffset: 0),
        ],
      );
      final ev3 = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: massiveText3,
        chunks: [
          PdfChunk(id: 'c3', text: 'Keyword target: $massiveText3', sectionTitle: 'Section 3', charOffset: 0),
        ],
      );

      final multiPrompt = SciChatProvider.buildMultiPaperContextPrompt(
        papers: [p1, p2, p3],
        evidenceMap: {'p1': ev1, 'p2': ev2, 'p3': ev3},
        userQuery: 'target',
      );

      // Verifikasi batas total
      expect(multiPrompt.length, lessThanOrEqualTo(SciChatProvider.kMultiPaperTotalMaxChars));

      // Verifikasi single paper prompt juga memiliki batas wajar
      final singlePrompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: p1,
        evidence: ev1,
        userQuery: 'target',
      );
      expect(singlePrompt.length, lessThan(8000));
    });

    // -------------------------------------------------------------------------
    // 6. Query kosong dan stopword-only menggunakan fallback eksplisit
    // -------------------------------------------------------------------------
    test('6. Query kosong dan stopword-only menggunakan fallback eksplisit', () {
      final paper = createTestPaper(
        id: '2401.0006',
        title: 'Overview Paper on AI',
        summary: 'Makalah pengantar umum mengenai AI modern.',
      );

      final chunks = [
        const PdfChunk(
          id: 'c_start',
          text: 'Introduction: Artificial intelligence has transformed numerous computational domains.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      // Kasus A: Query kosong
      final promptEmpty = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: '   ',
      );
      expect(promptEmpty, contains('Status Bukti: Pertanyaan umum / eksplorasi umum (tidak ada kata kunci spesifik).'));
      expect(promptEmpty, contains('Bagian Awal Dokumen (Konteks Umum):'));
      expect(promptEmpty, contains('[Bagian: Introduction]'));

      // Kasus B: Query hanya stopword (Indonesian & English)
      final promptStopwords = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'dan yang di ke and the is in on at',
      );
      expect(promptStopwords, contains('Status Bukti: Pertanyaan umum / eksplorasi umum (tidak ada kata kunci spesifik).'));
      expect(promptStopwords, contains('Bagian Awal Dokumen (Konteks Umum):'));
    });

    // -------------------------------------------------------------------------
    // 7. Query tanpa kecocokan tidak mengklaim bahwa bukti ditemukan
    // -------------------------------------------------------------------------
    test('7. Query tanpa kecocokan tidak mengklaim bahwa bukti ditemukan (anti-halusinasi)', () {
      final paper = createTestPaper(
        id: '2401.0007',
        title: 'Deep Learning Vision Transformers',
        summary: 'Penelitian komprehensif mengenai visi komputer menggunakan transformer.',
      );

      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Vision transformers process image patches as token sequences.',
          sectionTitle: 'Methods',
          charOffset: 0,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      // Query topik fisika kuantum yang sama sekali tidak ada di paper
      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Bagaimana fenomena teleportasi kuantum dan superposisi partikel qubit?',
      );

      expect(prompt, contains('Status Bukti: Tidak ditemukan kutipan spesifik'));
      expect(prompt, contains('Peringatan: Jangan mengarang bukti atau klaim yang tidak ada dalam teks.'));
      expect(prompt, contains('Gunakan abstrak di atas sebagai acuan umum'));
      expect(prompt, isNot(contains('Ditemukan 1 bagian relevan')));
    });

    // -------------------------------------------------------------------------
    // 8. PDF tanpa teks atau ekstraksi gagal tidak menyebabkan crash
    // -------------------------------------------------------------------------
    test('8. PDF tanpa teks atau ekstraksi gagal tidak menyebabkan crash', () {
      final paper = createTestPaper(
        id: '2401.0008',
        title: 'Paper Without Accessible Text',
        summary: 'Abstrak pendek yang masih sah sebagai ringkasan dasar penelitian.',
      );

      // Kasus A: AbstractOnly
      final promptAbstractOnly = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: const PaperEvidence(level: EvidenceLevel.abstractOnly),
        userQuery: 'Apa metodologi penelitian ini?',
      );
      expect(promptAbstractOnly, contains('Status Bukti: Hanya Abstrak (Teks lengkap PDF tidak tersedia atau gagal diekstrak).'));
      expect(promptAbstractOnly, contains('Batasi jawaban Anda HANYA pada informasi yang tercantum dalam abstrak'));

      // Kasus B: NoUsableText
      final promptNoUsable = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: const PaperEvidence(level: EvidenceLevel.noUsableText),
        userQuery: 'Apa kesimpulan eksperimen?',
      );
      expect(promptNoUsable, contains('Status Bukti: Tidak ada teks yang dapat digunakan (No Usable Text).'));

      // Kasus C: Evidence null (belum diekstrak)
      final promptNull = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: null,
        userQuery: 'Pertanyaan umum',
      );
      expect(promptNull, contains('Status Bukti: Ekstraksi teks PDF belum selesai.'));
    });

    // -------------------------------------------------------------------------
    // 9. Cache hit dan in-flight deduplication tetap berfungsi
    // -------------------------------------------------------------------------
    test('9. Cache hit dan in-flight deduplication tetap berfungsi dengan chunked evidence', () async {
      final fakePdf = FakePdfService();
      fakePdf.delay = const Duration(milliseconds: 50);

      final fakeStorage = FakeStorageService();
      final fakeSearch = FakeSearchService();
      final fakeGemini = FakeGeminiService();

      final provider = SciChatProvider(
        searchService: fakeSearch,
        geminiService: fakeGemini,
        pdfService: fakePdf,
        storageService: fakeStorage,
      );

      final paper = createTestPaper(
        id: '2401.0009',
        title: 'Caching and Deduplication Paper',
        summary: 'Penelitian tentang caching sistem terdistribusi.',
      );

      // Jalankan 2 pemanggilan in-flight paralel untuk paper yang sama
      final future1 = provider.fetchPaperEvidence(paper);
      final future2 = provider.fetchPaperEvidence(paper);

      final results = await Future.wait([future1, future2]);

      // Verifikasi deduplikasi in-flight: hanya 1x pemanggilan PDF service
      expect(fakePdf.extractCallCount, equals(1));
      expect(results[0].level, equals(EvidenceLevel.fullText));
      expect(results[1].level, equals(EvidenceLevel.fullText));
      expect(results[0].chunks, isNotEmpty);
      expect(identical(results[0], results[1]), isTrue);

      // Verifikasi cache hit: pemanggilan ketiga langsung membaca dari cache tanpa memanggil service
      final cachedResult = await provider.fetchPaperEvidence(paper);
      expect(fakePdf.extractCallCount, equals(1));
      expect(cachedResult.chunks, isNotEmpty);
      expect(identical(cachedResult, results[0]), isTrue);
    });

    // -------------------------------------------------------------------------
    // 10. Chunk overlap tidak menimbulkan pengulangan konteks berlebihan
    // -------------------------------------------------------------------------
    test('10. Chunk overlap tidak menimbulkan pengulangan konteks berlebihan', () {
      final sampleParagraphs = [
        'Introduction: Deep learning architectures utilize multilayer perceptrons with non-linear activation functions to approximate complex continuous mappings in high dimensional space.',
        'Methodology: Convolutional layers capture spatial translation invariance and hierarchical representations, while transformer blocks leverage self-attention mechanisms to dynamically weigh token interactions across arbitrary sequence lengths.',
        'Attention Analysis: Attention layers model pairwise token relationships through scaled dot-product operations, creating dense attention maps that visualize semantic alignments across cross-lingual corpora.',
        'Optimization & Regularization: Normalization layers such as LayerNorm and RMSNorm stabilize gradient variance during backpropagation, enabling stable training of deep networks with hundreds of layers without gradient explosion.',
      ].join('\n\n');

      final chunks = PdfChunker.chunkText(
        sampleParagraphs,
        targetChunkSize: 200,
        overlapSize: 50,
      );

      expect(chunks.length, greaterThan(1));

      // Verifikasi offset tidak regresif
      for (int i = 1; i < chunks.length; i++) {
        expect(chunks[i].charOffset, greaterThan(chunks[i - 1].charOffset));
      }

      // Verifikasi retriever combinedText tidak menduplikasi seluruh teks berkali-kali
      final retrieval = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'attention pairwise token',
        maxChunks: 2,
        maxChars: 500,
      );

      expect(retrieval.isFallback, isFalse);
      expect(retrieval.combinedText.length, lessThanOrEqualTo(500));
    });

    // -------------------------------------------------------------------------
    // 11. Cancellation atau pergantian konteks tidak memasukkan evidence dari generasi lama
    // -------------------------------------------------------------------------
    test('11. Cancellation atau pergantian konteks tidak memasukkan evidence dari generasi lama', () async {
      final fakePdf = FakePdfService();
      fakePdf.delay = const Duration(milliseconds: 100);

      final fakeStorage = FakeStorageService();
      final fakeSearch = FakeSearchService();
      final fakeGemini = FakeGeminiService();

      final provider = SciChatProvider(
        searchService: fakeSearch,
        geminiService: fakeGemini,
        pdfService: fakePdf,
        storageService: fakeStorage,
      );

      final paperA = createTestPaper(
        id: 'paper_A',
        title: 'Makalah A',
        summary: 'Ringkasan paper A yang valid.',
      );

      final paperB = createTestPaper(
        id: 'paper_B',
        title: 'Makalah B',
        summary: 'Ringkasan paper B yang valid.',
      );

      // 1. Set active paper A (memicu _retrieveEvidence A)
      provider.setActivePaper(paperA);
      expect(provider.activePaperContext?.id, equals('paper_A'));

      // 2. Sebelum ekstraksi A selesai, ganti konteks ke paper B
      await Future.delayed(const Duration(milliseconds: 20));
      provider.setActivePaper(paperB);
      expect(provider.activePaperContext?.id, equals('paper_B'));

      // 3. Tunggu hingga delay operasi A selesai
      await Future.delayed(const Duration(milliseconds: 150));

      // 4. Verifikasi bahwa konteks aktif tetap paper B dan evidence konteks aktif adalah untuk paper B
      expect(provider.activePaperContext?.id, equals('paper_B'));
      expect(provider.activeContexts.length, equals(1));
      expect(provider.activeContexts.first.id, equals('paper_B'));
    });

    // -------------------------------------------------------------------------
    // 12. Prompt tetap menyertakan identitas sumber yang benar (termasuk DOI)
    // -------------------------------------------------------------------------
    test('12. Prompt tetap menyertakan identitas sumber yang benar', () {
      final paperWithDoi = createTestPaper(
        id: '1706.03762',
        title: 'Attention Is All You Need',
        authors: ['Vaswani et al.'],
        summary: 'We propose the Transformer, a model architecture eschewing recurrence.',
        doi: '10.48550/arXiv.1706.03762',
      );

      final promptWithDoi = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paperWithDoi,
        evidence: const PaperEvidence(level: EvidenceLevel.abstractOnly),
        userQuery: 'What is the core contribution?',
      );

      expect(promptWithDoi, contains('Konteks Makalah: Attention Is All You Need'));
      expect(promptWithDoi, contains('ID: 1706.03762'));
      expect(promptWithDoi, contains('DOI: 10.48550/arXiv.1706.03762'));

      final paperWithoutDoi = createTestPaper(
        id: '1706.03763',
        title: 'Paper Without DOI',
        summary: 'Valid summary of the paper without DOI.',
      );

      final promptWithoutDoi = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paperWithoutDoi,
        evidence: const PaperEvidence(level: EvidenceLevel.abstractOnly),
        userQuery: 'What is the core contribution?',
      );

      expect(promptWithoutDoi, contains('ID: 1706.03763'));
      // Tidak boleh ada baris DOI palsu atau kosong
      expect(promptWithoutDoi, isNot(contains('DOI:')));
    });

    // -------------------------------------------------------------------------
    // 13. Regresi pada streaming, branching, retry, dan integritas konteks
    // -------------------------------------------------------------------------
    test('13. Regresi pada streaming sendMessage dengan active paper menggunakan query retrieval', () async {
      final fakePdf = FakePdfService();
      fakePdf.customExtractor = (url, maxChars) {
        return 'Introduction: Transformer models in language.\n\n'
            'Methodology: Pre-training on massive corpora.\n\n'
            'Results: Accuracy reaches 96.5% on downstream evaluation.';
      };

      final fakeStorage = FakeStorageService();
      final fakeSearch = FakeSearchService();
      final fakeGemini = FakeGeminiService();

      final provider = SciChatProvider(
        searchService: fakeSearch,
        geminiService: fakeGemini,
        pdfService: fakePdf,
        storageService: fakeStorage,
      );

      final paper = createTestPaper(
        id: '2401.0013',
        title: 'Downstream Evaluation of Transformers',
        summary: 'Evaluasi downstream model bahasa.',
      );

      provider.setActivePaper(paper);

      // Kirim pesan dengan pertanyaan tentang akurasi
      await provider.sendMessage('Berapa accuracy pada downstream evaluation?');

      // Verifikasi bahwa fakeGemini menerima prompt yang memuat hasil retrieval query-aware
      expect(fakeGemini.chatCallCount, equals(1));
      expect(fakeGemini.lastUserMessage, contains('Konteks Makalah: Downstream Evaluation of Transformers'));
      expect(fakeGemini.lastUserMessage, contains('ID: 2401.0013'));
      expect(fakeGemini.lastUserMessage, contains('Accuracy reaches 96.5%'));
      expect(fakeGemini.lastUserMessage, contains('Berapa accuracy pada downstream evaluation?'));

      // Verifikasi pesan masuk ke riwayat chat provider
      expect(provider.messages.length, equals(2));
      expect(provider.messages[0].isUser, isTrue);
      expect(provider.messages[1].isUser, isFalse);
      expect(provider.messages[1].content, contains('Respons Streaming Berhasil.'));

      // Verifikasi branching session tetap bekerja
      final branchSuccess = await provider.branchSessionFromMessage(provider.messages[1].id);
      expect(branchSuccess, isTrue);
      expect(provider.sessions.length, equals(2));
    });
  });
}
