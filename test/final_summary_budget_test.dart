import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CapturingGeminiService extends GeminiService {
  String? capturedPrompt;
  String? lastPdfText;
  int summarizeCallCount = 0;
  String stubbedSummary =
      '**Apa yang dilakukan** — Inovasi model representasi.\n'
      '**Metodologi** — Transformer arsitektur.\n'
      '**Temuan utama** — Akurasi meningkat 15%.\n'
      '**Keterbatasan & Catatan** — Membutuhkan resource komputasi besar.\n'
      '**Siapa yang harus membaca ini** — Peneliti NLP.';

  CapturingGeminiService({super.apiKey = 'test-api-key'});

  @override
  Future<String> summarizePaper(ArxivPaper paper, {String? pdfText}) async {
    summarizeCallCount++;
    lastPdfText = pdfText;
    // Mirip implementasi production di GeminiService.summarizePaper
    capturedPrompt =
        GeminiService.buildFinalSummaryPrompt(paper, pdfText: pdfText);
    return stubbedSummary;
  }

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
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
    yield 'Chat stream response';
  }
}

class FakePdfServiceForBudget extends PdfService {
  String? returnText;

  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async {
    return returnText ??
        'Introduction: Latar belakang riset.\n\n'
            'Methodology: Metode penelitian yang valid.\n\n'
            'Results: Hasil kuantitatif F1-score 95%.\n\n'
            'Discussion: Analisis komparatif.\n\n'
            'Conclusion: Kesimpulan paper.';
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes,
      {int maxChars = 8000}) async {
    return returnText ?? 'Bytes extracted text';
  }
}

