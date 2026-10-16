import 'package:flutter_test/flutter_test.dart';
import '../lib/providers/scichat_provider.dart';
import '../lib/services/gemini_service.dart';
import '../lib/models/models.dart';
import '../lib/services/storage_service.dart';

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
    return 'Mock Response';
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
    if (shouldThrow) {
      throw Exception('Network Error');
    }
    chatCallCount++;
    if (shouldDelay) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    yield 'Mock Response';
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
  Future<void> saveApiKey(String key) async { _key = key; }
  
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}

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

  test('BYOK: send message without API key generates error without calling API', () async {
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
}
