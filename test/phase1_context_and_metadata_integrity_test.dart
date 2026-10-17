import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';

// --- Mocks for Testing ---

class FakeSearchService extends SearchService {
  bool wasCalled = false;
  String? lastQuery;
  List<ArxivPaper> fakeResults = [];

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    wasCalled = true;
    lastQuery = query;
    return fakeResults;
  }
}

class FakeGeminiService extends GeminiService {
  String lastUserMessage = '';
  List<ArxivPaper> lastPapers = [];
  List<ChatMessage> lastHistory = [];
  String responseText = 'Fake response from Gemini';

  FakeGeminiService() : super(apiKey: 'fake-key');

  @override
  Future<Map<String, String>> extractSearchIntent(String userMessage) async {
    final lower = userMessage.toLowerCase();
    if (lower.contains('paper kedua') || lower.contains('paper tadi') || lower.contains('makalah ini')) {
      return {'intent': 'summarize', 'query': userMessage, 'keywords': userMessage};
    }
    return {'intent': 'search', 'query': userMessage, 'keywords': userMessage};
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
    lastHistory = List.from(history);
    lastUserMessage = userMessage;
    lastPapers = List.from(papers);
    yield responseText;
  }
}

class FakeStorageService extends StorageService {
  String? _key = 'test-api-key';
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

ArxivPaper makePaper({
  required String id,
  required String title,
  List<String> authors = const ['John Doe'],
  String year = '2023',
  String? doi,
  String summary = 'Detailed research abstract about the methodology and findings.',
  String pdfUrl = 'https://example.com/paper.pdf',
  String absUrl = 'https://example.com/abs',
  List<String> sources = const ['arXiv'],
  int? citationCount,
  int? referenceCount,
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: summary,
    published: '$year-05-10T00:00:00Z',
    updated: '$year-05-10T00:00:00Z',
    categories: ['cs.AI'],
    pdfUrl: pdfUrl,
    absUrl: absUrl,
    doi: doi,
    sources: sources,
    citationCount: citationCount,
    referenceCount: referenceCount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tugas A (CTX-01) — Multi-Turn Conversation Context Integrity', () {
    late FakeSearchService fakeSearch;
    late FakeGeminiService fakeGemini;
    late FakeStorageService fakeStorage;
    late SciChatProvider provider;

    setUp(() async {
      fakeSearch = FakeSearchService();
      fakeGemini = FakeGeminiService();
      fakeStorage = FakeStorageService();
      provider = SciChatProvider(
        searchService: fakeSearch,
        geminiService: fakeGemini,
        storageService: fakeStorage,
      );
      await provider.init();
      await provider.setApiKey('valid-key');
    });

    test('Turn 1 paper metadata remains available in Turn 2 without manual active context', () async {
      final paper1 = makePaper(
        id: 'arxiv.1706.03762',
        title: 'Attention Is All You Need',
        authors: ['Ashish Vaswani', 'Noam Shazeer'],
        year: '2017',
        doi: '10.48550/arXiv.1706.03762',
        summary: 'We propose the Transformer architecture based solely on attention mechanisms.',
      );
      final paper2 = makePaper(
        id: 'arxiv.1810.04805',
        title: 'BERT: Pre-training of Deep Bidirectional Transformers',
        authors: ['Jacob Devlin', 'Ming-Wei Chang'],
        year: '2018',
        doi: '10.48550/arXiv.1810.04805',
        summary: 'BERT is designed to pre-train deep bidirectional representations from unlabeled text.',
      );

      // Turn 1: Initial search query
      fakeSearch.fakeResults = [paper1, paper2];
      await provider.sendMessage('Cari paper tentang transformer');

      expect(fakeSearch.wasCalled, isTrue);
      expect(provider.messages.length, 2);
      expect(provider.messages[1].papers.length, 2);

      // Turn 2: Follow-up question referencing the 2nd paper without pinning active context
      fakeSearch.wasCalled = false;
      await provider.sendMessage('Bahas paper kedua tadi');

      // 1. Must NOT trigger external re-search for string "Bahas paper kedua tadi"
      expect(fakeSearch.wasCalled, isFalse,
          reason: 'Follow-up on prior paper should not launch external search');

      // 2. Turn 2 assistant message must preserve Paper 2 identity
      expect(provider.messages.length, 4);
      final turn2AssistantMsg = provider.messages[3];
      expect(turn2AssistantMsg.papers.length, 1);
      expect(turn2AssistantMsg.papers.first.id, 'arxiv.1810.04805');
      expect(turn2AssistantMsg.papers.first.title, contains('BERT'));

      // 3. Gemini payload construction: Turn 1 papers must be present with full metadata
      final gemini = GeminiService(apiKey: 'key');
      final payload = gemini.buildChatMessages(
        history: provider.messages.sublist(0, 2),
        userMessage: 'Bahas paper kedua tadi',
      );

      // Turn 1 user message in the prompt payload should contain [RETRIEVED PAPERS]
      final turn1UserContent = payload.firstWhere((m) => m['role'] == 'user')['content']!;
      expect(turn1UserContent, contains('[RETRIEVED PAPERS]'));
      expect(turn1UserContent, contains('Paper 1:'));
      expect(turn1UserContent, contains('Attention Is All You Need'));
      expect(turn1UserContent, contains('DOI: 10.48550/arXiv.1706.03762'));
      expect(turn1UserContent, contains('Paper 2:'));
      expect(turn1UserContent, contains('BERT: Pre-training of Deep Bidirectional Transformers'));
      expect(turn1UserContent, contains('DOI: 10.48550/arXiv.1810.04805'));

      // Turn 2 user message does not duplicate [RETRIEVED PAPERS]
      final turn2UserContent = payload.last['content']!;
      expect(turn2UserContent, contains('Bahas paper kedua tadi'));
      expect(turn2UserContent.contains('[RETRIEVED PAPERS]'), isFalse,
          reason: 'Turn 2 user prompt should not duplicate already retrieved papers');
    });

    test('resolveReferencedPaper correctly maps Indonesian ordinals to exact paper index', () {
      final papers = [
        makePaper(id: 'p1', title: 'First Paper'),
        makePaper(id: 'p2', title: 'Second Paper'),
        makePaper(id: 'p3', title: 'Third Paper'),
        makePaper(id: 'p4', title: 'Fourth Paper'),
        makePaper(id: 'p5', title: 'Fifth Paper'),
      ];

      expect(SciChatProvider.resolveReferencedPaper('Bahas paper kedua tadi', papers)?.id, 'p2');
      expect(SciChatProvider.resolveReferencedPaper('jelaskan metodologi paper ke-2', papers)?.id, 'p2');
      expect(SciChatProvider.resolveReferencedPaper('makalah kedua tersebut', papers)?.id, 'p2');
      expect(SciChatProvider.resolveReferencedPaper('bagaimana dengan paper pertama?', papers)?.id, 'p1');
      expect(SciChatProvider.resolveReferencedPaper('makalah 1', papers)?.id, 'p1');
      expect(SciChatProvider.resolveReferencedPaper('analisis paper ke-3', papers)?.id, 'p3');
      expect(SciChatProvider.resolveReferencedPaper('apa kesimpulan paper keempat', papers)?.id, 'p4');
      expect(SciChatProvider.resolveReferencedPaper('paper kelima tadi', papers)?.id, 'p5');
      expect(SciChatProvider.resolveReferencedPaper('bagaimana kesimpulan umum?', papers), isNull);
    });

    test('Follow-up query in new session does NOT leak papers from previous session', () async {
      // Session 1: Search papers
      fakeSearch.fakeResults = [makePaper(id: 'sess1.p1', title: 'Session 1 Neural Networks')];
      await provider.sendMessage('Cari paper neural networks');
      expect(provider.messages[1].papers.first.id, 'sess1.p1');

      // User creates a fresh new session
      provider.createNewSession();
      expect(provider.messages, isEmpty);

      // In the new session, user asks about a prior paper
      fakeSearch.wasCalled = false;
      await provider.sendMessage('Bahas paper kedua tadi');

      // The new session has no prior papers, so it must not use session 1's papers
      final lastMsg = provider.messages.last;
      expect(lastMsg.papers, isEmpty,
          reason: 'New session must never inherit papers from previous session');
    });

    test('Unrelated search in same session does not contaminate prior search context', () async {
      final quant1 = makePaper(id: 'q1', title: 'Quantum Teleportation');
      final quant2 = makePaper(id: 'q2', title: 'Quantum Supremacy');
      final bio1 = makePaper(id: 'b1', title: 'Photosynthesis Efficiency');
      final bio2 = makePaper(id: 'b2', title: 'Plant Chloroplast Evolution');

      // Turn 1: Search Quantum
      fakeSearch.fakeResults = [quant1, quant2];
      await provider.sendMessage('Cari paper tentang quantum');

      // Turn 2: Explicit new search for Biology
      fakeSearch.fakeResults = [bio1, bio2];
      await provider.sendMessage('Cari paper baru tentang fotosintesis');
      expect(fakeSearch.wasCalled, isTrue);

      // Turn 3: User asks "Bahas paper kedua tadi"
      fakeSearch.wasCalled = false;
      await provider.sendMessage('Bahas paper kedua tadi');

      // Must resolve to bio2 (most recent search in this topic), not quant2
      final turn3Msg = provider.messages.last;
      expect(turn3Msg.papers.first.id, 'b2');
      expect(turn3Msg.papers.first.title, 'Plant Chloroplast Evolution');
    });

    test('Context formatting includes DOI and handles unavailable information cleanly', () {
      final papers = [
        makePaper(
          id: 'p1',
          title: 'Paper With DOI',
          doi: '10.1234/test.doi',
          summary: 'Available abstract text.',
        ),
        makePaper(
          id: 'p2',
          title: 'Paper Without DOI',
          doi: null,
          summary: '',
        ),
      ];

      final formatted = GeminiService.formatPapersContext(papers);
      expect(formatted, contains('Paper 1:'));
      expect(formatted, contains('DOI: 10.1234/test.doi'));
      expect(formatted, contains('Abstract: Available abstract text.'));

      expect(formatted, contains('Paper 2:'));
      expect(formatted, contains('DOI: Tidak tersedia'));
      expect(formatted, contains('Abstract: Abstrak tidak tersedia'));
    });
  });

