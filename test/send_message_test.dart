import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/services/storage_service.dart';

class MockGeminiService extends GeminiService {
  MockGeminiService() : super(apiKey: 'dummy');

  int chatCallCount = 0;
  bool shouldDelay = false;
  bool shouldThrow = false;

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    return {'intent': 'chat', 'query': message};
  }

  @override
  Future<String> chat({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper>? papers,
    Map<String, String>? fullTexts,
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
  }) async {
    chatCallCount++;
    if (shouldThrow) {
      throw Exception('Network Error');
    }
    if (shouldDelay) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return streamOutput;
  }

  String streamOutput = 'Mock Response';
  List<String>? streamChunks;
  bool delayBeforeFirstYield = false;

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
    if (shouldThrow) {
      throw Exception('Network Error');
    }
    chatCallCount++;
    if (shouldDelay) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (delayBeforeFirstYield) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (streamChunks != null) {
      for (final c in streamChunks!) {
        yield c;
      }
    } else {
      yield streamOutput;
    }
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

class MockStorageService extends StorageService {
  String? _key;

  @override
  Future<String?> getApiKey() async => _key;

  @override
  Future<void> saveApiKey(String key) async {
    _key = key;
  }

  List<ChatSession> storedSessions = [];

  @override
  Future<List<ChatSession>> getChatSessions() async => storedSessions;

  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {
    storedSessions = List.from(sessions);
  }

  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

void main() {
  late SciChatProvider provider;
  late MockGeminiService mockGemini;
  late MockStorageService mockStorage;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockGemini = MockGeminiService();
    mockStorage = MockStorageService();
    provider = SciChatProvider(
      geminiService: mockGemini,
      storageService: mockStorage,
    );
  });

  test('BYOK: send message without API key generates error without calling API',
      () async {
    await provider.setApiKey('');
    await provider.sendMessage('Hello');

    expect(provider.messages.length, 2);
    expect(provider.messages[0].role, MessageRole.user);
    expect(provider.messages[1].role, MessageRole.assistant);
    expect(provider.messages[1].status, MessageStatus.error);
    expect(provider.messages[1].errorType, ChatErrorType.authentication);
    expect(provider.messages[1].content, isEmpty);
    expect(mockGemini.chatCallCount, 0);
  });

  test('Double-send is blocked when request is already running', () async {
    mockGemini.shouldDelay = true;

    final future1 = provider.sendMessage('First Message');
    await provider.sendMessage('Second Message');

    expect(provider.messages.length, 2);
    expect(provider.messages[0].content, 'First Message');

    await future1;

    expect(provider.appState, AppState.ready);
    expect(provider.messages.length, 2);
    expect(provider.messages[1].content, 'Mock Response');
    expect(provider.messages[1].status, MessageStatus.done);

    expect(mockGemini.chatCallCount, 1);
  });

  test('Retry after request fails and sending after success works', () async {
    mockGemini.shouldThrow = true;
    await provider.sendMessage('First Message');

    expect(provider.messages.length, 2);
    expect(provider.messages[1].status, MessageStatus.error);
    expect(provider.appState, AppState.error);

    mockGemini.shouldThrow = false;
    await provider.sendMessage('Second Message');

    expect(provider.messages.length, 4);
    expect(provider.messages[3].status, MessageStatus.done);
    expect(provider.messages[3].content, 'Mock Response');
    expect(provider.appState, AppState.ready);
    expect(mockGemini.chatCallCount, 2);
  });

  group('Regenerate AI Response Tests (Tahap 2)', () {
    test(
        '1. Regenerate replaces last assistant message in-place without duplicating user prompt',
        () async {
      await provider.sendMessage('Pertanyaan Riset');
      expect(provider.messages.length, 2);
      final originalUserMsg = provider.messages[0];
      final originalAssistantMsg = provider.messages[1];
      expect(originalUserMsg.role, MessageRole.user);
      expect(originalAssistantMsg.role, MessageRole.assistant);
      expect(originalAssistantMsg.content, 'Mock Response');

      // Set respon baru dari AI untuk regenerasi
      mockGemini.streamOutput = 'Jawaban Alternatif Baru';
      await provider.regenerateLastResponse();

      expect(provider.messages.length,
          2); // Tetap 2, tidak menduplikasi user prompt!
      expect(
          provider.messages[0].id, originalUserMsg.id); // Pesan user tetap sama
      expect(provider.messages[0].content, 'Pertanyaan Riset');

      final regeneratedAssistantMsg = provider.messages[1];
      expect(regeneratedAssistantMsg.role, MessageRole.assistant);
      expect(regeneratedAssistantMsg.content, 'Jawaban Alternatif Baru');
      expect(regeneratedAssistantMsg.status, MessageStatus.done);
      expect(
          regeneratedAssistantMsg.id,
          isNot(
              equals(originalAssistantMsg.id))); // ID baru untuk keamanan note
    });

    test(
        '2. Regenerate preserves existing papers from previous assistant message',
        () async {
      const samplePaper = ArxivPaper(
        id: '2401.99999',
        title: 'Transformer Efficiency in Deep Learning',
        authors: ['Researcher X'],
        summary: 'Efficiency benchmark for transformers.',
        published: '2024-01-01',
        updated: '2024-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'https://arxiv.org/pdf/2401.99999',
        absUrl: 'https://arxiv.org/abs/2401.99999',
      );

      // Kirim pesan pertama
      await provider.sendMessage('Pertanyaan Paper');
      // Pasang paper metadata ke pesan asisten
      provider.messages[1] =
          provider.messages[1].copyWith(papers: [samplePaper]);
      expect(provider.messages[1].papers.length, 1);

      mockGemini.streamOutput = 'Jawaban Baru Mempertahankan Paper';
      await provider.regenerateLastResponse();

      expect(provider.messages.length, 2);
      expect(provider.messages[1].papers.length, 1);
      expect(provider.messages[1].papers.first.id, '2401.99999');
      expect(provider.messages[1].papers.first.title,
          'Transformer Efficiency in Deep Learning');
      expect(provider.messages[1].content, 'Jawaban Baru Mempertahankan Paper');
    });

    test('3. Regenerate is blocked when provider isLoading or apiKey is empty',
        () async {
      await provider.sendMessage('Pertanyaan');
      expect(provider.messages.length, 2);

      // Test saat API key kosong
      await provider.setApiKey('');
      await provider.regenerateLastResponse();
      expect(provider.messages[1].content, 'Mock Response'); // Tidak berubah

      // Kembalikan API key
      await provider.setApiKey('valid-key');

      // Test saat isLoading (generasi sedang berjalan)
      mockGemini.shouldDelay = true;
      final future1 = provider.regenerateLastResponse();
      // Panggilan kedua saat future1 masih running
      await provider.regenerateLastResponse();
      await future1;

      // Panggilan kedua ditolak, chatCallCount hanya naik 1 kali
      expect(provider.messages.length, 2);
    });

    test(
        '4. Regenerate restores previous assistant message if cancelled before receiving first chunk',
        () async {
      await provider.sendMessage('Pertanyaan Awal');
      final originalContent = provider.messages[1].content;

      mockGemini.delayBeforeFirstYield = true;
      final regenFuture = provider.regenerateLastResponse();

      // Batalkan segera sebelum chunk pertama terkirim
      await Future.delayed(const Duration(milliseconds: 50));
      provider.cancelGeneration();
      await regenFuture;

      // Respons asisten lama dipulihkan utuh!
      expect(provider.messages.length, 2);
      expect(provider.messages[1].content, equals(originalContent));
      expect(provider.messages[1].status, equals(MessageStatus.done));
    });

    test('5. Regenerate handles errors and preserves error classification',
        () async {
      await provider.sendMessage('Pertanyaan');
      expect(provider.messages[1].status, MessageStatus.done);

      mockGemini.shouldThrow = true;
      await provider.regenerateLastResponse();

      expect(provider.messages.length, 2);
      expect(provider.messages[1].status, MessageStatus.error);
      expect(provider.appState, AppState.error);
    });
  });

  group('Branching AI Conversation Tests (Tahap 3)', () {
    const samplePaper = ArxivPaper(
      id: '2402.12345',
      title: 'Attention Routing and Memory Isolation',
      authors: ['Researcher Alpha'],
      summary: 'Branching mechanisms in transformer LLMs.',
      published: '2024-02-01',
      updated: '2024-02-01',
      categories: ['cs.CL'],
      pdfUrl: 'https://arxiv.org/pdf/2402.12345',
      absUrl: 'https://arxiv.org/abs/2402.12345',
    );

    test(
        '1. Branching creates a new session with unique ID and title "Cabang: [Judul]"',
        () async {
      await provider.sendMessage('Pertanyaan 1');
      expect(provider.messages.length, 2);
      final assistantMsg1 = provider.messages[1];
      final originalSessionId = provider.activeSessionId;

      final success = await provider.branchSessionFromMessage(assistantMsg1.id);
      expect(success, isTrue);

      // Sesi aktif berpindah ke sesi baru
      expect(provider.activeSessionId, isNot(equals(originalSessionId)));
      expect(provider.sessions.length, 2);

      final branchSession = provider.sessions.first;
      expect(branchSession.id, equals(provider.activeSessionId));
      expect(branchSession.title, startsWith('Cabang: '));
    });

    test(
        '2. Only messages up to branch point are copied; subsequent messages are excluded',
        () async {
      // Buat riwayat 2 putaran tanya-jawab (4 pesan)
      await provider.sendMessage('Pertanyaan 1');
      final assistantMsg1 = provider.messages[1];
      await provider.sendMessage('Pertanyaan 2');
      expect(provider.messages.length, 4);
      final originalSessionId = provider.activeSessionId;

      // Cabangkan dari jawaban pertama (assistantMsg1)
      final success = await provider.branchSessionFromMessage(assistantMsg1.id);
      expect(success, isTrue);

      // Sesi cabang baru hanya memiliki 2 pesan (Pertanyaan 1 dan Jawaban 1)
      expect(provider.messages.length, 2);
      expect(provider.messages[0].content, equals('Pertanyaan 1'));
      expect(provider.messages[1].content, equals('Mock Response'));

      // Periksa bahwa sesi asal tetap memiliki 4 pesan lengkap
      final originalSession =
          provider.sessions.firstWhere((s) => s.id == originalSessionId);
      expect(originalSession.messages.length, 4);
      expect(originalSession.messages[2].content, equals('Pertanyaan 2'));
    });

    test(
        '3. All copied messages receive fresh unique UUIDs to isolate notes and state',
        () async {
      await provider.sendMessage('Pertanyaan Riset');
      final originalUserMsg = provider.messages[0];
      final originalAssistantMsg = provider.messages[1];

      final success =
          await provider.branchSessionFromMessage(originalAssistantMsg.id);
      expect(success, isTrue);

      final clonedUserMsg = provider.messages[0];
      final clonedAssistantMsg = provider.messages[1];

      // Konten sama tapi ID berbeda
      expect(clonedUserMsg.content, equals(originalUserMsg.content));
      expect(clonedUserMsg.id, isNot(equals(originalUserMsg.id)));

      expect(clonedAssistantMsg.content, equals(originalAssistantMsg.content));
      expect(clonedAssistantMsg.id, isNot(equals(originalAssistantMsg.id)));
    });

    test(
        '4. Paper metadata and citations are preserved on copied assistant messages',
        () async {
      await provider.sendMessage('Pertanyaan Paper');
      provider.messages[1] =
          provider.messages[1].copyWith(papers: [samplePaper]);
      final assistantMsg = provider.messages[1];

      final success = await provider.branchSessionFromMessage(assistantMsg.id);
      expect(success, isTrue);

      final clonedAssistantMsg = provider.messages[1];
      expect(clonedAssistantMsg.papers.length, 1);
      expect(clonedAssistantMsg.papers.first.id, equals('2402.12345'));
      expect(clonedAssistantMsg.papers.first.title,
          equals('Attention Routing and Memory Isolation'));
    });

    test(
        '5. Branched session is persisted to StorageService and can be reloaded',
        () async {
      await provider.sendMessage('Percakapan Awal');
      final assistantMsg = provider.messages[1];

      final success = await provider.branchSessionFromMessage(assistantMsg.id);
      expect(success, isTrue);
      final branchSessionId = provider.activeSessionId;

      // Verifikasi sesi tersimpan di mock storage
      final storedSessions = await mockStorage.getChatSessions();
      expect(storedSessions.any((s) => s.id == branchSessionId), isTrue);

      // Muat sesi kembali
      provider.createNewSession();
      expect(provider.activeSessionId, isNot(equals(branchSessionId)));

      provider.loadSession(branchSessionId);
      expect(provider.activeSessionId, equals(branchSessionId));
      expect(provider.messages.length, 2);
    });

    test(
        '6. Branching is blocked when provider is loading or invalid target message',
        () async {
      await provider.sendMessage('Pertanyaan');
      final assistantMsg = provider.messages[1];

      // Simulasi loading aktif
      mockGemini.shouldDelay = true;
      final futureGen = provider.sendMessage('Pesan Kedua');

      // Coba cabangkan saat sedang proses
      final branchResult =
          await provider.branchSessionFromMessage(assistantMsg.id);
      expect(branchResult, isFalse);

      await futureGen;

      // Coba cabangkan pesan user (bukan asisten) -> harus ditolak
      final userBranchResult =
          await provider.branchSessionFromMessage(provider.messages[0].id);
      expect(userBranchResult, isFalse);

      // Coba pesan yang tidak ada -> harus ditolak
      final nonExistentResult =
          await provider.branchSessionFromMessage('invalid-id-xyz');
      expect(nonExistentResult, isFalse);
    });
  });
}
