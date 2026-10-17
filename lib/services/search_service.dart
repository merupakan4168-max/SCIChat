import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
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

class _ScoredPaper {
  final ArxivPaper paper;
  final double score;
  final int originalIndex;
  const _ScoredPaper(this.paper, this.score, this.originalIndex);
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
  static const _arxivBase = 'https://export.arxiv.org/api/query';
  static const _crossrefBase = 'https://api.crossref.org/works';
  static const _openAlexBase = 'https://api.openalex.org/works';
  static const _semanticScholarBase = 'https://api.semanticscholar.org/graph/v1/paper/search';
  static const _archiveSearchBase = 'https://archive.org/advancedsearch.php';
  static const _archiveMetadataBase = 'https://archive.org/metadata';
  static const _archiveFtsBase = 'https://be-api.us.archive.org/ia-pub-fts-api';

  /// Polite identity headers for Crossref, OpenAlex, and public literature APIs.
  static const appUserAgent = 'SCIChat/1.0 (https://github.com/merupakan4168-max/SCIChat; mailto:mssodikinns@gmail.com)';
  static const politeEmail = 'mssodikinns@gmail.com';

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
  final Future<void> Function(Duration) _delay;
  final Map<String, _ArchiveFiles> _archiveFilesCache = {};

  /// Diagnostics of the most recent [search] call.
  SearchDiagnostics lastDiagnostics = SearchDiagnostics();

  SearchService({
    http.Client? client,
    Future<void> Function(Duration)? delay,
  })  : _client = client,
        _delay = delay ?? Future.delayed;

  static String? _labelForHost(String host) {
    if (host.contains('arxiv.org')) return arxivSource;
    if (host.contains('crossref.org')) return crossrefSource;
    if (host.contains('openalex.org')) return openAlexSource;
    if (host.contains('semanticscholar.org')) return semanticScholarSource;
    if (host.contains('archive.org')) return archiveSource;
    return null;
  }

  Map<String, String> _buildHeaders({Map<String, String>? extra}) {
    final h = <String, String>{'User-Agent': appUserAgent};
    if (extra != null) h.addAll(extra);
    return h;
  }

