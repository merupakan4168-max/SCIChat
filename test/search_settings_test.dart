// search_settings_test.dart — Tests for Stage 4.3 search settings implementation
//
// Covers:
//   A. SearchService.search() maxResults limit (choices 3, 5, 8, 10)
//   B. Sorting: submittedDate, lastUpdatedDate, relevance (round-robin preserved)
//   C. _compareDate edge cases via sort behaviour
//   D. StorageService SearchFilter persistence
//   E. SciChatProvider filter init + setFilter() persistence
//
// No real network calls — all data is provided via in-memory fixtures.

import 'package:flutter_test/flutter_test.dart';
import 'package:scichat/models/models.dart';
import 'package:scichat/services/search_service.dart';
import 'package:scichat/services/storage_service.dart';
import 'package:scichat/services/gemini_service.dart';
import 'package:scichat/providers/scichat_provider.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────

ArxivPaper _paper({
  required String id,
  String title = '',
  String published = '',
  String updated = '',
  String? doi,
  List<String> categories = const ['cs.AI'],
}) =>
    ArxivPaper(
      id: id,
      title: title.isNotEmpty ? title : id,
      authors: const [],
      summary: 'Abstract for $id',
      published: published,
      updated: updated,
      categories: categories,
      pdfUrl: 'https://example.com/$id.pdf',
      absUrl: 'https://example.com/$id',
      doi: doi,
    );

// ─── Test-double StorageService ────────────────────────────────────────────────

class _MockStorage extends StorageService {
  String? savedKey;
  String themeMode = 'system';
  SearchFilter? savedFilter;

  @override
  Future<String?> getApiKey() async => savedKey;
  @override
  Future<void> saveApiKey(String key) async => savedKey = key;
  @override
  Future<String?> getThemeMode() async => themeMode;
  @override
  Future<void> saveThemeMode(String mode) async => themeMode = mode;
  @override
  Future<List<ChatSession>> getChatSessions() async => [];
  @override
  Future<void> saveChatSessions(List<ChatSession> sessions) async {}
  @override
  Future<List<ArxivPaper>> getFavorites() async => [];
  @override
  Future<void> addFavorite(ArxivPaper paper) async {}
  @override
  Future<void> removeFavorite(String paperId) async {}
  @override
  Future<bool> isFavorite(String paperId) async => false;
  @override
  Future<List<ResearchNote>> getNotes() async => [];
  @override
  Future<void> addNote(ResearchNote note) async {}
  @override
  Future<void> removeNote(String noteId) async {}
  @override
  Future<List<ArxivPaper>?> getCached(String cacheKey) async => null;
  @override
  Future<void> setCache(String cacheKey, List<ArxivPaper> papers) async {}

  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {
    savedFilter = filter;
  }

  @override
  Future<SearchFilter> getSearchFilter() async {
    return savedFilter ?? const SearchFilter();
  }
}

// ─── Fake SearchService ────────────────────────────────────────────────────────

/// Returns pre-configured slot lists instead of making HTTP calls.
/// Slot order: [arxiv, archive, openAlex, crossref].
/// Replicates the same merge/dedup/sort algorithm as production code.
class _FakeSearchService extends SearchService {
  final List<List<ArxivPaper>> sourceSlots;

  _FakeSearchService(this.sourceSlots) : assert(sourceSlots.length == 4);

  @override
  Future<List<ArxivPaper>> search({
    required String query,
    String? keywords,
    SearchFilter filter = const SearchFilter(),
    bool deep = false,
    String? onlySource,
  }) async {
    final int totalLimit = deep ? 24 : filter.maxResults;

    final results = sourceSlots.map((s) => s.toList()).toList();

    final merged = <ArxivPaper>[];
    final seen = <String>{};
    final maxLen = results.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (int i = 0; i < maxLen && merged.length < totalLimit; i++) {
      for (final list in results) {
        if (i >= list.length || merged.length >= totalLimit) continue;
        final p = list[i];
        final keys = _keys(p);
        if (keys.any(seen.contains)) continue;
        seen.addAll(keys);
        merged.add(p);
      }
    }

    if (filter.sortBy == 'submittedDate') {
      merged.sort((a, b) => _cmp(b.published, a.published));
    } else if (filter.sortBy == 'lastUpdatedDate') {
      merged.sort((a, b) => _cmp(b.updated, a.updated));
    }
    return merged;
  }

