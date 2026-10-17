import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/models/models.dart';
import 'package:scichat/services/search_service.dart';

class _TrackingMockClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request, int callCount) handler;
  final List<http.Request> recordedRequests = [];
  int callCount = 0;

  _TrackingMockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = request as http.Request;
    recordedRequests.add(r);
    callCount++;
    final res = await handler(r, callCount);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      request: request,
    );
  }
}

String _sampleCrossrefResponse() => jsonEncode({
      'message': {
        'items': [
          {
            'title': ['Sample Crossref Paper'],
            'DOI': '10.1000/cr1',
            'URL': 'https://doi.org/10.1000/cr1',
            'author': [
              {'given': 'Ada', 'family': 'Lovelace'}
            ],
            'created': {'date-time': '2021-01-01T00:00:00Z'},
            'subject': ['Computer Science'],
          }
        ]
      }
    });

String _sampleOpenAlexResponse() => jsonEncode({
      'results': [
        {
          'id': 'https://openalex.org/W100',
          'title': 'Sample OpenAlex Paper',
          'display_name': 'Sample OpenAlex Paper',
          'publication_date': '2022-01-01',
          'authorships': [
            {
              'author': {'display_name': 'Alan Turing'}
            }
          ],
          'primary_location': {'landing_page_url': 'https://openalex.org/W100', 'pdf_url': ''},
          'doi': 'https://doi.org/10.1000/oa1',
        }
      ]
    });

String _sampleSemanticScholarResponse() => jsonEncode({
      'total': 1,
      'data': [
        {
          'paperId': 's2_100',
          'title': 'Sample Semantic Scholar Paper',
          'abstract': 'Abstract of sample S2 paper.',
          'year': 2023,
          'publicationDate': '2023-05-01',
          'externalIds': {'DOI': '10.1000/s2.1'},
          'url': 'https://www.semanticscholar.org/paper/s2_100',
          'authors': [
            {'name': 'Claude Shannon'}
          ],
          'openAccessPdf': {'url': 'https://example.com/s2.pdf'},
        }
      ]
    });

String _sampleArxivAtom() => '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>http://arxiv.org/abs/2101.00001v1</id>
    <title>Sample arXiv Paper</title>
    <summary>Abstract of sample arXiv paper.</summary>
    <published>2021-01-01T00:00:00Z</published>
    <updated>2021-01-01T00:00:00Z</updated>
    <author><name>John von Neumann</name></author>
    <link rel="alternate" type="text/html" href="http://arxiv.org/abs/2101.00001v1"/>
  </entry>
