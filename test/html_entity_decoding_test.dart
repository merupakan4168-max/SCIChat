// html_entity_decoding_test.dart — Tahap 1: dekoding HTML entity pada ingestion
// CrossRef dan Internet Archive.

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
    final response = await handler(request as http.Request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

const _emptyBody =
    '{"message": {"items": []}, "results": [], "response": {"docs": []}, "data": [], "hits": {"hits": []}}';

void main() {
  group('SearchService.decodeHtmlEntities', () {
    test(r'1. $\lambda &gt;0$ -> $\lambda >0$', () {
      expect(SearchService.decodeHtmlEntities(r'$\lambda &gt;0$'),
          r'$\lambda >0$');
    });

    test(r'2. $B&lt;B_{1}$ -> $B<B_{1}$', () {
      expect(SearchService.decodeHtmlEntities(r'$B&lt;B_{1}$'), r'$B<B_{1}$');
    });

    test('3. AT&T dan R&D tanpa titik koma tetap utuh', () {
      expect(SearchService.decodeHtmlEntities('AT&T'), 'AT&T');
      expect(SearchService.decodeHtmlEntities('R&D and AT&T Labs'),
          'R&D and AT&T Labs');
      // Ampersand diikuti kata lalu titik koma yang bukan entity dikenal
      expect(SearchService.decodeHtmlEntities('AT&T; wins'), 'AT&T; wins');
      expect(SearchService.decodeHtmlEntities('a &unknownentity; b'),
          'a &unknownentity; b');
    });

    test('4. &amp;lt; hanya didekode SATU kali menjadi &lt;', () {
      expect(SearchService.decodeHtmlEntities('&amp;lt;'), '&lt;');
      expect(
          SearchService.decodeHtmlEntities('&amp;gt;&amp;amp;'), '&gt;&amp;');
      expect(SearchService.decodeHtmlEntities('&#38;lt;'), '&lt;');
    });

    test('5. Entity bernama dasar: quot, apos, amp, minus', () {
      expect(SearchService.decodeHtmlEntities('&quot;x&quot; &apos;y&apos;'),
          '"x" \'y\'');
      expect(SearchService.decodeHtmlEntities('a &amp; b'), 'a & b');
      expect(
          SearchService.decodeHtmlEntities(r'$&minus;\infty$'), r'$-\infty$');
    });

    test('6. Entity numerik desimal dan heksadesimal yang valid', () {
      expect(SearchService.decodeHtmlEntities('&#39;'), "'");
      expect(SearchService.decodeHtmlEntities('&#60;&#62;'), '<>');
      expect(SearchService.decodeHtmlEntities('&#x3bb;'), 'λ');
      expect(SearchService.decodeHtmlEntities('&#X3BB;'), 'λ');
      expect(SearchService.decodeHtmlEntities('&#8722;'), '\u2212');
      expect(SearchService.decodeHtmlEntities('&#x1F600;'), '\u{1F600}');
    });

    test('7. Entity numerik tidak valid dibiarkan apa adanya', () {
      expect(SearchService.decodeHtmlEntities('&#0;'), '&#0;');
      expect(SearchService.decodeHtmlEntities('&#xD800;'), '&#xD800;');
      expect(SearchService.decodeHtmlEntities('&#1114112;'), '&#1114112;');
      expect(SearchService.decodeHtmlEntities('&#1;'), '&#1;');
      expect(SearchService.decodeHtmlEntities('&#xZZ;'), '&#xZZ;');
      expect(SearchService.decodeHtmlEntities('&#;'), '&#;');
      expect(SearchService.decodeHtmlEntities('&#99999999;'), '&#99999999;');
    });

    test('8. Teks tanpa ampersand dan string kosong tidak berubah', () {
      expect(SearchService.decodeHtmlEntities(''), '');
      expect(SearchService.decodeHtmlEntities(r'$x_{1} < y$'), r'$x_{1} < y$');
      expect(SearchService.decodeHtmlEntities('B->K*mu+mu-'), 'B->K*mu+mu-');
    });
  });

  group('Ingestion: CrossRef & Internet Archive', () {
    test('9. CrossRef: judul dan abstrak didekode setelah tag JATS dibuang',
        () async {
      final crossrefBody = jsonEncode({
        'message': {
          'items': [
            {
              'DOI': '10.14492/hokmj/1277472866',
              'title': [
                r'Asymptotic behavior of positive solutions with $\alpha &lt;0$ and $\lambda &gt;0$ <i>AT&T</i>'
              ],
              'author': [
                {'given': 'Ichiro', 'family': 'TSUKAMOTO'}
              ],
              'abstract':
                  r'<jats:p>In the case $\lambda &gt;0$, if $B&lt;B_{1}$ and $B&amp;lt;1$ then &#x3bb; &amp; AT&T.</jats:p>',
              'created': {'date-time': '2013-11-19T00:00:00Z'},
              'URL': 'https://doi.org/10.14492/hokmj/1277472866',
              'subject': <String>[],
            }
          ]
        }
      });

      final client = _MockHttpClient((request) async {
        if (request.url.host.contains('crossref.org')) {
          return http.Response(crossrefBody, 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response(_emptyBody, 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(
        query: 'asymptotic behavior positive solutions',
        filter: const SearchFilter(maxResults: 5),
      );
      final paper = results.firstWhere(
        (p) => p.sources.contains(SearchService.crossrefSource),
        orElse: () => throw Exception('CrossRef paper not found'),
      );

      expect(paper.title,
          r'Asymptotic behavior of positive solutions with $\alpha <0$ and $\lambda >0$ AT&T');
      expect(paper.summary, contains(r'$\lambda >0$'));
      expect(paper.summary, contains(r'$B<B_{1}$'));
      // &amp;lt; hanya satu kali didekode -> &lt;
      expect(paper.summary, contains(r'$B&lt;1$'));
      expect(paper.summary, contains('λ & AT&T.'));
      expect(paper.summary, isNot(contains('<jats')));
      expect(paper.summary, isNot(contains('&gt;')));
    });

    test('10. Internet Archive: judul dan deskripsi didekode', () async {
      final archiveBody = jsonEncode({
        'response': {
          'docs': [
            {
              'identifier': 'arxiv-entity-test',
              'title':
                  r'Power corrections &amp; observables with $\lambda &gt;0$',
              'creator': ['Some Author'],
              'description':
                  r'<p>Case $B&lt;B_{1}$ and AT&T &quot;quoted&quot; &#39;x&#39; &amp;lt; literal</p>',
              'date': '2014-07-31T00:00:00Z',
            }
          ]
        }
      });

      final client = _MockHttpClient((request) async {
        if (request.url.host == 'archive.org' &&
            request.url.path.contains('advancedsearch')) {
          return http.Response(archiveBody, 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response(_emptyBody, 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(
        query: 'power corrections observables',
        filter: const SearchFilter(maxResults: 5),
      );
      final paper = results.firstWhere(
        (p) => p.sources.contains(SearchService.archiveSource),
        orElse: () => throw Exception('Internet Archive paper not found'),
      );

      expect(paper.title, r'Power corrections & observables with $\lambda >0$');
      expect(paper.summary, contains(r'$B<B_{1}$'));
      expect(paper.summary, contains('AT&T "quoted" \'x\' &lt; literal'));
      expect(paper.summary, isNot(contains('<p>')));
    });
  });
}
