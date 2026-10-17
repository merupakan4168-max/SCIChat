// Test Regresi Wajib Fase 3.2: Streaming Session Isolation
// Memastikan stream dari sesi lama tidak mencemari sesi baru saat berpindah sesi,
// pesan parsial tersimpan dengan benar pada sesi asalnya, dan cleanup berjalan aman.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';

// ── Mock / Fake deterministik untuk pengujian isolasi sesi ──

class _FakeGeminiService extends GeminiService {
  Stream<String> Function({required String userMessage, required List<ChatMessage> history})? streamHandler;
  Stream<String> Function({required String userMessage, required String partialAssistantResponse})? continueStreamHandler;

  _FakeGeminiService({
    this.streamHandler,
    this.continueStreamHandler,
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
    if (streamHandler != null) {
      yield* streamHandler!(userMessage: userMessage, history: history);
    } else {
      yield 'Respons default.';
      lastStreamFinishReason = 'stop';
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
    if (continueStreamHandler != null) {
      yield* continueStreamHandler!(
        userMessage: userMessage,
        partialAssistantResponse: partialAssistantResponse,
      );
    } else {
      yield ' kelanjutan default.';
      lastStreamFinishReason = 'stop';
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
    return 'Fallback Monolith';
  }
}

class _MockStorageService extends StorageService {
  String? _key = 'dummy-api-key';
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
  Future<List<ArxivPaper>?> getCached(String key) async => null;
  @override
  Future<void> setCache(String key, List<ArxivPaper> papers) async {}
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

  late _MockStorageService mockStorage;
  late _MockSearchService mockSearch;
  late _MockPdfService mockPdf;

  setUp(() {
    mockStorage = _MockStorageService();
    mockSearch = _MockSearchService();
    mockPdf = _MockPdfService();
  });

  group('Fase 3.2: Streaming Session Isolation', () {
    test('1. Perpindahan sesi saat stream aktif tidak mencemari sesi tujuan', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Chunk A1 dari Sesi A.';
          await completerA.future;
          yield ' Chunk A2 yang seharusnya tidak muncul di Sesi B.';
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      // Pastikan berada di Sesi A
      provider.loadSession(sessionAId);
      expect(provider.activeSessionId, equals(sessionAId));

      // Jalankan sendMessage di Sesi A (asinkron)
      final sendFuture = provider.sendMessage('Pertanyaan di Sesi A');

      // Tunggu hingga provider masuk ke state streaming
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      expect(provider.appState, equals(AppState.streaming));
      expect(provider.messages.isNotEmpty, isTrue);

      // PENGGUNA BERPINDAH KE SESI B saat stream Sesi A masih berjalan
      provider.loadSession(sessionBId);

      // Verifikasi state provider langsung berpindah dan bersih di Sesi B
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.messages.isEmpty, isTrue);
      expect(provider.appState, equals(AppState.ready));

      // Lepaskan generator A
      completerA.complete();
      await sendFuture;

      // Verifikasi Sesi B TIDAK TERCEMARI oleh Chunk A2 atau state selesai dari Sesi A
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.messages.isEmpty, isTrue);
      expect(provider.appState, equals(AppState.ready));
    });

    test('2. Pesan parsial sesi A tetap tersimpan dengan status done dan cancelled', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Teks parsial berharga dari Sesi A.';
          await completerA.future;
          yield ' Teks lanjutan yang dibuang.';
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      provider.loadSession(sessionAId);
      final sendFuture = provider.sendMessage('Analisis metodologi');

      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pindah ke Sesi B
      provider.loadSession(sessionBId);
      completerA.complete();
      await sendFuture;

      // Periksa data tersimpan Sesi A di storage
      final savedA = mockStorage.sessions.firstWhere((s) => s.id == sessionAId);
      expect(savedA.messages.length, equals(2));
      final userMsg = savedA.messages.first;
      final assistantMsg = savedA.messages.last;

      expect(userMsg.isUser, isTrue);
      expect(assistantMsg.isUser, isFalse);
      expect(assistantMsg.content, contains('Teks parsial berharga dari Sesi A.'));
      expect(assistantMsg.status, equals(MessageStatus.done));
      expect(assistantMsg.isTruncated, isTrue);
      expect(assistantMsg.finishReason, equals('cancelled'));

      // Jika kembali ke Sesi A, pesan parsial ditampilkan dengan benar
      provider.loadSession(sessionAId);
      expect(provider.messages.length, equals(2));
      expect(provider.messages.last.content, contains('Teks parsial berharga dari Sesi A.'));
      expect(provider.messages.last.finishReason, equals('cancelled'));
    });

    test('2b. Placeholder kosong pada Sesi A dibuang jika sesi ditinggalkan sebelum chunk pertama', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final holdCompleter = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          await holdCompleter.future;
          yield 'Chunk terlambat.';
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      provider.loadSession(sessionAId);
      final sendFuture = provider.sendMessage('Pertanyaan cepat');

      while (provider.appState != AppState.thinking) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      expect(provider.appState, equals(AppState.thinking));

      // Pengguna langsung berpindah ke Sesi B sebelum chunk pertama tiba
      provider.loadSession(sessionBId);

      holdCompleter.complete();
      await sendFuture;

      // Periksa Sesi A: placeholder assistant kosong harus dibuang, hanya tersisa pesan user
      final savedA = mockStorage.sessions.firstWhere((s) => s.id == sessionAId);
      expect(savedA.messages.length, equals(1));
      expect(savedA.messages.first.isUser, isTrue);
    });

