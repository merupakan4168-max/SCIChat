import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/theme/scichat_theme.dart';
import 'package:scichat/widgets/chat_bubble.dart';

class _FakeStorageService extends StorageService {
  final List<ChatSession> _sessions = [];

  @override
  Future<String?> getApiKey() async => 'test-api-key';

  @override
  Future<void> saveApiKey(String key) async {}

  @override
  Future<List<ChatSession>> getChatSessions() async => _sessions;

  Future<void> saveChatSession(ChatSession session) async {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx != -1) {
      _sessions[idx] = session;
    } else {
      _sessions.add(session);
    }
  }

  Future<void> deleteChatSession(String id) async {
    _sessions.removeWhere((s) => s.id == id);
  }

  @override
  Future<List<ArxivPaper>> getFavorites() async => [];

  Future<void> saveFavorites(List<ArxivPaper> papers) async {}

  @override
  Future<List<ResearchNote>> getNotes() async => [];

  Future<void> saveNotes(List<ResearchNote> notes) async {}

  @override
  Future<String?> getThemeMode() async => 'dark';

  @override
  Future<void> saveThemeMode(String mode) async {}

  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

class _FakeSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    return [];
  }

  @override
  Future<List<ArxivPaper>> fetchTrending() async => [];
}

class _FakePdfService extends PdfService {}

class _TestGeminiService extends GeminiService {
  int followUpCallCount = 0;
  List<String> streamChunks = [];
  bool streamShouldThrowBeforeFirstChunk = false;
  String fallbackChatResponse = '';
  Completer<void>? streamPauseCompleter;

  _TestGeminiService() : super(apiKey: 'test-key');

  @override
  Future<Map<String, String>> extractSearchIntent(String userMessage) async {
    return {
      'query': userMessage,
      'keywords': userMessage,
      'category': '',
      'intent': 'chat',
    };
  }

