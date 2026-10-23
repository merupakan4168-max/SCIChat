import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/utils/pdf_chunker.dart';
import 'package:scichat/utils/lexical_retriever.dart';
import 'package:scichat/utils/summary_context_selector.dart';
import 'package:scichat/services/pdf_service.dart';

// Helper fixtures
ArxivPaper createTestPaper({
  required String id,
  required String title,
  String summary = 'Valid summary for test paper context.',
  String pdfUrl = 'https://arxiv.org/pdf/test.pdf',
  String? doi,
  List<String> authors = const ['Test Author'],
  List<String> categories = const ['cs.AI'],
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: summary,
    published: '2024-01-01',
    updated: '2024-01-01',
    categories: categories,
    pdfUrl: pdfUrl,
    absUrl: 'https://arxiv.org/abs/$id',
    doi: doi,
  );
}

class FakePdfService extends PdfService {
  int extractUrlCallCount = 0;
  int extractBytesCallCount = 0;
  final List<int> recordedMaxChars = [];
  String? mockExtractedText;

  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 40000}) async {
    extractUrlCallCount++;
    recordedMaxChars.add(maxChars);
    return mockExtractedText ?? 'Mock text from URL';
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 40000}) async {
    extractBytesCallCount++;
    recordedMaxChars.add(maxChars);
    return mockExtractedText ?? 'Mock text from Bytes';
  }
}

