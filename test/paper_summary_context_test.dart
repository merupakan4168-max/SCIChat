import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/utils/summary_context_selector.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

ArxivPaper createSummaryTestPaper({
  required String id,
  required String title,
  String summary = 'Abstrak penelitian yang valid sebagai context anchor ringkasan.',
  String pdfUrl = 'https://arxiv.org/pdf/test.pdf',
  String? doi,
  List<String> authors = const ['Test Author', 'Co-Author'],
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

class FakePdfSummaryService extends PdfService {
  int extractCallCount = 0;
  Duration delay = Duration.zero;
  String? returnText;

  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async {
    extractCallCount++;
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    return returnText ??
        'Introduction: Background on foundation models.\n\n'
        'Methodology: Architectural formulation and training objective.\n\n'
        'Results: Experimental results showing state-of-the-art accuracy.\n\n'
        'Discussion: Analysis of limitations and computational footprint.\n\n'
        'Conclusion: Concluding remarks and future directions.';
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 8000}) async {
    extractCallCount++;
    return returnText ?? 'Bytes content';
  }
}

class FakeGeminiSummaryService extends GeminiService {
  int summarizeCallCount = 0;
  String lastPdfText = '';
  String lastCustomPrompt = '';
  String summaryResponse =
      '**Apa yang dilakukan** — Kontribusi utama dalam 2 kalimat.\n'
      '**Metodologi** — Metode utama yang digunakan.\n'
      '**Temuan utama** — Hasil kuantitatif F1-score 94.2%.\n'
      '**Keterbatasan & Catatan** — Keterbatasan komputasi.\n'
      '**Siapa yang harus membaca ini** — Peneliti deep learning.';

  FakeGeminiSummaryService() : super(apiKey: 'fake_key');

  @override
  Future<String> summarizePaper(
    ArxivPaper paper, {
    String? pdfText,
  }) async {
    summarizeCallCount++;
    lastPdfText = pdfText ?? '';
    return summaryResponse;
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
    yield 'Chat response stream';
  }

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
  }
}

