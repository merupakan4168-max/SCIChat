import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/storage_service.dart';

// ── Test Fakes ─────────────────────────────────────────────────────────────

class ControllablePdfService extends PdfService {
  int extractUrlCallCount = 0;
  int extractBytesCallCount = 0;
  final List<int> recordedMaxChars = [];
  final List<String> recordedUrls = [];

  Completer<String?>? delayCompleter;
  bool shouldThrow = false;
  String? returnText;

  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 40000}) async {
    extractUrlCallCount++;
    recordedUrls.add(url);
    recordedMaxChars.add(maxChars);
    if (delayCompleter != null) {
      await delayCompleter!.future;
    }
    if (shouldThrow) {
      throw Exception('Simulated network error during PDF extraction');
    }
    return returnText ??
        'This is valid extracted full text from PDF for scientific research analysis and evaluation.';
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes,
      {int maxChars = 40000}) async {
    extractBytesCallCount++;
    recordedMaxChars.add(maxChars);
    if (delayCompleter != null) {
      await delayCompleter!.future;
    }
    if (shouldThrow) {
      throw Exception('Simulated bytes error during PDF extraction');
    }
    return returnText ??
        'This is valid extracted full text from PDF for scientific research analysis and evaluation.';
  }
}

class FakeStorageService extends StorageService {
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

class FakeGeminiService extends GeminiService {
  FakeGeminiService() : super(apiKey: 'fake-key');

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
    return 'Fake AI response based on context.';
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
    yield 'Fake AI stream chunk.';
  }
}

ArxivPaper createDummyPaper({
  required String id,
  String title = 'Deep Learning Foundations',
  String summary =
      'A comprehensive study on neural optimization and convergence properties.',
  String pdfUrl = 'https://arxiv.org/pdf/2301.00001.pdf',
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: const ['Alice Researcher', 'Bob Scientist'],
    summary: summary,
    published: '2023-01-01',
    updated: '2023-01-01',
    categories: const ['cs.AI'],
    pdfUrl: pdfUrl,
    absUrl: 'https://arxiv.org/abs/$id',
  );
}

// ── Test Suites ────────────────────────────────────────────────────────────