ArxivPaper makeTestPaper({
  String id = '2401.0001',
  String title = 'Attention Is All You Need in Scientific Synthesis',
  String summary =
      'Makalah ini menyajikan pendekatan baru untuk analisis makalah akademik.',
  List<String> authors = const ['Peneliti Utama', 'Rekan Peneliti'],
  String? doi = '10.1000/182',
  String category = 'cs.AI',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: summary,
    published: '2024-01-01',
    updated: '2024-01-02',
    categories: [category],
    pdfUrl: 'https://arxiv.org/pdf/$id.pdf',
    absUrl: 'https://arxiv.org/abs/$id',
    doi: doi,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'gemini_api_key': 'test-key'});
  });

  group('Fase 5.1: Final Summary Prompt Budget Guard', () {
    const canonicalInstructionHeader =
        'INSTRUKSI RANGKUMAN (EVIDENCE-FIRST):';
    const canonicalAntiHallucination =
        'Harap spesifik dan presisi. Jangan tambahkan informasi yang tidak ada dalam dokumen.';
    const canonicalSection1 = '**Apa yang dilakukan**';
    const canonicalSection2 = '**Metodologi**';
    const canonicalSection3 = '**Temuan utama**';
    const canonicalSection4 = '**Keterbatasan & Catatan**';
    const canonicalSection5 = '**Siapa yang harus membaca ini**';

    // 1. Prompt normal tidak melebihi 16.000 karakter
    test('1. Prompt normal tidak melebihi 16.000 karakter', () {
      final paper = makeTestPaper();
      const normalPdf =
          'Introduction: Pembahasan awal mengenai konteks penelitian.\n\n'
          'Methodology: Model transformer dievaluasi pada dataset publik.\n\n'
          'Results: Akurasi mencapai 94.2% dengan efisiensi tinggi.\n\n'
          'Conclusion: Metode ini terbukti andal.';

      final prompt = GeminiService.buildFinalSummaryPrompt(
        paper,
        pdfText: normalPdf,
      );

      expect(prompt.length, lessThanOrEqualTo(16000));
      expect(prompt, contains('Judul: ${paper.title}'));
      expect(prompt, contains('Penulis: Peneliti Utama, Rekan Peneliti'));
      expect(prompt, contains('Konteks Dokumen:'));
      expect(prompt, contains(canonicalInstructionHeader));
      expect(prompt, contains(canonicalAntiHallucination));
    });

    // 2. Abstrak yang sangat panjang tidak membuat prompt melampaui batas
    test('2. Abstrak yang sangat panjang (30.000 char) tidak melampaui batas',
        () {
      final hugeAbstract =
          'Abstrak sangat panjang untuk menguji ketahanan budget prompt. ' * 500;
      expect(hugeAbstract.length, greaterThan(25000));

      final paper = makeTestPaper(summary: hugeAbstract);
      final prompt = GeminiService.buildFinalSummaryPrompt(
        paper,
        pdfText: 'Konteks PDF standar.',
      );

      expect(prompt.length, lessThanOrEqualTo(16000));
      // Buktikan abstrak dibatasi secara aman tanpa merusak struktur
      expect(prompt, contains('Abstrak:'));
      expect(prompt, contains('...'));
      // Instruksi penting tetap utuh
      expect(prompt, contains(canonicalInstructionHeader));
      expect(prompt, contains(canonicalAntiHallucination));
    });

    // 3. Metadata yang sangat panjang tetap ditangani dengan aman
    test('3. Metadata yang sangat panjang (judul, penulis, DOI) ditangani aman',
        () {
      final massiveTitle = 'Judul Ekstrem Yang Sangat Panjang ' * 200; // ~6.800 char
      final massiveAuthors = List.generate(
          100, (i) => 'Profesor Sangat Bernama Panjang Ke-$i yang Memiliki Gelar Banyak');
      final massiveDoi = '10.1234/extremely_long_doi_string_' * 100;
      final massiveCategory = 'cs.AI.computation.logic.advanced.' * 100;

      final paper = makeTestPaper(
        title: massiveTitle,
        authors: massiveAuthors,
        doi: massiveDoi,
        category: massiveCategory,
      );

      final prompt = GeminiService.buildFinalSummaryPrompt(
        paper,
        pdfText: 'Konteks dokumen penelitian standar.',
      );

      expect(prompt.length, lessThanOrEqualTo(16000));
      expect(prompt, contains('Judul: '));
      expect(prompt, contains('Penulis: '));
      expect(prompt, contains('Diterbitkan: '));
      expect(prompt, contains('Kategori: '));
      expect(prompt, contains('DOI: '));
      expect(prompt, contains(canonicalInstructionHeader));
      expect(prompt, contains(canonicalAntiHallucination));
    });

    // 4. Prompt dengan konteks PDF besar tetap tidak melebihi batas
    test('4. Prompt dengan konteks PDF besar (50.000 char) tetap <= 16.000 char',
        () {
      final paper = makeTestPaper();
      final hugePdf =
          'Section 1: Data extraction and benchmark metrics analysis. ' * 1000;
      expect(hugePdf.length, greaterThan(50000));

      final prompt = GeminiService.buildFinalSummaryPrompt(
        paper,
        pdfText: hugePdf,
      );

      expect(prompt.length, lessThanOrEqualTo(16000));
      expect(prompt, contains('Konteks Dokumen:'));
      expect(prompt, contains('...'));
      // Instruksi tetap berada di akhir dan lengkap
      expect(prompt, contains(canonicalInstructionHeader));
      expect(prompt.endsWith(canonicalAntiHallucination), isTrue);
    });

    // 5. Instruksi inti evidence-first tetap utuh setelah pembatasan
    test(
        '5. Instruksi inti evidence-first dan 5 bagian rangkuman tetap 100% utuh',
        () {
      final paper = makeTestPaper(
        title: 'Super Long Title ' * 100,
        summary: 'Super Long Abstract ' * 300,
      );
      final hugePdf = 'Very Long Document Context ' * 2000;

      final prompt = GeminiService.buildFinalSummaryPrompt(
        paper,
        pdfText: hugePdf,
      );

      expect(prompt.length, lessThanOrEqualTo(16000));
      // Seluruh 5 bagian terstruktur wajib ada tanpa terpotong
      expect(prompt, contains(canonicalInstructionHeader));
      expect(prompt, contains(canonicalSection1));
      expect(prompt, contains(canonicalSection2));
      expect(prompt, contains(canonicalSection3));
      expect(prompt, contains(canonicalSection4));
      expect(prompt, contains(canonicalSection5));
      expect(prompt, contains('JANGAN mencampuradukkan isi dengan makalah lain.'));
      expect(prompt, contains(canonicalAntiHallucination));
    });

    // 6. Peringatan cakupan parsial dipertahankan jika relevan
    test('6. Peringatan cakupan parsial dipertahankan saat PDF context dipangkas',
        () {
      final paper = makeTestPaper();
      const partialNotice =
          '[Pemberitahuan Cakupan Dokumen: Teks PDF yang diekstrak mencakup sebagian dokumen. Bagian yang tidak tercantum mungkin berada di luar jangkauan ekstraksi.]';
      final repeatedText = 'Bagian teks penelitian parsial yang berulang. ' * 1000;
      final largeContextWithNotice = '$partialNotice\n\n$repeatedText';

      final prompt = GeminiService.buildFinalSummaryPrompt(
        paper,
        pdfText: largeContextWithNotice,
      );

      expect(prompt.length, lessThanOrEqualTo(16000));
      // Peringatan di awal blok konteks PDF harus tetap utuh
      expect(prompt, contains(partialNotice));
      expect(prompt, contains(canonicalInstructionHeader));
    });

    // 7. pdfText kosong atau null tetap berfungsi aman
    test('7. pdfText kosong atau null tetap berfungsi tanpa error', () {
      final paper = makeTestPaper();

      // Kasus A: null
      final promptNull = GeminiService.buildFinalSummaryPrompt(paper, pdfText: null);
      expect(promptNull.length, lessThanOrEqualTo(16000));
      expect(promptNull, isNot(contains('Konteks Dokumen:')));
      expect(promptNull, contains('Judul: ${paper.title}'));
      expect(promptNull, contains(canonicalInstructionHeader));

      // Kasus B: string kosong
      final promptEmpty = GeminiService.buildFinalSummaryPrompt(paper, pdfText: '');
      expect(promptEmpty.length, lessThanOrEqualTo(16000));
      expect(promptEmpty, isNot(contains('Konteks Dokumen:')));
      expect(promptEmpty, contains(canonicalInstructionHeader));

      // Kasus C: spasi dan whitespace
      final promptWhitespace =
          GeminiService.buildFinalSummaryPrompt(paper, pdfText: '   \n\t   ');
      expect(promptWhitespace.length, lessThanOrEqualTo(16000));
      expect(promptWhitespace, isNot(contains('Konteks Dokumen:')));
      expect(promptWhitespace, contains(canonicalInstructionHeader));
    });

    // 8. Signature dan perilaku publik summarizePaper() tetap kompatibel
    test(
        '8. Signature summarizePaper(paper, {pdfText}) dan perilaku publik kompatibel',
        () async {
      final capturingGemini = CapturingGeminiService();
      final paper = makeTestPaper();

      // Panggilan tanpa pdfText
      final result1 = await capturingGemini.summarizePaper(paper);
      expect(result1, contains('**Apa yang dilakukan**'));
      expect(capturingGemini.capturedPrompt, isNotNull);
      expect(capturingGemini.capturedPrompt!.length, lessThanOrEqualTo(16000));

      // Panggilan dengan pdfText
      const samplePdf = 'Konteks dokumen lengkap untuk ringkasan.';
      final result2 =
          await capturingGemini.summarizePaper(paper, pdfText: samplePdf);
      expect(result2, contains('**Apa yang dilakukan**'));
      expect(capturingGemini.capturedPrompt, contains(samplePdf));
      expect(capturingGemini.capturedPrompt!.length, lessThanOrEqualTo(16000));
    });

    // 9. Ringkasan tetap terisolasi dari state chat
    test(
        '9. Ringkasan melalui provider tetap terisolasi dari riwayat & state chat',
        () async {
      final storage = StorageService();
      final capturingGemini = CapturingGeminiService();
      final fakePdf = FakePdfServiceForBudget();

      final provider = SciChatProvider(
        pdfService: fakePdf,
        geminiService: capturingGemini,
        storageService: storage,
        searchService: SearchService(),
      );

      await provider.init();
      await provider.setApiKey('test_key');

      // Pastikan ada sesi aktif awal
      final initialSessionId = provider.activeSessionId;
      final initialMessageCount = provider.messages.length;

      final paper = makeTestPaper();
      final summaryResult = await provider.summarizePaper(paper);

      // Verifikasi bahwa ringkasan berhasil dikembalikan
      expect(summaryResult, isNotNull);
      expect(capturingGemini.summarizeCallCount, equals(1));
      expect(capturingGemini.capturedPrompt!.length, lessThanOrEqualTo(16000));

      // Verifikasi isolasi terhadap state chat
      expect(provider.activeSessionId, equals(initialSessionId));
      expect(provider.messages.length, equals(initialMessageCount));
    });

    // 10. Fitur menyimpan ringkasan ke Notes/Favorites tidak mengalami regresi
    test(
        '10. Fitur menyimpan ringkasan ke Notes dan status favorit tidak mengalami regresi',
        () async {
      final storage = StorageService();
      final capturingGemini = CapturingGeminiService();
      final fakePdf = FakePdfServiceForBudget();

      final provider = SciChatProvider(
        pdfService: fakePdf,
        geminiService: capturingGemini,
        storageService: storage,
        searchService: SearchService(),
      );

      await provider.init();
      await provider.setApiKey('test_key');

      final paper = makeTestPaper(id: '2401.9999', title: 'Paper Riset Penting');

      // 1. Eksekusi ringkasan
      final summary = await provider.summarizePaper(paper);
      expect(summary, isNotNull);
      expect(capturingGemini.capturedPrompt!.length, lessThanOrEqualTo(16000));

      // 2. Simpan sebagai Research Note melalui savePaperSummary
      final success = await provider.savePaperSummary(
        paper: paper,
        summary: summary!,
      );
      expect(success, isTrue);
      expect(provider.isPaperSummarySaved(paper.id), isTrue);

      // 3. Verifikasi catatan tersimpan di storage
      final notes = provider.notes;
      final savedNote = notes.firstWhere((n) => n.primaryPaper?.id == paper.id);
      expect(savedNote.primaryPaper?.title, equals(paper.title));
      expect(savedNote.content, equals(summary));

      // 4. Verifikasi toggle favorite paper tetap berjalan lancar
      await provider.toggleFavorite(paper);
      expect(provider.isFavorite(paper.id), isTrue);

      await provider.toggleFavorite(paper);
      expect(provider.isFavorite(paper.id), isFalse);
    });
  });
}