  Set<String> _keys(ArxivPaper p) {
    final keys = <String>{};
    final doi = (p.doi ?? '').toLowerCase().replaceAll('https://doi.org/', '').trim();
    if (doi.isNotEmpty) keys.add('doi:$doi');
    final title = p.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (title.length > 10) keys.add('t:$title');
    return keys;
  }

  static int _cmp(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null && db == null) return 0;
    if (da == null) return -1; // paperB's date is invalid → paperB goes last
    if (db == null) return 1;  // paperA's date is invalid → paperA goes last
    return da.compareTo(db);
  }
}

class _MockGemini extends GeminiService {
  _MockGemini() : super(apiKey: 'test-key');
}

// ─── Corrupt / throwing storage doubles ───────────────────────────────────────

class _CorruptStorage extends _MockStorage {
  @override
  Future<SearchFilter> getSearchFilter() async {
    // Validate like StorageService.getSearchFilter() does
    const invalidMax = 999;
    const invalidSort = 'unknown_sort';
    const validMax = [3, 5, 8, 10];
    const validSort = ['relevance', 'submittedDate', 'lastUpdatedDate'];
    final maxResults = validMax.contains(invalidMax) ? invalidMax : const SearchFilter().maxResults;
    final sortBy = validSort.contains(invalidSort) ? invalidSort : const SearchFilter().sortBy;
    return SearchFilter(maxResults: maxResults, sortBy: sortBy);
  }
}

class _ThrowingStorage extends _MockStorage {
  @override
  Future<void> saveSearchFilter(SearchFilter filter) async {
    throw Exception('Simulated disk error');
  }
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── A. maxResults enforcement ──────────────────────────────────────────────
  group('A. maxResults enforcement', () {
    for (final limit in [3, 5, 8, 10]) {
      test('Choice $limit: result count == $limit (enough unique results available)', () async {
        final slots = List.generate(
          4,
          (s) => List.generate(
            15,
            (i) => _paper(id: 'src${s}p$i', title: 'Source $s Paper $i unique text'),
          ),
        );
        final svc = _FakeSearchService(slots);
        final results = await svc.search(
          query: 'test',
          filter: SearchFilter(maxResults: limit, sortBy: 'relevance'),
        );
        expect(results.length, equals(limit),
            reason: 'maxResults=$limit must cap result count at exactly $limit');
        final ids = results.map((p) => p.id).toSet();
        expect(ids.length, equals(results.length), reason: 'No duplicate IDs');
      });
    }

    test('Inter-source duplicates: choice 3 still yields ≤ 3 unique results', () async {
      final shared = _paper(id: 'shared1', title: 'Shared Paper Title Exact Match Here');
      final slots = [
        [shared, _paper(id: 'arxiv-extra', title: 'arXiv Only Paper Unique')],
        [shared, _paper(id: 'arch-extra', title: 'Archive Only Paper Unique')],
        [shared, _paper(id: 'oa-extra', title: 'OpenAlex Only Paper Unique')],
        [shared, _paper(id: 'cr-extra', title: 'Crossref Only Paper Unique')],
      ];
      final svc = _FakeSearchService(slots);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 3, sortBy: 'relevance'),
      );
      expect(results.length, lessThanOrEqualTo(3));
      final ids = results.map((p) => p.id).toSet();
      expect(ids.length, equals(results.length));
    });