  Stream<String> Function()? customStreamHandler;

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
    if (customStreamHandler != null) {
      yield* customStreamHandler!();
      return;
    }
    if (streamShouldThrowBeforeFirstChunk) {
      throw Exception('Network stream disconnected immediately');
    }
    for (int i = 0; i < streamChunks.length; i++) {
      if (i > 0 && streamPauseCompleter != null) {
        await streamPauseCompleter!.future;
      }
      yield streamChunks[i];
    }
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
    return fallbackChatResponse;
  }

  List<String> continueStreamChunks = [];
  String? mockStreamFinishReason;

  @override
  String? get lastStreamFinishReason => mockStreamFinishReason;

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
    for (final chunk in continueStreamChunks) {
      yield chunk;
    }
  }

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required String userQuestion,
    required String aiAnswer,
    List<ArxivPaper> papers = const [],
  }) async {
    followUpCallCount++;
    return ['Legacy 1', 'Legacy 2', 'Legacy 3'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Merged Follow-Up Streaming Integration Tests', () {
    test(
        '10 & 11. Stream berakhir normal: saran diekstrak, teks bersih, dan tidak ada tag bocor ke listener',
        () async {
      final gemini = _TestGeminiService();
      gemini.streamChunks = [
        'Jawaban riset bagian awal. ',
        'Bagian metodologi lengkap.\n\n',
        '<',
        'fol',
        'low_up>',
        '["Bandingkan akurasi model", ',
        '"Apa limitasi dataset?", ',
        '"Bagaimana reproduktibilitasnya?"]',
        '</follow_up>',
      ];

      final storage = _FakeStorageService();
      final provider = SciChatProvider(
        geminiService: gemini,
        storageService: storage,
        searchService: _FakeSearchService(),
        pdfService: _FakePdfService(),
      );
      await provider.init();

      final listenerContentSnapshots = <String>[];
      provider.addListener(() {
        final msgs = provider.messages;
        if (msgs.isNotEmpty && msgs.last.isAssistant) {
          listenerContentSnapshots.add(msgs.last.content);
        }
      });

      await provider.sendMessage('Jelaskan metodologi riset');

      // 1. Verifikasi tidak pernah ada tag internal bocor ke listener selama streaming
      for (final snapshot in listenerContentSnapshots) {
        expect(snapshot.contains('<follow_up'), isFalse);
        expect(snapshot.contains('</follow_up>'), isFalse);
        expect(snapshot.endsWith('<fol'), isFalse);
        expect(snapshot.endsWith('<'), isFalse);
        expect(snapshot.contains('Bandingkan akurasi'), isFalse);
      }

      // 2. Verifikasi pesan akhir asisten
      final assistantMsg = provider.messages.last;
      expect(assistantMsg.status, equals(MessageStatus.done));
      expect(
        assistantMsg.content,
        equals('Jawaban riset bagian awal. Bagian metodologi lengkap.'),
      );
      expect(assistantMsg.followUpSuggestions.length, equals(3));
      expect(assistantMsg.followUpSuggestions[0],
          equals('Bandingkan akurasi model'));
      expect(
          assistantMsg.followUpSuggestions[1], equals('Apa limitasi dataset?'));
      expect(assistantMsg.followUpSuggestions[2],
          equals('Bagaimana reproduktibilitasnya?'));

      // 3. Verifikasi PENTING: request terpisah generateFollowUpSuggestions() TIDAK PERNAH DIPANGGIL (0 kali)
      expect(gemini.followUpCallCount, equals(0));
    });

    test(
        '9. Pembatalan stream ketika tag sedang ditulis tidak meninggalkan fragmen tag',
        () async {
      final gemini = _TestGeminiService();
      final cancelCompleter = Completer<void>();

      gemini.customStreamHandler = () async* {
        yield 'Teks jawaban sebelum dibatalkan.\n\n';
        yield '<follow_up>["Saran yang belum selesai';
        await cancelCompleter.future;
        yield ' potongan tag selanjutnya"]</follow_up>';
      };

      final storage = _FakeStorageService();
      final provider = SciChatProvider(
        geminiService: gemini,
        storageService: storage,
        searchService: _FakeSearchService(),
        pdfService: _FakePdfService(),
      );
      await provider.init();

      // Mulai mengirim pesan secara asinkron
      final sendFuture = provider.sendMessage('Pertanyaan user');

      // Tunggu hingga token pertama tiba dan provider beralih ke state streaming
      await Future.delayed(const Duration(milliseconds: 50));

      // Pengguna membatalkan saat potongan tag sedang ditulis
      provider.cancelGeneration();
      cancelCompleter.complete();

      await sendFuture;

      final assistantMsgs =
          provider.messages.where((m) => m.isAssistant).toList();
      expect(assistantMsgs.isNotEmpty, isTrue);
      final finalMsg = assistantMsgs.last;

      expect(finalMsg.finishReason, equals('cancelled'));
      expect(finalMsg.content, equals('Teks jawaban sebelum dibatalkan.'));
      expect(finalMsg.content.contains('<follow_up'), isFalse);
      expect(gemini.followUpCallCount, equals(0));
    });

    test(
        '13. Fallback monolitik mengekstrak tag follow-up tanpa memanggil request terpisah',
        () async {
      final gemini = _TestGeminiService();
      gemini.streamShouldThrowBeforeFirstChunk = true;
      gemini.fallbackChatResponse = '''
Jawaban dari fallback monolitik.
<follow_up>["Saran fallback 1", "Saran fallback 2", "Saran fallback 3"]</follow_up>''';

      final storage = _FakeStorageService();
      final provider = SciChatProvider(
        geminiService: gemini,
        storageService: storage,
        searchService: _FakeSearchService(),
        pdfService: _FakePdfService(),
      );
      await provider.init();

      await provider.sendMessage('Uji fallback');

      final assistantMsg = provider.messages.last;
      expect(assistantMsg.status, equals(MessageStatus.done));
      expect(assistantMsg.content, equals('Jawaban dari fallback monolitik.'));
      expect(assistantMsg.content.contains('<follow_up'), isFalse);
      expect(assistantMsg.followUpSuggestions.length, equals(3));
      expect(assistantMsg.followUpSuggestions[0], equals('Saran fallback 1'));
      expect(assistantMsg.followUpSuggestions[1], equals('Saran fallback 2'));
      expect(assistantMsg.followUpSuggestions[2], equals('Saran fallback 3'));

      // Request follow-up terpisah tetap 0!
      expect(gemini.followUpCallCount, equals(0));
    });

    testWidgets('12. Saran yang dihasilkan dapat ditekan dan memicu input baru',
        (tester) async {
      String? tappedSuggestion;
      final msg = ChatMessage(
        id: 'msg-merged-test',
        role: MessageRole.assistant,
        content: 'Hasil inferensi model bahasa ilmiah.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        followUpSuggestions: const [
          'Bagaimana performa pada dataset benchmark?',
          'Berapa latensi inferensi?',
          'Apakah model tahan terhadap noise?',
        ],
      );

      final provider = SciChatProvider(
        storageService: _FakeStorageService(),
        geminiService: _TestGeminiService(),
        searchService: _FakeSearchService(),
        pdfService: _FakePdfService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(
                children: [
                  ChatBubble(
                    message: msg,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                    onFollowUpTap: (s) => tappedSuggestion = s,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verifikasi 3 chip muncul
      expect(find.text('Bagaimana performa pada dataset benchmark?'),
          findsOneWidget);
      expect(find.text('Berapa latensi inferensi?'), findsOneWidget);
      expect(find.text('Apakah model tahan terhadap noise?'), findsOneWidget);

      // Tap saran kedua
      await tester.tap(find.text('Berapa latensi inferensi?'));
      await tester.pumpAndSettle();

      expect(tappedSuggestion, equals('Berapa latensi inferensi?'));
    });

    test(
        '14. continueMessage: respons awal terpotong tanpa blok, respons lanjutan menyelesaikan blok, teks utuh dan saran diekstrak 1x',
        () async {
      final gemini = _TestGeminiService();
      // Respons awal: terpotong di tengah kalimat karena batas token (finishReason = 'length'), tanpa follow-up block
      gemini.streamChunks = [
        'Bagian pertama pembahasan astrofisika kuantum. Kami mendiskusikan singularitas',
      ];
      gemini.mockStreamFinishReason = 'length';

      final storage = _FakeStorageService();
      final provider = SciChatProvider(
        geminiService: gemini,
        storageService: storage,
        searchService: _FakeSearchService(),
        pdfService: _FakePdfService(),
      );
      await provider.init();

      await provider.sendMessage('Jelaskan singularitas lubang hitam');

      // Verifikasi kondisi respons awal:
      final initialMsg = provider.messages.last;
      expect(initialMsg.status, equals(MessageStatus.done));
      expect(initialMsg.isTruncated, isTrue);
      expect(initialMsg.finishReason, equals('length'));
      expect(initialMsg.followUpSuggestions, isEmpty);
      expect(
        initialMsg.content,
        equals(
            'Bagian pertama pembahasan astrofisika kuantum. Kami mendiskusikan singularitas'),
      );
      expect(gemini.followUpCallCount, equals(0));

      // Siapkan chunk lanjutan yang menyelesaikan penjelasan dan menyertakan tag follow-up
      gemini.continueStreamChunks = [
        ' dan radiasi Hawking pada horizon peristiwa.\n\n',
        '<follow_up>["Bagaimana termodinamika lubang hitam?", "Apa solusi paradoks informasi?", "Jelaskan radiasi Unruh"]</follow_up>',
      ];
      gemini.mockStreamFinishReason = 'stop';

      // Panggil continueMessage
      await provider.continueMessage(initialMsg.id);

      // Verifikasi kondisi akhir setelah lanjutan selesai
      final continuedMsg = provider.messages.last;
      expect(continuedMsg.status, equals(MessageStatus.done));
      expect(continuedMsg.isTruncated, isFalse);
      expect(continuedMsg.finishReason, equals('stop'));

      // 1. Teks jawaban gabungan utuh dan bersih dari tag internal
      expect(
        continuedMsg.content,
        equals(
          'Bagian pertama pembahasan astrofisika kuantum. Kami mendiskusikan singularitas dan radiasi Hawking pada horizon peristiwa.',
        ),
      );
      expect(continuedMsg.content.contains('<follow_up'), isFalse);

      // 2. Tiga saran lanjutan berhasil diekstrak satu kali
      expect(continuedMsg.followUpSuggestions.length, equals(3));
      expect(continuedMsg.followUpSuggestions[0],
          equals('Bagaimana termodinamika lubang hitam?'));
      expect(continuedMsg.followUpSuggestions[1],
          equals('Apa solusi paradoks informasi?'));
      expect(continuedMsg.followUpSuggestions[2],
          equals('Jelaskan radiasi Unruh'));

      // 3. Request follow-up terpisah tetap 0 (tidak pernah dipanggil)
      expect(gemini.followUpCallCount, equals(0));
    });
  });
}
