// semantic_scholar_integration_test.dart — Stage 5.2 Semantic Scholar Integration Tests
//
// Covers:
//   1. Full response parsing (all fields, authors, abstract, DOI, PDF, citations)
//   2. Partial response without DOI
//   3. Abstract null or empty handling
//   4. Missing open-access PDF handling
//   5. Duplicate matching via DOI, arXiv ID, and guarded title/author
//   6. Metadata enrichment (enriching missing DOI/PDF/abstract without overwriting valid data)
//   7. Error isolation: HTTP 429, 5xx, timeout, malformed JSON
//   8. Failure of Semantic Scholar leaves other 4 sources intact
//   9. maxResults (3, 5, 8, 10) and sorting contracts
//   10. Deep Search, DynamicSourceButton, and context evidence compatibility

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/models/models.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/providers/scichat_provider.dart';
import 'package:scichat/widgets/dynamic_source_button.dart';

/// Test client that dispatches requests to a customizable handler function.
class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;
  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      final response = await handler(request);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    }
    throw UnimplementedError('Only http.Request supported');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Fixtures ────────────────────────────────────────────────────────────────
  const s2FullJson = '''
{
  "total": 1,
  "offset": 0,
  "data": [
    {
      "paperId": "s2_vaswani_2017",
      "title": "Attention Is All You Need",
      "abstract": "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks that include an encoder and a decoder. We propose a new simple network architecture, the Transformer.",
      "year": 2017,
      "publicationDate": "2017-06-12",
      "externalIds": {
        "DOI": "10.48550/arXiv.1706.03762",
        "ArXiv": "1706.03762",
        "CorpusId": 13756489
      },
      "url": "https://www.semanticscholar.org/paper/s2_vaswani_2017",
      "authors": [
        {"authorId": "1", "name": "Ashish Vaswani"},
        {"authorId": "2", "name": "Noam Shazeer"}
      ],
      "openAccessPdf": {
        "url": "https://arxiv.org/pdf/1706.03762.pdf",
        "status": "GOLD"
      },
      "citationCount": 110000,
      "referenceCount": 42,
      "venue": "NeurIPS"
    }
  ]
}
''';

  const s2PartialNoDoiJson = '''
{
  "total": 1,
  "offset": 0,
  "data": [
    {
      "paperId": "s2_partial_001",
      "title": "A Survey of Federated Learning Approaches",
      "abstract": "Federated learning is an emerging privacy-preserving paradigm.",
      "year": 2021,
      "publicationDate": "2021-03-01",
      "externalIds": {},
      "url": "https://www.semanticscholar.org/paper/s2_partial_001",
      "authors": [
        {"name": "Alice Smith"}
      ],
      "openAccessPdf": null,
      "citationCount": 12,
      "referenceCount": 20
    }
  ]
}
''';

  const s2NoAbstractJson = '''
{
  "total": 1,
  "offset": 0,
  "data": [
    {
      "paperId": "s2_no_abs_002",
      "title": "Document Title Without Abstract",
      "abstract": null,
      "year": 2022,
      "publicationDate": "2022-05-10",
      "externalIds": {
        "DOI": "10.1000/182"
      },
      "url": "https://www.semanticscholar.org/paper/s2_no_abs_002",
      "authors": [
        {"name": "Bob Jones"}
      ],
      "openAccessPdf": {
        "url": "https://example.com/paper.pdf"
      }
    }
  ]
}
''';

  group('1. Semantic Scholar Parsing Tests', () {
    test('Parses full response with all fields mapped correctly', () async {
      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2FullJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'attention transformer', filter: const SearchFilter(maxResults: 5));

      final s2Paper = results.firstWhere(
        (p) => p.categories.contains(SearchService.semanticScholarCategory),
        orElse: () => throw Exception('Semantic Scholar paper not found in results'),
      );

      expect(s2Paper.id, equals('s2_vaswani_2017'));
      expect(s2Paper.title, equals('Attention Is All You Need'));
      expect(s2Paper.authors, equals(['Ashish Vaswani', 'Noam Shazeer']));
      expect(s2Paper.summary, contains('dominant sequence transduction'));
      expect(s2Paper.published, equals('2017-06-12'));
      expect(s2Paper.doi, equals('10.48550/arXiv.1706.03762'));
      expect(s2Paper.pdfUrl, equals('https://arxiv.org/pdf/1706.03762.pdf'));
      expect(s2Paper.absUrl, equals('https://www.semanticscholar.org/paper/s2_vaswani_2017'));
      expect(s2Paper.citationCount, equals(110000));
      expect(s2Paper.referenceCount, equals(42));
      expect(s2Paper.journalRef, equals('NeurIPS'));
    });

    test('Parses partial response without DOI gracefully', () async {
      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2PartialNoDoiJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'federated learning', filter: const SearchFilter(maxResults: 5));

      final paper = results.firstWhere((p) => p.id == 's2_partial_001');
      expect(paper.doi, isNull);
      expect(paper.title, equals('A Survey of Federated Learning Approaches'));
      expect(paper.authors, equals(['Alice Smith']));
      expect(paper.pdfUrl, isEmpty);
      expect(paper.citationCount, equals(12));
    });

    test('Abstract null or empty falls back to standard placeholder', () async {
      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2NoAbstractJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'test', filter: const SearchFilter(maxResults: 5));

      final paper = results.firstWhere((p) => p.id == 's2_no_abs_002');
      expect(paper.summary, contains('Tidak ada abstrak yang tersedia untuk makalah Semantic Scholar ini.'));

      final provider = SciChatProvider();
      expect(provider.isAbstractValid(paper.summary), isFalse,
          reason: 'Placeholder abstract must be rejected by isAbstractValid');
    });

    test('Missing openAccessPdf yields empty string without throwing', () async {
      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2PartialNoDoiJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'test', filter: const SearchFilter(maxResults: 5));

      final paper = results.firstWhere((p) => p.id == 's2_partial_001');
      expect(paper.pdfUrl, equals(''));
    });
  });

  group('2. Deduplication and Metadata Enrichment Tests', () {
    test('Deduplicates and enriches older paper when Semantic Scholar returns matching DOI', () async {
      const crossrefMatchJson = '''
{
  "message": {
    "items": [
      {
        "DOI": "10.1000/182",
        "title": ["A Novel Neural Optimization Framework"],
        "author": [{"given": "Jane", "family": "Doe"}],
        "abstract": "",
        "created": {"date-time": "2023-01-15T00:00:00Z"},
        "URL": "https://doi.org/10.1000/182"
      }
    ]
  }
}
''';

      const s2MatchJson = '''
{
  "total": 1,
  "offset": 0,
  "data": [
    {
      "paperId": "s2_rich_182",
      "title": "A Novel Neural Optimization Framework",
      "abstract": "In this paper we demonstrate 3x speedup on deep learning workloads using gradient scaling.",
      "year": 2023,
      "publicationDate": "2023-01-15",
      "externalIds": {
        "DOI": "10.1000/182"
      },
      "url": "https://www.semanticscholar.org/paper/s2_rich_182",
      "authors": [{"name": "Jane Doe"}],
      "openAccessPdf": {
        "url": "https://openaccess.org/papers/10.1000_182.pdf"
      },
      "citationCount": 45,
      "referenceCount": 18
    }
  ]
}
''';

      final client = MockHttpClient((request) async {
        if (request.url.host.contains('api.crossref.org')) {
          return http.Response(crossrefMatchJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2MatchJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'neural optimization', filter: const SearchFilter(maxResults: 5));

      final matching = results.where((p) => p.doi == '10.1000/182').toList();
      expect(matching.length, equals(1), reason: 'DOI match must deduplicate into 1 entry');

      final mergedPaper = matching.first;
      expect(mergedPaper.summary, contains('In this paper we demonstrate 3x speedup'));
      expect(mergedPaper.pdfUrl, equals('https://openaccess.org/papers/10.1000_182.pdf'));
      expect(mergedPaper.categories.contains('Crossref'), isTrue);
      expect(mergedPaper.categories.contains(SearchService.semanticScholarCategory), isTrue);
      expect(mergedPaper.citationCount, equals(45));
    });

    test('Enrichment does NOT overwrite existing valid abstract or valid PDF', () async {
      const arxivFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2103.99999</id>
    <title>High Quality Existing Paper</title>
    <summary>Original highly detailed abstract from the arXiv authors.</summary>
    <published>2021-03-20T00:00:00Z</published>
    <updated>2021-03-20T00:00:00Z</updated>
    <author><name>Author A</name></author>
    <link rel="related" type="application/pdf" href="https://arxiv.org/pdf/2103.99999.pdf"/>
  </entry>
</feed>''';

      const s2DuplicateLesserJson = '''
{
  "total": 1,
  "offset": 0,
  "data": [
    {
      "paperId": "s2_dup_999",
      "title": "High Quality Existing Paper",
      "abstract": null,
      "year": 2021,
      "publicationDate": "2021-03-20",
      "externalIds": {
        "ArXiv": "2103.99999",
        "DOI": "10.48550/arXiv.2103.99999"
      },
      "url": "https://arxiv.org/abs/2103.99999",
      "authors": [{"name": "Author A"}],
      "openAccessPdf": null,
      "citationCount": 5
    }
  ]
}
''';

      final client = MockHttpClient((request) async {
        if (request.url.host.contains('export.arxiv.org')) {
          return http.Response(arxivFeed, 200, headers: {'content-type': 'application/atom+xml'});
        }
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2DuplicateLesserJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'test', filter: const SearchFilter(maxResults: 5));

      final paper = results.firstWhere((p) => p.title == 'High Quality Existing Paper');
      expect(paper.summary, equals('Original highly detailed abstract from the arXiv authors.'));
      expect(paper.pdfUrl, equals('https://arxiv.org/pdf/2103.99999.pdf'));
      expect(paper.doi, equals('10.48550/arXiv.2103.99999'));
      expect(paper.citationCount, equals(5));
    });

    test('Different papers with short titles and different authors are NOT merged', () async {
      const openAlexJson = '''
{
  "results": [
    {
      "id": "https://openalex.org/W1",
      "title": "Deep Learning",
      "authorships": [{"author": {"display_name": "Ian Goodfellow"}}],
      "abstract_inverted_index": {"A": [0], "book": [1], "on": [2], "deep": [3], "learning": [4]},
      "publication_date": "2016-11-18",
      "primary_location": {"landing_page_url": "https://example.com/w1", "pdf_url": ""}
    }
  ]
}
''';

      const s2Json = '''
{
  "total": 1,
  "offset": 0,
  "data": [
    {
      "paperId": "s2_lecun_dl",
      "title": "Deep Learning",
      "abstract": "Deep learning allows computational models composed of multiple processing layers to learn.",
      "year": 2015,
      "publicationDate": "2015-05-28",
      "url": "https://www.semanticscholar.org/paper/s2_lecun_dl",
      "authors": [{"name": "Yann LeCun"}],
      "openAccessPdf": null
    }
  ]
}
''';

      final client = MockHttpClient((request) async {
        if (request.url.host.contains('openalex.org')) {
          return http.Response(openAlexJson, 200, headers: {'content-type': 'application/json'});
        }
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(s2Json, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'deep learning', filter: const SearchFilter(maxResults: 5));

      final dlPapers = results.where((p) => p.title == 'Deep Learning').toList();
      expect(dlPapers.length, equals(2),
          reason: 'Different authors Goodfellow vs LeCun must NOT be merged despite identical short title');
    });
  });

  group('3. Error Isolation and Fault Tolerance Tests', () {
    for (final status in [429, 500, 503]) {
      test('HTTP $status from Semantic Scholar does not fail overall search or drop other sources', () async {
        const mockCrossref = '''
{
  "message": {
    "items": [
      {
        "DOI": "10.1234/cr1",
        "title": ["Crossref Paper Survives Error"],
        "author": [{"given": "John", "family": "Smith"}],
        "abstract": "Valid abstract from Crossref.",
        "created": {"date-time": "2023-01-01T00:00:00Z"},
        "URL": "https://doi.org/10.1234/cr1"
      }
    ]
  }
}
''';

        final client = MockHttpClient((request) async {
          if (request.url.host.contains('semanticscholar.org')) {
            return http.Response('{"message": "Error response from server"}', status);
          }
          if (request.url.host.contains('crossref.org')) {
            return http.Response(mockCrossref, 200, headers: {'content-type': 'application/json'});
          }
          return http.Response('{"results": [], "response": {"docs": []}}', 200);
        });

        final service = SearchService(client: client);
        final results = await service.search(query: 'test', filter: const SearchFilter(maxResults: 5));

        expect(results.isNotEmpty, isTrue, reason: 'Other sources must still return results');
        expect(results.any((p) => p.title == 'Crossref Paper Survives Error'), isTrue);
      });
    }

    test('Timeout on Semantic Scholar does not throw or abort other sources', () async {
      const mockOpenAlex = '''
{
  "results": [
    {
      "id": "https://openalex.org/W_timeout_test",
      "title": "OpenAlex Paper Survives S2 Timeout",
      "authorships": [{"author": {"display_name": "Test Author"}}],
      "abstract_inverted_index": {"Abstract": [0]},
      "publication_date": "2023-01-01",
      "primary_location": {"landing_page_url": "https://example.com", "pdf_url": ""}
    }
  ]
}
''';

      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          throw TimeoutException('Simulated Semantic Scholar timeout');
        }
        if (request.url.host.contains('openalex.org')) {
          return http.Response(mockOpenAlex, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"message": {"items": []}, "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'test', filter: const SearchFilter(maxResults: 5));

      expect(results.any((p) => p.title == 'OpenAlex Paper Survives S2 Timeout'), isTrue);
    });

    test('Malformed HTML response from Semantic Scholar does not throw', () async {
      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response('<html><body>502 Bad Gateway</body></html>', 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'test', filter: const SearchFilter(maxResults: 5));
      expect(results, isNotNull);
    });
  });

  group('4. Federated Search Contract: maxResults and Sorting', () {
    test('maxResults is strictly respected with 5 sources active', () async {
      for (final limit in [3, 5, 8, 10]) {
        final client = MockHttpClient((request) async {
          if (request.url.host.contains('semanticscholar.org')) {
            final papers = List.generate(
              10,
              (i) => {
                'paperId': 's2_$i',
                'title': 'S2 Paper $i unique content',
                'authors': [{'name': 'Author $i'}],
                'publicationDate': '2023-01-0$i',
                'url': 'https://example.com/s2_$i',
              },
            );
            return http.Response(jsonEncode({'total': 10, 'data': papers}), 200);
          }
          return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
        });

        final service = SearchService(client: client);
        final results = await service.search(
          query: 'test',
          filter: SearchFilter(maxResults: limit, sortBy: 'relevance'),
        );

        expect(results.length, equals(limit),
            reason: 'maxResults=$limit must strictly limit total result count');
      }
    });

    test('Sorting by submittedDate correctly orders papers descending', () async {
      final client = MockHttpClient((request) async {
        if (request.url.host.contains('semanticscholar.org')) {
          return http.Response(
            jsonEncode({
              'data': [
                {
                  'paperId': 's2_old',
                  'title': 'Older Paper',
                  'publicationDate': '2019-01-01',
                  'authors': [{'name': 'Author A'}],
                  'url': 'https://example.com/1',
                },
                {
                  'paperId': 's2_new',
                  'title': 'Newer Paper',
                  'publicationDate': '2024-05-01',
                  'authors': [{'name': 'Author B'}],
                  'url': 'https://example.com/2',
                },
              ]
            }),
            200,
          );
        }
        return http.Response('{"message": {"items": []}, "results": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 5, sortBy: 'submittedDate'),
      );

      expect(results.first.title, equals('Newer Paper'));
      expect(results.last.title, equals('Older Paper'));
    });
  });

  group('5. Deep Search, DynamicSourceButton, and Context Evidence Compatibility', () {
    test('DynamicSourceButton correctly recognizes Semantic Scholar domain', () {
      final config = SourceConfig.fromUrl('https://www.semanticscholar.org/paper/12345');
      expect(config, isNotNull);
      expect(config!.label, equals('Open on Semantic Scholar'));
      expect(config.icon, equals(Icons.school_outlined));
    });

    test('Provider recognizes Semantic Scholar paper in evidence retrieval', () {
      final provider = SciChatProvider();
      const s2Paper = ArxivPaper(
        id: 's2_test_paper',
        title: 'Semantic Scholar Context Paper',
        authors: ['Researcher X'],
        summary: 'This is a genuine scientific abstract with sufficient depth and length for testing purposes.',
        published: '2023-01-01',
        updated: '2023-01-01',
        categories: [SearchService.semanticScholarCategory],
        pdfUrl: '',
        absUrl: 'https://www.semanticscholar.org/paper/s2_test_paper',
      );

      provider.setActiveContexts([s2Paper]);
      expect(provider.activePaperContext?.id, equals('s2_test_paper'));

      final evidence = provider.contextEvidence['s2_test_paper'];
      expect(evidence, isNotNull);
      expect(evidence!.level, equals(EvidenceLevel.abstractOnly),
          reason: 'Valid S2 abstract without PDF must yield EvidenceLevel.abstractOnly');
    });

    test('Serialization roundtrip preserves citationCount and referenceCount', () {
      const paper = ArxivPaper(
        id: 's2_serial_test',
        title: 'Serialization Test',
        authors: ['Author 1'],
        summary: 'Valid summary text.',
        published: '2023-01-01',
        updated: '2023-01-01',
        categories: ['Semantic Scholar'],
        pdfUrl: 'https://example.com/test.pdf',
        absUrl: 'https://example.com/test',
        doi: '10.1234/test',
        citationCount: 150,
        referenceCount: 30,
      );

      final jsonMap = paper.toJson();
      expect(jsonMap['citationCount'], equals(150));
      expect(jsonMap['referenceCount'], equals(30));

      final deserialized = ArxivPaper.fromJson(jsonMap);
      expect(deserialized.citationCount, equals(150));
      expect(deserialized.referenceCount, equals(30));
      expect(deserialized.id, equals(paper.id));
    });
  });
}