</feed>''';

String _sampleArchiveSearchResponse() => jsonEncode({
      'response': {
        'numFound': 1,
        'docs': [
          {
            'identifier': 'sample_archive_book',
            'title': 'Sample Archive Treatise',
            'creator': 'Galileo Galilei',
            'description': 'Historical manuscript.',
            'date': '1632-01-01',
          }
        ]
      }
    });

void main() {
  group('Fase 2: Polite Headers & App Identity', () {
    test('Crossref request includes polite User-Agent and mailto parameter', () async {
      final client = _TrackingMockClient((req, count) async {
        return http.Response(_sampleCrossrefResponse(), 200, headers: {'content-type': 'application/json'});
      });

      final service = SearchService(client: client);
      await service.search(query: 'neural networks', onlySource: SearchService.crossrefSource);

      expect(client.recordedRequests, isNotEmpty);
      final req = client.recordedRequests.first;
      expect(req.url.host, contains('crossref.org'));
      expect(req.url.queryParameters['mailto'], equals('mssodikinns@gmail.com'));
      expect(req.headers['User-Agent'] ?? req.headers['user-agent'], contains('SCIChat'));
      expect(req.headers['User-Agent'] ?? req.headers['user-agent'], contains('mailto:mssodikinns@gmail.com'));
    });

    test('OpenAlex request includes mailto parameter and User-Agent', () async {
      final client = _TrackingMockClient((req, count) async {
        return http.Response(_sampleOpenAlexResponse(), 200, headers: {'content-type': 'application/json'});
      });

      final service = SearchService(client: client);
      await service.search(query: 'quantum mechanics', onlySource: SearchService.openAlexSource);

      expect(client.recordedRequests, isNotEmpty);
      final req = client.recordedRequests.first;
      expect(req.url.host, contains('openalex.org'));
      expect(req.url.queryParameters['mailto'], equals('mssodikinns@gmail.com'));
      expect(req.headers['User-Agent'] ?? req.headers['user-agent'], contains('SCIChat'));
    });

    test('arXiv and Semantic Scholar requests include SCIChat User-Agent', () async {
      final client = _TrackingMockClient((req, count) async {
        if (req.url.host.contains('arxiv.org')) {
          return http.Response(_sampleArxivAtom(), 200, headers: {'content-type': 'application/xml'});
        }
        if (req.url.host.contains('semanticscholar.org')) {
          return http.Response(_sampleSemanticScholarResponse(), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200);
      });

      final service = SearchService(client: client);
      await service.search(query: 'deep learning', onlySource: SearchService.arxivSource);
      await service.search(query: 'deep learning', onlySource: SearchService.semanticScholarSource);

      for (final req in client.recordedRequests) {
        expect(req.headers['User-Agent'] ?? req.headers['user-agent'], contains('SCIChat'));
      }
    });
  });

  group('Fase 2: Rate Limit 429 & Retry with Exponential Backoff', () {
    test('429 on first attempt succeeds on retry and returns valid results', () async {
      final delayLog = <Duration>[];
      int attempts = 0;

      final client = _TrackingMockClient((req, count) async {
        if (req.url.host.contains('crossref.org')) {
          attempts++;
          if (attempts == 1) {
            return http.Response('Rate limit exceeded', 429);
          }
          return http.Response(_sampleCrossrefResponse(), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (d) async => delayLog.add(d),
      );

      final results = await service.search(query: 'computing', onlySource: SearchService.crossrefSource);

      expect(attempts, equals(2));
      expect(delayLog, isNotEmpty);
      expect(results, isNotEmpty);
      expect(results.first.title, equals('Sample Crossref Paper'));
      expect(service.lastDiagnostics.httpStatus[SearchService.crossrefSource], equals('200'));
    });

    test('Persistent 429 exhausts retries gracefully without throwing', () async {
      final delayLog = <Duration>[];
      int attempts = 0;

      final client = _TrackingMockClient((req, count) async {
        if (req.url.host.contains('semanticscholar.org')) {
          attempts++;
          return http.Response('Rate limited', 429);
        }
        return http.Response('{}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (d) async => delayLog.add(d),
      );

      final results = await service.search(query: 'transformer', onlySource: SearchService.semanticScholarSource);

      expect(attempts, greaterThanOrEqualTo(2));
      expect(results, isEmpty);
      expect(service.lastDiagnostics.httpStatus[SearchService.semanticScholarSource], equals('429'));
    });

    test('Honors Retry-After header seconds on 429', () async {
      final delayLog = <Duration>[];

      final client = _TrackingMockClient((req, count) async {
        if (count == 1) {
          return http.Response('Rate limit', 429, headers: {'retry-after': '2'});
        }
        return http.Response(_sampleCrossrefResponse(), 200, headers: {'content-type': 'application/json'});
      });

      final service = SearchService(
        client: client,
        delay: (d) async => delayLog.add(d),
      );

      final results = await service.search(query: 'logic', onlySource: SearchService.crossrefSource);

      expect(results, isNotEmpty);
      expect(delayLog, isNotEmpty);
      expect(delayLog.first.inSeconds, equals(2));
    });

    test('Excessive Retry-After (> 5s) aborts retry to protect interactive search latency', () async {
      final delayLog = <Duration>[];
      int attempts = 0;

      final client = _TrackingMockClient((req, count) async {
        attempts++;
        return http.Response('Rate limit', 429, headers: {'retry-after': '60'});
      });

      final service = SearchService(
        client: client,
        delay: (d) async => delayLog.add(d),
      );

      final results = await service.search(query: 'logic', onlySource: SearchService.crossrefSource);

      expect(results, isEmpty);
      expect(attempts, equals(1)); // Aborted retry because 60s is excessive
      expect(delayLog, isEmpty);
      expect(service.lastDiagnostics.httpStatus[SearchService.crossrefSource], equals('429'));
    });
  });

  group('Fase 2: Transient 503 & Network Error Handling', () {
    test('Transient 503 retries and recovers on next attempt', () async {
      int attempts = 0;

      final client = _TrackingMockClient((req, count) async {
        if (req.url.host.contains('openalex.org')) {
          attempts++;
          if (attempts == 1) {
            return http.Response('Service Unavailable', 503);
          }
          return http.Response(_sampleOpenAlexResponse(), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      final results = await service.search(query: 'physics', onlySource: SearchService.openAlexSource);

      expect(attempts, equals(2));
      expect(results, isNotEmpty);
      expect(results.first.title, equals('Sample OpenAlex Paper'));
      expect(service.lastDiagnostics.httpStatus[SearchService.openAlexSource], equals('200'));
    });

    test('Transient network timeout retries and recovers', () async {
      int attempts = 0;

      final client = _TrackingMockClient((req, count) async {
        if (req.url.host.contains('arxiv.org')) {
          attempts++;
          if (attempts == 1) {
            throw TimeoutException('Simulated connection timeout');
          }
          return http.Response(_sampleArxivAtom(), 200, headers: {'content-type': 'application/xml'});
        }
        return http.Response('{}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      final results = await service.search(query: 'cosmology', onlySource: SearchService.arxivSource);

      expect(attempts, equals(2));
      expect(results, isNotEmpty);
      expect(results.first.title, equals('Sample arXiv Paper'));
      expect(service.lastDiagnostics.httpStatus[SearchService.arxivSource], equals('200'));
    });

    test('Permanent 400 Bad Request does NOT retry', () async {
      int attempts = 0;

      final client = _TrackingMockClient((req, count) async {
        attempts++;
        return http.Response('Bad Request syntax', 400);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      final results = await service.search(query: 'syntax error query', onlySource: SearchService.openAlexSource);

      expect(attempts, equals(1)); // Permanent error must not be retried
      expect(results, isEmpty);
      expect(service.lastDiagnostics.httpStatus[SearchService.openAlexSource], equals('400'));
    });
  });

  group('Fase 2: Multi-Source Fault Isolation', () {
    test('Crossref 503 and OpenAlex 429 do NOT stop arXiv, S2, or Internet Archive results', () async {
      final client = _TrackingMockClient((req, count) async {
        final host = req.url.host;
        if (host.contains('crossref.org')) {
          return http.Response('Service Unavailable', 503);
        }
        if (host.contains('openalex.org')) {
          return http.Response('Rate limited', 429);
        }
        if (host.contains('arxiv.org')) {
          return http.Response(_sampleArxivAtom(), 200, headers: {'content-type': 'application/xml'});
        }
        if (host.contains('semanticscholar.org')) {
          return http.Response(_sampleSemanticScholarResponse(), 200, headers: {'content-type': 'application/json'});
        }
        if (host.contains('archive.org')) {
          if (req.url.path.contains('metadata')) {
            return http.Response('{"result": []}', 200);
          }
          return http.Response(_sampleArchiveSearchResponse(), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      final results = await service.search(query: 'unified science');

      // The remaining sources should return papers!
      expect(results, isNotEmpty);
      final sources = results.map((p) => p.sources.first).toSet();
      expect(sources, contains(SearchService.arxivSource));
      expect(sources, contains(SearchService.semanticScholarSource));
      expect(sources, contains(SearchService.archiveSource));

      // Diagnostics accurately reflect each source
      expect(service.lastDiagnostics.httpStatus[SearchService.crossrefSource], equals('503'));
      expect(service.lastDiagnostics.httpStatus[SearchService.openAlexSource], equals('429'));
      expect(service.lastDiagnostics.httpStatus[SearchService.arxivSource], equals('200'));
      expect(service.lastDiagnostics.httpStatus[SearchService.semanticScholarSource], equals('200'));
      expect(service.lastDiagnostics.httpStatus[SearchService.archiveSource], equals('200'));
    });

    test('All sources failing simultaneously produces empty results without throwing', () async {
      final client = _TrackingMockClient((req, count) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = SearchService(
        client: client,
        delay: (_) async {},
      );

      final results = await service.search(query: 'all down');

      expect(results, isEmpty);
      for (final s in [
        SearchService.arxivSource,
        SearchService.crossrefSource,
        SearchService.openAlexSource,
        SearchService.semanticScholarSource,
        SearchService.archiveSource,
      ]) {
        expect(service.lastDiagnostics.httpStatus[s], equals('500'));
      }
    });
  });
}
