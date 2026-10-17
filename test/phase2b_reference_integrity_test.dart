// phase2b_reference_integrity_test.dart — Regression test suite for Phase 2B (Tahap 2A)
//
// Target vulnerabilities under audit:
// 1. Identical DOI with conflicting titles/authors (e.g. conference volume DOIs)
// 2. Generic editorial / preface titles with unknown authors
// 3. Semantic Scholar openAccessPdf URL: direct PDF vs HTML landing page
// 4. arXiv ID scheme handling (http:// vs https:// and short ID)
// 5. Summarization safeguard when abstract and document text are absent
// 6. APA 7 aggregator name pollution and ISO publication date precision in enrichment

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:scichat/models/models.dart';
import 'package:scichat/services/gemini_service.dart';
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

ArxivPaper _makeSyntheticPaper({
  required String id,
  required String title,
  List<String> authors = const ['Author Name'],
  String published = '2023-01-01',
  String? doi,
  String summary = 'Standard scientific abstract text for synthetic fixture testing.',
  String pdfUrl = '',
  String absUrl = '',
  String? journalRef,
  List<String> sources = const ['arXiv'],
  List<String> categories = const ['cs.AI'],
}) {
  return ArxivPaper(
    id: id,
    title: title,
    authors: authors,
    summary: summary,
    published: published,
    updated: published,
    categories: categories,
    pdfUrl: pdfUrl,
    absUrl: absUrl.isNotEmpty ? absUrl : (doi != null ? 'https://doi.org/$doi' : id),
    doi: doi,
    journalRef: journalRef,
    sources: sources,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── 1. DOI Sama Tetapi Judul / Penulis Bertentangan ─────────────────────────
  group('1. Identical DOI with Conflicting Titles / Authors', () {
    test('1.1 canMerge rejects two papers sharing a volume DOI when titles and authors conflict', () {
      final paperA = _makeSyntheticPaper(
        id: 'proc_vol_paper_1',
        title: 'Advancements in Quantum Error Correction and Fault Tolerance',
        authors: ['Raymond Laflamme', 'Emanuel Knill'],
        doi: '10.1007/978-3-030-volume-1',
        summary: 'We present quantum threshold theorems for fault-tolerant gates.',
        sources: ['CrossRef'],
      );

      final paperB = _makeSyntheticPaper(
        id: 'proc_vol_paper_2',
        title: 'Tropical Soil Microbial Diversity and Nitrogen Cycling',
        authors: ['Siti Aminah', 'Budi Santoso'],
        doi: '10.1007/978-3-030-volume-1', // Identical volume/proceedings DOI
        summary: 'Metagenomic analysis of soil bacteria in tropical rainforests.',
        sources: ['OpenAlex'],
      );

      // Contract: canMerge must be FALSE because titles and authors conflict completely
      final result = SearchService.canMerge(paperA, paperB);
      expect(result, isFalse,
          reason: 'Papers with identical proceedings DOI but contradictory titles/authors must NOT be merged');
    });

    test('1.2 canMerge accepts two papers sharing DOI when title and authors match', () {
      final paperA = _makeSyntheticPaper(
        id: 'p1',
        title: 'Attention Is All You Need',
        authors: ['Ashish Vaswani', 'Noam Shazeer'],
        doi: '10.48550/arxiv.1706.03762',
        sources: ['arXiv'],
      );

      final paperB = _makeSyntheticPaper(
        id: 'p2',
        title: 'Attention is all you need',
        authors: ['Ashish Vaswani', 'Niki Parmar'],
        doi: '10.48550/arXiv.1706.03762',
        sources: ['Semantic Scholar'],
      );

      expect(SearchService.canMerge(paperA, paperB), isTrue,
          reason: 'Matching DOI with compatible title and first author must merge safely');
    });

    test('1.3 enrichPaper does NOT corrupt abstract when canMerge rejects conflicting DOI papers', () {
      final quantumPaper = _makeSyntheticPaper(
        id: 'q1',
        title: 'Quantum Hamiltonian Simulation',
        authors: ['Seth Lloyd'],
        doi: '10.1000/shared-doi-1',
        summary: '', // Empty abstract
        pdfUrl: '',
      );

      final bioPaper = _makeSyntheticPaper(
        id: 'b1',
        title: 'Photosynthesis In Marine Algae',
        authors: ['Robert Emerson'],
        doi: '10.1000/shared-doi-1', // Same DOI
        summary: 'Detailed experimental study on chlorophyll excitation.',
        pdfUrl: 'https://example.org/algae.pdf',
      );

      final service = SearchService();
      final enriched = service.enrichPaper(quantumPaper, bioPaper);

      // If canMerge correctly rejects, quantumPaper is returned untouched without algae abstract
      expect(enriched.summary, isNot(equals(bioPaper.summary)),
          reason: 'Abstract of algae paper must not contaminate quantum paper');
      expect(enriched.pdfUrl, isNot(equals(bioPaper.pdfUrl)),
          reason: 'PDF of algae paper must not contaminate quantum paper');
    });
  });

  // ── 2. Judul Editorial Generik dengan Penulis Tidak Diketahui ───────────────
  group('2. Generic Editorial / Preface Titles with Unknown Authors', () {
    test('2.1 canMerge rejects merging generic editorial titles when author is unknown', () {
      final editorialA = _makeSyntheticPaper(
        id: 'ia_editorial_1',
        title: 'Editorial: Special Issue on Emerging Technologies and Society',
        authors: ['Unknown'],
        published: '2022-01-01',
        doi: null,
        sources: ['Internet Archive'],
      );

      final editorialB = _makeSyntheticPaper(
        id: 'cr_editorial_2',
        title: 'Editorial: Special Issue on Emerging Technologies and Society',
        authors: ['John Smith'],
        published: '2022-06-01',
        doi: '10.1016/j.emtech.2022.01.001',
        sources: ['CrossRef'],
      );

      // Contract: Length >= 20 alone must not merge generic editorial titles across different journals
      final result = SearchService.canMerge(editorialA, editorialB);
      expect(result, isFalse,
          reason: 'Generic editorial titles without author match must not be merged across different venues');
    });

    test('2.2 canMerge accepts non-generic distinct titles with unknown author if title is sufficiently distinctive', () {
      final specificPaperA = _makeSyntheticPaper(
        id: 'rec1',
        title: 'Topological Quantum Memory in Three-Dimensional Toric Code Models',
        authors: ['Unknown'],
        published: '2021-05-01',
        doi: null,
      );

      final specificPaperB = _makeSyntheticPaper(
        id: 'rec2',
        title: 'Topological Quantum Memory in Three-Dimensional Toric Code Models',
        authors: ['Claudio Chamon'],
        published: '2021-08-01',
        doi: '10.1103/physrevb.71.195103',
      );

      // Distinct scientific monograph/paper title can merge when one source lacks author
      expect(SearchService.canMerge(specificPaperA, specificPaperB), isTrue);
    });
  });

  // ── 3. URL Semantic Scholar: PDF Langsung vs Landing Page HTML ──────────────
  group('3. Semantic Scholar Parser: Direct PDF vs HTML Landing Page', () {
    test('3.1 Semantic Scholar parser does NOT assign HTML landing page URL to pdfUrl', () async {
      final s2JsonWithLandingPage = jsonEncode({
        'data': [
          {
            'paperId': 's2_item_1',
            'title': 'Machine Learning in Medical Diagnostics',
            'abstract': 'We survey ML methods for clinical imaging.',
            'year': 2023,
            'publicationDate': '2023-03-01',
            'url': 'https://www.semanticscholar.org/paper/s2_item_1',
            'openAccessPdf': {
              // Landing page, NOT direct PDF
              'url': 'https://university.edu/repository/handle/12345/article-landing',
              'status': 'GOLD',
            },
            'authors': [{'name': 'Dr. Alice Wong'}],
          }
        ]
      });

      final client = _MockHttpClient((request) async {
        return http.Response(s2JsonWithLandingPage, 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(
        query: 'medical diagnostics',
        onlySource: SearchService.semanticScholarSource,
      );

      expect(results, isNotEmpty);
      final paper = results.first;
      // Contract: An HTML landing page must NOT be populated into pdfUrl
      expect(paper.pdfUrl, isEmpty,
          reason: 'Landing page URL from Semantic Scholar must not be assigned to pdfUrl without direct PDF check');
    });

    test('3.2 Semantic Scholar parser keeps direct PDF URL ending in .pdf', () async {
      final s2JsonWithDirectPdf = jsonEncode({
        'data': [
          {
            'paperId': 's2_item_2',
            'title': 'Convolutional Networks for Speech Recognition',
            'abstract': 'Direct PDF experiment.',
            'year': 2021,
            'publicationDate': '2021-01-01',
            'url': 'https://www.semanticscholar.org/paper/s2_item_2',
            'openAccessPdf': {
              'url': 'https://example.org/papers/speech_cnn.pdf',
              'status': 'HYBRID',
            },
            'authors': [{'name': 'Geoffrey Hinton'}],
          }
        ]
      });

      final client = _MockHttpClient((request) async {
        return http.Response(s2JsonWithDirectPdf, 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(
        query: 'speech recognition',
        onlySource: SearchService.semanticScholarSource,
      );

      expect(results, isNotEmpty);
      expect(results.first.pdfUrl, equals('https://example.org/papers/speech_cnn.pdf'),
          reason: 'Direct PDF URL must be preserved');
    });
  });

  // ── 4. ID arXiv Berskema HTTPS & URL PDF ────────────────────────────────────
  group('4. arXiv ID Schemes (http://, https://, and Short ID)', () {
    test('4.1 shortId correctly strips https:// scheme from arXiv id', () {
      final paperHttps = _makeSyntheticPaper(
        id: 'https://arxiv.org/abs/2301.00001v1',
        title: 'Test Paper Https',
      );

      // Contract: shortId should be '2301.00001v1', not 'https://arxiv.org/abs/2301.00001v1'
      expect(paperHttps.shortId, equals('2301.00001v1'),
          reason: 'shortId getter must handle both https:// and http:// prefixes');
    });

    test('4.2 BibTeX eprint uses clean short ID for https:// arXiv paper', () {
      final paperHttps = _makeSyntheticPaper(
        id: 'https://arxiv.org/abs/2301.00001v1',
        title: 'Deep Learning Advances',
        authors: ['Alice Smith'],
        sources: ['arXiv'],
      );

      final bib = paperHttps.bibtex;
      expect(bib, contains('eprint={2301.00001v1}'),
          reason: 'BibTeX eprint field must not contain https:// URL');
      expect(bib, isNot(contains('eprint={https://')),
          reason: 'BibTeX eprint must never contain URL prefix');
    });

    test('4.3 arXiv Atom parser builds correct pdfUrl when entry id uses https://', () async {
      const atomXml = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>https://arxiv.org/abs/2301.00001v1</id>
    <title>Deep Learning Advances</title>
    <summary>A study on deep learning.</summary>
    <published>2023-01-15T00:00:00Z</published>
    <updated>2023-01-15T00:00:00Z</updated>
    <author><name>Alice Smith</name></author>
    <link rel="alternate" type="text/html" href="https://arxiv.org/abs/2301.00001v1"/>
  </entry>
</feed>''';

      final client = _MockHttpClient((request) async {
        return http.Response(atomXml, 200);
      });

      final service = SearchService(client: client);
      final results = await service.search(query: 'deep learning', onlySource: SearchService.arxivSource);

      expect(results, isNotEmpty);
      final paper = results.first;
      // Contract: pdfUrl must be 'https://arxiv.org/pdf/2301.00001v1', NOT 'https://arxiv.org/pdf/https://arxiv.org/abs/...'
      expect(paper.pdfUrl, equals('https://arxiv.org/pdf/2301.00001v1'),
          reason: 'pdfUrl fallback must strip https:// prefix cleanly');
    });
  });

  // ── 5. Rangkuman Tanpa Abstrak Maupun Teks Dokumen ──────────────────────────
  group('5. Summarization Safeguard for Papers Lacking Evidence', () {
    test('5.1 formatPapersContext flags paper without usable abstract explicitly', () {
      final papers = [
        _makeSyntheticPaper(
          id: 'cr_no_abs',
          title: 'A Study on Industrial Policy',
          summary: 'Tidak ada abstrak yang tersedia untuk makalah CrossRef ini.',
        ),
      ];

      final contextText = GeminiService.formatPapersContext(papers);
      expect(contextText, contains('Abstrak tidak tersedia'),
          reason: 'formatPapersContext must not pass placeholder text as genuine abstract');
    });

    test('5.2 Prompt instructions guard against fabricating findings for text-less papers', () {
      // System prompt must include explicit instruction that absent info must be stated as absent
      final prompt = GeminiService.systemPrompt;
      expect(prompt, contains('Informasi yang tidak tersedia:'),
          reason: 'System prompt must instruct model to acknowledge absent details');
      expect(prompt, contains('nyatakan secara jujur dan transparan bahwa detail tersebut tidak tercantum'),
          reason: 'System prompt must forbid inventing details missing from abstract/context');
    });
  });

  // ── 6. Sitasi APA/BibTeX dan Presisi Tanggal Publikasi ──────────────────────
  group('6. Citations (APA / BibTeX) & Publication Date Precision', () {
    test('6.1 APA 7 citation does NOT list search aggregator names as journal venue', () {
      final paperAggregators = _makeSyntheticPaper(
        id: 'agg_paper_1',
        title: 'Foundations of Cryptography',
        authors: ['Oded Goldreich'],
        published: '2004-01-01',
        doi: '10.1017/cbo9780511546891',
        sources: ['Semantic Scholar', 'OpenAlex'],
        categories: ['Semantic Scholar', 'OpenAlex'],
        journalRef: null, // No journal specified
      );

      final apa = paperAggregators.apa;
      // Contract: 'Semantic Scholar, OpenAlex' must NOT be displayed as the publication venue
      expect(apa, isNot(contains('. Semantic Scholar, OpenAlex.')),
          reason: 'Search engines / aggregators are not publication venues in APA 7');
      expect(apa, isNot(contains('. Semantic Scholar.')),
          reason: 'Semantic Scholar alone is not a journal name');
    });

    test('6.2 enrichPaper prefers precise ISO publication date over coarse year-only string', () {
      final targetCoarseDate = _makeSyntheticPaper(
        id: 'item_1',
        title: 'Quantum Field Theory in Curved Spacetime',
        authors: ['Robert Wald'],
        published: '1994', // Year only
        sources: ['Internet Archive'],
      );

      final incomingPreciseDate = _makeSyntheticPaper(
        id: 'item_1_exact',
        title: 'Quantum Field Theory in Curved Spacetime',
        authors: ['Robert Wald'],
        published: '1994-06-15T00:00:00Z', // Exact ISO timestamp
        sources: ['CrossRef'],
      );

      final service = SearchService();
      final enriched = service.enrichPaper(targetCoarseDate, incomingPreciseDate);

      // Contract: If publication year matches, enrichPaper should preserve the more complete date
      expect(enriched.published, equals('1994-06-15T00:00:00Z'),
          reason: 'Higher-precision date must not be discarded in favor of a coarse 4-digit year');
    });

    test('6.3 BibTeX export for non-book Internet Archive items does not force @book when type is unspecified', () {
      final iaArticle = _makeSyntheticPaper(
        id: 'ia_article_001',
        title: 'Technical Report on Network Packet Routing Protocols',
        authors: ['David Clark'],
        published: '1988-08-01',
        sources: ['Internet Archive'],
        categories: ['Archive'],
        absUrl: 'https://archive.org/details/ia_article_001',
      );

      final bib = iaArticle.bibtex;
      // Many IA items are reports or articles. Forcing @book creates invalid BibTeX without publisher/book fields
      expect(bib, isNot(contains('@book')),
          reason: 'Internet Archive technical items should not be unconditionally classified as @book');
    });
  });
}
