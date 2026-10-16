import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:scichat/models/models.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/providers/scichat_provider.dart';

class MockStorageService extends StorageService {
  @override
  Future<String?> getApiKey() async => 'test-key';
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

class MockSearchService extends SearchService {
  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords = '',
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SSE Inactivity Timeout Verification Tests', () {
    test('1. Stream yang berhenti setelah mengirim data akhirnya melempar TimeoutException', () async {
      final streamController = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }
        return http.StreamedResponse(
          streamController.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final stream = service.chatStream(
        history: [],
        userMessage: 'Test',
        inactivityTimeout: const Duration(milliseconds: 200),
      );

      final receivedChunks = <String>[];
      Object? capturedError;
      final completer = Completer<void>();

      final subscription = stream.listen(
        (chunk) => receivedChunks.add(chunk),
        onError: (e) {
          capturedError = e;
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Kirim chunk awal
      streamController.add(utf8.encode('data: {"choices":[{"delta":{"content":"Halo "}}]}\n\n'));
      await Future.delayed(const Duration(milliseconds: 50));
      expect(receivedChunks, equals(['Halo ']));

      // Server berhenti mengirim data (inactivity stall)
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('Stream tidak melempar timeout dalam batas waktu wajar'),
      );

      expect(capturedError, isA<TimeoutException>());
      expect((capturedError as TimeoutException).message, contains('Batas waktu inaktivitas stream'));

      await subscription.cancel();
      await streamController.close();
    });

    test('2. Stream yang terus aktif tidak timeout hanya karena durasi total respons panjang', () async {
      final streamController = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }
        return http.StreamedResponse(
          streamController.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      // Inactivity timeout 200ms
      final stream = service.chatStream(
        history: [],
        userMessage: 'Test',
        inactivityTimeout: const Duration(milliseconds: 200),
      );

      final receivedChunks = <String>[];
      Object? capturedError;
      final completer = Completer<void>();

      final subscription = stream.listen(
        (chunk) => receivedChunks.add(chunk),
        onError: (e) {
          capturedError = e;
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Kirim 5 chunk berurutan dengan jeda 80ms antar-chunk
      // Total waktu = 5 * 80ms = 400ms (jauh melebihi ambang batas 200ms total),
      // namun interval antar-chunk selalu 80ms (< 200ms).
      final words = ['Satu ', 'dua ', 'tiga ', 'empat ', 'lima!'];
      for (final word in words) {
        await Future.delayed(const Duration(milliseconds: 80));
        streamController.add(utf8.encode('data: {"choices":[{"delta":{"content":"$word"}}]}\n\n'));
      }
      await Future.delayed(const Duration(milliseconds: 50));
      streamController.add(utf8.encode('data: [DONE]\n\n'));
      await streamController.close();

      await completer.future;

      expect(capturedError, isNull, reason: 'Stream yang terus aktif tidak boleh timeout');
      expect(receivedChunks, equals(words));

      await subscription.cancel();
    });

    test('3. Jeda antar-event di bawah ambang batas (termasuk SSE keepalive comment) tidak memicu timeout', () async {
      final streamController = StreamController<List<int>>();
      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }
        return http.StreamedResponse(
          streamController.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final stream = service.chatStream(
        history: [],
        userMessage: 'Test',
        inactivityTimeout: const Duration(milliseconds: 250),
      );

      final receivedChunks = <String>[];
      Object? capturedError;
      final completer = Completer<void>();

      final subscription = stream.listen(
        (chunk) => receivedChunks.add(chunk),
        onError: (e) {
          capturedError = e;
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Event 1
      streamController.add(utf8.encode('data: {"choices":[{"delta":{"content":"Mulai "}}]}\n\n'));
      // Jeda 150ms (< 250ms), kirim SSE keepalive comment
      await Future.delayed(const Duration(milliseconds: 150));
      streamController.add(utf8.encode(': keepalive ping\n\n'));
      // Jeda 150ms (< 250ms), kirim Event 2
      await Future.delayed(const Duration(milliseconds: 150));
      streamController.add(utf8.encode('data: {"choices":[{"delta":{"content":"Selesai"}}]}\n\n'));
      await Future.delayed(const Duration(milliseconds: 50));
      streamController.add(utf8.encode('data: [DONE]\n\n'));
      await streamController.close();

      await completer.future;

      expect(capturedError, isNull);
      expect(receivedChunks, equals(['Mulai ', 'Selesai']));

      await subscription.cancel();
    });

    test('4. Timeout setelah teks parsial mempertahankan teks dan memulihkan state SciChatProvider', () async {
      final controller = StreamController<String>();
      final service = _TestGeminiService(streamGenerator: () => controller.stream);

      final provider = SciChatProvider(
        geminiService: service,
        storageService: MockStorageService(),
        searchService: MockSearchService(),
      );

      final sendFuture = provider.sendMessage('Uji recovery timeout partial');
      await Future.delayed(const Duration(milliseconds: 20));

      // Token parsial diterima
      controller.add('Sebagian teks berhasil diterima...');
      await Future.delayed(const Duration(milliseconds: 120));
      expect(provider.appState, equals(AppState.streaming));
      expect(provider.isLoading, isTrue);

      // Simulasikan inactivity timeout dilempar
      controller.addError(TimeoutException('Batas waktu inaktivitas stream terlampaui.'));
      await controller.close();
      await sendFuture;

      // Verifikasi pemulihan state oleh provider:
      expect(provider.isLoading, isFalse, reason: 'isLoading harus kembali false');
      expect(provider.appState, equals(AppState.error), reason: 'appState harus menjadi error');
      expect(provider.messages.last.status, equals(MessageStatus.error));
      expect(provider.messages.last.content, equals('Sebagian teks berhasil diterima...'));
      expect(provider.messages.last.errorType, equals(ChatErrorType.timeout));
      expect(service.chatCallCount, equals(0), reason: 'Fallback monolitik TIDAK boleh dipanggil saat ada teks parsial');
    });

    test('5. Sumber stream dibatalkan dan dibersihkan ketika inactivity timeout terjadi', () async {
      bool streamCancelled = false;
      final streamController = StreamController<List<int>>(
        onCancel: () {
          streamCancelled = true;
        },
      );

      final mockClient = MockClient.streaming((request, bodyStream) async {
        if (request.url.path.endsWith('/models')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode({'data': [{'id': 'agnes-3.0-flash'}]}))),
            200,
          );
        }
        return http.StreamedResponse(
          streamController.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final service = GeminiService(
        apiKey: 'test-key',
        client: mockClient,
      );

      final stream = service.chatStream(
        history: [],
        userMessage: 'Test',
        inactivityTimeout: const Duration(milliseconds: 100),
      );

      final completer = Completer<void>();
      final sub = stream.listen(
        (_) {},
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Diamkan tanpa event sehingga timeout 100ms terpicu
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('Stream tidak melempar timeout'),
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(streamCancelled, isTrue, reason: 'Subscription sumber stream harus dibatalkan saat timeout');
      await sub.cancel();
      await streamController.close();
    });
  });
}

class _TestGeminiService extends GeminiService {
  final Stream<String> Function() streamGenerator;
  int chatCallCount = 0;

  _TestGeminiService({required this.streamGenerator}) : super(apiKey: 'dummy');

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
    chatCallCount++;
    return 'Fallback Response';
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
}
