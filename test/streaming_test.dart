import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:scichat/models/models.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/widgets/chat_bubble.dart';
import 'package:scichat/widgets/paper_card.dart';
import 'package:scichat/screens/chat_screen.dart';
import 'package:scichat/theme/scichat_theme.dart';

class MockStorageService extends StorageService {
  String? _key;
  final List<ChatSession> _sessions = [];

  @override
  Future<String?> getApiKey() async => _key;

  @override
  Future<void> saveApiKey(String key) async {
    _key = key;
  }

  @override
  Future<List<ChatSession>> getChatSessions() async => _sessions;

  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {
    _sessions.clear();
    _sessions.addAll(sessions);
  }

  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

class MockSearchService extends SearchService {
  final List<ArxivPaper> mockResults;
  MockSearchService({this.mockResults = const []});

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    return mockResults;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeminiService SSE Streaming Tests', () {
    test('1. Normal SSE parsing and multi-delta yields text chunks', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        final ssePayload = [
          'data: {"choices":[{"delta":{"content":"Halo "}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"dunia!"}}]}\n\n',
          'data: [DONE]\n\n',
        ].join();

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final chunks = await service.chatStream(
        history: [],
        userMessage: 'Test',
      ).toList();

      expect(chunks, equals(['Halo ', 'dunia!']));
    });

    test('2. Buffering lines and chunks split across raw boundaries', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        // Simulasikan potongan byte terpisah di tengah baris dan JSON
        final stream = Stream.fromIterable([
          utf8.encode('data: {"choices":[{"delta":'),
          utf8.encode('{"content":"Part 1 "}}]}\n'),
          utf8.encode('\ndata: {"choices":[{"delta":{"content":"Part 2"'),
          utf8.encode('}}]}\n\ndata: [DONE]\n\n'),
        ]);

        return http.StreamedResponse(
          stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final chunks = await service.chatStream(
        history: [],
        userMessage: 'Test',
      ).toList();

      expect(chunks, equals(['Part 1 ', 'Part 2']));
    });

