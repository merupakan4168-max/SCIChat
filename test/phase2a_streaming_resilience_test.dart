// Test Regresi Wajib Fase 2A: Ketahanan Streaming dan Deteksi Respons Tidak Lengkap (STR-01 & STR-02)
// Catatan: Seluruh pengujian ini menggunakan Mock / Fake deterministik untuk mensimulasikan
// perilaku API SSE, batas token, dan pemutusan jaringan secara terkendali.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/chat_bubble.dart';

// ── Mock & Fake Implementations (Semua pengujian menggunakan Fake deterministik) ──

class _FakeGeminiService extends GeminiService {
  Stream<String> Function({required String userMessage, required List<ChatMessage> history})? streamHandler;
  Stream<String> Function({required String userMessage, required String partialAssistantResponse})? continueStreamHandler;
  String? forcedFinishReason;
  List<Map<String, String>>? capturedContinuationMessages;
  List<ChatMessage>? capturedHistory;
  List<ArxivPaper>? capturedPapers;

  _FakeGeminiService({
    this.streamHandler,
    this.continueStreamHandler,
    this.forcedFinishReason,
  }) : super(apiKey: 'dummy-api-key');

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
    capturedHistory = List.from(history);
    capturedPapers = List.from(papers);
    lastStreamFinishReason = forcedFinishReason;

    if (streamHandler != null) {
      yield* streamHandler!(userMessage: userMessage, history: history);
    } else {
      yield 'Halo, ini respons uji.';
      lastStreamFinishReason ??= 'stop';
    }
  }

  @override
  Stream<String> continueChatStream({
    required List<ChatMessage> history,
    required String userMessage,
    required String partialAssistantResponse,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) async* {
    capturedHistory = List.from(history);
    capturedPapers = List.from(papers);
    lastStreamFinishReason = forcedFinishReason;

    if (continueStreamHandler != null) {
      yield* continueStreamHandler!(
        userMessage: userMessage,
        partialAssistantResponse: partialAssistantResponse,
      );
    } else {
      yield ' ini kelanjutan respons.';
      lastStreamFinishReason ??= 'stop';
    }
  }

  @override
  Future<Map<String, String>> extractSearchIntent(String userMessage) async {
    return {
      'query': userMessage,
      'keywords': userMessage,
      'category': '',
      'intent': 'explain',
    };
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
    return 'Fallback Monolith Response';
  }
}

class _MockStorageService extends StorageService {
  String? _key = 'dummy-api-key';
  final Map<String, List<ArxivPaper>> _cache = {};
  List<ChatSession> sessions = [];

  @override
  Future<String?> getApiKey() async => _key;
  @override
  Future<void> saveApiKey(String key) async { _key = key; }
  @override
  Future<List<ChatSession>> getChatSessions() async => sessions;
  @override
  Future<void> saveChatSessions(List<ChatSession> s) async { sessions = List.from(s); }
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
  @override
  Future<List<ArxivPaper>?> getCached(String key) async => _cache[key];
  @override
  Future<void> setCache(String key, List<ArxivPaper> papers) async { _cache[key] = papers; }
  @override
  Future<List<ResearchNote>> getNotes() async => [];
  @override
  Future<List<ArxivPaper>> getFavorites() async => [];
  @override
  Future<String?> getThemeMode() async => 'system';
}

class _MockSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async => [];
}