  group('Tugas B (REF-01) — Metadata Deduplication & Enrichment Integrity', () {
    test('1. Same title, same year, DIFFERENT valid DOIs -> CANNOT merge (different works)', () {
      final paperA = makePaper(
        id: 'work1',
        title: 'Deep Residual Learning for Image Recognition',
        year: '2016',
        doi: '10.1109/cvpr.2016.90',
        authors: ['Kaiming He', 'Xiangyu Zhang'],
      );
      final paperB = makePaper(
        id: 'work2',
        title: 'Deep Residual Learning for Image Recognition',
        year: '2016',
        doi: '10.1007/978-3-319-46484-8_25', // Conflicting DOI (different publication/work)
        authors: ['Kaiming He', 'Xiangyu Zhang'],
      );

      final canMerge = SearchService.canMerge(paperA, paperB);
      expect(canMerge, isFalse,
          reason: 'Two records with conflicting valid DOIs must never be merged');
    });

    test('2. Same title, SAME valid DOI, different sources -> CAN merge & enrich sources', () {
      final arxivPaper = makePaper(
        id: 'arxiv.1706.03762',
        title: 'Attention Is All You Need',
        year: '2017',
        doi: '10.48550/arxiv.1706.03762',
        sources: ['arXiv'],
        citationCount: 50000,
      );
      final crossrefPaper = makePaper(
        id: 'https://doi.org/10.48550/arxiv.1706.03762',
        title: 'Attention is all you need',
        year: '2017',
        doi: '10.48550/arXiv.1706.03762',
        sources: ['CrossRef'],
        citationCount: 65000,
        referenceCount: 40,
      );

      final canMerge = SearchService.canMerge(arxivPaper, crossrefPaper);
      expect(canMerge, isTrue, reason: 'Identical normalized DOI must allow safe merge');

      // Test enrichment behavior via SearchService
      final service = SearchService();
      final enriched = service.enrichPaper(arxivPaper, crossrefPaper);

      // Verify DOI preserved
      expect(enriched.doi, '10.48550/arxiv.1706.03762');
      // Sources merged
      expect(enriched.sources, containsAll(['arXiv', 'CrossRef']));
      // Citation count takes highest
      expect(enriched.citationCount, 65000);
      expect(enriched.referenceCount, 40);
    });

    test('3. Missing DOI on one or both records -> Merges ONLY if author, title, and year match', () {
      // 3a. Both missing DOI, matching author & year
      final record1 = makePaper(
        id: 'rec1',
        title: 'Graph Neural Networks in Molecular Chemistry',
        authors: ['Duvenaud', 'Maclaurin'],
        year: '2015',
        doi: null,
      );
      final record2 = makePaper(
        id: 'rec2',
        title: 'Graph Neural Networks in Molecular Chemistry',
        authors: ['David Duvenaud', 'Dougal Maclaurin'],
        year: '2015',
        doi: null,
      );
      expect(SearchService.canMerge(record1, record2), isTrue,
          reason: 'Matching title, compatible author, and year should merge when DOI is missing');

      // 3b. One has DOI, one missing DOI, matching author & year
      final recordWithDoi = makePaper(
        id: 'rec3',
        title: 'Graph Neural Networks in Molecular Chemistry',
        authors: ['David Duvenaud'],
        year: '2015',
        doi: '10.5555/chem.2015.1',
      );
      expect(SearchService.canMerge(record1, recordWithDoi), isTrue,
          reason: 'Record without DOI can merge into record with DOI if author & year match');

      // 3c. Both missing DOI, same title, but DIFFERENT first author
      final diffAuthor = makePaper(
        id: 'rec4',
        title: 'Graph Neural Networks in Molecular Chemistry',
        authors: ['Smith', 'Johnson'],
        year: '2015',
        doi: null,
      );
      expect(SearchService.canMerge(record1, diffAuthor), isFalse,
          reason: 'Different first authors must NOT merge even if title is identical');

      // 3d. Both missing DOI, same author, but year difference > 1 year
      final diffYear = makePaper(
        id: 'rec5',
        title: 'Graph Neural Networks in Molecular Chemistry',
        authors: ['Duvenaud'],
        year: '2019',
        doi: null,
      );
      expect(SearchService.canMerge(record1, diffYear), isFalse,
          reason: 'Year difference > 1 year must NOT merge when DOI is missing');
    });

    test('4. Similar or same title with different authors or publication year -> CANNOT merge', () {
      final paper1 = makePaper(
        id: 'ai1',
        title: 'Advances in Deep Reinforcement Learning',
        authors: ['Silver', 'Sutton'],
        year: '2016',
      );
      final paper2 = makePaper(
        id: 'ai2',
        title: 'Advances in Deep Reinforcement Learning',
        authors: ['Mnih', 'Kavukcuoglu'], // Different author
        year: '2016',
      );
      expect(SearchService.canMerge(paper1, paper2), isFalse);

      final paper3 = makePaper(
        id: 'ai3',
        title: 'Advances in Deep Reinforcement Learning',
        authors: ['Silver', 'Sutton'],
        year: '2022', // 6 years apart
      );
      expect(SearchService.canMerge(paper1, paper3), isFalse);
    });

    test('5. PDF URL and Abstract collision guard preserves distinct works', () {
      final work1 = makePaper(
        id: 'w1',
        title: 'First Distinct Scientific Work',
        doi: '10.1111/first.2021',
        pdfUrl: 'https://example.com/first.pdf',
        summary: 'Abstract of the first distinct scientific work.',
      );
      final work2 = makePaper(
        id: 'w2',
        title: 'Second Distinct Scientific Work',
        doi: '10.2222/second.2021',
        pdfUrl: 'https://example.com/second.pdf',
        summary: 'Abstract of the second distinct scientific work.',
      );

      final service = SearchService();
      // enrichPaper must reject merge when canMerge is false
      final result = service.enrichPaper(work1, work2);

      expect(result.id, work1.id);
      expect(result.doi, work1.doi);
      expect(result.pdfUrl, work1.pdfUrl);
      expect(result.summary, work1.summary);
      expect(result.pdfUrl, isNot(work2.pdfUrl));
      expect(result.summary, isNot(work2.summary));
    });
  });
}
