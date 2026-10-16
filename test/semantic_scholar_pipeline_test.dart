// semantic_scholar_pipeline_test.dart — Stage 5.2.1 regression tests
//
// Proves (with mocked HTTP only — NOT the real APIs) that Semantic Scholar
// results are parsed, keep provenance through dedupe, reach the AI context,
// can be targeted explicitly, and that S2 failure leaves the 4 old sources.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/models/models.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';

class _MockClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request) handler;
  final List<Uri> requests = [];
  _MockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    requests.add(r.url);
    final res = await handler(r);
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode,
        headers: res.headers, request: request);
  }
}

const _vaswaniDoi = '10.48550/arxiv.1706.03762';

String _s2Json() => jsonEncode({
      'total': 5,
      'data': [
        {
          'paperId': 's2a',
          'title': 'Attention Is All You Need',
          'abstract': 'The dominant sequence transduction models are based on recurrent networks. We propose the Transformer.',
          'year': 2017,
          'publicationDate': '2017-06-12',
          'externalIds': {'DOI': _vaswaniDoi},
          'url': 'https://www.semanticscholar.org/paper/s2a',
          'authors': [
            {'name': 'Ashish Vaswani'},
            {'name': 'Noam Shazeer'}
          ],
          'openAccessPdf': {'url': 'https://arxiv.org/pdf/1706.03762.pdf'},
        },
        for (final e in [
          ['s2b', 'BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding', 'Jacob Devlin', 2018, '10.18653/v1/N19-1423'],
          ['s2c', 'Language Models are Few-Shot Learners', 'Tom Brown', 2020, '10.5555/3495724.3495883'],
          ['s2d', 'RoBERTa: A Robustly Optimized BERT Pretraining Approach', 'Yinhan Liu', 2019, '10.48550/arxiv.1907.11692'],
          ['s2e', 'Exploring the Limits of Transfer Learning with a Unified Text-to-Text Transformer', 'Colin Raffel', 2020, '10.5555/3455716.3455856'],
        ])
          {
            'paperId': e[0],
            'title': e[1],
            'abstract': 'Abstract of ${e[1]} describing a transformer based approach for natural language processing.',
            'year': e[3],
            'publicationDate': '${e[3]}-01-01',
            'externalIds': {'DOI': e[4]},
            'url': 'https://www.semanticscholar.org/paper/${e[0]}',
            'authors': [
              {'name': e[2]}
            ],
          },
      ],
    });

String _openAlexJson() => jsonEncode({
      'results': [
        {
          'title': 'Attention Is All You Need',
          'doi': 'https://doi.org/$_vaswaniDoi',
          'publication_date': '2017-06-12',
          'authorships': [
            {'author': {'display_name': 'Ashish Vaswani'}}
          ],
          'primary_location': {'landing_page_url': 'https://openalex.org/W1', 'pdf_url': ''},
        },
      ],
    });

String _crossrefJson() => jsonEncode({
      'message': {
        'items': [
          {
            'title': ['Crossref-only Study of Neural Machine Translation Systems'],
            'DOI': '10.1000/crossref.only.1',
            'URL': 'https://doi.org/10.1000/crossref.only.1',
            'author': [
              {'given': 'Carla', 'family': 'Ross'}
            ],
            'created': {'date-time': '2019-02-02T00:00:00Z'},
            'subject': ['Computer Science'],
          },
        ],
      },
    });

http.Response _empty(Uri u) {
  if (u.host.contains('arxiv.org')) {
    return http.Response('<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"></feed>', 200);
  }
  if (u.host.contains('crossref')) return http.Response('{"message":{"items":[]}}', 200);
  if (u.host.contains('openalex')) return http.Response('{"results":[]}', 200);
  if (u.host.contains('semanticscholar')) return http.Response('{"data":[]}', 200);
  return http.Response('{"response":{"docs":[]}}', 200);
}

_MockClient _client({int s2Status = 200, bool others = true}) => _MockClient((r) async {
      final h = r.url.host;
      if (h.contains('semanticscholar')) {
        return s2Status == 200 ? http.Response(_s2Json(), 200) : http.Response('rate limited', s2Status);
      }
      if (others && h.contains('openalex')) return http.Response(_openAlexJson(), 200);
      if (others && h.contains('crossref')) return http.Response(_crossrefJson(), 200);
      return _empty(r.url);
    });

class _CapturingGemini extends GeminiService {
  _CapturingGemini() : super(apiKey: 'dummy');
  String? lastUserMessage;
  List<ArxivPaper> lastPapers = [];

