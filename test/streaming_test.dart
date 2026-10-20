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

      final selectableFinder = find.byWidgetPredicate(
        (w) =>
            w is SelectableText &&
            (w.textSpan
                    ?.toPlainText()
                    .contains('Teks yang sedang dialirkan...') ??
                false),
      );
      expect(selectableFinder, findsOneWidget);
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

      // Tap kembali untuk menutup sumber (collapse)
      await tester.tap(find.text('Sumber makalah (1)'));
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