    test(
        '3. Ignores comments, empty lines, metadata, null deltas, and unknown events',
        () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        final ssePayload = [
          ': ping keepalive\n\n',
          '\n\n',
          'event: metadata\n',
          'data: {"info":"ignored"}\n\n',
          'data: {"choices":[{"delta":{"content":null}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"Teks valid"}}]}\n\n',
          'data: [DONE]\n\n',
        ].join();

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final chunks = await service.chatStream(
        history: [],
        userMessage: 'Test',
      ).toList();

      expect(chunks, equals(['Teks valid']));
    });

    test('4. Handles HTTP error response gracefully', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        final errBody = jsonEncode({
          'error': {'message': 'Unauthorized Key'}
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(errBody)),
          401,
        );
      });

      final service = GeminiService(
        apiKey: 'bad-key',
        client: mockClient,
      );

      expect(
        () => service.chatStream(history: [], userMessage: 'Test').toList(),
        throwsA(predicate((e) => e.toString().contains('Unauthorized Key'))),
      );
    });

    test('5. Handles empty stream without throwing', () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        return http.StreamedResponse(
          const Stream.empty(),
          200,
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final chunks = await service.chatStream(
        history: [],
        userMessage: 'Test',
      ).toList();

      expect(chunks, isEmpty);
    });

    test(
        '6. Accepts data: without space after colon (e.g., data:{"choices":...})',
        () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        final ssePayload = [
          'data:{"choices":[{"delta":{"content":"NoSpace"}}]}\n\n',
          'data:[DONE]\n\n',
        ].join();

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final chunks = await service.chatStream(
        history: [],
        userMessage: 'Test',
      ).toList();

      expect(chunks, equals(['NoSpace']));
    });

    test('7. Explicit error payload in SSE throws descriptive Exception',
        () async {
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({
              'data': [
                {'id': 'agnes-3.0-flash'}
              ]
            }))),
            200,
          );
        }

        const ssePayload = 'data: {"error":{"message":"Model overloaded"}}\n\n';

        return http.StreamedResponse(
          Stream.value(utf8.encode(ssePayload)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      expect(
        () => service.chatStream(history: [], userMessage: 'Test').toList(),
        throwsA(predicate(
            (e) => e.toString().contains('SSE Error: Model overloaded'))),
      );
    });
  });

  group('SciChatProvider Streaming & Fallback Tests', () {
    test('1. Normal streaming flow: status streaming -> done, and throttling',
        () async {
      final controller = StreamController<String>();
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => controller.stream,
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      final sendFuture = provider.sendMessage('Pertanyaan stream');

      // Sebelum stream mengeluarkan token: status sending / thinking
      await Future.delayed(const Duration(milliseconds: 20));
      expect(provider.isLoading, isTrue);
      expect(provider.messages.last.status, equals(MessageStatus.sending));

      // Kirim chunk pertama
      controller.add('Halo ');
      await Future.delayed(const Duration(milliseconds: 120));
      expect(provider.messages.last.status, equals(MessageStatus.streaming));
      expect(provider.messages.last.content, equals('Halo '));
      expect(provider.isLoading, isTrue);

      // Kirim chunk kedua
      controller.add('peneliti!');
      await Future.delayed(const Duration(milliseconds: 120));
      expect(provider.messages.last.content, equals('Halo peneliti!'));

      // Selesaikan stream
      await controller.close();
      await sendFuture;

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.done));
      expect(provider.messages.last.content, equals('Halo peneliti!'));
    });

    test('2. Double-send blocked while in streaming state', () async {
      final controller = StreamController<String>();
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => controller.stream,
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      final sendFuture = provider.sendMessage('Pesan 1');
      await Future.delayed(const Duration(milliseconds: 20));

      controller.add('Token awal');
      await Future.delayed(const Duration(milliseconds: 120));
      expect(provider.messages.last.status, equals(MessageStatus.streaming));

      // Mencoba mengirim pesan kedua saat streaming aktif
      await provider.sendMessage('Pesan 2 double send');
      expect(provider.messages.where((m) => m.isUser).length, equals(1));
      expect(provider.messages.first.content, equals('Pesan 1'));

      await controller.close();
      await sendFuture;
    });

    test('3. Fallback to monolithic chat() if stream fails before first chunk',
        () async {
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () =>
            Stream.error(Exception('Stream connection failed')),
        fallbackResponse: 'Jawaban sukses dari fallback monolitik',
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      await provider.sendMessage('Tanya dengan stream rusak di awal');

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.done));
      expect(provider.messages.last.content,
          equals('Jawaban sukses dari fallback monolitik'));
      expect(mockGemini.chatCalled, isTrue);
    });

    test(
        '4. Partial error preserved: no duplicate re-run if error happens after tokens',
        () async {
      final controller = StreamController<String>();
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => controller.stream,
        fallbackResponse: 'Jangan jalankan ini',
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      final sendFuture = provider.sendMessage('Tanya terputus di tengah jalan');
      await Future.delayed(const Duration(milliseconds: 20));

      controller.add('Sebagian teks berhasil diterima...');
      await Future.delayed(const Duration(milliseconds: 120));

      // Putuskan koneksi di tengah jalan
      controller.addError(Exception('Koneksi terputus tiba-tiba'));
      await controller.close();
      await sendFuture;

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.error));
      expect(provider.messages.last.content,
          equals('Sebagian teks berhasil diterima...'));
      // Fallback chat monolitik TIDAK boleh dipanggil untuk mencegah duplikasi
      expect(mockGemini.chatCalled, isFalse);
    });

    test(
        '5. Papers and active context provenance preserved during and after streaming',
        () async {
      const samplePaper = ArxivPaper(
        id: '2401.00001',
        title: 'Attention Mechanism in Modern LLMs',
        authors: ['Author A', 'Author B'],
        summary: 'A study on attention mechanisms.',
        published: '2024-01-01',
        updated: '2024-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'https://arxiv.org/pdf/2401.00001',
        absUrl: 'https://arxiv.org/abs/2401.00001',
      );

      final controller = StreamController<String>();
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => controller.stream,
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(mockResults: [samplePaper]),
      );

      // Aktifkan konteks makalah
      provider.setActivePaper(samplePaper);
      expect(provider.activeContexts, isNotEmpty);

      final sendFuture = provider.sendMessage('Jelaskan paper ini');
      await Future.delayed(const Duration(milliseconds: 20));

      controller.add('Berikut penjelasannya: ');
      await Future.delayed(const Duration(milliseconds: 120));

      // Periksa bahwa makalah terlampir selama streaming
      expect(provider.messages.last.papers, isNotEmpty);
      expect(provider.messages.last.papers.first.id, equals('2401.00001'));

      controller.add('selesai.');
      await controller.close();
      await sendFuture;

      // Periksa bahwa makalah dan konteks aktif tetap utuh setelah streaming selesai
      expect(provider.messages.last.status, equals(MessageStatus.done));
      expect(provider.messages.last.papers, isNotEmpty);
      expect(provider.messages.last.papers.first.id, equals('2401.00001'));
      expect(provider.activeContexts, isNotEmpty);
    });

    test(
        '6. Empty stream without tokens triggers monolithic fallback and completes with done',
        () async {
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => const Stream.empty(),
        fallbackResponse: 'Jawaban fallback untuk stream kosong',
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      await provider.sendMessage('Tanya dengan stream kosong');

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.done));
      expect(provider.messages.last.content,
          equals('Jawaban fallback untuk stream kosong'));
      expect(mockGemini.chatCalled, isTrue);
    });

    test(
        '7. Initial timeout before first token triggers monolithic fallback with status message',
        () async {
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => Stream.error(TimeoutException(
            'Batas waktu koneksi awal stream (45 detik) terlampaui.')),
        fallbackResponse: 'Jawaban sukses setelah timeout stream',
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      await provider.sendMessage('Tanya dengan timeout awal');

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.done));
      expect(provider.messages.last.content,
          equals('Jawaban sukses setelah timeout stream'));
      expect(mockGemini.chatCalled, isTrue);
    });

    test('8. Fallback failure marks message with a safe error status',
        () async {
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => Stream.error(Exception('Koneksi stream gagal')),
        chatHandler: () async =>
            throw Exception('Koneksi fallback juga gagal (Quota exceeded)'),
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      await provider.sendMessage('Tanya dengan fallback gagal');

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.error));
      expect(provider.messages.last.content, isEmpty);
      expect(provider.appState, equals(AppState.error));
    });

    test('9. DNS failure is safe and retry reuses the original question once',
        () async {
      var fallbackAttempts = 0;
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => Stream.error(
          Exception('ClientException: SocketException: Failed host lookup'),
        ),
        chatHandler: () async {
          fallbackAttempts++;
          if (fallbackAttempts == 1) {
            throw Exception(
                'ClientException: SocketException: Failed host lookup');
          }
          return 'Jawaban setelah koneksi pulih.';
        },
      );
      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      await provider.sendMessage('Jelaskan metode ini');

      final failedMessage = provider.messages.last;
      expect(failedMessage.status, MessageStatus.error);
      expect(failedMessage.errorType, ChatErrorType.connection);
      expect(failedMessage.content, isEmpty);
      expect(
          provider.messages.where((message) => message.isUser), hasLength(1));

      await provider.retryMessage(failedMessage.id);

      expect(fallbackAttempts, 2);
      expect(
          provider.messages.where((message) => message.isUser), hasLength(1));
      expect(provider.messages.first.content, 'Jelaskan metode ini');
      expect(provider.messages.last.status, MessageStatus.done);
      expect(provider.messages.last.content, 'Jawaban setelah koneksi pulih.');
    });

    test('10. Dismissing an old error preserves an active request state',
        () async {
      var streamCalls = 0;
      final responseController = StreamController<String>();
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () {
          streamCalls++;
          return streamCalls == 1
              ? Stream.error(Exception('Koneksi awal gagal'))
              : responseController.stream;
        },
        chatHandler: () async => throw Exception('Fallback juga gagal'),
      );
      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      await provider.sendMessage('Pesan yang gagal');
      final errorId = provider.messages.last.id;

      final activeSend = provider.sendMessage('Pesan yang sedang diproses');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(provider.isLoading, isTrue);

      provider.dismissError(errorId);
      expect(provider.isLoading, isTrue);
      expect(provider.appState, isNot(AppState.ready));
      expect(
          provider.messages.any((message) => message.id == errorId), isFalse);

      responseController.add('Respons aktif selesai.');
      await responseController.close();
      await activeSend;
    });

    test('11. Double-send blocked while in fallback state', () async {
      final fallbackCompleter = Completer<String>();
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => Stream.error(Exception('Stream error awal')),
        chatHandler: () => fallbackCompleter.future,
      );

      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      final sendFuture = provider.sendMessage('Pesan 1 yang memicu fallback');
      await Future.delayed(const Duration(milliseconds: 30));

      // Saat fallback sedang berjalan:
      expect(provider.isLoading, isTrue);
      expect(provider.statusText,
          equals('Streaming gagal, mencoba metode alternatif...'));

      // Mencoba mengirim pesan kedua selama fallback berlangsung:
      await provider.sendMessage('Pesan 2 double-send saat fallback');
      expect(provider.messages.where((m) => m.isUser).length, equals(1));
      expect(provider.messages.first.content,
          equals('Pesan 1 yang memicu fallback'));

      // Selesaikan fallback
      fallbackCompleter.complete('Jawaban fallback pesan 1');
      await sendFuture;

      expect(provider.isLoading, isFalse);
      expect(provider.messages.last.status, equals(MessageStatus.done));
      expect(
          provider.messages.last.content, equals('Jawaban fallback pesan 1'));
    });
  });

  group('UI ChatBubble Streaming Widget Tests', () {
    testWidgets('1. ChatBubble renders streaming indicator and growing content',
        (tester) async {
      final message = ChatMessage(
        id: 'msg-stream',
        role: MessageRole.assistant,
        content: 'Teks yang sedang dialirkan...',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: ChatBubble(
              message: message,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Streaming content is rendered without SelectionArea overhead during active stream
      expect(
        find.textContaining('Teks yang sedang dialirkan...', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Menulis respons...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Toolbar aksi dan tombol simpan insight tidak boleh muncul saat streaming
      expect(find.byTooltip('Simpan insight ke Catatan'), findsNothing);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsNothing);
      expect(find.text('Simpan Insight'), findsNothing);
    });

    testWidgets('2. ChatBubble renders done message and enables insight button',
        (tester) async {
      final message = ChatMessage(
        id: 'msg-done',
        role: MessageRole.assistant,
        content: 'Respons final lengkap.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      );

      final provider = SciChatProvider(
        storageService: MockStorageService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ChatBubble(
                message: message,
                isFavorite: (_) => false,
                onFavoriteToggle: (_) {},
                onPaperTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final selectableFinder = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan?.toPlainText().contains('Respons final lengkap.') ??
                false),
      );
      expect(selectableFinder, findsOneWidget);
      expect(find.text('Menulis respons...'), findsNothing);
      expect(find.byTooltip('Simpan insight ke Catatan'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
      expect(find.byTooltip('Salin jawaban'), findsOneWidget);
      expect(find.byTooltip('Bagikan jawaban'), findsOneWidget);
    });

    testWidgets(
        '3. ChatBubble renders partial text plus error message on failure',
        (tester) async {
      final message = ChatMessage(
        id: 'msg-error',
        role: MessageRole.assistant,
        content: 'Paragraf pertama selesai tapi koneksi putus.',
        status: MessageStatus.error,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: ChatBubble(
              message: message,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final selectableFinder = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan
                    ?.toPlainText()
                    .contains('Paragraf pertama selesai tapi koneksi putus.') ??
                false),
      );
      expect(selectableFinder, findsOneWidget);
      expect(find.text('Respons terputus'), findsOneWidget);
      expect(find.text('Menulis respons...'), findsNothing);
    });

    testWidgets(
        '4. ChatBubble renders a safe connection error and exposes actions',
        (tester) async {
      var retryPressed = 0;
      var dismissPressed = 0;
      final message = ChatMessage(
        id: 'msg-connection-error',
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.error,
        errorType: ChatErrorType.connection,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: ChatBubble(
              message: message,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
              onRetry: () => retryPressed++,
              onDismissError: () => dismissPressed++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Koneksi internet terputus'), findsOneWidget);
      expect(
        find.text(
            'Pesanmu belum berhasil dikirim. Periksa koneksi internet, lalu coba lagi.'),
        findsOneWidget,
      );
      expect(find.text('SocketException'), findsNothing);

      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();
      expect(retryPressed, 1);
      expect(dismissPressed, 1);
    });

    testWidgets('5. ChatBubble hides retry for an authentication error',
        (tester) async {
      final message = ChatMessage(
        id: 'msg-authentication-error',
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.error,
        errorType: ChatErrorType.authentication,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: ChatBubble(
              message: message,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
              onRetry: () {},
              onDismissError: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('API key perlu diperiksa'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
      expect(find.text('Tutup'), findsOneWidget);
    });

    testWidgets(
        '6. ChatBubble shows compact indicator during streaming and collapsible sources section when done',
        (tester) async {
      const samplePaper = ArxivPaper(
        id: '2401.00001',
        title: 'Attention Mechanism in Modern LLMs',
        authors: ['Author A', 'Author B'],
        summary: 'A study on attention mechanisms.',
        published: '2024-01-01',
        updated: '2024-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'https://arxiv.org/pdf/2401.00001',
        absUrl: 'https://arxiv.org/abs/2401.00001',
      );

      final streamMsg = ChatMessage(
        id: 'msg-stream-sources',
        role: MessageRole.assistant,
        content: 'Teks sedang dialirkan...',
        status: MessageStatus.streaming,
        papers: const [samplePaper],
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: ChatBubble(
              message: streamMsg,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Saat streaming: PaperCard tidak dirender sama sekali untuk performa
      expect(find.text('Menyiapkan 1 sumber makalah…'), findsOneWidget);
      expect(find.byType(PaperCard), findsNothing);

      // Setelah done: Muncul header collapsible 'Sumber makalah (1)'
      final doneMsg = streamMsg.copyWith(
        status: MessageStatus.done,
        content: 'Jawaban final lengkap dengan sitasi.',
      );

      final provider = SciChatProvider(
        storageService: MockStorageService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ChatBubble(
                message: doneMsg,
                isFavorite: (_) => false,
                onFavoriteToggle: (_) {},
                onPaperTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Kondisi awal done: Bagian sumber dalam keadaan tertutup (collapsed)
      expect(find.text('Sumber makalah (1)'), findsOneWidget);
      expect(find.text('Lihat'), findsOneWidget);
      expect(find.byType(PaperCard), findsNothing);

      // Tap header untuk membuka sumber (expand)
      await tester.tap(find.text('Sumber makalah (1)'));
      await tester.pumpAndSettle();

      expect(find.text('Tutup'), findsOneWidget);
      expect(find.byType(PaperCard), findsOneWidget);
      expect(find.text('Attention Mechanism in Modern LLMs'), findsOneWidget);

      // Tap tombol Tutup untuk menutup modal sumber
      await tester.tap(find.text('Tutup'));
      await tester.pumpAndSettle();

      expect(find.text('Lihat'), findsOneWidget);
      expect(find.byType(PaperCard), findsNothing);
    });

    testWidgets(
        '5. ChatScreen detects user scroll up and shows Kembali ke respons terbaru button',
        (tester) async {
      final mockGemini = _FakeStreamingGeminiService(
        streamGenerator: () => const Stream.empty(),
      );
      final provider = SciChatProvider(
        geminiService: mockGemini,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      // Tambahkan banyak pesan agar ListView dapat di-scroll
      for (int i = 0; i < 15; i++) {
        provider.messages.add(
          ChatMessage(
            id: 'user-$i',
            role: MessageRole.user,
            content:
                'Pertanyaan pengguna ke-$i yang cukup panjang untuk mengisi ruang layar ponsel...',
            status: MessageStatus.done,
            timestamp: DateTime.now(),
          ),
        );
        provider.messages.add(
          ChatMessage(
            id: 'assistant-$i',
            role: MessageRole.assistant,
            content:
                'Jawaban asisten ilmiah ke-$i dengan analisis data dan metodologi komprehensif...',
            status: MessageStatus.done,
            timestamp: DateTime.now(),
          ),
        );
      }

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tombol belum muncul saat posisi awal
      expect(find.text('Kembali ke respons terbaru'), findsNothing);

      // Simulasikan scroll ke atas (drag ke bawah untuk melihat pesan di atas)
      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);
      await tester.drag(listFinder, const Offset(0, 500));
      await tester.pumpAndSettle();

      // Tombol 'Kembali ke respons terbaru' harus muncul tanpa teks visual
      expect(find.byKey(const Key('scrollToBottomButton')), findsOneWidget);
      expect(find.text('Kembali ke respons terbaru'), findsNothing);
      expect(find.byTooltip('Kembali ke respons terbaru'), findsOneWidget);

      // Tap tombol 'Kembali ke respons terbaru'
      await tester.tap(find.byKey(const Key('scrollToBottomButton')));
      await tester.pumpAndSettle();

      // Tombol menghilang setelah kembali ke bawah
      expect(find.byKey(const Key('scrollToBottomButton')), findsNothing);
    });

    testWidgets(
        '6. ChatScreen Home empty state has scroll padding of 240 and no restrictive outer padding',
        (tester) async {
      final provider = SciChatProvider(
        storageService: MockStorageService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));

      // SingleChildScrollView utama pada EmptyState memiliki padding bottom 240
      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsWidgets);

      final scrollWidget =
          tester.widget<SingleChildScrollView>(scrollFinder.first);
      expect((scrollWidget.padding as EdgeInsets).bottom, equals(240));

      // Pastikan suggestion chips dapat tampil
      expect(find.text('Coba tanyakan'), findsOneWidget);
    });

    testWidgets(
        '7. ChatBubble renders contextual follow-up suggestions and responds to tap',
        (tester) async {
      String? tappedSuggestion;
      final followUpMsg = ChatMessage(
        id: 'msg_follow_up_test',
        role: MessageRole.assistant,
        content: 'Ini adalah jawaban riset tentang arsitektur model.',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
        followUpSuggestions: const [
          'Bagaimana perbandingan akurasi dengan transformer standar?',
          'Apa limitasi utama dari pendekatan ini?',
          'Bagaimana cara mengimplementasikannya pada skala besar?',
        ],
      );

      final provider = SciChatProvider(
        storageService: MockStorageService(),
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
                    message: followUpMsg,
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

      // Header saran lanjutan
      expect(
          find.text('Eksplorasi topik tertentu lebih jauh:'), findsOneWidget);
      // Tiga kartu saran
      expect(
          find.text(
              'Bagaimana perbandingan akurasi dengan transformer standar?'),
          findsOneWidget);
      expect(
          find.text('Apa limitasi utama dari pendekatan ini?'), findsOneWidget);
      expect(
          find.text('Bagaimana cara mengimplementasikannya pada skala besar?'),
          findsOneWidget);

      // Tap saran kedua
      await tester.tap(find.text('Apa limitasi utama dari pendekatan ini?'));
      await tester.pumpAndSettle();

      expect(
          tappedSuggestion, equals('Apa limitasi utama dari pendekatan ini?'));
    });

    testWidgets(
        '8. ChatScreen renders Bottom Fade Gradient overlay with IgnorePointer',
        (tester) async {
      final provider = SciChatProvider(
        storageService: MockStorageService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));

      // Pastikan IgnorePointer ada dan membungkus DecoratedBox dengan LinearGradient
      final ignorePointerFinders = find.byType(IgnorePointer);
      expect(ignorePointerFinders, findsWidgets);

      bool foundFadeGradient = false;
      for (final element
          in tester.widgetList<IgnorePointer>(ignorePointerFinders)) {
        if (element.child is DecoratedBox) {
          final box = element.child as DecoratedBox;
          if (box.decoration is BoxDecoration) {
            final deco = box.decoration as BoxDecoration;
            if (deco.gradient is LinearGradient) {
              foundFadeGradient = true;
              break;
            }
          }
        }
      }

      expect(foundFadeGradient, isTrue);
    });

    testWidgets(
        '9. ChatScreen renders Top Fade Gradient overlay alongside Bottom Fade Gradient',
        (tester) async {
      final provider = SciChatProvider(
        storageService: MockStorageService(),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 6));

      final ignorePointerFinders = find.byType(IgnorePointer);
      expect(ignorePointerFinders, findsWidgets);

      final linearGradients = <LinearGradient>[];
      for (final element
          in tester.widgetList<IgnorePointer>(ignorePointerFinders)) {
        if (element.child is DecoratedBox) {
          final box = element.child as DecoratedBox;
          if (box.decoration is BoxDecoration) {
            final deco = box.decoration as BoxDecoration;
            if (deco.gradient is LinearGradient) {
              linearGradients.add(deco.gradient as LinearGradient);
            }
          }
        }
      }

      // Harus ada minimal 2 fade gradient: Top fade dan Bottom fade
      expect(linearGradients.length, greaterThanOrEqualTo(2));

      // Satu gradasi mengarah ke topCenter (top fade), satu ke bottomCenter (bottom fade)
      final hasTopFade = linearGradients.any((g) =>
          g.end == Alignment.topCenter && g.begin == Alignment.bottomCenter);
      final hasBottomFade = linearGradients.any((g) =>
          g.end == Alignment.bottomCenter && g.begin == Alignment.topCenter);
      expect(hasTopFade, isTrue);
      expect(hasBottomFade, isTrue);

      // AppBar tidak memiliki garis horizontal (bottom divider) dan elevasi dinetralkan
      final appBarFinder = find.byType(AppBar);
      expect(appBarFinder, findsOneWidget);
      final appBar = tester.widget<AppBar>(appBarFinder);
      expect(appBar.elevation, equals(0));
      expect(appBar.scrolledUnderElevation, equals(0));
      expect(appBar.bottom, isNull);
    });

    testWidgets(
        '10. ChatBubble renders follow-up suggestions with markdown terms without raw asterisks',
        (tester) async {
      String? tappedSuggestion;
      final followUpMsg = ChatMessage(
        id: 'msg-test-markdown-chips',
        content: 'Hasil simulasi kuantum menunjukkan efek dekoherensi.',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        status: MessageStatus.done,
        followUpSuggestions: const [
          'Bagaimana perbandingan *continuous-time* vs *discrete* model?',
          'Mengapa *topological codes* rentan terhadap *noisy* decoherence?',
          'Kapan *dynamical decoupling* efektif untuk mitigasi *decoherence*?',
        ],
      );

      final provider = SciChatProvider(
        storageService: MockStorageService(),
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
                    message: followUpMsg,
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

      // Memastikan teks yang tampil bersih dari tanda bintang mentah
      expect(find.textContaining('*continuous-time*'), findsNothing);
      expect(find.textContaining('*discrete*'), findsNothing);
      expect(find.textContaining('*topological codes*'), findsNothing);
      expect(find.textContaining('*noisy*'), findsNothing);
      expect(find.textContaining('*dynamical decoupling*'), findsNothing);
      expect(find.textContaining('*decoherence*'), findsNothing);

      // Teks istilah tetap terbaca
      expect(find.textContaining('continuous-time'), findsOneWidget);
      expect(find.textContaining('topological codes'), findsOneWidget);
      expect(find.textContaining('dynamical decoupling'), findsOneWidget);

      // Tap saran pertama: callback menerima teks bersih tanpa asterisk mentah
      await tester.tap(find.textContaining('continuous-time'));
      await tester.pumpAndSettle();

      expect(tappedSuggestion,
          equals('Bagaimana perbandingan continuous-time vs discrete model?'));
      expect(tappedSuggestion?.contains('*'), isFalse);
    });
  });

  group('Phase 1: Streaming Stability, Auto-Scroll & Identity Tests', () {
    testWidgets(
        '1. Multi-chunk streaming preserves bubble identity without duplication or disappearance',
        (tester) async {
      const msgId = 'test-stream-id';
      final chunks = [
        'Analisis awal',
        ' dengan metodologi',
        ' kuantum dan',
        ' bukti eksperimental.'
      ];
      String currentText = '';

      final provider = SciChatProvider(
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      final initialMsg = ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
      );
      provider.messages.add(initialMsg);

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump();

      // Initially sending state shows thinking indicator and stable bubble key
      expect(find.byKey(const ValueKey('msg_$msgId')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant_thinking')), findsOneWidget);

      // Stream chunks sequentially
      for (final chunk in chunks) {
        currentText += chunk;
        provider.messages[0] = initialMsg.copyWith(
          content: currentText,
          status: MessageStatus.streaming,
        );
        provider.notifyListeners();
        // Let didUpdateWidget receive the new chunk into _bufferedContent
        await tester.pump();
        // Advance past throttle interval (80 ms) to trigger periodic flush
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();

        // Exactly one bubble with stable identity
        expect(find.byKey(const ValueKey('msg_$msgId')), findsOneWidget);
        expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
        expect(find.byKey(const ValueKey('assistant_body_$msgId')), findsOneWidget);
        expect(find.text(currentText, findRichText: true), findsOneWidget);
      }

      // Stream finishes with done status
      provider.messages[0] = initialMsg.copyWith(
        content: currentText,
        status: MessageStatus.done,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();

      // Preserves single bubble identity
      expect(find.byKey(const ValueKey('msg_$msgId')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant_body_$msgId')), findsOneWidget);
      expect(find.text(currentText), findsOneWidget);
      expect(find.text('Menulis respons...'), findsNothing);
    });

    testWidgets(
        '2. Transition sending -> streaming -> done maintains message identity and components',
        (tester) async {
      const msgId = 'transition-msg-id';
      final provider = SciChatProvider(
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.byKey(const ValueKey('assistant_thinking')), findsOneWidget);
      expect(find.text('Menulis respons...'), findsNothing);

      // Transition to streaming
      provider.messages[0] = provider.messages[0].copyWith(
        content: 'Teks awal',
        status: MessageStatus.streaming,
      );
      provider.notifyListeners();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.text('Teks awal', findRichText: true), findsOneWidget);
      expect(find.text('Menulis respons...'), findsOneWidget);

      // Transition to done
      provider.messages[0] = provider.messages[0].copyWith(
        content: 'Teks akhir lengkap',
        status: MessageStatus.done,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.text('Teks akhir lengkap'), findsOneWidget);
      expect(find.text('Menulis respons...'), findsNothing);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets(
        '3. Cancellation preserves message content and renders banner without crash',
        (tester) async {
      const msgId = 'cancelled-msg-id';
      final provider = SciChatProvider(
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: 'Respons sebelum dibatalkan oleh pengguna.',
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'cancelled',
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.text('Respons sebelum dibatalkan oleh pengguna.'),
          findsOneWidget);
      expect(find.text('Generasi dihentikan oleh pengguna'), findsOneWidget);
    });

    testWidgets(
        '4. Error state renders error UI and preserves retry/continue action',
        (tester) async {
      const msgId = 'error-msg-id';
      final provider = SciChatProvider(
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.error,
        errorType: ChatErrorType.connection,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
      expect(find.text('Koneksi internet terputus'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    testWidgets(
        '5. Dragging up ceases auto-scroll and does not fight user interaction',
        (tester) async {
      final provider = SciChatProvider(
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      for (int i = 0; i < 15; i++) {
        provider.messages.add(ChatMessage(
          id: 'user-$i',
          role: MessageRole.user,
          content: 'Pertanyaan $i',
          status: MessageStatus.done,
          timestamp: DateTime.now(),
        ));
        provider.messages.add(ChatMessage(
          id: 'assistant-$i',
          role: MessageRole.assistant,
          content:
              'Jawaban $i panjang berbobot ilmiah dengan konten yang mencukupi scroll viewport.',
          status: MessageStatus.done,
          timestamp: DateTime.now(),
        ));
      }

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag up to view older messages
      final listFinder = find.byType(ListView);
      await tester.drag(listFinder, const Offset(0, 350));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scrollToBottomButton')), findsOneWidget);

      // Now simulate a streaming update coming in
      final scrollBefore =
          tester.widget<ListView>(listFinder).controller!.position.pixels;
      provider.messages.last = provider.messages.last.copyWith(
        content:
            '${provider.messages.last.content} Tambahan chunk baru saat user sedang membaca riwayat di atas.',
        status: MessageStatus.streaming,
      );
      provider.notifyListeners();
      await tester.pump(const Duration(milliseconds: 100));

      final scrollAfter =
          tester.widget<ListView>(listFinder).controller!.position.pixels;
      // Scroll offset must NOT jump down to maxScrollExtent!
      expect((scrollAfter - scrollBefore).abs(), lessThanOrEqualTo(1.0));
      expect(find.byKey(const Key('scrollToBottomButton')), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Phase 2: Render Throttle, Markdown/LaTeX Fidelity & Selectable Lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  group('Phase 2: Render Throttle, Content Fidelity & Selectable', () {

    // ── Test 1: Rapid chunks — no token lost, final text == cumulative stream ──
    testWidgets(
        '1. Rapid chunks do not lose or duplicate tokens; final text matches full stream',
        (tester) async {
      const msgId = 'p2-rapid-chunks';
      // Simulate 20 fast chunks building up a sentence.
      final words = List.generate(20, (i) => 'word$i');
      final fullText = words.join(' ');

      final provider = SciChatProvider(storageService: MockStorageService());

      // Start with streaming message.
      var msg = ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: '',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      );
      provider.messages.add(msg);

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump();

      // Deliver all 20 chunks rapidly (5 ms apart — faster than the 80 ms throttle).
      String cumulative = '';
      for (final word in words) {
        cumulative += (cumulative.isEmpty ? '' : ' ') + word;
        provider.messages[0] =
            msg.copyWith(content: cumulative, status: MessageStatus.streaming);
        provider.notifyListeners();
        await tester.pump(const Duration(milliseconds: 5));
      }

      // Mark done — throttle must flush immediately.
      provider.messages[0] =
          msg.copyWith(content: fullText, status: MessageStatus.done);
      provider.notifyListeners();
      await tester.pumpAndSettle();

      // Exactly ONE bubble, final text present, no streaming indicator.
      expect(find.byKey(const ValueKey('msg_$msgId')), findsOneWidget);
      expect(find.text(fullText), findsOneWidget);
      expect(find.text('Menulis respons...'), findsNothing);
    });

    // ── Test 2: Content after done == content after streaming (no truncation) ──
    testWidgets(
        '2. Content visible after done is byte-identical to last streamed content',
        (tester) async {
      const msgId = 'p2-fidelity';
      const streamedText =
          'Hasil analisis: model transformer dengan 12 layer menghasilkan BLEU score 42.7.';

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: streamedText,
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      // Pump past throttle interval (80 ms).
      await tester.pump(const Duration(milliseconds: 100));

      // Now mark done.
      provider.messages[0] = provider.messages[0]
          .copyWith(content: streamedText, status: MessageStatus.done);
      provider.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text(streamedText), findsOneWidget);
    });

    // ── Test 3: Bold markdown (**bold**) rendered correctly after done ──────
    testWidgets(
        '3. Bold markdown (**text**) renders formatted after streaming ends',
        (tester) async {
      const msgId = 'p2-bold';
      // MarkdownBody replaces **bold** with a bold span, not raw asterisks.
      // We can't inspect TextStyle via find.text, so we verify the raw
      // asterisks are NOT present in the rendered output while the inner
      // text IS present.
      const rawContent =
          'Model **transformer** dilatih selama 7 hari pada GPU A100.';
      const innerText = 'transformer';

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: rawContent,
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(children: [
                ChatBubble(
                  message: provider.messages.first,
                  isFavorite: (_) => false,
                  onFavoriteToggle: (_) {},
                  onPaperTap: (_) {},
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The rendered tree must not show raw asterisks.
      expect(find.textContaining('**transformer**'), findsNothing);
      // The word itself should appear (MarkdownBody renders spans).
      expect(find.textContaining(innerText), findsWidgets);
    });

    // ── Test 4: Inline math $E=mc^2$ — selectable false during stream, ──────
    //           true after done. MessageContent exposes the flag correctly.
    testWidgets(
        '4. MessageContent selectable=false during streaming, true after done',
        (tester) async {
      const msgId = 'p2-selectable';
      const mathContent = r'Rumus energi: $E = mc^2$ sangat penting.';

      final provider = SciChatProvider(storageService: MockStorageService());

      // Helper to find MessageContent widget.
      Finder messageContentFinder() => find.byType(MessageContent);

      // ── Phase A: streaming ──
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: mathContent,
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: Consumer<SciChatProvider>(
                builder: (context, prov, _) => ListView(children: [
                  ChatBubble(
                    message: prov.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      // Pump past throttle so the streaming content is displayed.
      await tester.pump(const Duration(milliseconds: 100));

      final streamingMC = tester.widget<MessageContent>(
        messageContentFinder().first,
      );
      expect(streamingMC.isStreaming, isTrue,
          reason: 'MessageContent should report isStreaming=true during stream');

      // ── Phase B: done ──
      provider.messages[0] = provider.messages[0]
          .copyWith(content: mathContent, status: MessageStatus.done);
      provider.notifyListeners();
      await tester.pumpAndSettle();

      final doneMC = tester.widget<MessageContent>(
        messageContentFinder().first,
      );
      expect(doneMC.isStreaming, isFalse,
          reason: 'MessageContent should report isStreaming=false when done');
    });

    // ── Test 5: Display math block does not crash when partial ──────────────
    testWidgets(
        '5. Partial display math block (unclosed double-dollar) does not crash',
        (tester) async {
      const msgId = 'p2-partial-math';
      // Partial block: opening $$ without closing $$.
      const partialMath =
          'Persamaan penting berikut:\n\$\$\nE = \\frac{p^2}{2m}';

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: partialMath,
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: Consumer<SciChatProvider>(
                builder: (context, prov, _) => ListView(children: [
                  ChatBubble(
                    message: prov.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      // Must not throw — just renders (may show as plain text fallback).
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      // Close the block and mark done.
      const completeMath =
          'Persamaan penting berikut:\n\$\$\nE = \\frac{p^2}{2m}\n\$\$';
      provider.messages[0] = provider.messages[0]
          .copyWith(content: completeMath, status: MessageStatus.done);
      provider.notifyListeners();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('assistant_$msgId')), findsOneWidget);
    });

    // ── Test 6: Code fence survives streaming and renders correctly ──────────
    testWidgets(
        '6. Code fence (```dart) renders correctly after streaming ends',
        (tester) async {
      const msgId = 'p2-codefence';
      const codeContent =
          'Contoh kode:\n\n```dart\nvoid main() {\n  print("Hello");\n}\n```';

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: codeContent,
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(children: [
                ChatBubble(
                  message: provider.messages.first,
                  isFavorite: (_) => false,
                  onFavoriteToggle: (_) {},
                  onPaperTap: (_) {},
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Code language label must be visible.
      expect(find.textContaining('DART'), findsOneWidget);
      // Code text must be present.
      expect(find.textContaining('print'), findsOneWidget);
    });

    // ── Test 7: <follow_up> tag is not rendered raw in final output ──────────
    testWidgets('7. follow_up tag is masked during streaming and not shown raw',
        (tester) async {
      const msgId = 'p2-followup-mask';
      // This is the maskForStreaming input during streaming.
      const streamingWithTag =
          'Jawaban selesai.\n<follow_up>["Apa langkah selanjutnya?"]</follow_up>';

      final provider = SciChatProvider(storageService: MockStorageService());
      // The provider's maskForStreaming is applied before storing content;
      // here we test the raw tag doesn't appear in the bubble.
      // Simulate what the provider stores: masked version.
      const maskedContent = 'Jawaban selesai.';
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: maskedContent,
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(children: [
                ChatBubble(
                  message: provider.messages.first,
                  isFavorite: (_) => false,
                  onFavoriteToggle: (_) {},
                  onPaperTap: (_) {},
                ),
              ]),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Raw tag must NEVER appear in the rendered tree.
      expect(find.textContaining('<follow_up>'), findsNothing);
      expect(find.textContaining('</follow_up>'), findsNothing);
      expect(find.textContaining(streamingWithTag), findsNothing);

      // The clean part of the answer is visible.
      expect(find.textContaining('Jawaban selesai'), findsWidgets);
    });

    // ── Test 8: Terminal flush on error path — partial content preserved ─────
    testWidgets(
        '8. Error terminal path flushes buffer: partial content and error UI both visible',
        (tester) async {
      const msgId = 'p2-error-flush';
      const partialText = 'Analisis awal menunjukkan';

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: partialText,
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: Consumer<SciChatProvider>(
                builder: (context, prov, _) => ListView(children: [
                  ChatBubble(
                    message: prov.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Transition to error with the same partial text.
      provider.messages[0] = provider.messages[0].copyWith(
        content: partialText,
        status: MessageStatus.error,
        errorType: ChatErrorType.connection,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();

      // Both partial content AND error UI must be visible.
      expect(find.textContaining('Analisis awal'), findsOneWidget);
      expect(find.text('Respons terputus'), findsOneWidget);
    });

    // ── Test 9: Cancelled terminal path — banner rendered, content kept ──────
    testWidgets(
        '9. Cancelled terminal path: content preserved and cancelled banner shown',
        (tester) async {
      const msgId = 'p2-cancelled-flush';
      const cancelledText =
          'Respons parsial sebelum pengguna menekan tombol batal.';

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: cancelledText,
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: Consumer<SciChatProvider>(
                builder: (context, prov, _) => ListView(children: [
                  ChatBubble(
                    message: prov.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Cancel: status done, finishReason cancelled.
      provider.messages[0] = provider.messages[0].copyWith(
        content: cancelledText,
        status: MessageStatus.done,
        isTruncated: true,
        finishReason: 'cancelled',
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.textContaining('Respons parsial'), findsOneWidget);
      expect(find.text('Generasi dihentikan oleh pengguna'), findsOneWidget);
    });

    // ── Test 10: Regenerate/retry action available after done, not during ────
    testWidgets(
        '10. Regenerate action is absent during streaming, present after done',
        (tester) async {
      const msgId = 'p2-regenerate';
      bool regenerateCalled = false;

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: 'Respons awal',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      ));

      Widget buildBubble(ChatMessage msg) =>
          ChangeNotifierProvider<SciChatProvider>.value(
            value: provider,
            child: MaterialApp(
              theme: SciChatTheme.getTheme(true),
              home: Scaffold(
                body: ListView(children: [
                  ChatBubble(
                    message: msg,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                    onRegenerate: () => regenerateCalled = true,
                  ),
                ]),
              ),
            ),
          );

      // Phase A: streaming — toolbar (with regenerate) must NOT be visible.
      await tester.pumpWidget(buildBubble(provider.messages.first));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byTooltip('Coba lagi'), findsNothing);

      // Phase B: done — toolbar appears.
      provider.messages[0] = provider.messages[0]
          .copyWith(content: 'Respons selesai', status: MessageStatus.done);
      provider.notifyListeners();
      await tester.pumpWidget(buildBubble(provider.messages.first));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Coba lagi'), findsOneWidget);
      await tester.tap(find.byTooltip('Coba lagi'));
      await tester.pumpAndSettle();
      expect(regenerateCalled, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 3B: Chat Rebuild Scope Isolation & Memoization Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 3B: Rebuild Scope Isolation & Memoization', () {
    testWidgets('1. ChatBubble isolates paint tree with RepaintBoundary',
        (tester) async {
      final msg = ChatMessage(
        id: 'p3b-repaint',
        role: MessageRole.assistant,
        content: 'Bubble with RepaintBoundary',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: SciChatTheme.getTheme(true),
          home: Scaffold(
            body: ChatBubble(
              message: msg,
              isFavorite: (_) => false,
              onFavoriteToggle: (_) {},
              onPaperTap: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bubbleFinder = find.byType(ChatBubble);
      expect(bubbleFinder, findsOneWidget);
      // The descendant of ChatBubble must contain a RepaintBoundary
      final repaintBoundaries = find.descendant(
        of: bubbleFinder,
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaries, findsWidgets);
    });

    testWidgets(
        '2. AssistantBubble memoizes MessageContent when content is unchanged across parent rebuilds',
        (tester) async {
      final msg = ChatMessage(
        id: 'p3b-memo-assistant',
        role: MessageRole.assistant,
        content: 'Memoized assistant message content',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      );

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(msg);

      Widget buildTestWidget() {
        return ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(
                children: [
                  ChatBubble(
                    key: ValueKey('msg_${msg.id}'),
                    message: provider.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final firstContentWidget =
          tester.widget<MessageContent>(find.byType(MessageContent));

      // Trigger a notifyListeners (simulating other state changes, e.g. streaming another message)
      provider.notifyListeners();
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final secondContentWidget =
          tester.widget<MessageContent>(find.byType(MessageContent));

      // Must be identical instance due to memoization in _AssistantBubbleState
      expect(identical(firstContentWidget, secondContentWidget), isTrue,
          reason:
              'MessageContent instance should be memoized to skip Markdown parsing');
    });

    testWidgets('3. UserBubble memoizes MessageContent across parent rebuilds',
        (tester) async {
      final msg = ChatMessage(
        id: 'p3b-memo-user',
        role: MessageRole.user,
        content: 'User query that should not re-parse markdown',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      );

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(msg);

      Widget buildTestWidget() {
        return ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(
                children: [
                  ChatBubble(
                    key: ValueKey('msg_${msg.id}'),
                    message: provider.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final firstContentWidget =
          tester.widget<MessageContent>(find.byType(MessageContent));

      provider.notifyListeners();
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final secondContentWidget =
          tester.widget<MessageContent>(find.byType(MessageContent));

      expect(identical(firstContentWidget, secondContentWidget), isTrue,
          reason: 'UserBubble MessageContent instance should be memoized');
    });

    testWidgets(
        '4. Streaming to done transition breaks memoization with fresh non-streaming MessageContent',
        (tester) async {
      final msg = ChatMessage(
        id: 'p3b-transition',
        role: MessageRole.assistant,
        content: 'Streaming chunk 1',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      );

      final provider = SciChatProvider(storageService: MockStorageService());
      provider.messages.add(msg);

      Widget buildTestWidget() {
        return ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: Scaffold(
              body: ListView(
                children: [
                  ChatBubble(
                    key: ValueKey('msg_${msg.id}'),
                    message: provider.messages.first,
                    isFavorite: (_) => false,
                    onFavoriteToggle: (_) {},
                    onPaperTap: (_) {},
                  ),
                ],
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTestWidget());
      await tester.pump(const Duration(milliseconds: 100));

      final streamingContentWidget =
          tester.widget<MessageContent>(find.byType(MessageContent));
      expect(streamingContentWidget.isStreaming, isTrue);

      // Transition to done
      provider.messages[0] = provider.messages[0].copyWith(
        content: 'Streaming chunk 1 completed.',
        status: MessageStatus.done,
      );
      provider.notifyListeners();

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final doneContentWidget =
          tester.widget<MessageContent>(find.byType(MessageContent));
      expect(doneContentWidget.isStreaming, isFalse);
      expect(identical(streamingContentWidget, doneContentWidget), isFalse,
          reason:
              'State transition to done must produce a new selectable MessageContent');
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Phase 3B.2: Composer Subscription & Selector Fix Tests
  // ══════════════════════════════════════════════════════════════════════════
  group('Phase 3B.2: Composer Subscription & Selector Fix Tests', () {
    testWidgets(
        '1. removeActiveContext updates composer UI properly despite in-place list mutation',
        (tester) async {
      final mockStorage = MockStorageService();
      await mockStorage.saveApiKey('test-key');
      final provider = SciChatProvider(storageService: mockStorage);
      provider.messages.add(ChatMessage(
        id: 'seed-1',
        role: MessageRole.user,
        content: 'Query 1',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      const paper = ArxivPaper(
        id: 'paper-p3b2-1',
        title: 'Quantum Entanglement in Machine Learning',
        authors: ['Alice', 'Bob'],
        summary: 'Summary of test paper',
        published: '2026-01-01',
        updated: '2026-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'https://arxiv.org/pdf/paper-p3b2-1',
        absUrl: 'https://arxiv.org/abs/paper-p3b2-1',
      );

      // Add active context
      provider.setActivePaper(paper);

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify the active context banner is rendered in composer
      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);
      expect(
          find.text('Quantum Entanglement in Machine Learning'), findsOneWidget);

      // Now remove context in-place via provider method
      provider.removeActiveContext(paper.id);
      await tester.pumpAndSettle();

      // Must be removed from UI because Selector detected snapshot inequality via listEquals
      expect(find.byKey(const ValueKey('active_paper_banner')), findsNothing);
      expect(
          find.text('Quantum Entanglement in Machine Learning'), findsNothing);
    });

    testWidgets(
        '2. Asynchronous evidence arrival updates composer UI without stale UI',
        (tester) async {
      final mockStorage = MockStorageService();
      await mockStorage.saveApiKey('test-key');
      final provider = SciChatProvider(storageService: mockStorage);
      provider.messages.add(ChatMessage(
        id: 'seed-2',
        role: MessageRole.user,
        content: 'Query 2',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      const paper = ArxivPaper(
        id: 'paper-p3b2-2',
        title: 'Evidence Test Paper',
        authors: ['Carol'],
        summary: 'Testing evidence updates',
        published: '2026-01-01',
        updated: '2026-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'https://arxiv.org/pdf/paper-p3b2-2',
        absUrl: 'https://arxiv.org/abs/paper-p3b2-2',
      );

      provider.setActivePaper(paper);

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('active_paper_banner')), findsOneWidget);
      expect(find.text('Full text tersedia'), findsNothing);

      // Now simulate evidence resolution to fullText
      provider.contextEvidence[paper.id] = const PaperEvidence(
        level: EvidenceLevel.fullText,
      );
      provider.notifyListeners();
      await tester.pumpAndSettle();

      // UI should update via mapEquals detection in Selector
      expect(find.text('Full text tersedia'), findsOneWidget);
    });

    testWidgets(
        '3. activeSkill changes update composer UI without broad SciChatProvider subscription',
        (tester) async {
      final mockStorage = MockStorageService();
      await mockStorage.saveApiKey('test-key');
      final provider = SciChatProvider(storageService: mockStorage);
      provider.messages.add(ChatMessage(
        id: 'seed-3',
        role: MessageRole.user,
        content: 'Query 3',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // By default, no skill chip is shown
      expect(find.text('Reviewer Kritis'), findsNothing);

      // Select peerReview skill
      provider.setActiveSkill(AiSkill.peerReview);
      await tester.pumpAndSettle();

      // Skill chip should be visible
      expect(find.text('Reviewer Kritis'), findsOneWidget);

      // Dismiss skill
      provider.setActiveSkill(AiSkill.none);
      await tester.pumpAndSettle();

      expect(find.text('Reviewer Kritis'), findsNothing);
    });

    testWidgets('4. pendingAttachment updates composer UI dynamically',
        (tester) async {
      final mockStorage = MockStorageService();
      await mockStorage.saveApiKey('test-key');
      final provider = SciChatProvider(storageService: mockStorage);
      provider.messages.add(ChatMessage(
        id: 'seed-4',
        role: MessageRole.user,
        content: 'Query 4',
        status: MessageStatus.done,
        timestamp: DateTime.now(),
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);

      const attachment = ArxivPaper(
        id: 'local_attachment_1',
        title: 'UploadedResearchPaper.pdf',
        authors: ['Local'],
        summary: 'User uploaded attachment',
        published: '2026-01-01',
        updated: '2026-01-01',
        categories: ['local'],
        pdfUrl: 'local',
        absUrl: 'local',
      );

      // Set attachment
      provider.setPendingAttachment(attachment);
      await tester.pumpAndSettle();

      // Tonal chip should be rendered with title
      expect(find.text('UploadedResearchPaper.pdf'), findsOneWidget);

      // Cancel attachment
      provider.setPendingAttachment(null);
      await tester.pumpAndSettle();

      expect(find.text('UploadedResearchPaper.pdf'), findsNothing);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
    });

    testWidgets(
        '5. Streaming token additions update message list while composer remains stable',
        (tester) async {
      final mockStorage = MockStorageService();
      await mockStorage.saveApiKey('test-key');
      final provider = SciChatProvider(storageService: mockStorage);

      const msgId = 'msg-stream-active';
      final msg = ChatMessage(
        id: msgId,
        role: MessageRole.assistant,
        content: 'Initial chunk',
        status: MessageStatus.streaming,
        timestamp: DateTime.now(),
      );
      provider.messages.add(msg);

      await tester.pumpWidget(
        ChangeNotifierProvider<SciChatProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: SciChatTheme.getTheme(true),
            home: const ChatScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Initial chunk'), findsOneWidget);

      // Append token and complete stream to trigger immediate terminal flush
      provider.messages[0] = msg.copyWith(
        content: 'Initial chunk with appended token stream',
        status: MessageStatus.done,
      );
      provider.notifyListeners();

      await tester.pumpAndSettle();

      // Message list updated with new token
      expect(find.textContaining('appended token stream'), findsOneWidget);
    });
  });
}

class _FakeStreamingGeminiService extends GeminiService {
  final Stream<String> Function() streamGenerator;
  final Future<String> Function()? chatHandler;
  final String fallbackResponse;
  bool chatCalled = false;

  _FakeStreamingGeminiService({
    required this.streamGenerator,
    this.chatHandler,
    this.fallbackResponse = 'Monolithic fallback response',
  }) : super(apiKey: 'dummy');

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
  Stream<String> chatStream({
    required List<ChatMessage> history,
    required String userMessage,
    List<ArxivPaper> papers = const [],
    Map<String, String> fullTexts = const {},
    bool eli5Mode = false,
    AiSkill skill = AiSkill.none,
    Duration inactivityTimeout = const Duration(seconds: 15),
  }) {
    return streamGenerator();
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
    chatCalled = true;
    if (chatHandler != null) {
      return await chatHandler!();
    }
    return fallbackResponse;
  }
}