  Duration? _parseRetryAfter(String? header) {
    if (header == null) return null;
    final trimmed = header.trim();
    if (trimmed.isEmpty) return null;
    final seconds = int.tryParse(trimmed);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds);
    }
    final date = DateTime.tryParse(trimmed);
    if (date != null) {
      final diff = date.difference(DateTime.now());
      if (!diff.isNegative) return diff;
    }
    return null;
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 15),
    int maxRetries = 2,
    Duration initialDelay = const Duration(milliseconds: 250),
  }) async {
    final label = _labelForHost(uri.host);
    int attempts = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      attempts++;
      try {
        final reqHeaders = _buildHeaders(extra: headers);
        final future = _client != null
            ? _client!.get(uri, headers: reqHeaders)
            : http.get(uri, headers: reqHeaders);
        final response = await future.timeout(timeout);

        final status = response.statusCode;
        final isTransient = (status == 429 || status == 503 || status == 502 || status == 504);

        if (isTransient && attempts <= maxRetries) {
          Duration waitDuration = currentDelay;
          final retryAfter = _parseRetryAfter(response.headers['retry-after']);
          if (retryAfter != null) {
            if (retryAfter.inSeconds > 5) {
              // Retry-After is too long for interactive search; abort retry
              if (label != null) {
                lastDiagnostics.httpStatus[label] = status.toString();
              }
              return response;
            }
            waitDuration = retryAfter;
          }
          if (label != null) {
            lastDiagnostics.httpStatus[label] = status.toString();
          }
          await _delay(waitDuration);
          currentDelay *= 2;
          continue;
        }

        if (label != null) {
          lastDiagnostics.httpStatus[label] = status.toString();
        }
        return response;
      } catch (e) {
        final isTransientError = e is TimeoutException ||
            e is http.ClientException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection');

        if (isTransientError && attempts <= maxRetries) {
          await _delay(currentDelay);
          currentDelay *= 2;
          continue;
        }

        if (label != null) {
          lastDiagnostics.httpStatus[label] = 'error:${e.runtimeType}';
        }
        rethrow;
      }
    }
  }

  Future<http.Response> _post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
    int maxRetries = 2,
    Duration initialDelay = const Duration(milliseconds: 250),
  }) async {
    final label = _labelForHost(uri.host);
    int attempts = 0;
    Duration currentDelay = initialDelay;

    while (true) {
      attempts++;
      try {
        final reqHeaders = _buildHeaders(extra: headers);
        final future = _client != null
            ? _client!.post(uri, headers: reqHeaders, body: body)
            : http.post(uri, headers: reqHeaders, body: body);
        final response = await future.timeout(timeout);

        final status = response.statusCode;
        final isTransient = (status == 429 || status == 503 || status == 502 || status == 504);

        if (isTransient && attempts <= maxRetries) {
          if (label != null) {
            lastDiagnostics.httpStatus[label] = status.toString();
          }
          await _delay(currentDelay);
          currentDelay *= 2;
          continue;
        }

        if (label != null) {
          lastDiagnostics.httpStatus[label] = status.toString();
        }
        return response;
      } catch (e) {
        final isTransientError = e is TimeoutException ||
            e is http.ClientException ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection');

        if (isTransientError && attempts <= maxRetries) {
          await _delay(currentDelay);
          currentDelay *= 2;
          continue;
        }

        if (label != null) {
          lastDiagnostics.httpStatus[label] = 'error:${e.runtimeType}';
        }
        rethrow;
      }
    }
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

  /// Number of distinct papers across [lists] using the same dedupe rules as the
  /// merge (uncapped; used for diagnostics only).
  int _countUnique(List<List<ArxivPaper>> lists) {
    final unique = <ArxivPaper>[];
    for (final list in lists) {
      for (final p in list) {
        if (!unique.any((u) => canMerge(u, p))) {
          unique.add(p);
        }
      }
    }
    return unique.length;
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
    final maxLen = results.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (int i = 0; i < maxLen && merged.length < totalLimit; i++) {
      for (final list in results) {
        if (i >= list.length) continue;
        final p = list[i];

        int matchIdx = -1;
        for (int m = 0; m < merged.length; m++) {
          if (canMerge(merged[m], p)) {
            matchIdx = m;
            break;
          }
        }

        if (matchIdx != -1) {
          // Enrich the existing entry with missing/better metadata
          merged[matchIdx] = _enrichPaper(merged[matchIdx], p);
        } else if (merged.length < totalLimit) {
          merged.add(p);
        }
      }
    }
    diag.uniqueAfterDedupe = _countUnique(results);

    if (filter.sortBy == 'submittedDate') {
      merged.sort((a, b) => _compareDate(b.published, a.published));
    } else if (filter.sortBy == 'lastUpdatedDate') {
      merged.sort((a, b) => _compareDate(b.updated, a.updated));
    } else if (onlySource == null) {
      final ranked = rankPapersByRelevance(merged, plain.isNotEmpty ? plain : query);
      merged
        ..clear()
        ..addAll(ranked);
    }
    for (final p in merged) {
      for (final s in p.sources) {
        diag.finalPerSource[s] = (diag.finalPerSource[s] ?? 0) + 1;
      }
    }
    if (kDebugMode) debugPrint('[SEARCH_DIAG] $diag');
    return merged;
  }

  static const _stopWords = <String>{
    // English
    'a', 'an', 'the', 'and', 'or', 'of', 'in', 'on', 'at', 'to', 'for',
    'with', 'by', 'from', 'about', 'as', 'into', 'like', 'through', 'after',
    'over', 'between', 'out', 'against', 'during', 'without', 'before',
    'under', 'around', 'among', 'is', 'are', 'was', 'were', 'be', 'been',
    'being', 'have', 'has', 'had', 'do', 'does', 'did', 'this', 'that',
    'these', 'those', 'it', 'its', 'can', 'could', 'will', 'would', 'should',
    'effect', 'effects', 'affect', 'affects', 'study', 'studies', 'paper', 'papers',
    // Indonesian
    'dan', 'atau', 'dari', 'ke', 'di', 'pada', 'untuk', 'dengan', 'yang',
    'ini', 'itu', 'tentang', 'adalah', 'sebagai', 'dalam', 'oleh', 'olehnya',
    'antara', 'setelah', 'sebelum', 'tanpa', 'terhadap', 'bisa', 'dapat',
    'efek', 'pengaruh', 'studi', 'kajian',
  };

  /// Computes a deterministic local relevance score for [paper] against [query].
  ///
  /// Criteria:
  /// - Exact phrase in title (dominant): +100 to +170 pts.
  /// - Keywords in title: +25 pts per token, up to +30 coverage bonus.
  /// - Exact phrase in abstract: +20 pts.
  /// - Keywords in abstract: up to 9 pts per token, +15 coverage bonus.
  /// - Stop words are filtered out to prevent false matches on generic words.
  /// - PDF availability gives 0 bonus.
  /// - Citations & recency give minor tie-breaker bonus (max 4 pts) ONLY if relevance > 0.
  static double computeRelevanceScore(ArxivPaper paper, String query) {
    final cleanQuery = toPlainKeywords(query).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanQuery.length < 2) return 0.0;

    final queryWords = cleanQuery
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((w) => w.isNotEmpty)
        .toList();

    if (queryWords.isEmpty) return 0.0;

    var meaningfulTokens = queryWords.where((w) => !_stopWords.contains(w) && w.length > 1).toList();
    if (meaningfulTokens.isEmpty) {
      meaningfulTokens = queryWords;
    }

    final title = paper.title.toLowerCase();
    final cleanTitle = title.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final summary = paper.summary.toLowerCase();
    final cleanSummary = summary.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    double score = 0.0;

    // 1. Title Matching (Dominant)
    final hasExactPhraseInTitle = cleanTitle.contains(cleanQuery);
    if (hasExactPhraseInTitle) {
      score += 100.0;
      if (cleanTitle == cleanQuery) {
        score += 50.0; // Perfect full title match
      } else if (cleanTitle.startsWith(cleanQuery)) {
        score += 20.0;
      }
    }

    int titleTokenMatches = 0;
    for (final token in meaningfulTokens) {
      final tokenRegex = RegExp(r'\b' + RegExp.escape(token) + r'\b');
      if (tokenRegex.hasMatch(cleanTitle)) {
        titleTokenMatches++;
        score += 25.0;
      } else if (cleanTitle.contains(token)) {
        score += 10.0;
      }
    }

    if (meaningfulTokens.isNotEmpty && titleTokenMatches > 0) {
      final coverage = titleTokenMatches / meaningfulTokens.length;
      score += coverage * 30.0;
    }

    // 2. Summary / Abstract Matching (Secondary)
    final hasExactPhraseInSummary = cleanSummary.isNotEmpty && cleanSummary.contains(cleanQuery);
    if (hasExactPhraseInSummary) {
      score += 20.0;
    }

    int summaryTokenMatches = 0;
    for (final token in meaningfulTokens) {
      final tokenRegex = RegExp(r'\b' + RegExp.escape(token) + r'\b');
      final matches = tokenRegex.allMatches(cleanSummary).length;
      if (matches > 0) {
        summaryTokenMatches++;
        score += matches.clamp(1, 3) * 3.0;
      }
    }

    if (meaningfulTokens.length > 1 && summaryTokenMatches == meaningfulTokens.length) {
      score += 15.0; // All keywords appear in abstract
    }

    // 3. Minor Secondary Tie-breakers (Strictly capped; only if paper has topic relevance)
    if (score > 0) {
      if (paper.citationCount != null && paper.citationCount! > 0) {
        final logCitations = math.log(1 + paper.citationCount!) / math.ln10;
        score += (logCitations * 0.5).clamp(0.0, 3.0);
      }
      final pubYear = int.tryParse(RegExp(r'\b\d{4}\b').firstMatch(paper.published)?.group(0) ?? '');
      if (pubYear != null && (DateTime.now().year - pubYear) <= 2) {
        score += 1.0;
      }
    }

    return score;
  }

  /// Re-ranks a list of papers by relevance against [query], breaking ties stably.
  static List<ArxivPaper> rankPapersByRelevance(List<ArxivPaper> papers, String query) {
    if (papers.isEmpty) return [];
    final scored = <_ScoredPaper>[];
    for (int i = 0; i < papers.length; i++) {
      scored.add(_ScoredPaper(papers[i], computeRelevanceScore(papers[i], query), i));
    }
    scored.sort((a, b) {
      final diff = b.score.compareTo(a.score);
      if (diff != 0) return diff;
      return a.originalIndex.compareTo(b.originalIndex); // Stable tie-breaker
    });
    return scored.map((e) => e.paper).toList();
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

  /// Determines whether two paper records refer to the exact same scientific work
  /// and can be safely merged without metadata corruption.
  @visibleForTesting
  static bool canMerge(ArxivPaper a, ArxivPaper b) {
    // 1. Conflict guard: If both have valid DOIs that differ, they CANNOT be merged.
    final doiA = ArxivPaper.normalizeDoi(a.doi)?.toLowerCase();
    final doiB = ArxivPaper.normalizeDoi(b.doi)?.toLowerCase();
    if (doiA != null && doiB != null && doiA != doiB) {
      return false;
    }

    // 2. Positive DOI match: identical valid DOIs -> check for volume/proceedings conflict
    if (doiA != null && doiB != null && doiA == doiB) {
      // Must not merge if titles conflict completely (e.g. conference volume DOIs)
      final titleSim = _titleTokenSimilarity(a.title, b.title);
      if (titleSim < 0.35) {
        return false;
      }

      // Check author compatibility
      final authorsA = _extractAuthorLastNames(a.authors);
      final authorsB = _extractAuthorLastNames(b.authors);
      if (authorsA.isNotEmpty && authorsB.isNotEmpty && authorsA.intersection(authorsB).isEmpty) {
        return false;
      }
      return true;
    }

    // 3. arXiv ID check
    final arxivA = _extractArxivId(a);
    final arxivB = _extractArxivId(b);
    if (arxivA != null && arxivB != null) {
      if (arxivA == arxivB) return true;
      // Conflicting arXiv IDs -> different preprints
      return false;
    }

    // 4. Title, Author, and Year matching when DOI is missing on one or both
    // Disallow generic titles (editorial, preface, erratum, corrigendum, book review) from title-based merge
    if (_isGenericTitle(a.title) || _isGenericTitle(b.title)) {
      return false;
    }

    final cleanTitleA = a.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanTitleB = b.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Titles must be substantial (at least 10 alphanumeric chars) and match exactly
    if (cleanTitleA.length < 10 || cleanTitleB.length < 10) return false;
    if (cleanTitleA != cleanTitleB) return false;

    // Check author compatibility
    final authorA = _firstAuthorLastName(a.authors);
    final authorB = _firstAuthorLastName(b.authors);
    final hasBothAuthors = authorA != null && authorB != null;

    // If both records specify a known first author, they MUST match
    if (hasBothAuthors && authorA != authorB) {
      return false;
    }

    // Check publication year compatibility (allow at most 1 year difference for preprint-to-journal publication lag)
    final yearA = int.tryParse(_extractYear(a.published) ?? '');
    final yearB = int.tryParse(_extractYear(b.published) ?? '');
    if (yearA != null && yearB != null) {
      if ((yearA - yearB).abs() > 1) {
        return false;
      }
    }

    // If both authors are known and match, titles match, and years compatible:
    if (hasBothAuthors && authorA == authorB) {
      return true;
    }

    // If one author is missing/unknown, require distinct title length >= 20 and compatible year
    if (cleanTitleA.length >= 20 && yearA != null && yearB != null && (yearA - yearB).abs() <= 1) {
      return true;
    }

    return false;
  }

  static double _titleTokenSimilarity(String a, String b) {
    final tokensA = a
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 2)
        .toSet();
    final tokensB = b
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length >= 2)
        .toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;
    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    final jaccard = union > 0 ? intersection / union : 0.0;
    final minLen = tokensA.length < tokensB.length ? tokensA.length : tokensB.length;
    final overlapCoeff = minLen > 0 ? intersection / minLen : 0.0;
    return jaccard > overlapCoeff ? jaccard : overlapCoeff;
  }

  static Set<String> _extractAuthorLastNames(List<String> authors) {
    final result = <String>{};
    for (final a in authors) {
      final clean = a.trim();
      if (clean.isEmpty || clean.toLowerCase() == 'unknown') continue;
      final stripped = clean.replaceAll(RegExp(r',\s*\d{4}-.*$'), '').trim();
      final parts = stripped.split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        final last = parts.last.replaceAll(RegExp(r'[^a-zA-Z]'), '').toLowerCase();
        if (last.length >= 2) {
          result.add(last);
        }
      }
    }
    return result;
  }

  static bool _isGenericTitle(String title) {
    final lower = title.trim().toLowerCase();
    final genericPrefixes = [
      'editorial',
      'preface',
      'erratum',
      'errata',
      'corrigendum',
      'corrigenda',
      'book review',
      'book reviews',
      'review of',
      'introduction',
      'foreword',
      'proceedings',
      'table of contents',
      'author index',
      'subject index',
      'index to volume',
      'obituary',
      'in memoriam',
      'announcement',
      'announcements',
      'call for papers',
    ];
    for (final prefix in genericPrefixes) {
      if (lower == prefix ||
          lower.startsWith('$prefix:') ||
          lower.startsWith('$prefix -') ||
          lower.startsWith('$prefix—') ||
          lower.startsWith('$prefix ') ||
          lower.startsWith('$prefix.')) {
        return true;
      }
    }
    return false;
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

  @visibleForTesting
  ArxivPaper enrichPaper(ArxivPaper target, ArxivPaper incoming) => _enrichPaper(target, incoming);

  ArxivPaper _enrichPaper(ArxivPaper target, ArxivPaper incoming) {
    if (!canMerge(target, incoming)) {
      return target;
    }

    // 1. DOI: preserve target DOI if valid, otherwise take incoming if valid
    final targetDoi = ArxivPaper.normalizeDoi(target.doi);
    final incomingDoi = ArxivPaper.normalizeDoi(incoming.doi);
    final enrichedDoi = (targetDoi == null || targetDoi.isEmpty)
        ? incomingDoi
        : targetDoi;

    // 2. Abstract: keep target if usable; only adopt incoming if target has none
    final targetSummaryValid = _isAbstractUsable(target.summary);
    final incomingSummaryValid = _isAbstractUsable(incoming.summary);
    final enrichedSummary = (!targetSummaryValid && incomingSummaryValid)
        ? incoming.summary
        : (targetSummaryValid ? target.summary : (incoming.summary.isNotEmpty ? incoming.summary : target.summary));

    // 3. PDF URL: keep target if direct PDF; only adopt incoming if target has none
    final targetHasPdf = _isDirectPdfUrl(target.pdfUrl);
    final incomingHasPdf = _isDirectPdfUrl(incoming.pdfUrl);
    final enrichedPdfUrl = (!targetHasPdf && incomingHasPdf)
        ? incoming.pdfUrl
        : (targetHasPdf ? target.pdfUrl : (incomingHasPdf ? incoming.pdfUrl : ''));

    // 4. Authors: if target has valid authors, keep target; only fill from incoming if target is unknown
    final targetAuthorsUnknown = target.authors.isEmpty ||
        (target.authors.length == 1 && target.authors.first.toLowerCase() == 'unknown');
    final incomingAuthorsUnknown = incoming.authors.isEmpty ||
        (incoming.authors.length == 1 && incoming.authors.first.toLowerCase() == 'unknown');
    final enrichedAuthors = (targetAuthorsUnknown && !incomingAuthorsUnknown)
        ? incoming.authors
        : target.authors;

    // 5. Date: prefer higher-precision date if publication year matches
    final targetYear = _extractYear(target.published);
    final incomingYear = _extractYear(incoming.published);
    String enrichedPublished = target.published;
    String enrichedUpdated = target.updated;

    if (targetYear == null && incomingYear != null) {
      enrichedPublished = incoming.published;
      enrichedUpdated = incoming.updated;
    } else if (targetYear != null && incomingYear != null && targetYear == incomingYear) {
      if (incoming.published.length > target.published.length && incoming.published.startsWith(targetYear)) {
        enrichedPublished = incoming.published;
        enrichedUpdated = incoming.updated;
      }
    }

    // 6. Categories / Provenance: preserve all sources
    final catSet = <String>{...target.categories};
    for (final c in incoming.categories) {
      if (c.trim().isNotEmpty) catSet.add(c.trim());
    }

    // 7. Citations & References: prefer highest count
    int? enrichedCitation = target.citationCount;
    if (incoming.citationCount != null) {
      if (enrichedCitation == null || incoming.citationCount! > enrichedCitation) {
        enrichedCitation = incoming.citationCount;
      }
    }
    int? enrichedReference = target.referenceCount;
    if (incoming.referenceCount != null) {
      if (enrichedReference == null || incoming.referenceCount! > enrichedReference) {
        enrichedReference = incoming.referenceCount;
      }
    }

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
      final response = await _get(uri);
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
      'mailto': politeEmail,
    });

    try {
      final response = await _get(uri);
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
      'mailto': politeEmail,
    });

    try {
      final response = await _get(uri);
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
      final response = await _get(uri);
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
      final response = await _get(uri);
      if (response.statusCode == 200) {
        return _parseInternetArchive(response.body);
      }
    } catch (e) {
      debugPrint('Internet Archive error: $e');
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
      );
      if (response.statusCode == 200) {
        return _parseArchiveFullText(response.body);
      }
    } catch (e) {
      debugPrint('Internet Archive full-text error: $e');
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
      debugPrint('Internet Archive metadata error: $e');
    }
    _archiveFilesCache[identifier] = result;
    return result;
  }

  Future<ArxivPaper> _withResolvedPdf(ArxivPaper p) async {
    final files = await _resolveArchiveFiles(p.id);
    return p.copyWith(
      pdfUrl: files.pdfUrl ?? p.pdfUrl,
    );
  }

  @visibleForTesting
  Future<ArxivPaper> resolveArchivePdf(ArxivPaper p) => _withResolvedPdf(p);

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
      debugPrint('Internet Archive text download error: $e');
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
        final rawDoi = item['DOI']?.toString();
        final doi = ArxivPaper.normalizeDoi(rawDoi);
        final pdfUrl = _isDirectPdfUrl(url) ? url : '';
        final absUrl = url.isNotEmpty ? url : (doi != null ? 'https://doi.org/$doi' : '');

        papers.add(ArxivPaper(
          id: (doi != null && doi.isNotEmpty) ? doi : (url.isNotEmpty ? url : title),
          title: title,
          authors: authors,
          summary: abstractText,
          published: created,
          updated: created,
          categories: categories,
          pdfUrl: pdfUrl,
          absUrl: absUrl,
          doi: doi,
          sources: const [crossrefSource],
        ));
      }
    } catch (e) {
      debugPrint('Crossref parse error: $e');
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
        final rawPdfUrl = primaryLoc['pdf_url']?.toString() ?? '';
        final pdfUrl = _isDirectPdfUrl(rawPdfUrl) ? rawPdfUrl : '';
        final rawDoi = item['doi']?.toString();
        final doi = ArxivPaper.normalizeDoi(rawDoi);
        final id = item['id']?.toString() ?? '';
        final absUrl = url.isNotEmpty ? url : (doi != null ? 'https://doi.org/$doi' : id);

        papers.add(ArxivPaper(
          id: id,
          title: title,
          authors: authors,
          summary: abstractText,
          published: created,
          updated: created,
          categories: ['OpenAlex'],
          pdfUrl: pdfUrl,
          absUrl: absUrl,
          doi: doi,
          sources: const [openAlexSource],
        ));
      }
    } catch (e) {
      debugPrint('OpenAlex parse error: $e');
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
            pdfUrl = _isDirectPdfUrl(u) ? u : '';
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
          doi = ArxivPaper.normalizeDoi(d);
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
          sources: const [semanticScholarSource],
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
          doi: null,
          sources: const [archiveSource],
        ));
      }
    } catch (e) {
      debugPrint('Internet Archive parse error: $e');
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
          doi: null,
          sources: const [archiveSource],
        ));
      }
    } catch (e) {
      debugPrint('Internet Archive full-text parse error: $e');
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
          var cleanShortId = id.trim();
          cleanShortId = cleanShortId.replaceAll(RegExp(r'^https?:\/\/arxiv\.org\/(abs|pdf)\/', caseSensitive: false), '');
          cleanShortId = cleanShortId.replaceAll(RegExp(r'^arxiv:\s*', caseSensitive: false), '');
          cleanShortId = cleanShortId.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
          pdfUrl = 'https://arxiv.org/pdf/$cleanShortId';
        }

        final rawDoi = _text(entry, 'doi', namespaceUri: 'http://arxiv.org/schemas/atom');
        final doi = ArxivPaper.normalizeDoi(rawDoi);
        final journalRef = _text(entry, 'journal_ref', namespaceUri: 'http://arxiv.org/schemas/atom');

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
          journalRef: journalRef.isNotEmpty ? journalRef : null,
          sources: const [arxivSource],
        ));
      } catch (_) {}
    }
    return papers;
  }

  String _text(XmlElement node, String tag, {String? namespaceUri}) {
    final name = (namespaceUri != null && tag.contains(':'))
        ? tag.split(':').last
        : tag;
    final elements = namespaceUri != null
        ? node.findElements(name, namespaceUri: namespaceUri)
        : node.findElements(tag);
    if (elements.isEmpty) return '';
    return elements.first.innerText.trim();
  }

  String _childText(XmlElement node, String tag) {
    final elements = node.findElements(tag);
    if (elements.isEmpty) return '';
    return elements.first.innerText.trim();
  }
}
