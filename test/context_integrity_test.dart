import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/pdf_service.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:flutter/material.dart';

// Fake implementations for testing
class FakeSearchService extends SearchService {
  bool wasCalled = false;
  List<ArxivPaper> fakeResults = [];
  bool shouldThrow = false;

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    wasCalled = true;
    if (shouldThrow) {
      throw Exception('Search failed manually for test');
    }
    return fakeResults;
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

class FakePdfService extends PdfService {
  @override
  Future<String?> extractTextFromUrl(String url, {int maxChars = 8000}) async {
    return 'Fake extracted text from $url for testing.';
  }

  @override
  Future<String?> extractTextFromBytes(List<int> bytes, {int maxChars = 8000}) async {
    return 'Fake extracted text from bytes for testing.';
  }
}

class FakeGeminiService extends GeminiService {
  String lastUserMessage = '';
  List<ArxivPaper> lastPapers = [];
  bool shouldThrow = false;
  String responseText = 'Fake response';

  FakeGeminiService() : super(apiKey: 'fake');

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async {
    // Basic fake logic for testing
    if (message.toLowerCase().contains('cari ') || message.toLowerCase().contains('makalah lain')) {
      return {'intent': 'search', 'query': message};
    }
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
    lastUserMessage = userMessage;
    lastPapers = papers;
    if (shouldThrow) throw Exception('Network Error');
    return responseText;
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
    lastUserMessage = userMessage;
    lastPapers = papers;
    if (shouldThrow) throw Exception('Network Error');
    yield responseText;
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

void main() {
  group('Phase 8B - Research Context Integrity Tests', () {
    late SciChatProvider provider;
    late FakeSearchService fakeSearch;
    late FakeGeminiService fakeGemini;

    ArxivPaper createDummyPaper(String id, String title) {
      return ArxivPaper(
        id: id,
        title: title,
        authors: ['Author $id'],
        summary: 'Abstract $id',
        published: '2023-01-01',
        updated: '2023-01-01',
        categories: ['cs.AI'],
        pdfUrl: 'http://example.com/$id.pdf',
        absUrl: 'http://example.com/$id',
      );
    }

    setUp(() {
      fakeSearch = FakeSearchService();
      fakeGemini = FakeGeminiService();
      
      provider = SciChatProvider(
        searchService: fakeSearch,
        geminiService: fakeGemini,
        storageService: FakeStorageService(),
        pdfService: FakePdfService(),
      );
      // Simulate init to set active session
      provider.createNewSession(notify: false);
    });

    test('Pertanyaan tentang konteks aktif tidak memicu pencarian otomatis', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      
      // Send a contextual question
      await provider.sendMessage('Tolong jelaskan metode makalah ini');
      
      if (provider.appState == AppState.error) {
        print('Error in provider: ${provider.errorMessage}');
      }

      expect(provider.appState, isNot(AppState.error), reason: 'Provider seharusnya tidak error');
      expect(fakeSearch.wasCalled, isFalse, reason: 'Pencarian tidak boleh dipanggil untuk pertanyaan kontekstual');
      expect(fakeGemini.lastPapers.isEmpty, isTrue, reason: 'Papers tidak boleh dikirim ke gemini untuk diinject RETRIEVED PAPERS');
      expect(fakeGemini.lastUserMessage, contains('Sunda Block Motion'));
      
      // Ensure the message metadata contains the correct paper
      final lastMsg = provider.messages.last;
      expect(lastMsg.papers.length, 1);
      expect(lastMsg.papers.first.id, 'active1');
    });

    test('Pertanyaan eksplisit meminta makalah baru TANPA membandingkan HANYA menyimpan hasil pencarian', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      
      fakeSearch.fakeResults = [createDummyPaper('search1', 'CIA Noncash Benefits')];
      
      await provider.sendMessage('Tolong cari makalah lain tentang benefits');
      
      expect(fakeSearch.wasCalled, isTrue);
      expect(fakeGemini.lastPapers.isNotEmpty, isTrue);
      
      final lastMsg = provider.messages.last;
      expect(lastMsg.papers.length, 1, reason: 'Harus HANYA berisi hasil pencarian baru');
      expect(lastMsg.papers.first.id, 'search1');
      
      // Active context tetap utuh di UI
      expect(provider.activePaperContext?.id, 'active1');
    });

    test('Pertanyaan "Bandingkan makalah aktif dengan tiga makalah terbaru" memicu pencarian dan menggabungkan konteks', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      fakeSearch.wasCalled = false;
      fakeSearch.fakeResults = [createDummyPaper('search2', 'New Paper 2026')];
      fakeGemini.lastPapers.clear();
      
      await provider.sendMessage('Bandingkan makalah aktif dengan tiga makalah terbaru');
      expect(fakeSearch.wasCalled, isTrue);
      
      final lastMsg = provider.messages.last;
      expect(lastMsg.papers.length, 2);
      expect(lastMsg.papers.map((p) => p.id).contains('active1'), isTrue);
      expect(lastMsg.papers.map((p) => p.id).contains('search2'), isTrue);
    });

    test('Pertanyaan "Apa yang dicari peneliti dalam makalah ini?" dipetakan ke konteks aktif', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      fakeSearch.wasCalled = false;
      fakeGemini.lastPapers.clear();
      
      await provider.sendMessage('Apa yang dicari peneliti dalam makalah ini?');
      expect(fakeSearch.wasCalled, isFalse);
      expect(fakeGemini.lastPapers.isEmpty, isTrue);
    });

