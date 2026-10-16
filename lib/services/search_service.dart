import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/models.dart';

/// Resolved downloadable files for an Internet Archive item.
class _ArchiveFiles {
  final String? pdfUrl;
  final String? textUrl; // OCR plain text (_djvu.txt)
  const _ArchiveFiles({this.pdfUrl, this.textUrl});
}

/// Per-search diagnostic snapshot. Contains only counts, source names and
/// HTTP status codes — never keys, headers or abstracts.
class SearchDiagnostics {
  /// Source label → HTTP status ('200', '429', 'error:TimeoutException', …).
  final Map<String, String> httpStatus = {};

  /// Source label → number of papers parsed from that source.
  final Map<String, int> parsedPerSource = {};
  int candidatesBeforeDedupe = 0;
  int uniqueAfterDedupe = 0;

  /// Source label → papers (by provenance, incl. merged duplicates) in the final list.
  final Map<String, int> finalPerSource = {};
  String? onlySource;
  bool cacheUsed = false;

  /// Source label → papers actually placed into the AI context.
  final Map<String, int> contextPerSource = {};

  @override
  String toString() =>
      'SearchDiagnostics(only=$onlySource, cache=$cacheUsed, http=$httpStatus, '
      'parsed=$parsedPerSource, before=$candidatesBeforeDedupe, '
      'after=$uniqueAfterDedupe, final=$finalPerSource, context=$contextPerSource)';
}

class SearchService {
  static const _arxivBase = 'http://export.arxiv.org/api/query';
  static const _crossrefBase = 'https://api.crossref.org/works';
  static const _openAlexBase = 'https://api.openalex.org/works';
  static const _semanticScholarBase = 'https://api.semanticscholar.org/graph/v1/paper/search';
  static const _archiveSearchBase = 'https://archive.org/advancedsearch.php';
  static const _archiveMetadataBase = 'https://archive.org/metadata';
  static const _archiveFtsBase = 'https://be-api.us.archive.org/ia-pub-fts-api';

  /// Category label used to tag Internet Archive results.
  static const archiveCategory = 'Archive';

  /// Category label used to tag Semantic Scholar results.
  static const semanticScholarCategory = 'Semantic Scholar';

  /// Source labels (stored in [ArxivPaper.sources]).
  static const arxivSource = 'arXiv';
  static const archiveSource = 'Internet Archive';
  static const openAlexSource = 'OpenAlex';
  static const crossrefSource = 'CrossRef';
  static const semanticScholarSource = 'Semantic Scholar';

  final http.Client? _client;
  final Map<String, _ArchiveFiles> _archiveFilesCache = {};

  /// Diagnostics of the most recent [search] call.
  SearchDiagnostics lastDiagnostics = SearchDiagnostics();

  SearchService({http.Client? client}) : _client = client;

  static String? _labelForHost(String host) {
    if (host.contains('arxiv.org')) return arxivSource;
    if (host.contains('crossref.org')) return crossrefSource;
    if (host.contains('openalex.org')) return openAlexSource;
    if (host.contains('semanticscholar.org')) return semanticScholarSource;
    if (host.contains('archive.org')) return archiveSource;
    return null;
  }