void main() {
  group('Fase 5: Full-Paper Summary Context Optimization Tests', () {
    // -------------------------------------------------------------------------
    // 1. Ringkasan mempertahankan representasi abstract dan seksi-seksi penting
    // -------------------------------------------------------------------------
    test('1. Ringkasan mempertahankan representasi abstract dan seksi penting (IMRaD + Conclusion)', () {
      final paper = createSummaryTestPaper(
        id: '2401.5001',
        title: 'Deep Architecture Analysis',
        summary: 'Abstrak: Makalah ini mengeksplorasi representasi pengetahuan laten.',
      );

      final chunks = [
        const PdfChunk(
          id: 'c_intro',
          text: 'Introduction: Neural synthesis transforms visual and textual modalities into unified spaces.',
          sectionTitle: 'Introduction',
          charOffset: 0,
          pageNumber: 1,
        ),
        const PdfChunk(
          id: 'c_methods',
          text: 'Methodology: We propose sparse mixture-of-experts routing with top-2 gate dispatching.',
          sectionTitle: 'Methodology',
          charOffset: 2000,
          pageNumber: 4,
        ),
        const PdfChunk(
          id: 'c_results',
          text: 'Results: Our architecture achieves 94.8% top-1 accuracy on ImageNet benchmarks.',
          sectionTitle: 'Results',
          charOffset: 6000,
          pageNumber: 7,
        ),
        const PdfChunk(
          id: 'c_discussion',
          text: 'Discussion: Scaling expert counts beyond 64 shows diminishing returns in latency.',
          sectionTitle: 'Discussion',
          charOffset: 9000,
          pageNumber: 9,
        ),
        const PdfChunk(
          id: 'c_conclusion',
          text: 'Conclusion: Sparse routing provides an efficient blueprint for multi-modal scaling.',
          sectionTitle: 'Conclusion',
          charOffset: 12000,
          pageNumber: 11,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text representation',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: evidence,
      );

      // Verifikasi Abstract sebagai anchor
      expect(prompt, contains('Abstrak (Jangkar Konteks):'));
      expect(prompt, contains('Makalah ini mengeksplorasi representasi pengetahuan laten.'));

      // Verifikasi seluruh seksi utama terwakili secara seimbang
      expect(prompt, contains('[[Bagian: Introduction, Hal: 1]]'));
      expect(prompt, contains('Neural synthesis transforms visual and textual modalities'));
      expect(prompt, contains('[[Bagian: Methodology, Hal: 4]]'));
      expect(prompt, contains('sparse mixture-of-experts routing'));
      expect(prompt, contains('[[Bagian: Results, Hal: 7]]'));
      expect(prompt, contains('achieves 94.8% top-1 accuracy'));
      expect(prompt, contains('[[Bagian: Discussion, Hal: 9]]'));
      expect(prompt, contains('Scaling expert counts beyond 64'));
      expect(prompt, contains('[[Bagian: Conclusion, Hal: 11]]'));
      expect(prompt, contains('Sparse routing provides an efficient blueprint'));
    });

    // -------------------------------------------------------------------------
    // 2. Bagian Results atau Conclusion yang berada jauh di dokumen tetap terpilih
    // -------------------------------------------------------------------------
    test('2. Bagian Results atau Conclusion di offset dokumen yang jauh tetap terpilih', () {
      final paper = createSummaryTestPaper(
        id: '2401.5002',
        title: 'Long Monolithic Paper',
      );

      // Skenario: Dokumen 35.000 karakter, Results di offset 25.000 dan Conclusion di 32.000
      final chunks = [
        const PdfChunk(
          id: 'c_intro',
          text: 'Introduction: Historical overview of continuous optimization.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c_related',
          text: 'Related Work: Discussion of prior classical algorithms from 1980 to 2010.',
          sectionTitle: 'Related Work',
          charOffset: 5000,
        ),
        const PdfChunk(
          id: 'c_theory',
          text: 'Theoretical Foundation: Proof of convex convergence bounds under Lipschitz continuity.',
          sectionTitle: 'Theory',
          charOffset: 15000,
        ),
        const PdfChunk(
          id: 'c_results',
          text: 'Results: Empirical evaluation confirms theoretical speedup with 3.2x faster convergence.',
          sectionTitle: 'Results',
          charOffset: 25000,
          pageNumber: 18,
        ),
        const PdfChunk(
          id: 'c_conclusion',
          text: 'Conclusion: The proposed optimizer establishes optimal minimax rates for non-convex objectives.',
          sectionTitle: 'Conclusion',
          charOffset: 32000,
          pageNumber: 22,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: evidence,
      );

      // Verifikasi bagian akhir dokumen tetap terwakili (tidak dipotong di 8000 karakter awal)
      expect(prompt, contains('[[Bagian: Results, Hal: 18]]'));
      expect(prompt, contains('Empirical evaluation confirms theoretical speedup with 3.2x'));
      expect(prompt, contains('[[Bagian: Conclusion, Hal: 22]]'));
      expect(prompt, contains('optimal minimax rates for non-convex objectives'));
    });

    // -------------------------------------------------------------------------
    // 3. Dokumen tanpa heading menggunakan fallback tersebar dan deterministik
    // -------------------------------------------------------------------------
    test('3. Dokumen tanpa heading menggunakan fallback stratified sampling yang deterministik', () {
      // Buat 10 chunk tanpa heading akademik (semua 'General')
      final chunks = List.generate(10, (i) {
        return PdfChunk(
          id: 'chunk_$i',
          text: 'Content span index $i covering specialized subtopics in computational domain $i.',
          sectionTitle: 'General',
          charOffset: i * 1500,
        );
      });

      final result = SummaryContextSelector.selectChunks(chunks: chunks);

      expect(result.hasHeadings, isFalse);
      expect(result.selectedChunks, isNotEmpty);

      // Verifikasi sampel mencakup awal (index 0), tengah (index 5), dan akhir (index 9)
      final selectedIds = result.selectedChunks.map((c) => c.id).toList();
      expect(selectedIds, contains('chunk_0')); // Awal
      expect(selectedIds, contains('chunk_5')); // Tengah
      expect(selectedIds, contains('chunk_9')); // Akhir

      // Verifikasi urutan natural offset tetap terjaga
      for (int i = 1; i < result.selectedChunks.length; i++) {
        expect(result.selectedChunks[i].charOffset,
            greaterThan(result.selectedChunks[i - 1].charOffset));
      }
    });

    // -------------------------------------------------------------------------
    // 4. Overlap chunk tidak menghasilkan duplikasi berlebihan
    // -------------------------------------------------------------------------
    test('4. Overlap chunk dideduplikasi agar tidak berulang berlebihan', () {
      const sentence1 = 'Deep neural networks learn hierarchical representations across multiple layers.';
      const sentenceOverlap = 'Convolutional filters extract localized spatial features while preserving translation invariance.';
      const sentence3 = 'Transformer self-attention models global dependencies across sequences.';

      const chunkA = PdfChunk(
        id: 'a',
        text: '$sentence1\n\n$sentenceOverlap',
        sectionTitle: 'Architecture',
        charOffset: 0,
      );

      const chunkB = PdfChunk(
        id: 'b',
        text: '$sentenceOverlap\n\n$sentence3',
        sectionTitle: 'Architecture',
        charOffset: 500,
      );

      final result = SummaryContextSelector.selectChunks(chunks: [chunkA, chunkB]);

      // Verifikasi sentenceOverlap tidak muncul dua kali dalam formattedContext
      final firstIdx = result.formattedContext.indexOf(sentenceOverlap);
      final lastIdx = result.formattedContext.lastIndexOf(sentenceOverlap);
      expect(firstIdx, equals(lastIdx),
          reason: 'Overlap text yang identik tidak boleh terulang dua kali berturut-turut');
    });

    // -------------------------------------------------------------------------
    // 5. Total konteks ringkasan tidak pernah melewati batas 16.000 karakter
    // -------------------------------------------------------------------------
    test('5. Total prompt ringkasan tidak pernah melewati plafon keras 16.000 karakter', () {
      final paper = createSummaryTestPaper(
        id: '2401.5005',
        title: 'Massive Paper Benchmark',
      );

      // Buat chunk raksasa masing-masing 5000 karakter
      final giantChunks = List.generate(8, (i) {
        return PdfChunk(
          id: 'giant_$i',
          text: 'Section $i: ${"X" * 4000}',
          sectionTitle: 'Methods $i',
          charOffset: i * 4000,
        );
      });

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Giant text',
        chunks: giantChunks,
      );

      final prompt = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: evidence,
      );

      expect(prompt.length, lessThanOrEqualTo(SummaryContextSelector.kMaxTotalPromptChars));
      expect(prompt.length, lessThanOrEqualTo(16000));
    });

    // -------------------------------------------------------------------------
    // 6. Label dan metadata sumber dipertahankan tanpa mengarang nomor halaman
    // -------------------------------------------------------------------------
    test('6. Label dan metadata dipertahankan dan nomor halaman tidak dikarang jika unknown', () {
      final paperWithDoi = createSummaryTestPaper(
        id: '2401.5006',
        title: 'Provenance Paper',
        doi: '10.1234/scichat.2024',
        authors: ['Alice Doe', 'Bob Ray'],
      );

      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Introduction without page number.',
          sectionTitle: 'Introduction',
          charOffset: 0,
          pageNumber: PdfChunk.kUnknownPage, // Sentinel unknown
        ),
        const PdfChunk(
          id: 'c2',
          text: 'Results with known page number.',
          sectionTitle: 'Results',
          charOffset: 1000,
          pageNumber: 14,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildPaperSummaryPrompt(
        paper: paperWithDoi,
        evidence: evidence,
      );

      expect(prompt, contains('Judul: Provenance Paper'));
      expect(prompt, contains('Penulis: Alice Doe, Bob Ray'));
      expect(prompt, contains('DOI: 10.1234/scichat.2024'));

      // Chunk 1 tidak boleh mencantumkan nomor halaman palsu atau -1
      expect(prompt, contains('[[Bagian: Introduction]]'));
      expect(prompt, isNot(contains('[[Bagian: Introduction, Hal:')));

      // Chunk 2 mencantumkan nomor halaman asli
      expect(prompt, contains('[[Bagian: Results, Hal: 14]]'));
    });

    // -------------------------------------------------------------------------
    // 7. Dokumen yang hanya memiliki sebagian teks ditandai dengan benar
    // -------------------------------------------------------------------------
    test('7. Dokumen dengan ekstraksi parsial mencantumkan pemberitahuan cakupan', () {
      final paper = createSummaryTestPaper(
        id: '2401.5007',
        title: 'Partial Paper',
      );

      // Hanya ada Introduction, seksi Methods dan Results tidak ada
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Introduction: Only early background could be extracted before download truncated.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Partial text',
        chunks: chunks,
      );

      final prompt = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: evidence,
      );

      expect(prompt, contains('Pemberitahuan Cakupan Dokumen: Teks PDF yang diekstrak mencakup sebagian dokumen.'));
      expect(prompt, contains('Bagian yang tidak tercantum mungkin berada di luar jangkauan ekstraksi.'));
    });

    // -------------------------------------------------------------------------
    // 8. PDF kosong, tidak tersedia, atau gagal diekstrak menghasilkan fallback aman
    // -------------------------------------------------------------------------
    test('8. PDF kosong, tidak tersedia, atau gagal diekstrak menghasilkan fallback aman', () {
      final paper = createSummaryTestPaper(
        id: '2401.5008',
        title: 'Abstract Only Paper',
        summary: 'Ringkasan ilmiah abstrak yang sah.',
      );

      // Kasus A: abstractOnly
      final promptAbstract = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: const PaperEvidence(level: EvidenceLevel.abstractOnly),
      );
      expect(promptAbstract, contains('Status Bukti: Hanya Abstrak (Teks lengkap PDF tidak tersedia atau gagal diekstrak).'));
      expect(promptAbstract, contains('Batasi rangkuman HANYA pada informasi yang tercantum dalam abstrak'));

      // Kasus B: noUsableText
      final promptNoUsable = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: const PaperEvidence(level: EvidenceLevel.noUsableText),
      );
      expect(promptNoUsable, contains('Status Bukti: Tidak ada teks yang dapat digunakan (No Usable Text).'));

      // Kasus C: null evidence
      final promptNull = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: null,
      );
      expect(promptNull, contains('Status Bukti: Ekstraksi teks PDF belum selesai'));
    });

    // -------------------------------------------------------------------------
    // 9. Cache, retry, dan in-flight deduplication tetap bekerja pada summarizePaper
    // -------------------------------------------------------------------------
    test('9. Cache, retry, dan in-flight deduplication tetap bekerja pada summarizePaper', () async {
      final fakePdf = FakePdfSummaryService();
      fakePdf.delay = const Duration(milliseconds: 50);

      final fakeGemini = FakeGeminiSummaryService();
      final storage = StorageService();
      SharedPreferences.setMockInitialValues({});

      final provider = SciChatProvider(
        pdfService: fakePdf,
        geminiService: fakeGemini,
        storageService: storage,
        searchService: SearchService(),
      );

      await provider.init();
      await provider.setApiKey('test_key');

      final paper = createSummaryTestPaper(
        id: '2401.5009',
        title: 'Concurrent Summary Paper',
      );

      // Panggil summarizePaper 2x secara bersamaan untuk paper yang sama
      final future1 = provider.summarizePaper(paper);
      final future2 = provider.summarizePaper(paper);

      final results = await Future.wait([future1, future2]);

      // In-flight deduplication: hanya 1x panggilan ekstraksi PDF
      expect(fakePdf.extractCallCount, equals(1));
      expect(results[0], isNotNull);
      expect(results[1], isNotNull);
      expect(results[0], equals(results[1]));

      // Pemanggilan ketiga: membaca dari cache LRU tanpa mengekstrak ulang PDF
      final thirdResult = await provider.summarizePaper(paper);
      expect(fakePdf.extractCallCount, equals(1));
      expect(thirdResult, equals(results[0]));
    });

    // -------------------------------------------------------------------------
    // 10. Jalur Tanya Paper Fase 4 tidak berubah perilakunya
    // -------------------------------------------------------------------------
    test('10. Jalur Tanya Paper Fase 4 tetap beroperasi independen dengan BM25 query-aware retrieval', () async {
      final paper = createSummaryTestPaper(
        id: '2401.5010',
        title: 'Query Aware Isolation Paper',
      );

      final chunks = [
        const PdfChunk(
          id: 'c_intro',
          text: 'Introduction: General discussion on artificial intelligence.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c_f1',
          text: 'Results: On the GLUE benchmark, our model obtains an F1-score of 93.4%.',
          sectionTitle: 'Results',
          charOffset: 1500,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      // Verifikasi buildSinglePaperContextPrompt Tanya Paper Fase 4 tetap menggunakan user query
      final chatPrompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: 'Berapa F1-score pada benchmark GLUE?',
      );

      expect(chatPrompt, contains('[Bagian: Results]'));
      expect(chatPrompt, contains('F1-score of 93.4%'));
      expect(chatPrompt, contains('Pertanyaan: Berapa F1-score pada benchmark GLUE?'));

      // Sedangkan summary prompt Fase 5 berorientasi pada cakupan menyeluruh (tanpa query spesifik)
      final summaryPrompt = SciChatProvider.buildPaperSummaryPrompt(
        paper: paper,
        evidence: evidence,
      );
      expect(summaryPrompt, contains('INSTRUKSI RANGKUMAN (EVIDENCE-FIRST)'));
      expect(summaryPrompt, isNot(contains('Pertanyaan: Berapa F1-score')));
    });

    // -------------------------------------------------------------------------
    // 11. Penyimpanan ringkasan ke Notes/Favorites tetap kompatibel
    // -------------------------------------------------------------------------
    test('11. Penyimpanan ringkasan ke Notes/Favorites tetap kompatibel', () async {
      final storage = StorageService();
      SharedPreferences.setMockInitialValues({});

      final provider = SciChatProvider(
        pdfService: FakePdfSummaryService(),
        geminiService: FakeGeminiSummaryService(),
        storageService: storage,
        searchService: SearchService(),
      );

      await provider.init();
      await provider.setApiKey('test_key');

      final paper = createSummaryTestPaper(
        id: '2401.5011',
        title: 'Saveable Summary Paper',
      );

      final summary = await provider.summarizePaper(paper);
      expect(summary, isNotNull);

      // Simpan ringkasan ke storage
      final saved = await provider.savePaperSummary(
        paper: paper,
        summary: summary!,
      );

      expect(saved, isTrue);
      expect(provider.isPaperSummarySaved(paper.id), isTrue);
      expect(provider.notes.length, equals(1));
      expect(provider.notes.first.isPaperSummary, isTrue);
      expect(provider.notes.first.content, equals(summary));
    });

    // -------------------------------------------------------------------------
    // 12. Cancellation dan pergantian sesi tidak membiarkan operasi lama mengubah state terbaru
    // -------------------------------------------------------------------------
    test('12. Operasi asinkron summarizePaper terisolasi dan tidak mengotori sesi percakapan chat', () async {
      final fakePdf = FakePdfSummaryService();
      fakePdf.delay = const Duration(milliseconds: 50);

      final fakeGemini = FakeGeminiSummaryService();
      final storage = StorageService();
      SharedPreferences.setMockInitialValues({});

      final provider = SciChatProvider(
        pdfService: fakePdf,
        geminiService: fakeGemini,
        storageService: storage,
        searchService: SearchService(),
      );

      await provider.init();
      await provider.setApiKey('test_key');

      final initialSessionId = provider.activeSessionId;

      final paper = createSummaryTestPaper(
        id: '2401.5012',
        title: 'Isolation Paper',
      );

      // Mulai ringkasan paper di latar belakang
      final summaryFuture = provider.summarizePaper(paper);

      // Ganti sesi percakapan atau buat sesi baru saat ringkasan berjalan
      provider.createNewSession();
      final newSessionId = provider.activeSessionId;
      expect(newSessionId, isNot(equals(initialSessionId)));

      final summaryResult = await summaryFuture;
      expect(summaryResult, isNotNull);

      // Sesi aktif tetap sesi baru dan tidak terdistorsi oleh operasi summary
      expect(provider.activeSessionId, equals(newSessionId));
      expect(provider.messages.isEmpty, isTrue);
    });
  });
}