    test('Pertanyaan "Cari bagian metode dalam PDF ini" dipetakan ke konteks aktif', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      fakeSearch.wasCalled = false;
      fakeGemini.lastPapers.clear();
      
      await provider.sendMessage('Cari bagian metode dalam PDF ini');
      expect(fakeSearch.wasCalled, isFalse);
      expect(fakeGemini.lastPapers.isEmpty, isTrue);
    });
    test('Penyimpanan Research Note dari jawaban perbandingan mempertahankan seluruh sumber gabungan', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      fakeSearch.wasCalled = false;
      fakeSearch.fakeResults = [createDummyPaper('search2', 'New Paper 2026')];
      
      await provider.sendMessage('Bandingkan makalah aktif dengan makalah terbaru');
      final lastMsg = provider.messages.last;
      
      await provider.saveInsight(lastMsg);
      
      final savedNote = provider.notes.last;
      expect(savedNote.sourceMessageId, lastMsg.id);
      expect(savedNote.sources.length, 2);
      expect(savedNote.sources.map((p) => p.id).contains('active1'), isTrue);
      expect(savedNote.sources.map((p) => p.id).contains('search2'), isTrue);
    });

    test('Pemulihan Research Note lama yang belum memiliki metadata provenance tambahan tetap aman', () {
      final jsonNote = {
        'id': 'note_old',
        'sourceMessageId': 'msg_old',
        'content': 'Isi catatan lama',
        'sources': [
          {
            'id': 'paper_old_1',
            'title': 'Judul Lama',
            'authors': ['Penulis Lama'],
            'summary': 'Abstrak',
            'published': '2010',
            'updated': '2010',
            'categories': ['cs.AI'],
            'pdfUrl': 'http://old.pdf',
            'absUrl': 'http://old.abs'
          }
        ],
        'savedAt': DateTime.now().toIso8601String()
      };
      
      final note = ResearchNote.fromJson(jsonNote);
      expect(note.id, 'note_old');
      expect(note.sources.length, 1);
      expect(note.sources.first.id, 'paper_old_1');
    });
    test('Kegagalan pencarian baru tidak menghapus konteks aktif', () async {
      final activePaper = createDummyPaper('active1', 'Sunda Block Motion');
      provider.setActiveContexts([activePaper]);
      
      fakeSearch.shouldThrow = true;
      
      await provider.sendMessage('Tolong cari makalah lain tentang benefits');
      
      expect(provider.appState, AppState.error);
      final lastMsg = provider.messages.last;
      expect(lastMsg.status, MessageStatus.error);
      expect(lastMsg.papers.isEmpty, isTrue); // Error msg should not have sources
      
      // Active context tetap utuh
      expect(provider.activePaperContext?.id, 'active1');
    });
  });
}
