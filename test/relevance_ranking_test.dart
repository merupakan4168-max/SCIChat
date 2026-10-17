import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/models/models.dart';
import 'package:scichat/services/search_service.dart';

class _MockClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;
  _MockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      request: request,
    );
  }
}

ArxivPaper _testPaper({
  required String id,
  required String title,
  String summary = '',
  String published = '2023-01-01',
  String updated = '2023-01-01',
  int? citationCount,
  String pdfUrl = '',
  List<String> sources = const [],
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: const ['Test Author'],
    summary: summary,
    published: published,
    updated: updated,
    categories: const ['cs.AI'],
    pdfUrl: pdfUrl,
    absUrl: 'https://example.com/$id',
    citationCount: citationCount,
    sources: sources,
  );
}

void main() {
  group('Fase 3: Smart Re-ranking & Relevance Scoring Unit Tests', () {
    test('1. Judul yang cocok tepat memiliki skor lebih tinggi daripada cocok sebagian', () {
      const query = 'Quantum Computing';
      final exactTitle = _testPaper(
        id: '1',
        title: 'Quantum Computing',
        summary: 'A general overview.',
      );
      final partialTitle = _testPaper(
        id: '2',
        title: 'Advances in Modern Computing Architecture and Cloud Networks',
        summary: 'Mentions quantum computing in passing.',
      );

      final exactScore = SearchService.computeRelevanceScore(exactTitle, query);
      final partialScore = SearchService.computeRelevanceScore(partialTitle, query);

      expect(exactScore, greaterThan(partialScore));
      expect(exactScore, greaterThan(100.0));
    });

    test('2. Kecocokan abstrak membedakan paper ketika judul serupa', () {
      const query = 'Reinforcement Learning';
      final relevantAbstract = _testPaper(
        id: '1',
        title: 'Artificial Intelligence Systems',
        summary: 'Deep study of reinforcement learning algorithms, policy gradient methods, and rewards.',
      );
      final unrelatedAbstract = _testPaper(
        id: '2',
        title: 'Artificial Intelligence Systems',
        summary: 'A study on computer vision and convolutional neural networks for image segmentation.',
      );

      final scoreRelevant = SearchService.computeRelevanceScore(relevantAbstract, query);
      final scoreUnrelated = SearchService.computeRelevanceScore(unrelatedAbstract, query);

      expect(scoreRelevant, greaterThan(scoreUnrelated));
      expect(scoreRelevant, greaterThan(20.0));
      expect(scoreUnrelated, equals(0.0));
    });

    test('3. Paper tidak relevan yang hanya berbagi kata umum tidak mendapat skor tinggi', () {
      const query = 'The Effects of Climate Change on Agriculture';
      final unrelatedPaper = _testPaper(
        id: '1',
        title: 'The Effects of Corporate Mergers on European Banking',
        summary: 'Analysis of financial regulations and banking liquidity.',
      );
      final climatePaper = _testPaper(
        id: '2',
        title: 'Climate Change Impact on Global Agriculture and Wheat Crops',
        summary: 'Investigating temperature changes and agricultural yields.',
      );

      final unrelatedScore = SearchService.computeRelevanceScore(unrelatedPaper, query);
      final climateScore = SearchService.computeRelevanceScore(climatePaper, query);

      expect(unrelatedScore, equals(0.0));
      expect(climateScore, greaterThan(80.0));
    });

    test('4. Query kosong atau sangat pendek menghasilkan skor 0 secara aman', () {
      final paper = _testPaper(
        id: '1',
        title: 'Neural Networks and Deep Learning',
        summary: 'Backpropagation and transformers.',
      );

      expect(SearchService.computeRelevanceScore(paper, ''), equals(0.0));
      expect(SearchService.computeRelevanceScore(paper, '   '), equals(0.0));
      expect(SearchService.computeRelevanceScore(paper, 'a'), equals(0.0));
    });

    test('5. Metadata tidak lengkap (tanpa abstrak, tanpa sitasi, tanggal kosong) dihitung secara aman', () {
      const query = 'Graph Neural Networks';
      final incompletePaper = const ArxivPaper(
        id: 'inc1',
        title: 'Graph Neural Networks for Chemistry',
        authors: [],
        summary: '',
        published: '',
        updated: '',
        categories: [],
        pdfUrl: '',
        absUrl: '',
      );

      expect(() => SearchService.computeRelevanceScore(incompletePaper, query), returnsNormally);
      final score = SearchService.computeRelevanceScore(incompletePaper, query);
      expect(score, greaterThan(50.0));
    });

    test('6. Keberadaan PDF tidak memberikan bobot relevansi', () {
      const query = 'Transformer Models';
      final paperWithPdf = _testPaper(
        id: '1',
        title: 'Transformer Models in NLP',
        summary: 'Attention mechanisms.',
        pdfUrl: 'https://example.com/paper.pdf',
      );
      final paperWithoutPdf = _testPaper(
        id: '2',
        title: 'Transformer Models in NLP',
        summary: 'Attention mechanisms.',
        pdfUrl: '',
      );

      final scoreWithPdf = SearchService.computeRelevanceScore(paperWithPdf, query);
      final scoreWithoutPdf = SearchService.computeRelevanceScore(paperWithoutPdf, query);

      expect(scoreWithPdf, equals(scoreWithoutPdf));
    });

    test('7. Jumlah sitasi tidak mendominasi relevansi topik', () {
      const query = 'CRISPR Gene Editing in Plants';
      final unrelatedFamousPaper = _testPaper(
        id: '1',
        title: 'Attention Is All You Need',
        summary: 'Sequence transduction with transformers for natural language translation.',
        citationCount: 150000,
      );
      final relevantObscurePaper = _testPaper(
        id: '2',
        title: 'CRISPR Gene Editing Applications in Wheat Agriculture',
        summary: 'Field trials using CRISPR Cas9 in plant biology.',
        citationCount: 2,
      );

      final famousScore = SearchService.computeRelevanceScore(unrelatedFamousPaper, query);
      final relevantScore = SearchService.computeRelevanceScore(relevantObscurePaper, query);

      expect(famousScore, equals(0.0));
      expect(relevantScore, greaterThan(80.0));
    });
  });

  group('Fase 3: Cross-Source Re-Ranking & Regression Guard Tests', () {
    test('8. Re-ranking mempromosikan paper sangat relevan dari sumber belakang ke posisi teratas', () async {
      // Mock returns:
      // arXiv (first source in round-robin): low relevance paper
      // Semantic Scholar (last source in round-robin): exact title match paper
      final client = _MockClient((req) async {
        if (req.url.host.contains('arxiv.org')) {
          return http.Response('''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2101.0001</id>
    <title>General Computer Science Notes</title>
    <summary>Miscellaneous computing observations.</summary>
    <published>2021-01-01T00:00:00Z</published>
    <updated>2021-01-01T00:00:00Z</updated>
    <link rel="alternate" type="text/html" href="http://arxiv.org/abs/2101.0001"/>
  </entry>
</feed>''', 200);
        }
        if (req.url.host.contains('semanticscholar.org')) {
          return http.Response(jsonEncode({
            'total': 1,
            'data': [
              {
                'paperId': 's2_opt',
                'title': 'Quantum Teleportation Protocols',
                'abstract': 'Theoretical and experimental protocols for quantum teleportation.',
                'year': 2022,
                'externalIds': {'DOI': '10.1000/s2.opt'},
                'url': 'https://example.com/s2_opt',
              }
            ]
          }), 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      final results = await service.search(
        query: 'Quantum Teleportation Protocols',
        filter: const SearchFilter(maxResults: 5, sortBy: 'relevance'),
      );

      expect(results, isNotEmpty);
      expect(results.first.title, equals('Quantum Teleportation Protocols'));
      expect(results.first.sources, contains(SearchService.semanticScholarSource));
    });

    test('9. Stabilitas urutan ketika skor relevansi seimbang mempertahankan keragaman sumber', () {
      final papers = [
        _testPaper(id: '1', title: 'Deep Learning', sources: ['arXiv']),
        _testPaper(id: '2', title: 'Deep Learning', sources: ['CrossRef']),
        _testPaper(id: '3', title: 'Deep Learning', sources: ['Semantic Scholar']),
      ];

      final ranked = SearchService.rankPapersByRelevance(papers, 'Deep Learning');

      expect(ranked[0].sources, equals(['arXiv']));
      expect(ranked[1].sources, equals(['CrossRef']));
      expect(ranked[2].sources, equals(['Semantic Scholar']));
    });

    test('10. Sorting submittedDate dan lastUpdatedDate tidak diubah oleh relevance ranking', () async {
      final client = _MockClient((req) async {
        if (req.url.host.contains('openalex.org')) {
          return http.Response(jsonEncode({
            'results': [
              {
                'id': 'oa_old',
                'title': 'Quantum Teleportation Exact Match',
                'publication_date': '2020-01-01',
                'primary_location': {'landing_page_url': 'https://example.com', 'pdf_url': ''},
              },
              {
                'id': 'oa_new',
                'title': 'Unrelated Title Mentioning Physics',
                'publication_date': '2024-05-01',
                'primary_location': {'landing_page_url': 'https://example.com', 'pdf_url': ''},
              },
            ]
          }), 200);
        }
        return http.Response('{"message": {"items": []}, "data": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      // When sortBy is submittedDate, date ordering MUST win over topic relevance
      final dateSorted = await service.search(
        query: 'Quantum Teleportation',
        filter: const SearchFilter(maxResults: 5, sortBy: 'submittedDate'),
      );

      expect(dateSorted.first.id, equals('oa_new'));
      expect(dateSorted.last.id, equals('oa_old'));
    });

    test('11. Batas maxResults tetap dipatuhi setelah re-ranking', () async {
      final client = _MockClient((req) async {
        if (req.url.host.contains('semanticscholar.org')) {
          return http.Response(jsonEncode({
            'total': 10,
            'data': List.generate(
              10,
              (i) => {
                'paperId': 's2_$i',
                'title': 'Transformer Paper $i',
                'abstract': 'Abstract about transformers in NLP.',
                'year': 2020 + (i % 4),
              },
            ),
          }), 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      for (final limit in [3, 5, 8]) {
        final results = await service.search(
          query: 'Transformer',
          filter: SearchFilter(maxResults: limit, sortBy: 'relevance'),
        );
        expect(results.length, equals(limit));
      }
    });
  });
}