  @override
  Future<Map<String, String>> extractSearchIntent(String message) async => {
        'intent': 'search',
        'query': 'transformer natural language processing',
        'keywords': 'transformer natural language processing Semantic Scholar',
        'category': '',
      };

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
    yield 'ok';
  }

  @override
  Future<List<String>> generateFollowUpSuggestions({
    required String userQuestion,
    required String aiAnswer,
    List<ArxivPaper> papers = const [],
  }) async =>
      const [];
}

class _MemStorage extends StorageService {
  @override
  Future<List<ArxivPaper>?> getCached(String cacheKey) async => null;
  @override
  Future<void> setCache(String cacheKey, List<ArxivPaper> papers) async {}
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}
  @override
  Future<SearchFilter> getSearchFilter() async => const SearchFilter();
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {}
}

const _userRequest =
    'Carikan 5 paper tentang transformer untuk NLP yang berasal dari Semantic Scholar. '
    'Tampilkan judul, penulis, tahun, dan tautan masing-masing. '
    'Jangan tampilkan paper hanya karena membahas Semantic Scholar.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Source request detection', () {
    test('explicit user request targets Semantic Scholar', () {
      expect(SearchService.detectRequestedSource(_userRequest), SearchService.semanticScholarSource);
      expect(SearchService.detectRequestedSource('papers from Semantic Scholar on BERT'),
          SearchService.semanticScholarSource);
    });
    test('topical mention is NOT a source request', () {
      expect(SearchService.detectRequestedSource('Carikan paper tentang Semantic Scholar'), isNull);
      expect(SearchService.detectRequestedSource('papers about Semantic Scholar API'), isNull);
    });
    test('generic query keeps federated search', () {
      expect(SearchService.detectRequestedSource('Carikan 5 paper tentang transformer untuk NLP'), isNull);
    });
    test('stripSourceMentions removes source name from keywords', () {
      expect(SearchService.stripSourceMentions('transformer NLP Semantic Scholar'), 'transformer NLP');
    });
  });

  group('Pipeline', () {
    test('1+3: S2 parsed correctly and tagged only as Semantic Scholar (targeted)', () async {
      final c = _client();
      final svc = SearchService(client: c);
      final res = await svc.search(
        query: 'transformer nlp',
        keywords: 'transformer nlp',
        onlySource: SearchService.semanticScholarSource,
      );
      expect(res.length, 5);
      expect(res.first.title, 'Attention Is All You Need');
      expect(res.first.authors, contains('Ashish Vaswani'));
      expect(res.first.published.startsWith('2017'), isTrue);
      expect(res.first.doi, _vaswaniDoi);
      expect(res.first.absUrl, 'https://www.semanticscholar.org/paper/s2a');
      for (final p in res) {
        expect(p.sources, [SearchService.semanticScholarSource]);
      }
      // Targeted: no other source was contacted.
      expect(c.requests.every((u) => u.host.contains('semanticscholar')), isTrue);
      expect(svc.lastDiagnostics.parsedPerSource[SearchService.semanticScholarSource], 5);
      expect(svc.lastDiagnostics.httpStatus[SearchService.semanticScholarSource], '200');
    });

    test('2+3: federated dedupe keeps S2 provenance and does not mislabel', () async {
      final svc = SearchService(client: _client());
      final res = await svc.search(query: 'transformer nlp', keywords: 'transformer nlp');

      final vaswani = res.firstWhere((p) => p.title == 'Attention Is All You Need');
      // Same DOI came from OpenAlex AND Semantic Scholar -> merged, both kept.
      expect(vaswani.sources, containsAll([SearchService.openAlexSource, SearchService.semanticScholarSource]));
      expect(res.where((p) => p.title == 'Attention Is All You Need').length, 1);
      // Source line given to AI must mention Semantic Scholar for the merged paper.
      expect(GeminiService.sourceLabel(vaswani), contains('Semantic Scholar'));

      // S2-only papers are never labeled Crossref/OpenAlex.
      for (final p in res.where((p) => p.title.startsWith('BERT') || p.title.startsWith('Language Models'))) {
        expect(p.sources, [SearchService.semanticScholarSource]);
        expect(GeminiService.sourceLabel(p), 'Semantic Scholar');
      }
      // Crossref-only paper keeps Crossref provenance.
      final cr = res.firstWhere((p) => p.title.startsWith('Crossref-only'));
      expect(cr.sources, [SearchService.crossrefSource]);

      final d = svc.lastDiagnostics;
      expect(d.parsedPerSource[SearchService.semanticScholarSource], 5);
      expect(d.candidatesBeforeDedupe, 7); // 1 OA + 1 CR + 5 S2
      expect(d.uniqueAfterDedupe, 6); // Vaswani duplicated
      expect(d.finalPerSource[SearchService.semanticScholarSource], greaterThan(0));
    });

    test('6: S2 HTTP 429 leaves the four old sources working', () async {
      final svc = SearchService(client: _client(s2Status: 429));
      final res = await svc.search(query: 'transformer nlp', keywords: 'transformer nlp');
      expect(res.map((p) => p.title), containsAll(['Attention Is All You Need', 'Crossref-only Study of Neural Machine Translation Systems']));
      expect(res.any((p) => p.sources.contains(SearchService.semanticScholarSource)), isFalse);
      expect(svc.lastDiagnostics.httpStatus[SearchService.semanticScholarSource], '429');
      expect(svc.lastDiagnostics.parsedPerSource[SearchService.semanticScholarSource], 0);
    });

    test('maxResults is still respected', () async {
      final svc = SearchService(client: _client());
      final res = await svc.search(
        query: 'transformer nlp',
        keywords: 'transformer nlp',
        filter: const SearchFilter(maxResults: 3),
      );
      expect(res.length, lessThanOrEqualTo(3));
    });

    test('provenance survives cache JSON round trip', () {
      final p = ArxivPaper(
        id: 'x', title: 't', authors: const ['a'], summary: 's', published: '2020-01-01',
        updated: '2020-01-01', categories: const ['c'], pdfUrl: '', absUrl: 'u',
        sources: const ['OpenAlex', 'Semantic Scholar'],
      );
      expect(ArxivPaper.fromJson(p.toJson()).sources, ['OpenAlex', 'Semantic Scholar']);
    });
  });

  group('AI context', () {
    test('4+7: real titles/metadata (no placeholders) and S2 source reach the model request', () async {
      Map<String, dynamic>? sent;
      final ai = _MockClient((r) async {
        if (r.url.path.endsWith('/models')) {
          return http.Response('{"data":[{"id":"agnes-3.0-flash"}]}', 200);
        }
        sent = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{"choices":[{"message":{"content":"ok"}}]}', 200);
      });
      final gemini = GeminiService(apiKey: 'k', client: ai);
      final papers = await SearchService(client: _client()).search(
        query: 'q', keywords: 'transformer nlp', onlySource: SearchService.semanticScholarSource,
      );
      await gemini.chat(history: const [], userMessage: 'daftar paper', papers: papers);

      final user = (sent!['messages'] as List).last['content'] as String;
      expect(user, contains('Source: Semantic Scholar'));
      expect(user, contains('Title: BERT: Pre-training of Deep Bidirectional Transformers'));
      expect(user, contains('Authors: Jacob Devlin'));
      expect(user, contains('Published: Jan 1, 2018'));
      expect(user, contains('URL: https://www.semanticscholar.org/paper/s2c'));
      expect(RegExp(r'Source: Semantic Scholar').allMatches(user).length, 5);
      expect(RegExp(r'Title: (Paper \d+)\n').hasMatch(user), isFalse);
    });

    test('5: provider sends S2-sourced papers (not S2-topic papers) for a source request', () async {
      final gemini = _CapturingGemini();
      final provider = SciChatProvider(
        searchService: SearchService(client: _client()),
        storageService: _MemStorage(),
        geminiService: gemini,
      );
      await provider.sendMessage(_userRequest);

      expect(gemini.lastPapers.length, 5);
      expect(gemini.lastPapers.every((p) => p.sources.contains(SearchService.semanticScholarSource)), isTrue);
      expect(gemini.lastPapers.any((p) => p.sources.contains(SearchService.crossrefSource)), isFalse);
      // Source name must not have polluted the topical query.
      expect(gemini.lastUserMessage, contains('[SEARCH STATUS]'));
      expect(gemini.lastUserMessage, contains('5 paper ditemukan dari sumber tersebut'));
    });

    test('honest status when requested source fails', () async {
      final gemini = _CapturingGemini();
      final provider = SciChatProvider(
        searchService: SearchService(client: _client(s2Status: 429)),
        storageService: _MemStorage(),
        geminiService: gemini,
      );
      await provider.sendMessage(_userRequest);

      expect(gemini.lastPapers, isEmpty);
      expect(gemini.lastUserMessage, contains('Semantic Scholar: permintaan gagal (429)'));
      expect(gemini.lastUserMessage, contains('0 paper ditemukan'));
    });

    test('generic request stays federated (all sources queried)', () async {
      final c = _client();
      final gemini = _CapturingGemini();
      final provider = SciChatProvider(
        searchService: SearchService(client: c),
        storageService: _MemStorage(),
        geminiService: gemini,
      );
      await provider.sendMessage('Carikan 5 paper tentang transformer untuk NLP');
      final hosts = c.requests.map((u) => u.host).toSet();
      expect(hosts.any((h) => h.contains('openalex')), isTrue);
      expect(hosts.any((h) => h.contains('crossref')), isTrue);
      expect(hosts.any((h) => h.contains('semanticscholar')), isTrue);
    });
  });
}
