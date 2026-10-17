// metadata_export_integrity_test.dart — Stage 1 tests for Phase 1
//
// Tests:
// 1. Metadata and provenance preservation in Internet Archive PDF resolution
// 2. Consistent DOI normalization (with/without URL prefixes)
// 3. Crossref landing page URL is not treated as direct PDF URL
// 4. BibTeX and APA 7 accuracy across arXiv, Crossref, OpenAlex, Semantic Scholar, and Internet Archive
// 5. Fallback safety when metadata is missing (no hallucinated values)

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Internet Archive PDF Resolution Metadata & Provenance Preservation', () {
    test('Resolving PDF preserves sources, citationCount, referenceCount, and all other metadata', () async {
      final client = _MockHttpClient((request) async {
        if (request.url.path.contains('/files')) {
          // IA files metadata response
          final body = jsonEncode({
            'result': [
              {'name': 'item_paper.pdf', 'format': 'Text PDF'},
              {'name': 'item_djvu.txt', 'format': 'DjVuTXT'},
            ]
          });
          return http.Response(body, 200);
        }
        if (request.url.host.contains('archive.org')) {
          final searchBody = jsonEncode({
            'response': {
              'docs': [
                {
                  'identifier': 'item123',
                  'title': 'Historical Science Document',
                  'creator': ['Dr. Jane Doe'],
                  'description': 'A rare document from archive.',
                  'date': '1950-01-01',
                }
              ]
            }
          });
          return http.Response(searchBody, 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "data": []}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(
        query: 'historical science',
        onlySource: SearchService.archiveSource,
      );

      expect(results, isNotEmpty);
      final paper = results.first;

      expect(paper.id, equals('item123'));
      expect(paper.title, equals('Historical Science Document'));
      expect(paper.authors, equals(['Dr. Jane Doe']));
      expect(paper.pdfUrl, equals('https://archive.org/download/item123/item_paper.pdf'));
      expect(paper.sources, equals([SearchService.archiveSource]),
          reason: 'sources provenance must contain Internet Archive');
    });

    test('Enriched Internet Archive paper retains citationCount and referenceCount after PDF resolution', () async {
      // Simulate an IA paper that already has citationCount & referenceCount
      const initial = ArxivPaper(
        id: 'ia_book_1',
        title: 'Archive Book',
        authors: ['Author One'],
        summary: 'Summary of archive book',
        published: '1975-01-01',
        updated: '1975-01-01',
        categories: [SearchService.archiveCategory],
        pdfUrl: '',
        absUrl: 'https://archive.org/details/ia_book_1',
        doi: '10.1000/ia.1',
        journalRef: 'Historical Review',
        citationCount: 42,
        referenceCount: 15,
        sources: [SearchService.archiveSource],
      );

      final client = _MockHttpClient((request) async {
        return http.Response(jsonEncode({
          'result': [
            {'name': 'ia_book_1.pdf', 'format': 'Text PDF'},
          ]
        }), 200);
      });

      final service = SearchService(client: client);
      final resolved = await service.resolveArchivePdf(initial);

      expect(resolved.pdfUrl, equals('https://archive.org/download/ia_book_1/ia_book_1.pdf'));
      expect(resolved.sources, equals([SearchService.archiveSource]),
          reason: 'sources must not be cleared during PDF resolution');
      expect(resolved.citationCount, equals(42),
          reason: 'citationCount must not be lost during PDF resolution');
      expect(resolved.referenceCount, equals(15),
          reason: 'referenceCount must not be lost during PDF resolution');
      expect(resolved.journalRef, equals('Historical Review'));
      expect(resolved.doi, equals('10.1000/ia.1'));
    });
  });

  group('2. Consistent DOI Normalization', () {
    test('Normalizes various DOI formats to canonical bare DOI', () {
      expect(ArxivPaper.normalizeDoi('10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('https://doi.org/10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('http://doi.org/10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('https://dx.doi.org/10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('http://dx.doi.org/10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('doi: 10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('DOI:10.1000/182'), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi('   10.1000/182   '), equals('10.1000/182'));
      expect(ArxivPaper.normalizeDoi(''), isNull);
      expect(ArxivPaper.normalizeDoi('   '), isNull);
      expect(ArxivPaper.normalizeDoi(null), isNull);
    });

    test('ArxivPaper.fromJson normalizes DOI from serialized data or cache', () {
      final jsonWithUrlDoi = {
        'id': 'p1',
        'title': 'Test Title',
        'authors': ['Author'],
        'summary': 'Summary',
        'published': '2023-01-01',
        'updated': '2023-01-01',
        'categories': ['cs.AI'],
        'pdfUrl': '',
        'absUrl': 'https://doi.org/10.1000/182',
        'doi': 'https://doi.org/10.1000/182',
      };

      final paper = ArxivPaper.fromJson(jsonWithUrlDoi);
      expect(paper.doi, equals('10.1000/182'),
          reason: 'fromJson must normalize DOI so no https://doi.org/ prefix is stored');
    });

    test('OpenAlex parser normalizes doi field from full URL', () async {
      final openAlexResponse = jsonEncode({
        'results': [
          {
            'id': 'https://openalex.org/W2741809807',
            'title': 'Attention Is All You Need',
            'doi': 'https://doi.org/10.48550/arxiv.1706.03762',
            'publication_date': '2017-06-12',
            'authorships': [
              {'author': {'display_name': 'Ashish Vaswani'}}
            ],
            'primary_location': {
              'landing_page_url': 'https://arxiv.org/abs/1706.03762',
              'pdf_url': 'https://arxiv.org/pdf/1706.03762.pdf',
            },
          }
        ]
      });

      final client = _MockHttpClient((request) async {
        if (request.url.host.contains('openalex.org')) {
          return http.Response(openAlexResponse, 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "data": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'attention', onlySource: SearchService.openAlexSource);

      expect(results, isNotEmpty);
      expect(results.first.doi, equals('10.48550/arxiv.1706.03762'),
          reason: 'OpenAlex DOI must be normalized without URL prefix');
    });
  });

  group('3. Crossref Parser: Landing Page vs Direct PDF URL', () {
    test('Crossref landing page URL is NOT mapped to pdfUrl', () async {
      final crossrefJson = jsonEncode({
        'message': {
          'items': [
            {
              'title': ['Sample Article in Journal of Computing'],
              'DOI': '10.1016/j.comp.2021.05.001',
              'URL': 'https://doi.org/10.1016/j.comp.2021.05.001', // Landing page, NOT a direct PDF
              'author': [
                {'given': 'John', 'family': 'Smith'}
              ],
              'created': {'date-time': '2021-05-15T00:00:00Z'},
              'subject': ['Computer Science'],
            }
          ]
        }
      });

      final client = _MockHttpClient((request) async {
        if (request.url.host.contains('crossref.org')) {
          return http.Response(crossrefJson, 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "data": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'computing', onlySource: SearchService.crossrefSource);

      expect(results, isNotEmpty);
      final paper = results.first;
      expect(paper.absUrl, equals('https://doi.org/10.1016/j.comp.2021.05.001'));
      expect(paper.pdfUrl, isEmpty,
          reason: 'A DOI landing page must not be stored as direct PDF URL in Crossref');
      expect(paper.doi, equals('10.1016/j.comp.2021.05.001'));
    });

    test('Crossref parser keeps pdfUrl only if the link is a direct PDF', () async {
      final crossrefJson = jsonEncode({
        'message': {
          'items': [
            {
              'title': ['Open Access Report with Direct PDF'],
              'DOI': '10.1000/direct.pdf.1',
              'URL': 'https://example.org/documents/report.pdf', // Direct PDF URL
              'author': [
                {'given': 'Alan', 'family': 'Turing'}
              ],
              'created': {'date-time': '2020-01-01T00:00:00Z'},
            }
          ]
        }
      });

      final client = _MockHttpClient((request) async {
        if (request.url.host.contains('crossref.org')) {
          return http.Response(crossrefJson, 200);
        }
        return http.Response('{"message": {"items": []}, "results": [], "data": [], "response": {"docs": []}}', 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'turing', onlySource: SearchService.crossrefSource);

      expect(results, isNotEmpty);
      expect(results.first.pdfUrl, equals('https://example.org/documents/report.pdf'));
    });
  });

  group('4. BibTeX & APA 7 Format Accuracy Across Sources', () {
    test('arXiv paper BibTeX has archivePrefix={arXiv} and eprint; APA mentions arXiv', () {
      const arxivPaper = ArxivPaper(
        id: 'http://arxiv.org/abs/2301.00001v1',
        title: 'Deep Learning Advances',
        authors: ['Alice Smith', 'Bob Jones'],
        summary: 'A study on deep learning.',
        published: '2023-01-15T00:00:00Z',
        updated: '2023-01-15T00:00:00Z',
        categories: ['cs.LG'],
        pdfUrl: 'https://arxiv.org/pdf/2301.00001.pdf',
        absUrl: 'http://arxiv.org/abs/2301.00001',
        doi: '10.48550/arXiv.2301.00001',
        sources: ['arXiv'],
      );

      final bib = arxivPaper.bibtex;
      expect(bib, contains('@article{Smith2023,'));
      expect(bib, contains('archivePrefix={arXiv}'));
      expect(bib, contains('eprint={2301.00001v1}'));
      expect(bib, contains('primaryClass={cs.LG}'));

      final apa = arxivPaper.apa;
      expect(apa, contains('Alice Smith, & Bob Jones (2023). Deep Learning Advances. arXiv. http://arxiv.org/abs/2301.00001'));
    });

    test('Internet Archive item BibTeX is @book without archivePrefix; APA mentions Internet Archive', () {
      const iaPaper = ArxivPaper(
        id: 'philosophiaenatu00newt',
        title: 'Philosophiae Naturalis Principia Mathematica',
        authors: ['Sir Isaac Newton'],
        summary: 'Classic physics treatise.',
        published: '1687-07-05',
        updated: '1687-07-05',
        categories: ['Archive', 'Book'],
        pdfUrl: 'https://archive.org/download/principia/principia.pdf',
        absUrl: 'https://archive.org/details/philosophiaenatu00newt',
        sources: ['Internet Archive'],
      );

      final bib = iaPaper.bibtex;
      expect(bib, contains('@book{Newton1687,'));
      expect(bib, isNot(contains('archivePrefix')));
      expect(bib, isNot(contains('eprint')));
      expect(bib, contains('url={https://archive.org/details/philosophiaenatu00newt}'));

      final apa = iaPaper.apa;
      expect(apa, contains('Sir Isaac Newton (1687). Philosophiae Naturalis Principia Mathematica. Internet Archive. https://archive.org/details/philosophiaenatu00newt'));
    });

    test('CrossRef journal paper BibTeX is @article WITHOUT archivePrefix or fake eprint; APA mentions venue/CrossRef', () {
      const crossrefPaper = ArxivPaper(
        id: '10.1038/nature12345',
        title: 'A Breakthrough in Quantum Teleportation',
        authors: ['Marie Curie', 'Pierre Curie'],
        summary: 'Experimental demonstration in nature.',
        published: '2022-04-10',
        updated: '2022-04-10',
        categories: ['Physics'],
        pdfUrl: '',
        absUrl: 'https://doi.org/10.1038/nature12345',
        doi: '10.1038/nature12345',
        journalRef: 'Nature 580',
        sources: ['CrossRef'],
      );

      final bib = crossrefPaper.bibtex;
      expect(bib, contains('@article{Curie2022,'));
      expect(bib, isNot(contains('archivePrefix')));
      expect(bib, isNot(contains('eprint')));
      expect(bib, contains('journal={Nature 580}'));
      expect(bib, contains('doi={10.1038/nature12345}'));

      final apa = crossrefPaper.apa;
      expect(apa, isNot(contains('. arXiv.')));
      expect(apa, contains('Nature 580'));
      expect(apa, contains('10.1038/nature12345'));
    });

    test('Semantic Scholar paper BibTeX does not claim arXiv provenance when not on arXiv', () {
      const s2Paper = ArxivPaper(
        id: 's2_conference_paper',
        title: 'Language Modeling with Transformers',
        authors: ['Colin Raffel'],
        summary: 'T5 transfer learning.',
        published: '2020-01-01',
        updated: '2020-01-01',
        categories: ['Semantic Scholar'],
        pdfUrl: 'https://aclanthology.org/2020.acl.pdf',
        absUrl: 'https://www.semanticscholar.org/paper/s2_conference_paper',
        doi: '10.18653/v1/2020.acl-main.1',
        journalRef: 'ACL 2020',
        sources: ['Semantic Scholar'],
      );

      final bib = s2Paper.bibtex;
      expect(bib, contains('@article{Raffel2020,'));
      expect(bib, isNot(contains('archivePrefix={arXiv}')));
      expect(bib, isNot(contains('eprint')));
      expect(bib, contains('doi={10.18653/v1/2020.acl-main.1}'));
      expect(bib, contains('journal={ACL 2020}'));

      final apa = s2Paper.apa;
      expect(apa, isNot(contains('. arXiv.')));
      expect(apa, contains('ACL 2020'));
    });

    test('OpenAlex paper BibTeX and APA without journalRef falls back safely to source without arXiv hallucination', () {
      const oaPaper = ArxivPaper(
        id: 'https://openalex.org/W999',
        title: 'Studies in Modern Linguistics',
        authors: ['Noam Chomsky'],
        summary: 'Syntax structures.',
        published: '2019-06-01',
        updated: '2019-06-01',
        categories: ['OpenAlex'],
        pdfUrl: '',
        absUrl: 'https://openalex.org/W999',
        doi: '10.1017/cbo9780511804533',
        sources: ['OpenAlex'],
      );

      final bib = oaPaper.bibtex;
      expect(bib, isNot(contains('archivePrefix={arXiv}')));
      expect(bib, isNot(contains('eprint')));
      expect(bib, contains('doi={10.1017/cbo9780511804533}'));

      final apa = oaPaper.apa;
      expect(apa, isNot(contains('arXiv')));
      expect(apa, contains('openalex.org'));
      expect(apa, isNot(contains('. OpenAlex.')));
    });
  });

  group('5. Fallback Safety for Incomplete Metadata', () {
    test('Paper with empty authors and unparseable year generates valid fallback citeKey and APA', () {
      const incompletePaper = ArxivPaper(
        id: 'unknown_01',
        title: 'Mysterious Manuscript',
        authors: [],
        summary: 'No abstract.',
        published: 'circa-medieval',
        updated: 'circa-medieval',
        categories: ['OpenAlex'],
        pdfUrl: '',
        absUrl: 'https://example.com/manuscript',
        sources: ['OpenAlex'],
      );

      final bib = incompletePaper.bibtex;
      expect(bib, contains('@article{paperunknown,'));
      expect(bib, contains('author={Unknown}'));
      expect(bib, contains('year={unknown}'));
      expect(bib, isNot(contains('archivePrefix')));

      final apa = incompletePaper.apa;
      expect(apa, contains('Unknown (n.d.). Mysterious Manuscript.'));
    });
  });
}
