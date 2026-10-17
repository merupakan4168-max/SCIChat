// test/arxiv_atom_parsing_test.dart — Regression test for arXiv Atom XML parsing
//
// Verifies:
// 1. Standard metadata (id, title, summary, published, author, category, pdfUrl).
// 2. Elements with correct arXiv namespace URI ('http://arxiv.org/schemas/atom'):
//    - <arxiv:doi>
//    - <arxiv:journal_ref>
// 3. Entries without DOI or journal reference evaluate to null.
// 4. Strict namespace isolation: foreign or unnamespaced <doi>/<journal_ref> tags
//    must NOT be mistakenly captured as arXiv metadata.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/models/models.dart';
import 'package:scichat/services/search_service.dart';

class _MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;
  _MockHttpClient(this.handler);

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
    throw UnimplementedError();
  }
}

void main() {
  group('arXiv Atom XML Parsing Tests', () {
    test('parses standard metadata, arxiv:doi, and arxiv:journal_ref when present', () async {
      const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
  <entry>
    <id>http://arxiv.org/abs/2301.12345v1</id>
    <title>Quantum Computing Advances in 2023</title>
    <summary>We present recent breakthroughs in fault-tolerant quantum computing.</summary>
    <published>2023-01-20T12:00:00Z</published>
    <updated>2023-01-22T15:30:00Z</updated>
    <author>
      <name>Alice Walker</name>
    </author>
    <author>
      <name>Bob Stone</name>
    </author>
    <category term="quant-ph" scheme="http://arxiv.org/schemas/atom"/>
    <link rel="alternate" type="text/html" href="http://arxiv.org/abs/2301.12345v1"/>
    <link rel="related" type="application/pdf" href="http://arxiv.org/pdf/2301.12345v1"/>
    <arxiv:doi>10.1103/PhysRevLett.123.456789</arxiv:doi>
    <arxiv:journal_ref>Phys. Rev. Lett. 123, 456789 (2023)</arxiv:journal_ref>
  </entry>
</feed>''';

      final client = _MockHttpClient((request) async {
        return http.Response(atomXml, 200, headers: {'content-type': 'application/atom+xml'});
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'quantum', onlySource: SearchService.arxivSource);

      expect(results, hasLength(1));
      final paper = results.first;

      expect(paper.id, equals('http://arxiv.org/abs/2301.12345v1'));
      expect(paper.title, equals('Quantum Computing Advances in 2023'));
      expect(paper.authors, equals(['Alice Walker', 'Bob Stone']));
      expect(paper.summary, equals('We present recent breakthroughs in fault-tolerant quantum computing.'));
      expect(paper.published, equals('2023-01-20T12:00:00Z'));
      expect(paper.pdfUrl, equals('http://arxiv.org/pdf/2301.12345v1'));
      expect(paper.doi, equals('10.1103/PhysRevLett.123.456789'),
          reason: '<arxiv:doi> with atom namespace must be parsed correctly into paper.doi');
      expect(paper.journalRef, equals('Phys. Rev. Lett. 123, 456789 (2023)'),
          reason: '<arxiv:journal_ref> with atom namespace must be parsed correctly into paper.journalRef');
    });

    test('handles absence of arxiv:doi and arxiv:journal_ref gracefully', () async {
      const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:arxiv="http://arxiv.org/schemas/atom">
  <entry>
    <id>http://arxiv.org/abs/2301.99999v1</id>
    <title>Preprint Without Publication</title>
    <summary>Pure preprint abstract without peer review publication yet.</summary>
    <published>2023-01-25T10:00:00Z</published>
    <updated>2023-01-25T10:00:00Z</updated>
    <author>
      <name>Carol Danvers</name>
    </author>
    <link rel="alternate" type="text/html" href="http://arxiv.org/abs/2301.99999v1"/>
  </entry>
</feed>''';

      final client = _MockHttpClient((request) async {
        return http.Response(atomXml, 200, headers: {'content-type': 'application/atom+xml'});
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'preprint', onlySource: SearchService.arxivSource);

      expect(results, hasLength(1));
      final paper = results.first;

      expect(paper.title, equals('Preprint Without Publication'));
      expect(paper.doi, isNull, reason: 'Entry without DOI must have paper.doi == null');
      expect(paper.journalRef, isNull, reason: 'Entry without journal_ref must have paper.journalRef == null');
    });

    test('enforces strict namespace isolation: foreign or unnamespaced tags are ignored', () async {
      const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" 
      xmlns:arxiv="http://arxiv.org/schemas/atom"
      xmlns:other="http://example.com/other-schema">
  <entry>
    <id>http://arxiv.org/abs/2301.88888v1</id>
    <title>Namespace Isolation Check</title>
    <summary>Checking that unrelated namespaces do not contaminate arXiv metadata.</summary>
    <published>2023-01-26T08:00:00Z</published>
    <author>
      <name>Eve Adams</name>
    </author>
    <link rel="alternate" type="text/html" href="http://arxiv.org/abs/2301.88888v1"/>
    <!-- Unrelated elements from a different namespace or no namespace -->
    <other:doi>10.9999/foreign-doi</other:doi>
    <other:journal_ref>Foreign Journal of Irreproducible Results</other:journal_ref>
    <doi>10.8888/unnamespaced-doi</doi>
    <journal_ref>Unnamespaced Journal</journal_ref>
  </entry>
</feed>''';

      final client = _MockHttpClient((request) async {
        return http.Response(atomXml, 200, headers: {'content-type': 'application/atom+xml'});
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'isolation', onlySource: SearchService.arxivSource);

      expect(results, hasLength(1));
      final paper = results.first;

      expect(paper.doi, isNull,
          reason: 'Foreign namespace <other:doi> or unnamespaced <doi> must NOT be parsed as arXiv DOI');
      expect(paper.journalRef, isNull,
          reason: 'Foreign namespace <other:journal_ref> or unnamespaced <journal_ref> must NOT be parsed as arXiv journalRef');
    });

    test('uses HTTPS scheme for arXiv API queries to prevent Android cleartext block', () async {
      Uri? capturedSearchUri;
      Uri? capturedFetchByIdUri;

      final client = _MockHttpClient((request) async {
        if (request.url.queryParameters.containsKey('search_query')) {
          capturedSearchUri = request.url;
        } else if (request.url.queryParameters.containsKey('id_list')) {
          capturedFetchByIdUri = request.url;
        }
        return http.Response(
          '<?xml version="1.0" encoding="UTF-8"?><feed xmlns="http://www.w3.org/2005/Atom"></feed>',
          200,
          headers: {'content-type': 'application/atom+xml'},
        );
      });

      final service = SearchService(client: client);
      await service.search(query: 'quantum', onlySource: SearchService.arxivSource);
      await service.fetchById('2301.12345');

      expect(capturedSearchUri, isNotNull);
      expect(capturedSearchUri!.scheme, equals('https'),
          reason: 'arXiv search_query endpoint must use HTTPS to satisfy Android Network Security');
      expect(capturedSearchUri!.host, equals('export.arxiv.org'));
      expect(capturedSearchUri!.path, equals('/api/query'));

      expect(capturedFetchByIdUri, isNotNull);
      expect(capturedFetchByIdUri!.scheme, equals('https'),
          reason: 'arXiv fetchById endpoint must use HTTPS to satisfy Android Network Security');
      expect(capturedFetchByIdUri!.host, equals('export.arxiv.org'));
      expect(capturedFetchByIdUri!.path, equals('/api/query'));
    });
  });
}