  Future<http.Response> _get(Uri uri, {Map<String, String>? headers}) async {
    final label = _labelForHost(uri.host);
    try {
      final response = _client != null
          ? await _client!.get(uri, headers: headers)
          : await http.get(uri, headers: headers);
      if (label != null) {
        lastDiagnostics.httpStatus[label] = response.statusCode.toString();
      }
      return response;
    } catch (e) {
      if (label != null) {
        lastDiagnostics.httpStatus[label] = 'error:${e.runtimeType}';
      }
      rethrow;
    }
  }

  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) {
    if (_client != null) return _client!.post(uri, headers: headers, body: body);
    return http.post(uri, headers: headers, body: body);
  }

  static List<ArxivPaper> _tag(List<ArxivPaper> list, String label) =>
      list.map((p) => p.copyWith(sources: [label])).toList();

  /// Detects an explicit request for papers *originating from* one source,
  /// e.g. "paper dari Semantic Scholar" / "papers from arXiv". Returns the
  /// source label, or null. A mere topical mention ("tentang Semantic Scholar",
  /// "about arXiv") is NOT a source request.
  static String? detectRequestedSource(String text) {
    final t = text.toLowerCase();
    const names = <String, String>{
      r'semantic\s*scholar': semanticScholarSource,
      r'open\s*alex': openAlexSource,
      r'cross\s*ref': crossrefSource,
      r'arxiv': arxivSource,
      r'internet\s*archive|archive\.org': archiveSource,
    };
    for (final entry in names.entries) {
      final n = entry.key;
      final req = RegExp(
        '(berasal dari|bersumber dari|sumber(nya)?( dari)?|dari|from|via|menggunakan|pakai|using|hanya dari|only from)\\s+(sumber\\s+|database\\s+|situs\\s+|layanan\\s+)?($n)',
      );
      final about = RegExp('(tentang|mengenai|membahas|about|regarding|topik)\\s+($n)');
      // Drop purely topical mentions, then look for a source-selection phrase.
      if (req.hasMatch(t.replaceAll(about, ' '))) return entry.value;
    }
    return null;
  }

  /// Removes source-selection phrases from search keywords so the source name
  /// is not used as a topical search term.
  static String stripSourceMentions(String keywords) {
    var k = keywords;
    k = k.replaceAll(
      RegExp(r'\b(semantic\s*scholar|open\s*alex|cross\s*ref|internet\s*archive|arxiv)\b', caseSensitive: false),
      ' ',
    );
    k = k.replaceAll(RegExp(r'\s+'), ' ').trim();
    return k;
  }

  /// Number of distinct papers across [lists] using the same dedupe keys as the
  /// merge (uncapped; used for diagnostics only).
  int _countUnique(List<List<ArxivPaper>> lists) {
    final seen = <String>{};
    int unique = 0;
    for (final list in lists) {
      for (final p in list) {
        final keys = _dedupeKeys(p);
        if (keys.any(seen.contains)) {
          seen.addAll(keys);
        } else {
          seen.addAll(keys);
          unique++;
        }
      }
    }
    return unique;
  }

  /// Searches arXiv, CrossRef, OpenAlex, Semantic Scholar and Internet Archive in parallel.
  ///
  /// [query] may contain arXiv field prefixes (ti:, abs:, au:, cat:) and is
  /// only sent as-is to arXiv. Other sources receive [keywords] (plain text);
  /// if absent, keywords are derived by stripping arXiv syntax from [query].
  ///
  /// [deep] increases per-source quotas and adds Internet Archive full-text
  /// search (searches inside the scanned/OCR'd text of documents).
  /// [onlySource] (a source label such as [semanticScholarSource]) restricts the
  /// search to that single source. When null, all sources are queried (federated).
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    final diag = SearchDiagnostics()..onlySource = onlySource;
    lastDiagnostics = diag;
    var plain = (keywords != null && keywords.trim().isNotEmpty)
        ? keywords.trim()
        : toPlainKeywords(query);
    if (onlySource != null) {
      final stripped = stripSourceMentions(plain);
      if (stripped.isNotEmpty) plain = stripped;
    }

    // Deep Search uses fixed quotas; normal search respects user's maxResults.
    // perSource is sized so that after inter-source deduplication we still have
    // enough candidates to fill the requested limit.
    final int totalLimit = deep ? 24 : filter.maxResults;
    final int perSource = deep ? 8 : ((totalLimit * 3 / 2).ceil()).clamp(3, 15);

    final List<List<ArxivPaper>> results;
    if (onlySource == null) {
      final raw = await Future.wait<List<ArxivPaper>>([
        _searchArxiv(query: query, filter: filter, rows: perSource),
        _searchInternetArchive(keywords: plain, rows: perSource, fullText: deep),
        _searchOpenAlex(keywords: plain, filter: filter, rows: perSource),
        _searchCrossref(keywords: plain, rows: perSource),
        _searchSemanticScholar(keywords: plain, rows: perSource),
      ]);
      const labels = [arxivSource, archiveSource, openAlexSource, crossrefSource, semanticScholarSource];
      results = [for (int i = 0; i < raw.length; i++) _tag(raw[i], labels[i])];
    } else {
      final Future<List<ArxivPaper>> single;
      switch (onlySource) {
        case arxivSource:
          single = _searchArxiv(query: query, filter: filter, rows: perSource);
        case archiveSource:
          single = _searchInternetArchive(keywords: plain, rows: perSource, fullText: deep);
        case openAlexSource:
          single = _searchOpenAlex(keywords: plain, filter: filter, rows: perSource);
        case crossrefSource:
          single = _searchCrossref(keywords: plain, rows: perSource);
        default:
          single = _searchSemanticScholar(keywords: plain, rows: perSource);
      }
      results = [_tag(await single, onlySource)];
    }

    const labelOrder = [arxivSource, archiveSource, openAlexSource, crossrefSource, semanticScholarSource];
    for (final list in results) {
      if (list.isEmpty) continue;
      final label = list.first.sources.first;
      diag.parsedPerSource[label] = list.length;
    }
    for (final l in labelOrder) {
      diag.parsedPerSource.putIfAbsent(l, () => 0);
    }
    if (onlySource != null) {
      diag.parsedPerSource.removeWhere((k, _) => k != onlySource);
    }
    diag.candidatesBeforeDedupe = results.fold<int>(0, (s, l) => s + l.length);

    // Round-robin merge so every source is represented, with metadata enrichment.
    final merged = <ArxivPaper>[];
    final keyToMergedIndex = <String, int>{};
    final maxLen = results.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (int i = 0; i < maxLen && merged.length < totalLimit; i++) {
      for (final list in results) {
        if (i >= list.length) continue;
        final p = list[i];
        final keys = _dedupeKeys(p);

        int? matchIdx;
        for (final k in keys) {
          if (keyToMergedIndex.containsKey(k)) {
            matchIdx = keyToMergedIndex[k];
            break;
          }
        }

        if (matchIdx != null) {
          // Enrich the existing entry with missing/better metadata
          merged[matchIdx] = _enrichPaper(merged[matchIdx], p);
          for (final k in keys) {
            keyToMergedIndex[k] = matchIdx;
          }
        } else if (merged.length < totalLimit) {
          final newIdx = merged.length;
          for (final k in keys) {
            keyToMergedIndex[k] = newIdx;
          }
          merged.add(p);
        }
      }
    }
    diag.uniqueAfterDedupe = _countUnique(results);

    if (filter.sortBy == 'submittedDate') {
      merged.sort((a, b) => _compareDate(b.published, a.published));
    } else if (filter.sortBy == 'lastUpdatedDate') {
      merged.sort((a, b) => _compareDate(b.updated, a.updated));
    }
    // 'relevance': keep round-robin order (each source returns its own
    // relevance-sorted results; no unified cross-source ranking is available).
    for (final p in merged) {
      for (final s in p.sources) {
        diag.finalPerSource[s] = (diag.finalPerSource[s] ?? 0) + 1;
      }
    }
    if (kDebugMode) debugPrint('[SEARCH_DIAG] $diag');
    return merged;
  }

  /// Removes arXiv query syntax so the text works on other search engines.
  static String toPlainKeywords(String query) {
    var q = query;
    q = q.replaceAll(RegExp(r'\bcat:\S+', caseSensitive: false), ' ');
    q = q.replaceAll(RegExp(r'\b(ti|abs|au|all|co|jr|rn|id):', caseSensitive: false), ' ');
    q = q.replaceAll(RegExp(r'\b(AND|OR|ANDNOT|NOT)\b'), ' ');
    q = q.replaceAll(RegExp(r'[()"]'), ' ');
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    return q.isEmpty ? query : q;
  }

  /// Compares two ISO-8601 / partial date strings for descending sort.
  ///
  /// Usage: `merged.sort((paperA, paperB) => _compareDate(paperB.date, paperA.date))`
  ///
  /// When [a] (paperB's date) is unparseable/empty → we want paperB to go last
  ///   → return -1 so comparator places paperA before paperB. ✓
  /// When [b] (paperA's date) is unparseable/empty → we want paperA to go last
  ///   → return +1 so comparator places paperB before paperA. ✓
  static int _compareDate(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null && db == null) return 0;
    if (da == null) return -1; // paperB's date is invalid → paperB goes last
    if (db == null) return 1;  // paperA's date is invalid → paperA goes last
    return da.compareTo(db);
  }

  Set<String> _dedupeKeys(ArxivPaper p) {
    final keys = <String>{};

    // 1. Normalized DOI (Primary key)
    final doi = _normalizeDoi(p.doi);
    if (doi != null) {
      keys.add('doi:$doi');
    }

    // 2. Source-specific identifiers (arXiv ID)
    final arxivId = _extractArxivId(p);
    if (arxivId != null) {
      keys.add('arxiv:$arxivId');
    }

    // 3. Guarded title fallback
    final cleanTitle = p.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (cleanTitle.length >= 15) {
      final firstAuthor = _firstAuthorLastName(p.authors);
      final year = _extractYear(p.published);

      if (firstAuthor != null) {
        keys.add('ta:${cleanTitle}_$firstAuthor');
      }
      if (year != null) {
        keys.add('ty:${cleanTitle}_$year');
      }
      // If title is distinct and long enough (>= 28 chars), allow title key
      if (cleanTitle.length >= 28) {
        keys.add('t:$cleanTitle');
      }
    } else if (cleanTitle.length > 10) {
      final firstAuthor = _firstAuthorLastName(p.authors);
      if (firstAuthor != null) {
        keys.add('ta:${cleanTitle}_$firstAuthor');
      } else {
        keys.add('t:$cleanTitle');
      }
    }

    return keys;
  }

  static String? _normalizeDoi(String? raw) {
    if (raw == null) return null;
    var d = raw.toLowerCase().trim();
    d = d.replaceAll('https://doi.org/', '');
    d = d.replaceAll('http://doi.org/', '');
    d = d.replaceAll('https://dx.doi.org/', '');
    d = d.replaceAll('http://dx.doi.org/', '');
    d = d.replaceAll('doi:', '');
    d = d.trim();
    return d.isNotEmpty ? d : null;
  }

  static String? _extractArxivId(ArxivPaper p) {
    for (final s in [p.id, p.absUrl, p.pdfUrl]) {
      if (s.contains('arxiv.org/abs/') || s.contains('arxiv.org/pdf/')) {
        final match = RegExp(
          r'arxiv\.org\/(abs|pdf)\/([0-9]+\.[0-9]+(v[0-9]+)?|[a-z\-]+(\.[a-z]+)?\/[0-9]+)',
          caseSensitive: false,
        ).firstMatch(s);
        if (match != null && match.group(2) != null) {
          return match.group(2)!.replaceAll(RegExp(r'v[0-9]+$'), '').toLowerCase();
        }
      }
    }
    return null;
  }

  static String? _firstAuthorLastName(List<String> authors) {
    if (authors.isEmpty) return null;
    final first = authors.first.trim();
    if (first.isEmpty || first.toLowerCase() == 'unknown') return null;
    final clean = first.replaceAll(RegExp(r',\s*\d{4}-.*$'), '').trim();
    final parts = clean.split(RegExp(r'\s+'));
    final last = parts.isNotEmpty
        ? parts.last.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase()
        : '';
    return last.length >= 2 ? last : null;
  }

  static String? _extractYear(String published) {
    if (published.length < 4) return null;
    final y = published.substring(0, 4);
    if (RegExp(r'^\d{4}$').hasMatch(y)) return y;
    return null;
  }

  static bool _isAbstractUsable(String summary) {
    final s = summary.trim().toLowerCase();
    if (s.isEmpty) return false;
    if (s.contains('tidak ada abstrak') ||
        s.contains('no abstract available') ||
        s.contains('abstrak tidak tersedia') ||
        s.contains('tidak ada deskripsi') ||
        s == 'abstract' ||
        s == 'none' ||
        s == 'n/a' ||
        s == 'tidak tersedia') {
      return false;
    }
    return s.length >= 20;
  }

  static bool _isDirectPdfUrl(String url) {
    final u = url.trim().toLowerCase();
    if (u.isEmpty) return false;
    return u.endsWith('.pdf') || u.contains('/pdf/') || u.contains('.pdf?');
  }

  ArxivPaper _enrichPaper(ArxivPaper target, ArxivPaper incoming) {
    // 1. DOI
    final targetDoi = _normalizeDoi(target.doi);
    final incomingDoi = _normalizeDoi(incoming.doi);
    final enrichedDoi = (targetDoi == null || targetDoi.isEmpty)
        ? (incomingDoi != null && incomingDoi.isNotEmpty ? incoming.doi : target.doi)
        : target.doi;

    // 2. Abstract
    final targetSummaryValid = _isAbstractUsable(target.summary);
    final incomingSummaryValid = _isAbstractUsable(incoming.summary);
    final enrichedSummary = (!targetSummaryValid && incomingSummaryValid)
        ? incoming.summary
        : (targetSummaryValid ? target.summary : (incoming.summary.isNotEmpty ? incoming.summary : target.summary));

    // 3. PDF URL
    final targetHasPdf = _isDirectPdfUrl(target.pdfUrl);
    final incomingHasPdf = _isDirectPdfUrl(incoming.pdfUrl);
    final enrichedPdfUrl = (!targetHasPdf && incomingHasPdf)
        ? incoming.pdfUrl
        : (target.pdfUrl.isNotEmpty ? target.pdfUrl : incoming.pdfUrl);

    // 4. Authors
    final targetAuthorsUnknown = target.authors.isEmpty ||
        (target.authors.length == 1 && target.authors.first.toLowerCase() == 'unknown');
    final incomingAuthorsUnknown = incoming.authors.isEmpty ||
        (incoming.authors.length == 1 && incoming.authors.first.toLowerCase() == 'unknown');
    final enrichedAuthors = (targetAuthorsUnknown && !incomingAuthorsUnknown)
        ? incoming.authors
        : target.authors;

    // 5. Date
    final targetDateValid = _extractYear(target.published) != null;
    final incomingDateValid = _extractYear(incoming.published) != null;
    final enrichedPublished = (!targetDateValid && incomingDateValid)
        ? incoming.published
        : target.published;
    final enrichedUpdated = (!targetDateValid && incomingDateValid)
        ? incoming.updated
        : target.updated;

    // 6. Categories / Provenance: preserve all sources
    final catSet = <String>{...target.categories};
    for (final c in incoming.categories) {
      if (c.trim().isNotEmpty) catSet.add(c.trim());
    }

    // 7. Citations & References
    final enrichedCitation = target.citationCount ?? incoming.citationCount;
    final enrichedReference = target.referenceCount ?? incoming.referenceCount;

    // 8. JournalRef
    final enrichedJournal = (target.journalRef == null || target.journalRef!.trim().isEmpty)
        ? incoming.journalRef
        : target.journalRef;

    return target.copyWith(
      doi: enrichedDoi,
      summary: enrichedSummary,
      pdfUrl: enrichedPdfUrl,
      authors: enrichedAuthors,
      published: enrichedPublished,
      updated: enrichedUpdated,
      categories: catSet.toList(),
      citationCount: enrichedCitation,
      referenceCount: enrichedReference,
      journalRef: enrichedJournal,
      sources: <String>{...target.sources, ...incoming.sources}.toList(),
    );
  }

  Future<List<ArxivPaper>> fetchTrending() async {
    // Top AI/CS/Physics categories
    const query = 'cat:cs.AI OR cat:cs.CL OR cat:cs.CV OR cat:cs.LG';
    
    final uri = Uri.parse(_arxivBase).replace(queryParameters: {
      'search_query': query,
      'max_results': '10',
      'sortBy': 'submittedDate',
      'sortOrder': 'descending',
    });

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return _parseAtom(response.body);
      }
    } catch (_) {}
    return [];
  }

  Future<List<ArxivPaper>> _searchArxiv({
    required String query,
    required SearchFilter filter,
    required int rows,
  }) async {
    String searchQuery = query;
    if (filter.category != null && filter.category != 'All') {
      searchQuery = 'cat:${filter.category} AND ($query)';
    }

    final uri = Uri.parse(_arxivBase).replace(queryParameters: {
      'search_query': searchQuery,
      'max_results': rows.toString(),
      'sortBy': filter.sortBy,
      'sortOrder': 'descending',
    });

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return _parseAtom(response.body);
      }
    } catch (_) {}
    return [];
  }

  Future<List<ArxivPaper>> _searchCrossref({
    required String keywords,
    required int rows,
  }) async {
    final uri = Uri.parse(_crossrefBase).replace(queryParameters: {
      'query.bibliographic': keywords,
      'select': 'DOI,title,author,abstract,created,URL,subject',
      'rows': rows.toString(),
    });

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return _parseCrossref(response.body);
      }
    } catch (_) {}
    return [];
  }

  Future<List<ArxivPaper>> _searchOpenAlex({
    required String keywords,
    required SearchFilter filter,
    required int rows,
  }) async {
    final uri = Uri.parse(_openAlexBase).replace(queryParameters: {
      'search': keywords,
      'per-page': rows.toString(),
      'sort': filter.sortBy == 'submittedDate' ? 'publication_date:desc' : 'relevance_score:desc',
    });

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return _parseOpenAlex(response.body);
      }
    } catch (_) {}
    return [];
  }

  Future<List<ArxivPaper>> _searchSemanticScholar({
    required String keywords,
    required int rows,
  }) async {
    final cleanKeywords = keywords.trim();
    if (cleanKeywords.isEmpty) return [];

    final uri = Uri.parse(_semanticScholarBase).replace(queryParameters: {
      'query': cleanKeywords,
      'limit': rows.clamp(1, 100).toString(),
      'fields': 'paperId,title,authors,abstract,year,publicationDate,externalIds,url,openAccessPdf,citationCount,referenceCount,venue',
    });

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return _parseSemanticScholar(response.body);
      } else if (response.statusCode == 429) {
        debugPrint('Semantic Scholar rate limit reached (HTTP 429)');
      } else {
        debugPrint('Semantic Scholar HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Semantic Scholar request error: $e');
    }
    return [];
  }

  // ── Internet Archive ──────────────────────────────────────────────────────

  Future<List<ArxivPaper>> _searchInternetArchive({
    required String keywords,
    required int rows,
    bool fullText = false,
  }) async {
    final lists = await Future.wait<List<ArxivPaper>>([
      _searchArchiveMetadata(keywords: keywords, rows: rows),
      if (fullText) _searchArchiveFullText(keywords: keywords, rows: rows),
    ]);

    // Merge metadata + full-text hits (alternating), dedupe by identifier.
    final merged = <ArxivPaper>[];
    final ids = <String>{};
    final maxLen = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (int i = 0; i < maxLen; i++) {
      for (final list in lists) {
        if (i < list.length && ids.add(list[i].id)) merged.add(list[i]);
      }
    }
    final top = merged.take(rows).toList();

    // Resolve real PDF file names (identifier.pdf is often wrong).
    return Future.wait(top.map(_withResolvedPdf));
  }

  Future<List<ArxivPaper>> _searchArchiveMetadata({
    required String keywords,
    required int rows,
  }) async {
    final uri = Uri.parse(_archiveSearchBase).replace(queryParameters: {
      'q': '($keywords) AND mediatype:texts',
      'fl[]': ['identifier', 'title', 'creator', 'description', 'publicdate', 'date'],
      'rows': rows.toString(),
      'output': 'json',
    });

    try {
      final response = await _get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return _parseInternetArchive(response.body);
      }
    } catch (e) {
      print('Internet Archive error: $e');
    }
    return [];
  }

  /// Searches inside the OCR'd text of Internet Archive documents.
  Future<List<ArxivPaper>> _searchArchiveFullText({
    required String keywords,
    required int rows,
  }) async {
    try {
      final response = await _post(
        Uri.parse(_archiveFtsBase),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': '!L $keywords',
          'size': (rows * 2).toString(), // hits are per-file; over-fetch
          'from': '0',
          'scroll': false,
        }),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        return _parseArchiveFullText(response.body);
      }
    } catch (e) {
      print('Internet Archive full-text error: $e');
    }
    return [];
  }

  Future<_ArchiveFiles> _resolveArchiveFiles(String identifier) async {
    final cached = _archiveFilesCache[identifier];
    if (cached != null) return cached;

    var result = const _ArchiveFiles();
    try {
      final uri = Uri.parse('$_archiveMetadataBase/${Uri.encodeComponent(identifier)}/files');
      final response = await _get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final files = (jsonDecode(response.body)['result'] as List?) ?? [];
        String? pdf;
        String? txt;
        for (final f in files) {
          final name = f['name']?.toString() ?? '';
          final format = f['format']?.toString() ?? '';
          if (pdf == null && name.toLowerCase().endsWith('.pdf')) pdf = name;
          if (txt == null && (format == 'DjVuTXT' || name.endsWith('_djvu.txt'))) txt = name;
        }
        String url(String name) =>
            'https://archive.org/download/${Uri.encodeComponent(identifier)}/${Uri.encodeComponent(name)}';
        result = _ArchiveFiles(
          pdfUrl: pdf != null ? url(pdf) : null,
          textUrl: txt != null ? url(txt) : null,
        );
      }
    } catch (e) {
      print('Internet Archive metadata error: $e');
    }
    _archiveFilesCache[identifier] = result;
    return result;
  }

  Future<ArxivPaper> _withResolvedPdf(ArxivPaper p) async {
    final files = await _resolveArchiveFiles(p.id);
    return ArxivPaper(
      id: p.id,
      title: p.title,
      authors: p.authors,
      summary: p.summary,
      published: p.published,
      updated: p.updated,
      categories: p.categories,
      pdfUrl: files.pdfUrl ?? '',
      absUrl: p.absUrl,
      doi: p.doi,
      journalRef: p.journalRef,
    );
  }

  /// Downloads the full text of a paper for deep reading.
  ///
  /// Internet Archive items use the OCR text file (fast, no PDF parsing).
  /// Returns null if no text is available; PDFs are handled by the caller.
  Future<String?> fetchArchiveText(ArxivPaper paper, {int maxChars = 8000}) async {
    if (!paper.categories.contains(archiveCategory)) return null;
    final files = await _resolveArchiveFiles(paper.id);
    if (files.textUrl == null) return null;
    try {
      final response = await _get(Uri.parse(files.textUrl!)).timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final text = utf8.decode(response.bodyBytes, allowMalformed: true)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return text.length > maxChars ? text.substring(0, maxChars) : text;
      }
    } catch (e) {
      print('Internet Archive text download error: $e');
    }
    return null;
  }

  Future<ArxivPaper?> fetchById(String arxivId) async {
    final uri = Uri.parse(_arxivBase).replace(queryParameters: {
      'id_list': arxivId,
    });
    final response = await _get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final papers = _parseAtom(response.body);
    return papers.isNotEmpty ? papers.first : null;
  }

  List<ArxivPaper> _parseCrossref(String jsonStr) {
    final papers = <ArxivPaper>[];
    try {
      final data = jsonDecode(jsonStr);
      final items = data['message']?['items'] as List? ?? [];

      for (var item in items) {
        final titleArr = item['title'] as List?;
        if (titleArr == null || titleArr.isEmpty) continue;
        final title = titleArr.first.toString().replaceAll('\n', ' ').replaceAll(RegExp(r'<[^>]*>'), '').trim();

        final authorArr = item['author'] as List? ?? [];
        final authors = authorArr.map((a) => '${a['given'] ?? ''} ${a['family'] ?? ''}'.trim()).where((a) => a.isNotEmpty).toList();
        if (authors.isEmpty) authors.add('Unknown');

        String abstractText = item['abstract']?.toString() ?? '';
        // Clean up jats xml tags from crossref abstract
        abstractText = abstractText.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (abstractText.isEmpty) {
          abstractText = 'Tidak ada abstrak yang tersedia untuk makalah CrossRef ini.';
        }

        final created = item['created']?['date-time']?.toString() ?? DateTime.now().toIso8601String();
        
        final subjectArr = item['subject'] as List? ?? [];
        final categories = subjectArr.map((s) => s.toString()).toList();
        if (categories.isEmpty) categories.add('Crossref');

        final url = item['URL']?.toString() ?? '';
        final doi = item['DOI']?.toString() ?? '';

        papers.add(ArxivPaper(
          id: doi.isNotEmpty ? doi : url,
          title: title,
          authors: authors,
          summary: abstractText,
          published: created,
          updated: created,
          categories: categories,
          pdfUrl: url,
          absUrl: url,
          doi: doi,
        ));
      }
    } catch (e) {
      print('Crossref parse error: $e');
    }
    return papers;
  }

  List<ArxivPaper> _parseOpenAlex(String jsonStr) {
    final papers = <ArxivPaper>[];
    try {
      final data = jsonDecode(jsonStr);
      final items = data['results'] as List? ?? [];

      for (var item in items) {
        final title = item['title']?.toString().replaceAll('\n', ' ').replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? 'Untitled';
        if (title.isEmpty || title == 'Untitled') continue;

        final authorArr = item['authorships'] as List? ?? [];
        final authors = authorArr.map((a) => a['author']?['display_name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
        if (authors.isEmpty) authors.add('Unknown');

        String abstractText = '';
        final invIndex = item['abstract_inverted_index'];
        if (invIndex != null && invIndex is Map) {
           final words = <int, String>{};
           invIndex.forEach((word, positions) {
             for (var pos in (positions as List)) {
               words[int.parse(pos.toString())] = word.toString();
             }
           });
           if (words.isNotEmpty) {
             final maxPos = words.keys.reduce((a, b) => a > b ? a : b);
             final list = <String>[];
             for (int i = 0; i <= maxPos; i++) {
               list.add(words[i] ?? '');
             }
             abstractText = list.join(' ');
           }
        }
        
        if (abstractText.isEmpty) {
          abstractText = 'Tidak ada abstrak yang tersedia untuk makalah OpenAlex ini.';
        }

        final created = item['publication_date']?.toString() ?? DateTime.now().toIso8601String();
        final primaryLoc = item['primary_location'] ?? {};
        final url = primaryLoc['landing_page_url']?.toString() ?? '';
        final pdfUrl = primaryLoc['pdf_url']?.toString() ?? '';
        final doi = item['doi']?.toString() ?? '';
        final id = item['id']?.toString() ?? '';

        papers.add(ArxivPaper(
          id: id,
          title: title,
          authors: authors,
          summary: abstractText,
          published: created,
          updated: created,
          categories: ['OpenAlex'],
          pdfUrl: pdfUrl,
          absUrl: url.isNotEmpty ? url : doi,
          doi: doi,
        ));
      }
    } catch (e) {
      print('OpenAlex parse error: $e');
    }
    return papers;
  }

  List<ArxivPaper> _parseSemanticScholar(String jsonStr) {
    final papers = <ArxivPaper>[];
    try {
      final data = jsonDecode(jsonStr);
      if (data is! Map) return papers;
      final items = data['data'] as List? ?? [];

      for (var item in items) {
        if (item is! Map) continue;
        final paperId = item['paperId']?.toString().trim() ?? '';
        final rawTitle = item['title']?.toString() ?? '';
        final title = rawTitle
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (title.isEmpty || title.toLowerCase() == 'untitled') continue;

        final authorArr = item['authors'] as List? ?? [];
        final authors = authorArr
            .map((a) => (a is Map ? (a['name']?.toString() ?? '') : a.toString()).trim())
            .where((n) => n.isNotEmpty)
            .toList();
        if (authors.isEmpty) authors.add('Unknown');

        String abstractText = item['abstract']?.toString() ?? '';
        abstractText = abstractText
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (abstractText.isEmpty) {
          abstractText = 'Tidak ada abstrak yang tersedia untuk makalah Semantic Scholar ini.';
        }

        String pubDate = item['publicationDate']?.toString().trim() ?? '';
        if (pubDate.isEmpty && item['year'] != null) {
          pubDate = '${item['year']}-01-01';
        }
        if (pubDate.isEmpty) {
          pubDate = DateTime.now().toIso8601String();
        }

        String pdfUrl = '';
        final openAccess = item['openAccessPdf'];
        if (openAccess is Map && openAccess['url'] != null) {
          final u = openAccess['url'].toString().trim();
          if (u.isNotEmpty) {
            pdfUrl = u;
          }
        }

        final webUrl = item['url']?.toString().trim() ?? '';
        final absUrl = webUrl.isNotEmpty
            ? webUrl
            : (paperId.isNotEmpty
                ? 'https://www.semanticscholar.org/paper/$paperId'
                : '');

        String? doi;
        final extIds = item['externalIds'];
        if (extIds is Map && extIds['DOI'] != null) {
          final d = extIds['DOI'].toString().trim();
          if (d.isNotEmpty) doi = d;
        }

        final venue = item['venue']?.toString().trim();
        final journalRef = (venue != null && venue.isNotEmpty) ? venue : null;

        int? citationCount;
        if (item['citationCount'] is int) {
          citationCount = item['citationCount'] as int;
        } else if (item['citationCount'] != null) {
          citationCount = int.tryParse(item['citationCount'].toString());
        }

        int? referenceCount;
        if (item['referenceCount'] is int) {
          referenceCount = item['referenceCount'] as int;
        } else if (item['referenceCount'] != null) {
          referenceCount = int.tryParse(item['referenceCount'].toString());
        }

        final effectiveId = paperId.isNotEmpty
            ? paperId
            : (doi != null && doi.isNotEmpty ? doi : (absUrl.isNotEmpty ? absUrl : title));

        papers.add(ArxivPaper(
          id: effectiveId,
          title: title,
          authors: authors,
          summary: abstractText,
          published: pubDate,
          updated: pubDate,
          categories: const [semanticScholarCategory],
          pdfUrl: pdfUrl,
          absUrl: absUrl,
          doi: doi,
          journalRef: journalRef,
          citationCount: citationCount,
          referenceCount: referenceCount,
        ));
      }
    } catch (e) {
      debugPrint('Semantic Scholar parse error: $e');
    }
    return papers;
  }

  List<ArxivPaper> _parseInternetArchive(String jsonStr) {
    final papers = <ArxivPaper>[];
    try {
      final data = jsonDecode(jsonStr);
      final docs = data['response']?['docs'] as List? ?? [];

      for (var doc in docs) {
        final identifier = doc['identifier']?.toString() ?? '';
        if (identifier.isEmpty) continue;

        final title = doc['title']?.toString() ?? 'Untitled';
        
        List<String> authors = [];
        if (doc['creator'] is List) {
          authors = (doc['creator'] as List).map((e) => e.toString()).toList();
        } else if (doc['creator'] != null) {
          authors = [doc['creator'].toString()];
        }
        if (authors.isEmpty) authors.add('Unknown');

        String description = '';
        if (doc['description'] is List) {
          description = (doc['description'] as List).join('\n');
        } else if (doc['description'] != null) {
          description = doc['description'].toString();
        }
        description = description.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
        if (description.isEmpty) description = 'Tidak ada deskripsi yang tersedia dari Internet Archive.';

        final date = doc['date']?.toString() ?? doc['publicdate']?.toString() ?? DateTime.now().toIso8601String();

        papers.add(ArxivPaper(
          id: identifier,
          title: title,
          authors: authors,
          summary: description,
          published: date,
          updated: date,
          categories: [archiveCategory],
          pdfUrl: '', // resolved later via metadata API
          absUrl: 'https://archive.org/details/$identifier',
          doi: '',
        ));
      }
    } catch (e) {
      print('Internet Archive parse error: $e');
    }
    return papers;
  }

  List<ArxivPaper> _parseArchiveFullText(String jsonStr) {
    final papers = <ArxivPaper>[];
    final seen = <String>{};
    String first(dynamic v) => v is List ? (v.isNotEmpty ? v.first.toString() : '') : (v?.toString() ?? '');

    try {
      final data = jsonDecode(jsonStr);
      final hits = data['hits']?['hits'] as List? ?? [];

      for (final hit in hits) {
        final fields = hit['fields'] ?? {};
        final identifier = first(fields['identifier']);
        if (identifier.isEmpty || !seen.add(identifier)) continue;

        final title = first(fields['meta_title']);
        final creators = fields['meta_creator'];
        final authors = creators is List
            ? creators.map((e) => e.toString()).toList()
            : <String>[if (creators != null) creators.toString()];
        if (authors.isEmpty) authors.add('Unknown');

        final date = first(fields['meta_date']).isNotEmpty
            ? first(fields['meta_date'])
            : first(fields['meta_publicdate']);

        // Highlighted passages where the query matched inside the document.
        final snippets = ((hit['highlight']?['text'] as List?) ?? [])
            .take(3)
            .map((s) => '…${s.toString().replaceAll('{{{', '').replaceAll('}}}', '').replaceAll('\n', ' ').trim()}…')
            .toList();
        final summary = snippets.isNotEmpty
            ? 'Kutipan dari isi dokumen (full-text):\n${snippets.join('\n')}'
            : 'Ditemukan melalui pencarian isi teks (full-text) Internet Archive.';

        papers.add(ArxivPaper(
          id: identifier,
          title: title.isNotEmpty ? title : identifier,
          authors: authors,
          summary: summary,
          published: date.isNotEmpty ? date : DateTime.now().toIso8601String(),
          updated: date.isNotEmpty ? date : DateTime.now().toIso8601String(),
          categories: [archiveCategory],
          pdfUrl: '',
          absUrl: 'https://archive.org/details/$identifier',
          doi: '',
        ));
      }
    } catch (e) {
      print('Internet Archive full-text parse error: $e');
    }
    return papers;
  }

  List<ArxivPaper> _parseAtom(String xml) {
    final doc = XmlDocument.parse(xml);
    final entries = doc.findAllElements('entry');
    final papers = <ArxivPaper>[];

    for (final entry in entries) {
      try {
        final id = _text(entry, 'id');
        final title = _text(entry, 'title').replaceAll('\n', ' ').trim();
        final summary = _text(entry, 'summary').replaceAll('\n', ' ').trim();
        final published = _text(entry, 'published');
        final updated = _text(entry, 'updated');

        final authors = entry
            .findAllElements('author')
            .map((a) => _childText(a, 'name'))
            .where((n) => n.isNotEmpty)
            .toList();

        final categories = entry
            .findAllElements('category')
            .map((c) => c.getAttribute('term') ?? '')
            .where((t) => t.isNotEmpty)
            .toList();

        String pdfUrl = '';
        String absUrl = id;
        for (final link in entry.findAllElements('link')) {
          final rel = link.getAttribute('rel') ?? '';
          final type = link.getAttribute('type') ?? '';
          final href = link.getAttribute('href') ?? '';
          if (rel == 'related' && type == 'application/pdf') {
            pdfUrl = href;
          }
          if (rel == 'alternate') {
            absUrl = href;
          }
        }
        if (pdfUrl.isEmpty && id.isNotEmpty) {
          final shortId = id.replaceAll('http://arxiv.org/abs/', '');
          pdfUrl = 'https://arxiv.org/pdf/$shortId';
        }

        final doi = _text(entry, 'arxiv:doi', namespace: 'http://arxiv.org/schemas/atom');
        final journalRef = _text(entry, 'arxiv:journal_ref', namespace: 'http://arxiv.org/schemas/atom');

        papers.add(ArxivPaper(
          id: id,
          title: title,
          authors: authors,
          summary: summary,
          published: published,
          updated: updated,
          categories: categories,
          pdfUrl: pdfUrl,
          absUrl: absUrl,
          doi: doi,
          journalRef: journalRef,
        ));
      } catch (_) {}
    }
    return papers;
  }

  String _text(XmlElement node, String tag, {String? namespace}) {
    final elements = node.findElements(tag, namespace: namespace);
    if (elements.isEmpty) return '';
    return elements.first.innerText.trim();
  }

  String _childText(XmlElement node, String tag) {
    final elements = node.findElements(tag);
    if (elements.isEmpty) return '';
    return elements.first.innerText.trim();
  }
}