void main() {
  group('Phase 4B: Perbaikan PDF Retrieval dan Pemahaman Dokumen', () {
    // -------------------------------------------------------------------------
    // 1. Teks pada bagian dokumen yang lebih akhir dapat masuk ke chunk ketika
    //    masih berada dalam batas ekstraksi (kChatEvidenceMaxChars = 48000).
    // -------------------------------------------------------------------------
    test('1. Teks di bagian dokumen yang lebih akhir tetap dapat masuk ke chunker dalam batas kChatEvidenceMaxChars', () {
      expect(SciChatProvider.kChatEvidenceMaxChars, equals(48000),
          reason: 'Batas chat evidence harus 48.000 karakter untuk mencakup paper konferensi 12-14 halaman');

      // Bangun simulasi teks paper panjang (~42.000 karakter)
      // Mencakup Abstract, Introduction, Related Work, Methodology, Experiments, Results, Conclusion
      final buffer = StringBuffer();
      buffer.writeln('Abstract\nThis paper proposes a novel deep neural architecture for scientific text processing.\n');
      buffer.writeln('1. Introduction\n${'Introduction context discussing historical approaches. ' * 70}');
      buffer.writeln('2. Related Work\n${'Literature review on transformers, attention, and retrieval. ' * 100}');
      // Seksi penting di offset tengah (sekitar 18.000 - 30.000)
      buffer.writeln('3. Methodology\n${'We propose a sparse cross-attention layer that scales quadratically to linearly. ' * 120}');
      buffer.writeln('4. Experiments and Dataset\n${'The benchmark evaluation uses the SciFact and PubMed datasets with 50000 papers. ' * 100}');
      // Seksi penting di offset akhir (sekitar 32.000 - 45.000 karakter)
      buffer.writeln('5. Results\n${'Our experimental findings achieve an F1-score of 94.6 on classification benchmarks. ' * 100}');
      buffer.writeln('6. Conclusion\n${'In conclusion, the proposed method significantly outperforms standard baselines. ' * 60}');

      final fullPaperText = buffer.toString();
      expect(fullPaperText.length, greaterThan(35000));
      expect(fullPaperText.length, lessThanOrEqualTo(SciChatProvider.kChatEvidenceMaxChars));

      // Lakukan chunking pada teks lengkap
      final chunks = PdfChunker.chunkText(fullPaperText);
      expect(chunks, isNotEmpty);

      // Verifikasi bahwa seksi-seksi di bagian akhir dokumen berhasil di-chunk
      final sectionTitles = chunks.map((c) => c.sectionTitle).toSet();
      expect(sectionTitles, contains('Methodology'));
      expect(sectionTitles, contains('Experiments'));
      expect(sectionTitles, contains('Results'));
      expect(sectionTitles, contains('Conclusion'));

      // Verifikasi bahwa chunk Results berada di offset jauh (> 25.000 karakter)
      final resultsChunks = chunks.where((c) => c.sectionTitle == 'Results').toList();
      expect(resultsChunks, isNotEmpty);
      expect(resultsChunks.first.charOffset, greaterThan(25000));

      // Verifikasi retrieval leksikal berhasil menemukan chunk di offset akhir tersebut
      final retrieval = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'F1-score classification benchmarks',
      );
      expect(retrieval.isFallback, isFalse);
      expect(retrieval.scoredChunks, isNotEmpty);
      expect(retrieval.scoredChunks.first.chunk.sectionTitle, equals('Results'));
      expect(retrieval.scoredChunks.first.chunk.charOffset, greaterThan(25000));
    });

    // -------------------------------------------------------------------------
    // 2. Retrieval noMatches tidak otomatis membuang seluruh konteks teks yang tersedia
    // -------------------------------------------------------------------------
    test('2. Retrieval noMatches tidak membuang seluruh teks dokumen dan menyediakan konteks cadangan', () {
      final paper = createTestPaper(
        id: 'paper_nomatch_fallback',
        title: 'Deep Representation Learning for Natural Science',
        summary: 'Makalah representasi mendalam untuk ilmu pengetahuan alam.',
      );

      final chunks = [
        const PdfChunk(
          id: 'c_intro',
          text: 'Introduction to deep learning applied to biological systems and molecular graphs.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c_method',
          text: 'Our model architecture implements geometric message passing on 3D molecular structures.',
          sectionTitle: 'Methodology',
          charOffset: 1500,
        ),
        const PdfChunk(
          id: 'c_results',
          text: 'Empirical results indicate strong performance on quantum chemistry benchmarks.',
          sectionTitle: 'Results',
          charOffset: 3000,
        ),
      ];

      final evidence = PaperEvidence(
        level: EvidenceLevel.fullText,
        extractedText: 'Full text',
        chunks: chunks,
      );

      // Kueri yang tidak cocok secara leksikal sama sekali dengan teks chunk
      const queryNoMatch = 'Apakah algoritma ini dapat dijalankan pada hardware telekomunikasi satelit 5G orbital?';

      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: paper,
        evidence: evidence,
        userQuery: queryNoMatch,
      );

      // Verifikasi status kejujuran dan anti-halusinasi
      expect(prompt, contains('Status Bukti: Tidak ditemukan kutipan spesifik dalam dokumen'));
      expect(prompt, contains('Peringatan: Jangan mengarang bukti atau klaim yang tidak ada dalam teks.'));
      expect(prompt, contains('Gunakan abstrak di atas sebagai acuan umum'));

      // Verifikasi bahwa teks dokumen TIDAK dibuang: konteks cadangan tetap disediakan
      expect(prompt, contains('Konteks Cadangan Dokumen (Relevansi leksikal spesifik belum terverifikasi):'));
      expect(prompt, contains('[Konteks Cadangan - Bagian:'));
      // Verifikasi model diberikan teks aktual dari dokumen, bukan prompt kosong
      expect(prompt, anyOf(contains('geometric message passing'), contains('biological systems')));
    });

    test('2b. Fallback cerdas memprioritaskan seksi yang relevan dengan topik pertanyaan', () {
      final chunks = [
        const PdfChunk(
          id: 'c1',
          text: 'Overview of historical methods and motivations.',
          sectionTitle: 'Introduction',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'c2',
          text: 'Detailed description of the proposed architecture and training loss formulation.',
          sectionTitle: 'Methodology',
          charOffset: 1200,
        ),
        const PdfChunk(
          id: 'c3',
          text: 'Tabular presentation of accuracy numbers and baseline comparisons.',
          sectionTitle: 'Results',
          charOffset: 2400,
        ),
      ];

      // Kueri menanyakan tentang metodologi/arsitektur
      final fallbackMethod = SciChatProvider.selectFallbackChunks(
        chunks: chunks,
        userQuery: 'Jelaskan rancangan arsitektur dan metodologi sistem ini',
      );
      expect(fallbackMethod, isNotEmpty);
      expect(fallbackMethod.first.sectionTitle, equals('Methodology'));

      // Kueri menanyakan tentang hasil / eksperimen
      final fallbackResults = SciChatProvider.selectFallbackChunks(
        chunks: chunks,
        userQuery: 'Bagaimana hasil dan performa yang diperoleh?',
      );
      expect(fallbackResults, isNotEmpty);
      expect(fallbackResults.first.sectionTitle, equals('Results'));
    });

    // -------------------------------------------------------------------------
    // 3. Pertanyaan berbahasa Indonesia dapat menemukan chunk berbahasa Inggris
    //    untuk istilah akademik kunci (arsitektur, metodologi, dataset, hasil, evaluasi)
    // -------------------------------------------------------------------------
    test('3. Cross-language retrieval: pertanyaan Indonesia menemukan chunk Inggris untuk istilah akademik', () {
      final chunks = [
        const PdfChunk(
          id: 'chunk_arch',
          text: 'In this section, we propose a novel neural architecture based on multi-scale transformers.',
          sectionTitle: 'Methodology',
          charOffset: 0,
        ),
        const PdfChunk(
          id: 'chunk_data',
          text: 'The training dataset comprises 2 million paired scientific document abstracts and citations.',
          sectionTitle: 'Experiments',
          charOffset: 1000,
        ),
        const PdfChunk(
          id: 'chunk_res',
          text: 'Our experimental results and findings confirm superior convergence speed and accuracy.',
          sectionTitle: 'Results',
          charOffset: 2000,
        ),
        const PdfChunk(
          id: 'chunk_eval',
          text: 'System evaluation is performed using rigorous cross-validation and standard test splits.',
          sectionTitle: 'Evaluation',
          charOffset: 3000,
        ),
      ];

      // 3.1 Kueri arsitektur -> architecture
      final retArch = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Jelaskan arsitektur model yang diusulkan',
      );
      expect(retArch.isFallback, isFalse, reason: 'Kueri arsitektur harus memetakan ke architecture');
      expect(retArch.scoredChunks.first.chunk.id, equals('chunk_arch'));

      // 3.2 Kueri dataset -> dataset / data
      final retData = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Apa dataset yang digunakan untuk pelatihan?',
      );
      expect(retData.isFallback, isFalse, reason: 'Kueri dataset harus menemukan chunk dataset');
      expect(retData.scoredChunks.first.chunk.id, equals('chunk_data'));

      // 3.3 Kueri hasil -> results / findings
      final retRes = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Bagaimana hasil utama dari penelitian ini?',
      );
      expect(retRes.isFallback, isFalse, reason: 'Kueri hasil harus menemukan chunk results');
      expect(retRes.scoredChunks.first.chunk.id, equals('chunk_res'));

      // 3.4 Kueri evaluasi -> evaluation / experiments
      final retEval = LexicalRetriever.retrieve(
        chunks: chunks,
        query: 'Bagaimana evaluasi sistem dilakukan?',
      );
      expect(retEval.isFallback, isFalse, reason: 'Kueri evaluasi harus menemukan chunk evaluation');
      expect(retEval.scoredChunks.first.chunk.id, equals('chunk_eval'));
    });

    // -------------------------------------------------------------------------
    // 4. Placeholder metadata PDF lokal tidak diteruskan sebagai abstrak asli
    // -------------------------------------------------------------------------
    test('4. Placeholder metadata PDF lokal tidak dianggap sebagai abstrak valid dan tidak mencemari prompt', () {
      const localPaper = ArxivPaper(
        id: 'local_1700000000',
        title: 'User_Research_Paper.pdf',
        authors: ['Local File'],
        summary: 'A local PDF file uploaded by user.',
        published: '2024-01-01',
        updated: '2024-01-01',
        categories: ['Local'],
        pdfUrl: 'file:///C:/Users/test/Documents/User_Research_Paper.pdf',
        absUrl: '',
      );

      // Verifikasi properti isLocal
      expect(localPaper.isLocal, isTrue);

      // Verifikasi bahwa placeholder ditolak oleh validator abstrak
      expect(localPaper.hasUsableAbstract, isFalse);
      expect(ArxivPaper.isAbstractUsable(localPaper.summary), isFalse);
      expect(SciChatProvider.checkAbstractValid(localPaper.summary), isFalse);

      // Verifikasi pada buildSinglePaperContextPrompt bahwa placeholder TIDAK pernah ditulis sebagai abstrak
      final prompt = SciChatProvider.buildSinglePaperContextPrompt(
        paper: localPaper,
        evidence: const PaperEvidence(level: EvidenceLevel.loading),
        userQuery: 'Apa isi dokumen ini?',
      );

      expect(prompt, contains('Sumber: Berkas PDF Lokal'));
      expect(prompt, isNot(contains('Abstrak (Jangkar Konteks):')));
      expect(prompt, isNot(contains('A local PDF file uploaded by user.')));
    });

    // -------------------------------------------------------------------------
    // 5. PDF tanpa teks yang dapat digunakan tetap menghasilkan respons yang jujur
    // -------------------------------------------------------------------------
    test('5. PDF lokal tanpa teks (scan/gambar) menghasilkan status jujur tanpa klaim palsu', () {
      const unreadableLocalPaper = ArxivPaper(
        id: 'local_scan_only',
        title: 'scanned_document.pdf',
        authors: ['Local File'],
        summary: '',
        published: '2024-01-01',
        updated: '2024-01-01',
        categories: ['Local'],
        pdfUrl: 'file:///C:/Users/test/scanned_document.pdf',
        absUrl: '',
      );

      final promptNoText = SciChatProvider.buildSinglePaperContextPrompt(
        paper: unreadableLocalPaper,
        evidence: const PaperEvidence(level: EvidenceLevel.noUsableText),
        userQuery: 'Jelaskan metodologi dan hasil dari paper ini',
      );

      expect(promptNoText, contains('Status Bukti: Tidak ada teks yang dapat digunakan (No Usable Text).'));
      expect(promptNoText, contains('Keterangan: Dokumen PDF lokal (scanned_document.pdf) tidak memiliki teks yang dapat diekstrak'));
      expect(promptNoText, contains('JANGAN mengarang isi dokumen atau memberikan klaim spekulatif'));
      expect(promptNoText, isNot(contains('Ditemukan 1 bagian relevan')));
    });

    // -------------------------------------------------------------------------
    // 6. Jalur PDF lokal tetap terisolasi dari dokumen dan sesi lain
    // -------------------------------------------------------------------------
    test('6. Isolasi PDF lokal: caching dan in-flight evidence terpartisi berdasarkan ID dan maxChars', () {
      final paper1 = createTestPaper(
        id: 'local_paper_1',
        title: 'Local Paper 1.pdf',
        pdfUrl: 'file:///path/paper1.pdf',
      );
      final paper2 = createTestPaper(
        id: 'local_paper_2',
        title: 'Local Paper 2.pdf',
        pdfUrl: 'file:///path/paper2.pdf',
      );

      final key1 = SciChatProvider.buildEvidenceKey(paper1, maxChars: SciChatProvider.kChatEvidenceMaxChars);
      final key2 = SciChatProvider.buildEvidenceKey(paper2, maxChars: SciChatProvider.kChatEvidenceMaxChars);
      final key1Summary = SciChatProvider.buildEvidenceKey(paper1, maxChars: SciChatProvider.kSummaryEvidenceMaxChars);

      expect(key1, isNot(equals(key2)), reason: 'Dua PDF lokal berbeda harus memiliki key cache berbeda');
      expect(key1, isNot(equals(key1Summary)), reason: 'Key chat dan summary harus terpartisi');
    });

    // -------------------------------------------------------------------------
    // 7. Batas jumlah chunk dan karakter tetap dipatuhi
    // -------------------------------------------------------------------------
    test('7. Batas jumlah chunk dan karakter tetap dipatuhi pada fallback cerdas', () {
      // Buat daftar 20 chunk panjang
      final chunks = List.generate(
        20,
        (i) => PdfChunk(
          id: 'chunk_$i',
          text: 'Detailed paragraph with extensive content describing aspect $i of the scientific domain. ' * 20,
          sectionTitle: 'Section $i',
          charOffset: i * 2000,
        ),
      );

      final fallback = SciChatProvider.selectFallbackChunks(
        chunks: chunks,
        userQuery: 'Tanya umum',
        maxChunks: 2,
        maxChars: 3000,
      );

      expect(fallback.length, lessThanOrEqualTo(2));
      final totalChars = fallback.fold<int>(0, (sum, c) => sum + c.text.length);
      expect(totalChars, lessThanOrEqualTo(3000));
    });

    // -------------------------------------------------------------------------
    // 8. Jalur ringkasan paper yang sudah ada tidak mengalami regresi
    // -------------------------------------------------------------------------
    test('8. Jalur ringkasan paper (SummaryContextSelector & kSummaryEvidenceMaxChars) tidak terganggu', () {
      expect(SciChatProvider.kSummaryEvidenceMaxChars, equals(40000));

      final chunks = [
        const PdfChunk(id: 'c_abs', text: 'Abstract text describing core idea.', sectionTitle: 'Abstract', charOffset: 0),
        const PdfChunk(id: 'c_meth', text: 'Methodology describing deep model.', sectionTitle: 'Methodology', charOffset: 5000),
        const PdfChunk(id: 'c_res', text: 'Results achieving state-of-the-art.', sectionTitle: 'Results', charOffset: 15000),
        const PdfChunk(id: 'c_con', text: 'Conclusion summarizing contribution.', sectionTitle: 'Conclusion', charOffset: 25000),
      ];

      final summaryResult = SummaryContextSelector.selectChunks(chunks: chunks);
      expect(summaryResult.selectedChunks, isNotEmpty);
      expect(summaryResult.totalCharCount, lessThanOrEqualTo(SummaryContextSelector.kMaxSummaryContextChars));

      final summarySections = summaryResult.selectedChunks.map((c) => c.sectionTitle).toSet();
      expect(summarySections, anyOf(contains('Introduction'), contains('Abstract')));
      expect(summarySections, contains('Methodology'));
      expect(summarySections, contains('Results'));
      expect(summarySections, contains('Conclusion'));
    });
  });
}