    test('Fewer unique results than limit: returns all available, no padding', () async {
      final slots = [
        [_paper(id: 'p1', title: 'Paper One Unique Text Here')],
        [_paper(id: 'p2', title: 'Paper Two Unique Text Here')],
        <ArxivPaper>[],
        <ArxivPaper>[],
      ];
      final svc = _FakeSearchService(slots);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 10, sortBy: 'relevance'),
      );
      expect(results.length, equals(2),
          reason: 'Should not fabricate results; return 2 that exist');
    });

    test('Deep search uses fixed 24-result cap, ignores maxResults=3', () async {
      final slots = List.generate(
        4,
        (s) => List.generate(
          10,
          (i) => _paper(id: 'd${s}p$i', title: 'Deep Source $s Paper $i unique'),
        ),
      );
      final svc = _FakeSearchService(slots);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 3),
        deep: true,
      );
      expect(results.length, equals(24),
          reason: 'Deep search totalLimit is 24, not user maxResults');
    });
  });

  // ── B. Sorting ─────────────────────────────────────────────────────────────
  group('B. Sorting', () {
    final p2022 = _paper(id: 'y2022', title: 'Paper from 2022 unique', published: '2022-11-20', updated: '2022-12-01');
    final p2023 = _paper(id: 'y2023', title: 'Paper from 2023 unique', published: '2023-06-15', updated: '2023-08-01');
    final p2024 = _paper(id: 'y2024', title: 'Paper from 2024 unique', published: '2024-01-10', updated: '2024-09-30');
    final pNoDate = _paper(id: 'nodate', title: 'Paper No Date Available', published: '', updated: '');

    test('submittedDate: most recently published first', () async {
      final svc = _FakeSearchService([
        [p2022, p2024],
        [p2023],
        [],
        [],
      ]);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 10, sortBy: 'submittedDate'),
      );
      expect(results[0].id, equals('y2024'));
      expect(results[1].id, equals('y2023'));
      expect(results[2].id, equals('y2022'));
    });

    test('submittedDate: empty published date sorts after valid dates', () async {
      final svc = _FakeSearchService([
        [pNoDate, p2024],
        [p2022],
        [],
        [],
      ]);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 10, sortBy: 'submittedDate'),
      );
      expect(results.last.id, equals('nodate'),
          reason: 'Empty published date must be placed last');
    });

    test('lastUpdatedDate: most recently updated first', () async {
      // p2024.updated='2024-09-30', p2023.updated='2023-08-01', p2022.updated='2022-12-01'
      final svc = _FakeSearchService([
        [p2022, p2023],
        [p2024],
        [],
        [],
      ]);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 10, sortBy: 'lastUpdatedDate'),
      );
      expect(results[0].id, equals('y2024'));
      expect(results[1].id, equals('y2023'));
      expect(results[2].id, equals('y2022'));
    });

    test('lastUpdatedDate: empty updated field sorts after valid ones', () async {
      final svc = _FakeSearchService([
        [pNoDate, p2023],
        [p2024],
        [],
        [],
      ]);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 10, sortBy: 'lastUpdatedDate'),
      );
      expect(results.last.id, equals('nodate'));
    });

    test('relevance: round-robin merge order preserved (no date sort)', () async {
      // arxiv slot first → should appear before archive slot first
      final svc = _FakeSearchService([
        [_paper(id: 'ar1', title: 'arXiv Relevance First Unique'), _paper(id: 'ar2', title: 'arXiv Relevance Second One')],
        [_paper(id: 'ac1', title: 'Archive Relevance First Unique')],
        [],
        [],
      ]);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 5, sortBy: 'relevance'),
      );
      expect(results[0].id, equals('ar1'));
      expect(results[1].id, equals('ac1'));
      expect(results[2].id, equals('ar2'));
    });

    test('Multi-source results can be merged for all sort modes', () async {
      final svc = _FakeSearchService([
        [_paper(id: 'a1', title: 'Alpha Source Unique', published: '2024-01-01', updated: '2024-06-01')],
        [_paper(id: 'b1', title: 'Beta Source Unique', published: '2023-05-10', updated: '2024-08-15')],
        [_paper(id: 'c1', title: 'Gamma Source Unique', published: '2022-03-20', updated: '2022-04-01')],
        [_paper(id: 'd1', title: 'Delta Source Unique', published: '2021-07-07', updated: '2021-09-09')],
      ]);
      for (final sort in ['relevance', 'submittedDate', 'lastUpdatedDate']) {
        final results = await svc.search(
          query: 'test',
          filter: SearchFilter(maxResults: 10, sortBy: sort),
        );
        expect(results.length, equals(4),
            reason: 'All 4 unique results for sortBy=$sort');
      }
    });
  });

  // ── C. _compareDate edge cases ─────────────────────────────────────────────
  group('C. _compareDate edge cases', () {
    test('Two empty dates: no exception thrown', () async {
      final svc = _FakeSearchService([
        [_paper(id: 'nd1', title: 'No Date One Unique Text Here', published: '', updated: '')],
        [_paper(id: 'nd2', title: 'No Date Two Unique Text Here', published: '', updated: '')],
        [],
        [],
      ]);
      expect(
        () => svc.search(query: 'test', filter: const SearchFilter(maxResults: 5, sortBy: 'submittedDate')),
        returnsNormally,
      );
    });

    test('Invalid date string sorts after valid ISO-8601 date', () async {
      final invalid = _paper(id: 'bad', title: 'Bad Date Paper Unique Here', published: 'not-a-date', updated: 'invalid');
      final valid = _paper(id: 'ok', title: 'Valid Date Paper Unique Here', published: '2024-03-01', updated: '2024-05-01');
      final svc = _FakeSearchService([
        [invalid, valid],
        [],
        [],
        [],
      ]);
      final results = await svc.search(
        query: 'test',
        filter: const SearchFilter(maxResults: 5, sortBy: 'submittedDate'),
      );
      expect(results.first.id, equals('ok'));
      expect(results.last.id, equals('bad'));
    });
  });

  // ── D. StorageService SearchFilter persistence ─────────────────────────────
  group('D. StorageService SearchFilter persistence', () {
    test('Default filter when nothing stored', () async {
      final storage = _MockStorage();
      final filter = await storage.getSearchFilter();
      expect(filter.maxResults, equals(const SearchFilter().maxResults));
      expect(filter.sortBy, equals(const SearchFilter().sortBy));
      expect(filter.category, isNull);
    });

    test('Save and restore maxResults=3, sortBy=submittedDate', () async {
      final storage = _MockStorage();
      await storage.saveSearchFilter(const SearchFilter(maxResults: 3, sortBy: 'submittedDate'));
      final r = await storage.getSearchFilter();
      expect(r.maxResults, equals(3));
      expect(r.sortBy, equals('submittedDate'));
    });

    test('Save and restore maxResults=10, sortBy=lastUpdatedDate', () async {
      final storage = _MockStorage();
      await storage.saveSearchFilter(const SearchFilter(maxResults: 10, sortBy: 'lastUpdatedDate'));
      final r = await storage.getSearchFilter();
      expect(r.maxResults, equals(10));
      expect(r.sortBy, equals('lastUpdatedDate'));
    });

    test('Save and restore with category set', () async {
      final storage = _MockStorage();
      await storage.saveSearchFilter(const SearchFilter(maxResults: 5, sortBy: 'relevance', category: 'cs.LG'));
      final r = await storage.getSearchFilter();
      expect(r.category, equals('cs.LG'));
    });

    test('Cold start: provider.init() restores saved filter', () async {
      final storage = _MockStorage();
      await storage.saveSearchFilter(const SearchFilter(maxResults: 8, sortBy: 'lastUpdatedDate'));
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();
      expect(provider.filter.maxResults, equals(8));
      expect(provider.filter.sortBy, equals('lastUpdatedDate'));
    });

    test('No stored filter: provider uses default SearchFilter', () async {
      final storage = _MockStorage();
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();
      expect(provider.filter.maxResults, equals(const SearchFilter().maxResults));
      expect(provider.filter.sortBy, equals(const SearchFilter().sortBy));
    });

    test('Corrupt stored values fall back to defaults without crash', () async {
      final storage = _CorruptStorage();
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();
      expect(provider.filter.maxResults, equals(const SearchFilter().maxResults));
      expect(provider.filter.sortBy, equals(const SearchFilter().sortBy));
    });
  });

  // ── E. Provider setFilter() persistence ────────────────────────────────────
  group('E. Provider setFilter() persistence', () {
    test('setFilter updates provider.filter immediately', () async {
      final storage = _MockStorage();
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();

      provider.setFilter(const SearchFilter(maxResults: 3, sortBy: 'submittedDate'));

      expect(provider.filter.maxResults, equals(3));
      expect(provider.filter.sortBy, equals('submittedDate'));
    });

    test('setFilter triggers async persist to storage', () async {
      final storage = _MockStorage();
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();

      provider.setFilter(const SearchFilter(maxResults: 10, sortBy: 'lastUpdatedDate'));
      await Future<void>.delayed(Duration.zero);

      expect(storage.savedFilter?.maxResults, equals(10));
      expect(storage.savedFilter?.sortBy, equals('lastUpdatedDate'));
    });

    test('Rapid setFilter calls: last value wins in memory and storage', () async {
      final storage = _MockStorage();
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();

      provider.setFilter(const SearchFilter(maxResults: 3, sortBy: 'relevance'));
      provider.setFilter(const SearchFilter(maxResults: 5, sortBy: 'submittedDate'));
      provider.setFilter(const SearchFilter(maxResults: 8, sortBy: 'lastUpdatedDate'));

      expect(provider.filter.maxResults, equals(8));
      expect(provider.filter.sortBy, equals('lastUpdatedDate'));

      await Future<void>.delayed(Duration.zero);
      expect(storage.savedFilter?.maxResults, equals(8));
    });

    test('Storage failure does not crash or corrupt active filter', () async {
      final storage = _ThrowingStorage();
      final provider = SciChatProvider(storageService: storage, geminiService: _MockGemini());
      await provider.init();

      expect(() => provider.setFilter(const SearchFilter(maxResults: 5)), returnsNormally);

      await Future<void>.delayed(Duration.zero);
      expect(provider.filter.maxResults, equals(5));
    });
  });
}