    test('3. Generasi baru di Sesi B berjalan normal tanpa terganggu pembatalan Sesi A', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          if (userMessage.contains('Sesi A')) {
            yield 'Teks parsial A.';
            await completerA.future;
            yield ' Selesai A.';
          } else {
            yield 'Jawaban lengkap dan sukses di Sesi B.';
          }
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      // Mulai di Sesi A
      provider.loadSession(sessionAId);
      final sendAFuture = provider.sendMessage('Pertanyaan di Sesi A');

      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pindah ke Sesi B
      provider.loadSession(sessionBId);

      // Mulai generasi baru di Sesi B
      final sendBFuture = provider.sendMessage('Pertanyaan di Sesi B');

      // Unblock stream Sesi A
      completerA.complete();

      await sendBFuture;
      await sendAFuture;

      // Verifikasi Sesi B berhasil tuntas tanpa terganggu
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.messages.length, equals(2));
      final bAssistantMsg = provider.messages.last;
      expect(bAssistantMsg.content, equals('Jawaban lengkap dan sukses di Sesi B.'));
      expect(bAssistantMsg.status, equals(MessageStatus.done));
      expect(bAssistantMsg.isTruncated, isFalse);
      expect(provider.appState, equals(AppState.ready));
    });

    test('4. Pergantian sesi berulang (A -> B -> C) meninggalkan Sesi C dalam keadaan bersih', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';
      const sessionCId = 'session-c';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionCId, title: 'Session C', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();
      final completerB = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          if (userMessage.contains('A')) {
            yield 'Chunk A';
            await completerA.future;
            yield ' A selesai';
          } else if (userMessage.contains('B')) {
            yield 'Chunk B';
            await completerB.future;
            yield ' B selesai';
          } else {
            yield 'Respons tuntas C';
          }
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      // Mulai di A
      provider.loadSession(sessionAId);
      final futureA = provider.sendMessage('Query A');
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pindah ke B dan mulai di B
      provider.loadSession(sessionBId);
      final futureB = provider.sendMessage('Query B');
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pindah ke C
      provider.loadSession(sessionCId);

      // Selesaikan stream A dan B yang menggantung
      completerA.complete();
      completerB.complete();

      await futureA;
      await futureB;

      // Verifikasi Sesi C bersih dan tidak ada pesan A maupun B yang masuk
      expect(provider.activeSessionId, equals(sessionCId));
      expect(provider.messages.isEmpty, isTrue);
      expect(provider.appState, equals(AppState.ready));
    });

    test('4b. Rapid toggle A -> B -> A tidak menerima sisa stream dari generasi A sebelumnya', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA1 = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          if (userMessage == 'A1') {
            yield 'Chunk A1-part1';
            await completerA1.future;
            yield ' Chunk A1-part2-stale';
          } else {
            yield 'Respons A2 baru yang valid';
          }
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      // Mulai A1
      provider.loadSession(sessionAId);
      final futureA1 = provider.sendMessage('A1');
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Beralih ke B
      provider.loadSession(sessionBId);

      // Beralih kembali ke A
      provider.loadSession(sessionAId);

      // Mulai generasi baru A2 pada Sesi A
      final futureA2 = provider.sendMessage('A2');

      // Emisi kelanjutan dari A1 lama
      completerA1.complete();

      await futureA1;
      await futureA2;

      // Verifikasi: generasi A2 sukses, dan chunk stale dari A1 tidak tertempel di pesan aktif
      final lastMsg = provider.messages.last;
      expect(lastMsg.content, equals('Respons A2 baru yang valid'));
      expect(lastMsg.content, isNot(contains('A1-part2-stale')));
    });

    test('5. Exception dari stream lama tidak mengubah status sesi aktif menjadi error', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Chunk awal sebelum error.';
          await completerA.future;
          throw TimeoutException('Koneksi Sesi A putus setelah switch');
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      provider.loadSession(sessionAId);
      final sendFuture = provider.sendMessage('Pertanyaan di A');
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pindah ke B
      provider.loadSession(sessionBId);
      expect(provider.appState, equals(AppState.ready));

      // Memicu error pada stream A
      completerA.complete();
      await sendFuture;

      // Verifikasi Sesi B tetap dalam state ready dan tidak terpengaruh error Sesi A
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.appState, equals(AppState.ready));
      expect(provider.errorMessage, isNull);
    });

    test('6. createNewSession() menghentikan stream aktif dan menyiapkan sesi baru yang bersih', () async {
      const sessionAId = 'session-a';
      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Konten parsial A.';
          await completerA.future;
          yield ' Sisa teks A.';
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      provider.loadSession(sessionAId);
      final sendFuture = provider.sendMessage('Uji createNewSession');
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pengguna menekan tombol New Chat saat stream masih aktif
      provider.createNewSession();

      expect(provider.activeSessionId, isNot(equals(sessionAId)));
      expect(provider.messages.isEmpty, isTrue);
      expect(provider.appState, equals(AppState.ready));

      completerA.complete();
      await sendFuture;

      // Verifikasi sesi baru tetap bersih
      expect(provider.messages.isEmpty, isTrue);
      expect(provider.appState, equals(AppState.ready));

      // Sesi A tetap menyimpan teks parsial
      final savedA = mockStorage.sessions.firstWhere((s) => s.id == sessionAId);
      expect(savedA.messages.last.finishReason, equals('cancelled'));
    });

    test('7. deleteSession() pada sesi aktif yang sedang streaming membersihkan state dengan aman', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';
      mockStorage.sessions = [
        ChatSession(id: sessionAId, title: 'Session A', messages: [], updatedAt: DateTime.now()),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final completerA = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        streamHandler: ({required userMessage, required history}) async* {
          yield 'Konten sesi A yang akan dihapus.';
          await completerA.future;
          yield ' Sisa stream.';
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      provider.loadSession(sessionAId);
      final sendFuture = provider.sendMessage('Pesan di sesi A');
      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Hapus sesi A yang sedang streaming
      provider.deleteSession(sessionAId);

      // Verifikasi sesi aktif berganti ke sesi lain (sessionBId) dan state ready
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.appState, equals(AppState.ready));

      completerA.complete();
      await sendFuture;

      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.messages.isEmpty, isTrue);
      expect(mockStorage.sessions.any((s) => s.id == sessionAId), isFalse);
    });

    test('8. continueMessage terisolasi saat pengguna berganti sesi sebelum kelanjutan selesai', () async {
      const sessionAId = 'session-a';
      const sessionBId = 'session-b';

      final truncatedMsg = ChatMessage(
        id: 'msg-truncated-1',
        role: MessageRole.assistant,
        content: 'Bagian awal pesan',
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'length',
        timestamp: DateTime.now(),
      );

      mockStorage.sessions = [
        ChatSession(
          id: sessionAId,
          title: 'Session A',
          messages: [
            ChatMessage(
              id: 'user-msg-1',
              role: MessageRole.user,
              content: 'Pertanyaan panjang',
              timestamp: DateTime.now(),
            ),
            truncatedMsg,
          ],
          updatedAt: DateTime.now(),
        ),
        ChatSession(id: sessionBId, title: 'Session B', messages: [], updatedAt: DateTime.now()),
      ];

      final continueCompleter = Completer<void>();

      final fakeGemini = _FakeGeminiService(
        continueStreamHandler: ({required userMessage, required partialAssistantResponse}) async* {
          yield ' kelanjutan bab 1.';
          await continueCompleter.future;
          yield ' kelanjutan bab 2.';
        },
      );

      final provider = SciChatProvider(
        storageService: mockStorage,
        searchService: mockSearch,
        pdfService: mockPdf,
        geminiService: fakeGemini,
      );
      await provider.init();

      provider.loadSession(sessionAId);
      final continueFuture = provider.continueMessage(truncatedMsg.id);

      while (provider.appState != AppState.streaming) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      // Pengguna berpindah ke Sesi B saat kelanjutan berjalan
      provider.loadSession(sessionBId);
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.messages.isEmpty, isTrue);

      continueCompleter.complete();
      await continueFuture;

      // Verifikasi Sesi B tidak tercemari oleh kelanjutan Sesi A
      expect(provider.activeSessionId, equals(sessionBId));
      expect(provider.messages.isEmpty, isTrue);
      expect(provider.appState, equals(AppState.ready));
    });
  });
}