void main() {
  group('Evidence Cache & Concurrency Safety (Phase 3.1 Hardening)', () {
    late ControllablePdfService pdfService;
    late FakeStorageService storageService;
    late FakeGeminiService geminiService;
    late SciChatProvider provider;

    setUp(() {
      pdfService = ControllablePdfService();
      storageService = FakeStorageService();
      geminiService = FakeGeminiService();
      provider = SciChatProvider(
        pdfService: pdfService,
        storageService: storageService,
        geminiService: geminiService,
      );
    });

    test(
        '1. Dua request untuk paper yang sama tetap dideduplikasi (hanya 1 ekstraksi berjalan)',
        () async {
      final paper = createDummyPaper(id: 'paper_concurrent_1');
      pdfService.delayCompleter = Completer<String?>();

      // Dua pemanggilan simultan untuk paper yang sama
      final future1 = provider.fetchPaperEvidence(paper);
      final future2 = provider.fetchPaperEvidence(paper);

      // Pastikan registry in-flight mencatat pekerjaan yang sedang berjalan dengan key berpartisi
      expect(provider.inflightEvidence, isNotEmpty);
      final key = SciChatProvider.buildEvidenceKey(paper,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      expect(provider.inflightEvidence.containsKey(key), isTrue);

      // Selesaikan ekstraksi PDF
      pdfService.delayCompleter!.complete(
          'Ekstraksi teks lengkap dari paper_concurrent_1 untuk pengujian.');

      final results = await Future.wait([future1, future2]);

      // Verifikasi: Hanya SATU pemanggilan download/ekstraksi yang terjadi
      expect(pdfService.extractUrlCallCount, equals(1));
      expect(results[0].level, equals(EvidenceLevel.fullText));
      expect(results[1].level, equals(EvidenceLevel.fullText));
      expect(results[0].extractedText, equals(results[1].extractedText));
    });

    test(
        '2. Dua paper berbeda dapat diproses secara independen tanpa saling memblokir',
        () async {
      final paperA = createDummyPaper(
        id: 'paper_A',
        pdfUrl: 'https://arxiv.org/pdf/paper_A.pdf',
      );
      final paperB = createDummyPaper(
        id: 'paper_B',
        pdfUrl: 'https://arxiv.org/pdf/paper_B.pdf',
      );

      final futureA = provider.fetchPaperEvidence(paperA);
      final futureB = provider.fetchPaperEvidence(paperB);

      final results = await Future.wait([futureA, futureB]);

      // Masing-masing paper diekstrak secara independen
      expect(pdfService.extractUrlCallCount, equals(2));
      expect(results[0].level, equals(EvidenceLevel.fullText));
      expect(results[1].level, equals(EvidenceLevel.fullText));
    });

    test(
        '3. Registry in-flight dibersihkan setelah sukses maupun kegagalan (exception)',
        () async {
      final paperSuccess = createDummyPaper(id: 'paper_success');
      final paperError = createDummyPaper(id: 'paper_error');

      // Kasus A: Sukses
      await provider.fetchPaperEvidence(paperSuccess);
      expect(provider.inflightEvidence, isEmpty,
          reason: 'Registry harus kosong setelah ekstraksi sukses');

      // Kasus B: Exception
      pdfService.shouldThrow = true;
      final fallbackResult = await provider.fetchPaperEvidence(paperError);

      expect(provider.inflightEvidence, isEmpty,
          reason:
              'Registry harus dibersihkan dalam finally block saat terjadi exception');
      expect(fallbackResult.level, equals(EvidenceLevel.abstractOnly));
    });

    test(
        '4. Kegagalan jaringan tidak di-cache sehingga retry dapat memanggil ekstraksi kembali',
        () async {
      final paper = createDummyPaper(id: 'paper_retry_network');
      final key = SciChatProvider.buildEvidenceKey(paper,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);

      // Simulasikan kegagalan jaringan sementara (timeout / SocketException)
      pdfService.shouldThrow = true;
      final firstResult = await provider.fetchPaperEvidence(paper);

      expect(pdfService.extractUrlCallCount, equals(1));
      expect(firstResult.level, equals(EvidenceLevel.abstractOnly));

      // Verifikasi: Kegagalan sementara TIDAK disimpan ke _paperEvidenceCache
      expect(provider.paperEvidenceCache.containsKey(key), isFalse,
          reason:
              'Kegagalan jaringan sementara tidak boleh disimpan ke cache permanen');

      // Pulihkan koneksi jaringan dan siapkan hasil sukses
      pdfService.shouldThrow = false;
      pdfService.returnText =
          'Full text extracted successfully after network recovered.';

      // Eksekusi retry
      final retryResult = await provider.fetchPaperEvidence(paper);

      // Verifikasi: Pemanggilan ekstraksi kedua benar-benar dilakukan (bukan cache hit semu)
      expect(pdfService.extractUrlCallCount, equals(2),
          reason: 'Retry setelah kegagalan jaringan harus memicu pemanggilan baru');
      expect(retryResult.level, equals(EvidenceLevel.fullText));
      expect(retryResult.extractedText,
          equals('Full text extracted successfully after network recovered.'));

      // Setelah sukses, entri baru tersimpan di cache
      expect(provider.paperEvidenceCache.containsKey(key), isTrue);
    });

    test(
        '5. Evidence abstrak yang valid untuk paper tanpa PDF dapat digunakan dan di-cache secara tepat',
        () async {
      // Paper tanpa URL PDF (open access tidak menyediakan PDF)
      final paperNoPdf = createDummyPaper(
        id: 'paper_no_pdf',
        pdfUrl: '',
        summary:
            'This paper provides rigorous theoretical bounds for gradient descent algorithms.',
      );
      final keyNoPdf = SciChatProvider.buildEvidenceKey(paperNoPdf,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);

      final result1 = await provider.fetchPaperEvidence(paperNoPdf);

      // Tidak ada pemanggilan ekstraksi URL PDF karena URL kosong
      expect(pdfService.extractUrlCallCount, equals(0));
      expect(result1.level, equals(EvidenceLevel.abstractOnly));
      expect(result1.extractedText, isNull);

      // Kondisi valid paper tanpa PDF di-cache agar tidak perlu evaluasi ulang
      expect(provider.paperEvidenceCache.containsKey(keyNoPdf), isTrue);

      // Paper tanpa PDF dan tanpa abstrak valid
      final paperNoPdfNoAbstract = createDummyPaper(
        id: 'paper_no_pdf_no_abs',
        pdfUrl: '',
        summary: 'Tidak ada abstrak yang tersedia.',
      );
      final result2 = await provider.fetchPaperEvidence(paperNoPdfNoAbstract);
      expect(result2.level, equals(EvidenceLevel.noUsableText));
    });

    test(
        '6. Cache 8.000 dan 40.000 karakter tidak saling tertukar (partisi cache per maxChars)',
        () async {
      final paper = createDummyPaper(id: 'paper_partition_chars');
      final key8k = SciChatProvider.buildEvidenceKey(paper,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      final key40k = SciChatProvider.buildEvidenceKey(paper,
          maxChars: SciChatProvider.kSummaryEvidenceMaxChars);

      expect(key8k, isNot(equals(key40k)),
          reason: 'Key cache harus dipartisi berdasarkan maxChars');

      // 1. Ekstraksi untuk Tanya Paper (kChatEvidenceMaxChars)
      await provider.fetchPaperEvidence(paper,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      expect(pdfService.extractUrlCallCount, equals(1));
      expect(pdfService.recordedMaxChars.last, equals(SciChatProvider.kChatEvidenceMaxChars));
      expect(provider.paperEvidenceCache.containsKey(key8k), isTrue);
      expect(provider.paperEvidenceCache.containsKey(key40k), isFalse);

      // 2. Ekstraksi untuk Ringkasan Paper (40.000 karakter)
      // Tidak boleh mengambil cache 8.000!
      await provider.fetchPaperEvidence(paper,
          maxChars: SciChatProvider.kSummaryEvidenceMaxChars);
      expect(pdfService.extractUrlCallCount, equals(2),
          reason:
              'Permintaan 40.000 karakter tidak boleh menggunakan hasil ekstraksi 8.000');
      expect(pdfService.recordedMaxChars.last, equals(40000));
      expect(provider.paperEvidenceCache.containsKey(key40k), isTrue);

      // 3. Panggilan kedua untuk masing-masing batas karakter harus cache hit
      await provider.fetchPaperEvidence(paper,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      await provider.fetchPaperEvidence(paper,
          maxChars: SciChatProvider.kSummaryEvidenceMaxChars);
      expect(pdfService.extractUrlCallCount, equals(2),
          reason: 'Keduanya sekarang berada di cache terpisah');
    });

    test(
        '7. Operasi lama tidak menghapus evidence baru saat paper dilepas lalu diaktifkan kembali',
        () async {
      final paperA = createDummyPaper(id: 'paper_toggle_race');
      final key = SciChatProvider.buildEvidenceKey(paperA,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);

      // Tahap 1: Mulai ekstraksi lambat untuk paperA (Operasi 1, generasi konteks token = 1)
      final completer1 = Completer<String?>();
      pdfService.delayCompleter = completer1;
      provider.setActivePaper(paperA);
      expect(provider.contextEvidence[paperA.id]?.level,
          equals(EvidenceLevel.loading));

      // Tahap 2: Pengguna melepas paperA dari konteks (generasi token = 2)
      provider.removeActiveContext(paperA.id);
      expect(provider.contextEvidence.containsKey(paperA.id), isFalse);

      // Tahap 3: PaperA diaktifkan kembali dan Operasi 2 selesai lebih dahulu (generasi token = 3)
      provider.inflightEvidence.remove(key); // Lepas dari inflight untuk simulasi Operasi 2 independen
      pdfService.delayCompleter = null; // Operasi 2 tidak tertahan
      pdfService.returnText = 'Teks baru dari Operasi 2';
      provider.setActivePaper(paperA);
      await pumpEventQueue();

      // Verifikasi Operasi 2 berhasil memasang evidence baru
      expect(provider.contextEvidence[paperA.id]?.level,
          equals(EvidenceLevel.fullText));
      expect(provider.contextEvidence[paperA.id]?.extractedText,
          equals('Teks baru dari Operasi 2'));

      // Tahap 4: Sekarang Operasi 1 lama selesai terlambat
      pdfService.returnText = 'Teks kadaluarsa dari Operasi 1';
      completer1.complete('Teks kadaluarsa dari Operasi 1');
      await pumpEventQueue();

      // Verifikasi: Operasi 1 tidak menghapus atau menimpa state valid dari Operasi 2
      expect(provider.contextEvidence.containsKey(paperA.id), isTrue,
          reason: 'Operasi lama tidak boleh menghapus evidence dari operasi baru');
      expect(provider.contextEvidence[paperA.id]?.extractedText,
          equals('Teks baru dari Operasi 2'),
          reason: 'Evidence operasi baru tidak boleh ditimpa oleh operasi lama');
    });

    test(
        '8. Operasi lama tidak menghapus Future baru pada registry in-flight dengan key sama (identical check)',
        () async {
      final paper = createDummyPaper(id: 'paper_inflight_identical');
      final key = SciChatProvider.buildEvidenceKey(paper,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);

      final completer1 = Completer<String?>();
      pdfService.delayCompleter = completer1;

      // Mulai future 1
      final future1 = provider.fetchPaperEvidence(paper);
      expect(provider.inflightEvidence.containsKey(key), isTrue);

      // Simulasikan penggantian entri di registry oleh operasi lain
      final dummyFuture2 = Completer<PaperEvidence>().future;
      provider.inflightEvidence[key] = dummyFuture2;

      // Selesaikan future 1
      completer1.complete('Teks dari future 1');
      await future1;

      // Verifikasi: Finally block dari future1 tidak menghapus dummyFuture2 karena tidak identical!
      expect(identical(provider.inflightEvidence[key], dummyFuture2), isTrue,
          reason:
              'Operasi lama tidak boleh menghapus Future baru yang menggunakan key sama');

      // Cleanup manual
      provider.inflightEvidence.remove(key);
    });

    test(
        '9. Cache tidak pernah melampaui batas kapasitas yang ditentukan (24 entri dengan LRU eviction)',
        () async {
      expect(SciChatProvider.kMaxEvidenceCacheEntries, equals(24));

      // 1. Isi cache tepat sampai kapasitas penuh (24 paper berbeda)
      for (int i = 1; i <= 24; i++) {
        final paper = createDummyPaper(id: 'paper_lru_$i');
        await provider.fetchPaperEvidence(paper);
      }
      expect(provider.paperEvidenceCache.length, equals(24));

      // 2. Akses kembali entri lama (paper_lru_1) yang secara default adalah calon korban terlama
      final paper1 = createDummyPaper(id: 'paper_lru_1');
      final key1 = SciChatProvider.buildEvidenceKey(paper1,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      await provider.fetchPaperEvidence(paper1); // Cache hit & LRU touch

      // 3. Tambahkan entri baru ke-25
      final paper25 = createDummyPaper(id: 'paper_lru_25');
      final key25 = SciChatProvider.buildEvidenceKey(paper25,
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      await provider.fetchPaperEvidence(paper25);

      // 4. Pastikan kapasitas tidak pernah melebihi 24
      expect(provider.paperEvidenceCache.length, equals(24),
          reason:
              'Ukuran cache tidak boleh melampaui kMaxEvidenceCacheEntries (24)');

      // 5. Pastikan paper_lru_1 yang baru diakses TIDAK menjadi korban eviction!
      expect(provider.paperEvidenceCache.containsKey(key1), isTrue,
          reason:
              'Entri lama yang baru saja diakses tidak boleh menjadi korban eviction pada implementasi LRU');

      // Sebaliknya, paper_lru_2 (yang tidak diakses ulang) menjadi korban eviction
      final key2 = SciChatProvider.buildEvidenceKey(
          createDummyPaper(id: 'paper_lru_2'),
          maxChars: SciChatProvider.kChatEvidenceMaxChars);
      expect(provider.paperEvidenceCache.containsKey(key2), isFalse,
          reason: 'Entri tertua yang tidak diakses (paper 2) harus di-evict');

      // Entri baru ke-25 berhasil masuk
      expect(provider.paperEvidenceCache.containsKey(key25), isTrue);
    });

    test(
        '10. Cache hit, fallback, dan perpindahan sesi tidak mengalami regresi',
        () async {
      // Sub-tes A: Cache hit langsung mengembalikan data tanpa memanggil service lagi
      final paperHit = createDummyPaper(id: 'paper_sub_hit');
      final first = await provider.fetchPaperEvidence(paperHit);
      expect(pdfService.extractUrlCallCount, equals(1));
      final second = await provider.fetchPaperEvidence(paperHit);
      expect(pdfService.extractUrlCallCount, equals(1),
          reason: 'Cache hit tidak boleh memicu ekstraksi ulang');
      expect(second.extractedText, equals(first.extractedText));

      // Sub-tes B: Fallback saat failure menghasilkan level yang benar
      pdfService.shouldThrow = true;
      final paperFallback = createDummyPaper(
        id: 'paper_sub_fallback',
        summary: 'Valid summary for fallback testing.',
      );
      final fallbackResult = await provider.fetchPaperEvidence(paperFallback);
      expect(fallbackResult.level, equals(EvidenceLevel.abstractOnly));

      // Sub-tes C: Perpindahan sesi membuang hasil retrieval lama secara aman
      pdfService.shouldThrow = false;
      provider.createNewSession();
      final paperSession = createDummyPaper(id: 'paper_session_stale');

      pdfService.delayCompleter = Completer<String?>();
      provider.setActivePaper(paperSession);

      // Sebelum ekstraksi selesai, pindah ke sesi baru
      provider.createNewSession();

      // Selesaikan ekstraksi lama
      pdfService.delayCompleter!.complete('Teks dari sesi sebelumnya');
      await pumpEventQueue();

      // Sesi baru tidak boleh tercemar oleh contextEvidence dari sesi lama
      expect(provider.contextEvidence.containsKey(paperSession.id), isFalse,
          reason:
              'Hasil retrieval dari sesi lama tidak boleh masuk ke contextEvidence sesi baru');
    });

    test(
        '11. Kunci identitas stabil tidak menyamakan dua paper berbeda hanya karena judulnya sama',
        () {
      final paper1 = createDummyPaper(
        id: 'arxiv_2301_0001',
        title: 'Attention Is All You Need',
        pdfUrl: 'https://arxiv.org/pdf/2301.0001.pdf',
      );
      final paper2 = createDummyPaper(
        id: 'arxiv_2301_0002',
        title: 'Attention Is All You Need', // Judul sama, ID berbeda
        pdfUrl: 'https://arxiv.org/pdf/2301.0002.pdf',
      );

      final key1 = SciChatProvider.buildEvidenceKey(paper1);
      final key2 = SciChatProvider.buildEvidenceKey(paper2);

      expect(key1, isNot(equals(key2)),
          reason:
              'Dua paper dengan ID berbeda harus menghasilkan kunci identitas yang berbeda');
      expect(key1, equals('id::arxiv_2301_0001'));
      expect(key2, equals('id::arxiv_2301_0002'));
    });

    test(
        '12. Verifikasi contextGenerationToken bertambah pada seluruh 7 transisi konteks & sesi',
        () async {
      final initialToken = provider.contextGenerationToken;
      final paper1 = createDummyPaper(id: 'paper_token_1');
      final paper2 = createDummyPaper(id: 'paper_token_2');

      // 1. setActivePaper
      provider.setActivePaper(paper1);
      final token1 = provider.contextGenerationToken;
      expect(token1, greaterThan(initialToken));

      // 2. setActiveContexts
      provider.setActiveContexts([paper1, paper2]);
      final token2 = provider.contextGenerationToken;
      expect(token2, greaterThan(token1));

      // 3. removeActiveContext
      provider.removeActiveContext(paper1.id);
      final token3 = provider.contextGenerationToken;
      expect(token3, greaterThan(token2));

      // 4. createNewSession
      provider.createNewSession();
      final token4 = provider.contextGenerationToken;
      expect(token4, greaterThan(token3));

      // Siapkan sesi untuk loadSession, deleteSession, branchSession
      final sessionAId = provider.activeSessionId;
      provider.messages.add(ChatMessage(
        id: 'msg_session_a',
        role: MessageRole.user,
        content: 'Pertanyaan riset sesi A',
        timestamp: DateTime.now(),
      ));
      provider.createNewSession();
      final sessionBId = provider.activeSessionId;
      expect(sessionBId, isNot(equals(sessionAId)));
      final token5 = provider.contextGenerationToken;
      expect(token5, greaterThan(token4));

      // 5. loadSession
      provider.loadSession(sessionAId);
      final token6 = provider.contextGenerationToken;
      expect(token6, greaterThan(token5));

      // 6. deleteSession
      provider.deleteSession(sessionBId);
      final token7 = provider.contextGenerationToken;
      expect(token7, greaterThan(token6));

      // 7. branchSessionFromMessage
      final userMsg = ChatMessage(
        id: 'user_msg_1',
        role: MessageRole.user,
        content: 'Pertanyaan riset',
        timestamp: DateTime.now(),
      );
      final assistantMsg = ChatMessage(
        id: 'asst_msg_1',
        role: MessageRole.assistant,
        content: 'Jawaban riset mendalam',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      );
      // Sinkronkan pesan ke sesi aktif
      provider.messages.addAll([userMsg, assistantMsg]);
      final branchSuccess =
          await provider.branchSessionFromMessage('asst_msg_1');
      expect(branchSuccess, isTrue);
      final token8 = provider.contextGenerationToken;
      expect(token8, greaterThan(token7));
    });
  });
}