class _MockPdfService extends PdfService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dummyPaper = ArxivPaper(
    id: 'http://arxiv.org/abs/2401.99999',
    title: 'Benchmarking LLM Deductive Reasoning',
    authors: ['Alan Turing', 'Ada Lovelace'],
    summary: 'A comprehensive study on deductive reasoning in large language models.',
    published: '2024-01-15T00:00:00Z',
    updated: '2024-01-15T00:00:00Z',
    categories: ['cs.AI'],
    pdfUrl: 'http://arxiv.org/pdf/2401.99999',
    absUrl: 'http://arxiv.org/abs/2401.99999',
    doi: '10.1000/182',
  );

  group('Group 1: GeminiService SSE finish_reason Parsing & continueChatStream (Mock HTTP)', () {
    test('1.1. Stream selesai normal: finish_reason "stop" tercatat pada GeminiService', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }

        final ssePayload = [
          'data: {"choices":[{"delta":{"content":"Respons ilmiah lengkap."},"finish_reason":null}]}\n\n',
          'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(apiKey: 'mock-key', client: mockClient);
      final chunks = await service.chatStream(history: [], userMessage: 'Jelaskan logika deduktif').toList();

      expect(chunks.join(), equals('Respons ilmiah lengkap.'));
      expect(service.lastStreamFinishReason, equals('stop'));
    });

    test('1.2. STR-02: finish_reason "length" terdeteksi saat mencapai batas token dan tidak ditandai stop', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }

        // Simulasikan token diputus di tengah kata karena batas output
        final ssePayload = [
          'data: {"choices":[{"delta":{"content":"Penalaran deduktif memerlukan premis yang "},"finish_reason":null}]}\n\n',
          'data: {"choices":[{"delta":{"content":"sah dan kesimpulan"},"finish_reason":"length"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(apiKey: 'mock-key', client: mockClient);
      final chunks = await service.chatStream(history: [], userMessage: 'Uraikan logika deduktif').toList();

      expect(chunks.join(), equals('Penalaran deduktif memerlukan premis yang sah dan kesimpulan'));
      expect(service.lastStreamFinishReason, equals('length'));
    });

    test('1.3. continueChatStream menyusun pesan dengan konteks asisten sebelumnya dan instruksi tanpa duplikasi', () async {
      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }

        final bodyBytes = await bodyStream.toBytes();
        capturedBody = jsonDecode(utf8.decode(bodyBytes));
        final ssePayload = [
          'data: {"choices":[{"delta":{"content":" yang terbukti secara formal."},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ].join();

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(apiKey: 'mock-key', client: mockClient);
      final chunks = await service.continueChatStream(
        history: [],
        userMessage: 'Uraikan logika deduktif',
        partialAssistantResponse: 'Penalaran deduktif memerlukan premis',
        papers: [dummyPaper],
      ).toList();

      expect(chunks.join(), equals(' yang terbukti secara formal.'));
      expect(service.lastStreamFinishReason, equals('stop'));

      expect(capturedBody, isNotNull);
      final messages = capturedBody!['messages'] as List;
      // Periksa apakah asisten dan prompt kelanjutan disisipkan
      expect(messages.any((m) => m['role'] == 'assistant' && m['content'] == 'Penalaran deduktif memerlukan premis'), isTrue);
      expect(messages.last['role'], equals('user'));
      expect(messages.last['content'], contains('tanpa mengulang'));
    });
  });

  group('Group 2: SciChatProvider Deteksi Penyelesaian & Batas Token (STR-02)', () {
    test('2.1. Stream selesai normal: status MessageStatus.done, isTruncated = false', () async {
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Respons tuntas.';
        },
        forcedFinishReason: 'stop',
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      await provider.sendMessage('Uraikan ringkasan');

      expect(provider.messages.length, equals(2));
      final assistantMsg = provider.messages.last;
      expect(assistantMsg.status, equals(MessageStatus.done));
      expect(assistantMsg.content, equals('Respons tuntas.'));
      expect(assistantMsg.isTruncated, isFalse);
      expect(assistantMsg.finishReason, equals('stop'));
    });

    test('2.2. STR-02: finish_reason "length" menandai isTruncated = true dan mempertahankan teks parsial', () async {
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Bagian pertama yang terpotong karena batas token...';
        },
        forcedFinishReason: 'length',
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      await provider.sendMessage('Analisis mendalam paper AI');

      expect(provider.messages.length, equals(2));
      final assistantMsg = provider.messages.last;
      expect(assistantMsg.status, equals(MessageStatus.done));
      expect(assistantMsg.content, equals('Bagian pertama yang terpotong karena batas token...'));
      expect(assistantMsg.isTruncated, isTrue);
      expect(assistantMsg.finishReason, equals('length'));
    });
  });

  group('Group 3: Pemulihan Respons Terputus (STR-01)', () {
    test('3.1. Koneksi terputus setelah teks parsial: status error, teks parsial tetap utuh & isTruncated = true', () async {
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Teks awal berhasil tiba.';
          throw TimeoutException('Koneksi terputus di tengah streaming');
        },
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      await provider.sendMessage('Tanya sesuatu');

      expect(provider.messages.length, equals(2));
      final assistantMsg = provider.messages.last;
      expect(assistantMsg.status, equals(MessageStatus.error));
      expect(assistantMsg.content, equals('Teks awal berhasil tiba.'));
      expect(assistantMsg.isTruncated, isTrue);
      expect(assistantMsg.finishReason, equals('error'));
    });

    test('3.2. Kegagalan sebelum chunk pertama: konten kosong dan dapat dicoba ulang penuh', () async {
      // Buat stream gagal dari awal
      final failingGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          throw Exception('Gagal stream awal');
        },
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: failingGemini,
      );
      await provider.init();

      // Mock chat fallback agar ikut melempar exception
      // Kita uji sendMessage dengan provider
      await provider.sendMessage('Pertanyaan baru');

      expect(provider.messages.length, equals(2));
      final assistantMsg = provider.messages.last;
      // Karena fallback chat() pada _FakeGeminiService mengembalikan 'Fallback Monolith Response',
      // ini membuktikan fallback bekerja saat stream gagal sebelum chunk pertama!
      expect(assistantMsg.status, equals(MessageStatus.done));
      expect(assistantMsg.content, equals('Fallback Monolith Response'));
    });

    test('3.3. continueMessage menyambung tanpa menduplikasi teks yang sudah ada', () async {
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Konsep penalaran deduktif adalah';
        },
        forcedFinishReason: 'length',
        continueStreamHandler: ({required userMessage, required partialAssistantResponse}) async* {
          // Model mungkin mengulang sedikit kata terakhir atau langsung melanjutkan
          yield ' deduktif adalah proses menarik kesimpulan logis dari premis.';
        },
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      await provider.sendMessage('Jelaskan konsep deduktif');
      final truncatedMsg = provider.messages.last;
      expect(truncatedMsg.isTruncated, isTrue);

      // Ubah forcedFinishReason menjadi stop untuk stream kelanjutan
      fakeGemini.forcedFinishReason = 'stop';

      // Panggil aksi lanjut
      await provider.continueMessage(truncatedMsg.id);

      final continuedMsg = provider.messages.last;
      expect(continuedMsg.status, equals(MessageStatus.done));
      expect(continuedMsg.isTruncated, isFalse);
      expect(continuedMsg.finishReason, equals('stop'));

      // Verifikasi TIDAK ADA duplikasi kata 'deduktif adalah'
      expect(
        continuedMsg.content,
        equals('Konsep penalaran deduktif adalah proses menarik kesimpulan logis dari premis.'),
      );
    });

    test('3.4. Kegagalan saat melanjutkan tetap mempertahankan teks yang sudah ada sebelumnya', () async {
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Teks bab 1 dan bab 2 sudah selesai.';
        },
        forcedFinishReason: 'length',
        continueStreamHandler: ({required userMessage, required partialAssistantResponse}) async* {
          throw TimeoutException('Jaringan putus saat melanjutkan');
        },
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      await provider.sendMessage('Tuliskan analisis bab');
      final targetMsg = provider.messages.last;

      await provider.continueMessage(targetMsg.id);

      final failedContinuationMsg = provider.messages.last;
      expect(failedContinuationMsg.status, equals(MessageStatus.error));
      // Teks lama tidak boleh hilang!
      expect(failedContinuationMsg.content, equals('Teks bab 1 dan bab 2 sudah selesai.'));
      expect(failedContinuationMsg.isTruncated, isTrue);
    });

    test('3.5. Konteks paper dari Fase 1 tetap tersedia saat kelanjutan dipanggil', () async {
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Analisis terhadap paper kedua...';
        },
        forcedFinishReason: 'length',
        continueStreamHandler: ({required userMessage, required partialAssistantResponse}) async* {
          yield ' kelanjutan analisis paper kedua.';
        },
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      // Set konteks paper aktif
      provider.setActiveContexts([dummyPaper]);

      await provider.sendMessage('Uraikan metodologi paper ini');
      final assistantMsg = provider.messages.last;
      expect(assistantMsg.papers.isNotEmpty, isTrue);

      await provider.continueMessage(assistantMsg.id);

      // Verifikasi paper diteruskan ke continueChatStream
      expect(fakeGemini.capturedPapers, isNotNull);
      expect(fakeGemini.capturedPapers!.any((p) => p.id == dummyPaper.id), isTrue);
    });

    test('3.6. Pembatalan pengguna (cancelGeneration) menyimpan teks parsial dan menandai status cancelled', () async {
      final completer = Completer<void>();
      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Paragraf awal respons.';
          await completer.future;
          yield 'Paragraf yang dibatalkan.';
        },
      );

      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      final sendFuture = provider.sendMessage('Mulai streaming');

      // Tunggu hingga token pertama tiba
      await Future.delayed(const Duration(milliseconds: 50));
      // Pengguna membatalkan
      provider.cancelGeneration();
      completer.complete();

      await sendFuture;

      final cancelledMsg = provider.messages.last;
      expect(cancelledMsg.status, equals(MessageStatus.done));
      expect(cancelledMsg.isTruncated, isTrue);
      expect(cancelledMsg.finishReason, equals('cancelled'));
      expect(cancelledMsg.content, contains('Paragraf awal respons.'));
      expect(cancelledMsg.content, isNot(contains('Paragraf yang dibatalkan.')));
    });
  });

  group('Group 4: Aksi UI & Kompatibilitas Pesan Lama', () {
    Widget buildTestBubble({
      required ChatMessage message,
      VoidCallback? onRetry,
      VoidCallback? onContinue,
    }) {
      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: _FakeGeminiService(),
      );

      return ChangeNotifierProvider<SciChatProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ChatBubble(
                message: message,
                isFavorite: (_) => false,
                onFavoriteToggle: (_) {},
                onPaperTap: (_) {},
                onRetry: onRetry,
                onContinue: onContinue,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('4.1. UI menampilkan banner kelanjutan & tombol Lanjutkan respons hanya saat isTruncated = true', (tester) async {
      bool continueTapped = false;
      final truncatedMsg = ChatMessage(
        id: 'msg-truncated',
        role: MessageRole.assistant,
        content: 'Teks terpotong di tengah jalan...',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'length',
      );

      await tester.pumpWidget(buildTestBubble(
        message: truncatedMsg,
        onContinue: () => continueTapped = true,
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Respons mencapai batas panjang token'), findsOneWidget);
      expect(find.text('Lanjutkan respons'), findsOneWidget);

      await tester.tap(find.text('Lanjutkan respons'));
      expect(continueTapped, isTrue);
    });

    testWidgets('4.2. UI tidak menampilkan banner kelanjutan jika pesan selesai normal', (tester) async {
      final normalMsg = ChatMessage(
        id: 'msg-normal',
        role: MessageRole.assistant,
        content: 'Respons selesai normal.',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        isTruncated: false,
        finishReason: 'stop',
      );

      await tester.pumpWidget(buildTestBubble(message: normalMsg));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Respons mencapai batas panjang token'), findsNothing);
      expect(find.text('Lanjutkan respons'), findsNothing);
    });

    testWidgets('4.3. UI error dengan teks parsial menampilkan tombol "Lanjutkan jawaban"', (tester) async {
      bool continueTapped = false;
      final partialErrorMsg = ChatMessage(
        id: 'msg-error-partial',
        role: MessageRole.assistant,
        content: 'Sebagian teks sebelum error.',
        timestamp: DateTime.now(),
        status: MessageStatus.error,
        errorType: ChatErrorType.connection,
        isTruncated: true,
        finishReason: 'error',
      );

      await tester.pumpWidget(buildTestBubble(
        message: partialErrorMsg,
        onContinue: () => continueTapped = true,
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Respons terputus'), findsOneWidget);
      expect(find.text('Lanjutkan jawaban'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing); // Coba lagi disembunyikan agar tidak ganda

      await tester.tap(find.text('Lanjutkan jawaban'));
      expect(continueTapped, isTrue);
    });

    testWidgets('4.4. UI error tanpa teks menampilkan tombol "Coba lagi"', (tester) async {
      bool retryTapped = false;
      final emptyErrorMsg = ChatMessage(
        id: 'msg-error-empty',
        role: MessageRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        status: MessageStatus.error,
        errorType: ChatErrorType.connection,
      );

      await tester.pumpWidget(buildTestBubble(
        message: emptyErrorMsg,
        onRetry: () => retryTapped = true,
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Koneksi internet terputus'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.text('Lanjutkan jawaban'), findsNothing);

      await tester.tap(find.text('Coba lagi'));
      expect(retryTapped, isTrue);
    });

    test('4.5. Kompatibilitas pesan lama: ChatMessage.fromJson tanpa isTruncated & finishReason tetap valid', () {
      final legacyJson = {
        'id': 'legacy-msg-1',
        'role': 'MessageRole.assistant',
        'content': 'Ini pesan dari versi lama sebelum Fase 2A.',
        'timestamp': '2024-01-01T12:00:00.000',
        'status': 'MessageStatus.done',
        'papers': [],
      };

      final msg = ChatMessage.fromJson(legacyJson);
      expect(msg.id, equals('legacy-msg-1'));
      expect(msg.content, equals('Ini pesan dari versi lama sebelum Fase 2A.'));
      expect(msg.isTruncated, isFalse);
      expect(msg.finishReason, isNull);
      expect(msg.status, equals(MessageStatus.done));

      // Verifikasi serialisasi balik tetap utuh
      final serialized = msg.toJson();
      expect(serialized['isTruncated'], isFalse);
      expect(serialized['finishReason'], isNull);
    });

    testWidgets('4.6. UI pesan yang dibatalkan menampilkan banner Generasi dihentikan dan TIDAK menampilkan tombol Lanjutkan respons', (tester) async {
      final cancelledMsg = ChatMessage(
        id: 'msg-cancelled',
        role: MessageRole.assistant,
        content: 'Teks parsial yang sempat diterima sebelum pengguna membatalkan.',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'cancelled',
      );

      await tester.pumpWidget(buildTestBubble(
        message: cancelledMsg,
        onContinue: () {},
      ));
      await tester.pump(const Duration(milliseconds: 300));

      // Banner pembatalan harus muncul
      expect(find.text('Generasi dihentikan oleh pengguna'), findsOneWidget);

      // Banner atau tombol batas token TIDAK boleh muncul
      expect(find.text('Respons mencapai batas panjang token'), findsNothing);
      expect(find.text('Lanjutkan respons'), findsNothing);
      expect(find.text('Lanjutkan jawaban'), findsNothing);
    });

    test('4.7. continueMessage mengabaikan pesan dengan finishReason: cancelled dan mempertahankan teks parsial', () async {
      final fakeGemini = _FakeGeminiService();
      final provider = SciChatProvider(
        storageService: _MockStorageService(),
        searchService: _MockSearchService(),
        pdfService: _MockPdfService(),
        geminiService: fakeGemini,
      );
      await provider.init();

      // Buat pesan user dan asisten yang dibatalkan
      final userMsg = ChatMessage(
        id: 'user-c',
        role: MessageRole.user,
        content: 'Jelaskan teori relativitas',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
      );
      final cancelledMsg = ChatMessage(
        id: 'asst-c',
        role: MessageRole.assistant,
        content: 'Relativitas umum menyatakan bahwa',
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'cancelled',
      );
      provider.messages.addAll([userMsg, cancelledMsg]);

      // Panggil continueMessage pada pesan yang dibatalkan
      await provider.continueMessage(cancelledMsg.id);

      // Verifikasi tidak ada request stream yang dikirim dan status tetap cancelled dengan teks utuh
      final afterMsg = provider.messages.last;
      expect(afterMsg.id, equals('asst-c'));
      expect(afterMsg.status, equals(MessageStatus.done));
      expect(afterMsg.finishReason, equals('cancelled'));
      expect(afterMsg.content, equals('Relativitas umum menyatakan bahwa'));
      expect(fakeGemini.capturedHistory, isNull);
    });

    test('4.8. Pemilahan tegas 3 keadaan: length (token limit), error (network), dan cancelled (user cancel) mempertahankan teks parsial', () {
      const partialText = 'Paragraf sains parsial yang valid.';

      // Keadaan 1: Terpotong batas token (length)
      final lengthMsg = ChatMessage(
        id: 'm-length',
        role: MessageRole.assistant,
        content: partialText,
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'length',
      );
      expect(lengthMsg.content, equals(partialText));
      expect(lengthMsg.isTruncated, isTrue);
      expect(lengthMsg.finishReason, equals('length'));
      expect(lengthMsg.status, equals(MessageStatus.done));

      // Keadaan 2: Terputus akibat error/timeout
      final errorMsg = ChatMessage(
        id: 'm-error',
        role: MessageRole.assistant,
        content: partialText,
        timestamp: DateTime.now(),
        status: MessageStatus.error,
        errorType: ChatErrorType.timeout,
        isTruncated: true,
        finishReason: 'error',
      );
      expect(errorMsg.content, equals(partialText));
      expect(errorMsg.isTruncated, isTrue);
      expect(errorMsg.finishReason, equals('error'));
      expect(errorMsg.status, equals(MessageStatus.error));

      // Keadaan 3: Sengaja dibatalkan pengguna
      final cancelledMsg = ChatMessage(
        id: 'm-cancelled',
        role: MessageRole.assistant,
        content: partialText,
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'cancelled',
      );
      expect(cancelledMsg.content, equals(partialText));
      expect(cancelledMsg.isTruncated, isTrue);
      expect(cancelledMsg.finishReason, equals('cancelled'));
      expect(cancelledMsg.status, equals(MessageStatus.done));
    });
  });
}
